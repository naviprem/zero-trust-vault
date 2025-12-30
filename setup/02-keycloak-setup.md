# Configure Keycloak

## Run Keycloak setup script

```bash
# Run Keycloak Setup Script
./scripts/configure-keycloak.sh
```

## Test User Login

```bash
# Get token for Alice
KEYCLOAK_URL="http://$(kubectl get ingress -n zero-trust-infra keycloak -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')"

# Get access token
ALICE_TOKEN=$(curl -s -X POST \
  "$KEYCLOAK_URL/realms/zero-trust/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=alice" \
  -d "password=alice123" \
  -d "grant_type=password" \
  -d "client_id=frontend-app" \
  | jq -r '.access_token')

echo $ALICE_TOKEN

# Decode token to verify roles (Robust version for Mac)
echo $ALICE_TOKEN | cut -d'.' -f2 | tr '_-' '/+' | xargs -I{} sh -c "echo {} | base64 -D" 2>/dev/null | jq .

# Should show: "realm_access": { "roles": ["manager", ...] }

# Install once
brew install jwt-cli
# Use anytime
jwt decode $ALICE_TOKEN
```

This script is an automation tool designed to bootstrap the Human Identity layer. It uses the Keycloak REST API to programmatically set up the authentication environment.

### Here is a summary of what it does:

1. Administrative Authentication
- It first locates your Keycloak instance in the K8s cluster via the ingress hostname.
- It obtains an Admin Access Token from the master realm using the root credentials (e.g., admin / password).

2. Realm Creation
- It creates a dedicated security domain called the zero-trust realm.
- This ensures that your demo users and policies are isolated from the system-level master configurations.

3. Role-Based Access Control (RBAC) Setup
- It defines two distinct security roles that are critical for your later OPA (Open Policy Agent) demonstrations:
- manager: Intended for elevated access (e.g., viewing Confidential documents).
- employee: Standard access level (e.g., viewing Public documents only).

4. User Provisioning
- It creates two "demo human" users and assigns them their respective roles:
- Alice: Assigned the manager role.
- Bob: Assigned the employee role.
- Secretless Note: While these users have passwords now, the goal is to show how these human identities are combined with machine identities (SPIRE) to make authorization decisions.

5. Client Registration
- It creates the frontend-app client.

