# Vault Setup

HashiCorp Vault is the central secrets manager for the Zero Trust Vault. Its role is to provide **dynamic, short-lived credentials** to services based on their **SPIFFE identity**, eliminating the need for hardcoded passwords.

**Version:** Vault v1.21.1

**Integration Method:** Vault authenticates SPIFFE identities by fetching JWT signing keys from the SPIRE OIDC Discovery Provider endpoint (`http://spire-server:8088/keys`). This allows Vault to cryptographically verify that JWT-SVIDs were issued by your trusted SPIRE Server.

---

## Step 1: Automated Configuration

We use the `scripts/configure-vault.sh` script to automate the complex setup of JWT authentication, SPIFFE mapping, and the Database secrets engine.

### What this script automates:
1.  **JWT Auth Method**: Enables and configures Vault to verify tokens from the SPIRE Server.
2.  **SPIFFE Trust**: Mounts the SPIRE Root CA bundle into Vault so it can cryptographically trust your services.
3.  **Security Policies**: Creates the `backend-policy` which strictly defines what endpoints the backend can access.
4.  **Identity Mapping**: Maps the `spiffe://zero-trust.local/backend` identity to the security policy.
5.  **Dynamic Database Credentials**: Configures the PostgreSQL engine to generate one-time use passwords for the backend.

### Execution:
Ensure your environment variables are set (usually by running `eval $(make aws-export)`), then run:

```bash
# Ensure the script is executable
chmod +x scripts/configure-vault.sh

# Run the automated vault configuration
./scripts/configure-vault.sh
```

**Success Verification:**
At the end of the script, it will attempt to generate a test database credential. You should see a JSON output containing a unique `username` and `password`.

---

## Step 2: Challenge Verification: "The Secretless Bootstrap"

To prove the setup works, we will deploy a test pod and fetch secrets using **only** its SPIFFE identity. This proves that we have eliminated the need for hardcoded "Secret Zero" bootstrap tokens.

**Note:** SPIRE 1.14.0+ removed the HTTP/1.x REST endpoint for the Workload API. We now use the `spire-agent` CLI tool to interact with the gRPC Workload API.

```bash
# 1. Deploy test pod with backend identity
kubectl apply -f infra/k8s/test-pod.yaml
kubectl wait --for=condition=ready pod/backend-test -n demo-apps --timeout=60s

# 2. Exec into the pod and "Request" a secret using identity
kubectl exec -n demo-apps backend-test -- sh -c '
  # Install tools needed for the demo
  apk add --no-cache curl jq >/dev/null 2>&1
  
  # Download SPIRE CLI (required for SPIRE 1.14.0+)
  curl -L -o /tmp/spire.tar.gz https://github.com/spiffe/spire/releases/download/v1.14.0/spire-1.14.0-linux-amd64-musl.tar.gz >/dev/null 2>&1
  tar -xzf /tmp/spire.tar.gz -C /tmp >/dev/null 2>&1
  
  # A. Get JWT-SVID (Identity Token) from the SPIRE Workload API
  # The audience MUST match the "bound_audiences" in the Vault role
  SVID_TOKEN=$(/tmp/spire-1.14.0/bin/spire-agent api fetch jwt -audience vault -socketPath /run/spire/sockets/agent.sock | grep -A 1 "token(spiffe://zero-trust.local/backend)" | tail -n 1 | tr -d "[:space:]")

  echo "--- IDENTITY VERIFIED BY SPIRE ---"
  echo "Token (first 20 chars): ${SVID_TOKEN:0:20}..."

  # B. Exchange SPIFFE Identity for a Vault Token
  VAULT_TOKEN=$(curl -s \
    --request POST \
    --data "{\"jwt\": \"${SVID_TOKEN}\", \"role\": \"backend\"}" \
    http://vault.zero-trust-infra.svc.cluster.local:8200/v1/auth/jwt/login \
    | jq -r ".auth.client_token")

  # C. Fetch Dynamic Database Credentials
  echo ""
  echo "--- DYNAMIC RDS CREDENTIALS RETRIEVED VIA SPIFFE ---"
  curl -s \
    --header "X-Vault-Token: ${VAULT_TOKEN}" \
    http://vault.zero-trust-infra.svc.cluster.local:8200/v1/database/creds/backend-role \
    | jq .
'
```

### Alternative: Automated Verification Script

For convenience, you can use the automated verification script:

```bash
# Make sure the test pod is running
kubectl apply -f infra/k8s/test-pod.yaml
kubectl wait --for=condition=ready pod/backend-test -n demo-apps --timeout=60s

# Run the automated verification
./scripts/verify-vault-integration.sh backend-test demo-apps
```

This script performs the same verification steps with better error handling and reporting.

### 🎯 Strategic Success Criteria:
*   ✅ **No Passwords**: The test pod did not have a Vault token or DB password in its environment.
*   ✅ **Identity-Based**: Access was granted purely because SPIRE verified the pod's "DNA" and Vault trusted the SPIRE signal.
*   ✅ **Dynamic**: Every time a pod restarts, it gets a *different* database password, making compromised credentials useless.
