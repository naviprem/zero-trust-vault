#!/bin/bash
# Verification script for SPIFFE-based Vault integration
# This script demonstrates the "Secretless Bootstrap" pattern

set -e

POD_NAME="${1:-backend-test}"
NAMESPACE="${2:-demo-apps}"

echo "========================================="
echo "Zero Trust Vault Verification"
echo "========================================="
echo "Pod: $POD_NAME"
echo "Namespace: $NAMESPACE"
echo ""

# Check if pod exists
if ! kubectl get pod "$POD_NAME" -n "$NAMESPACE" &>/dev/null; then
  echo "Error: Pod '$POD_NAME' not found in namespace '$NAMESPACE'"
  exit 1
fi

echo "→ Step 1: Installing dependencies..."
kubectl exec -n "$NAMESPACE" "$POD_NAME" -- sh -c 'apk add --no-cache curl jq >/dev/null 2>&1' || true

echo "→ Step 2: Downloading SPIRE CLI (v1.14.0)..."
kubectl exec -n "$NAMESPACE" "$POD_NAME" -- sh -c '
  if [ ! -f /tmp/spire-1.14.0/bin/spire-agent ]; then
    curl -L -o /tmp/spire.tar.gz https://github.com/spiffe/spire/releases/download/v1.14.0/spire-1.14.0-linux-amd64-musl.tar.gz 2>/dev/null
    tar -xzf /tmp/spire.tar.gz -C /tmp 2>/dev/null
    echo "✓ SPIRE CLI downloaded"
  else
    echo "✓ SPIRE CLI already present"
  fi
'

echo ""
echo "→ Step 3: Executing Secretless Bootstrap..."
echo ""

kubectl exec -n "$NAMESPACE" "$POD_NAME" -- sh -c '
  # Fetch JWT-SVID from SPIRE
  SVID_TOKEN=$(/tmp/spire-1.14.0/bin/spire-agent api fetch jwt \
    -audience vault \
    -socketPath /run/spire/sockets/agent.sock \
    | grep -A 1 "token(spiffe://zero-trust.local/backend)" \
    | tail -n 1 \
    | tr -d "[:space:]")

  if [ -z "$SVID_TOKEN" ]; then
    echo "✗ Failed to fetch JWT-SVID from SPIRE"
    exit 1
  fi

  echo "=== STEP A: IDENTITY VERIFICATION ==="
  echo "✓ JWT-SVID obtained from SPIRE Workload API"
  echo "Token (first 30 chars): ${SVID_TOKEN:0:30}..."
  echo ""

  # Login to Vault
  VAULT_RESPONSE=$(curl -s \
    --request POST \
    --data "{\"jwt\": \"${SVID_TOKEN}\", \"role\": \"backend\"}" \
    http://vault.zero-trust-infra.svc.cluster.local:8200/v1/auth/jwt/login)

  VAULT_TOKEN=$(echo "$VAULT_RESPONSE" | jq -r ".auth.client_token // empty")

  if [ -z "$VAULT_TOKEN" ]; then
    echo "=== STEP B: VAULT AUTHENTICATION ==="
    echo "✗ Vault login failed"
    echo "Response:"
    echo "$VAULT_RESPONSE" | jq .
    exit 1
  fi

  echo "=== STEP B: VAULT AUTHENTICATION ==="
  echo "✓ Successfully authenticated to Vault"
  echo "Vault Token (first 20 chars): ${VAULT_TOKEN:0:20}..."
  echo ""

  # Fetch database credentials
  DB_RESPONSE=$(curl -s \
    --header "X-Vault-Token: ${VAULT_TOKEN}" \
    http://vault.zero-trust-infra.svc.cluster.local:8200/v1/database/creds/backend-role)

  echo "=== STEP C: DYNAMIC CREDENTIAL GENERATION ==="
  
  # Check if we got credentials
  USERNAME=$(echo "$DB_RESPONSE" | jq -r ".data.username // empty")
  
  if [ -z "$USERNAME" ]; then
    echo "✗ Failed to fetch database credentials"
    echo "Response:"
    echo "$DB_RESPONSE" | jq .
    exit 1
  fi

  echo "✓ Dynamic PostgreSQL credentials generated!"
  echo ""
  echo "Full Response:"
  echo "$DB_RESPONSE" | jq .
'

EXIT_CODE=$?

echo ""
echo "========================================="
if [ $EXIT_CODE -eq 0 ]; then
  echo "✓ VERIFICATION SUCCESSFUL"
  echo "========================================="
  echo ""
  echo "Summary:"
  echo "  1. Pod obtained identity from SPIRE (no hardcoded credentials)"
  echo "  2. Vault verified the identity cryptographically"
  echo "  3. Vault issued dynamic, short-lived database credentials"
  echo ""
  echo "This demonstrates the elimination of 'Secret Zero'!"
else
  echo "✗ VERIFICATION FAILED"
  echo "========================================="
  echo ""
  echo "Check the error messages above for details."
fi

exit $EXIT_CODE
