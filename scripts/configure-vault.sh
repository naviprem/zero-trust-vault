#!/bin/bash
set -e

echo "Configuring Vault for SPIFFE authentication..."
echo ""

# Helper function to run vault commands
vault_exec() {
  kubectl exec -n zero-trust-infra vault-0 -- \
    env VAULT_ADDR='http://127.0.0.1:8200' VAULT_TOKEN='root' \
    vault "$@"
}

# Enable JWT auth
echo "→ Enabling JWT authentication method..."
vault_exec auth enable jwt 2>/dev/null || echo "  JWT auth already enabled"

# Configure JWT auth with SPIRE OIDC Discovery Provider
echo "→ Configuring JWT auth with SPIRE JWKS endpoint..."
vault_exec write auth/jwt/config \
  jwks_url="http://spire-server.spire-system.svc.cluster.local:8088/keys" \
  bound_issuer="zero-trust.local"

echo "✓ JWT auth configured"

# Create backend policy
echo "→ Creating backend-policy..."
kubectl exec -n zero-trust-infra vault-0 -- sh -c "
  cat <<'EOF' | env VAULT_ADDR='http://127.0.0.1:8200' VAULT_TOKEN='root' vault policy write backend-policy -
# Policy for backend service to read database credentials
path \"database/creds/backend-role\" {
  capabilities = [\"read\"]
}

path \"secret/data/backend/*\" {
  capabilities = [\"read\"]
}
EOF
"

echo "✓ Backend policy created"

# Create JWT role for backend
echo "→ Creating JWT role for backend..."
vault_exec write auth/jwt/role/backend \
  role_type="jwt" \
  bound_audiences="vault" \
  bound_subject="spiffe://zero-trust.local/backend" \
  user_claim="sub" \
  policies="backend-policy" \
  ttl=1h

echo "✓ JWT role 'backend' created"

# Enable database secrets engine
echo "→ Enabling database secrets engine..."
vault_exec secrets enable database 2>/dev/null || echo "  Database secrets engine already enabled"

# Get RDS endpoint from environment
# (Already sourced via make aws-export)

echo "→ Configuring PostgreSQL connection..."
vault_exec write database/config/postgres-db \
  plugin_name=postgresql-database-plugin \
  allowed_roles="backend-role" \
  connection_url="postgresql://{{username}}:{{password}}@${RDS_HOST}:${RDS_PORT}/${RDS_DATABASE}?sslmode=require" \
  username="${RDS_USERNAME}" \
  password="${RDS_PASSWORD}"

echo "✓ PostgreSQL connection configured"

# Create role for dynamic credentials
echo "→ Creating database role 'backend-role'..."
vault_exec write database/roles/backend-role \
  db_name=postgres-db \
  creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO \"{{name}}\";" \
  default_ttl="1h" \
  max_ttl="24h"

echo "✓ Database role created"

# Test credential generation
echo ""
echo "→ Testing database credential generation..."
vault_exec read database/creds/backend-role

echo ""
echo "===================================="
echo "Vault configuration complete!"
echo "===================================="
echo ""
echo "JWT Auth: Configured for SPIFFE"
echo "Policy: backend-policy"
echo "Role: backend (for backend service)"
echo "Database: postgres-db (connected to RDS)"
echo "Database Role: backend-role (dynamic credentials)"
echo ""
