#!/bin/bash
set -e

KEYCLOAK_URL=$(kubectl get ingress -n zero-trust-infra keycloak -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

echo "Configuring Keycloak at: http://${KEYCLOAK_URL}"
echo ""

# Get admin access token
echo "→ Obtaining admin token..."
ADMIN_TOKEN=$(curl -s -X POST "http://${KEYCLOAK_URL}/realms/master/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=admin" \
  -d "password=AdminPassword123!" \
  -d "grant_type=password" \
  -d "client_id=admin-cli" \
  | jq -r '.access_token')

if [ "$ADMIN_TOKEN" = "null" ] || [ -z "$ADMIN_TOKEN" ]; then
  echo "✗ Failed to get admin token"
  exit 1
fi

echo "✓ Admin token obtained"

# Create zero-trust realm
echo "→ Creating zero-trust realm..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "http://${KEYCLOAK_URL}/admin/realms" \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "realm": "zero-trust",
    "enabled": true,
    "displayName": "Zero Trust Realm",
    "accessTokenLifespan": 300,
    "sslRequired": "none",
    "registrationAllowed": false,
    "loginWithEmailAllowed": true,
    "duplicateEmailsAllowed": false,
    "resetPasswordAllowed": true,
    "editUsernameAllowed": false,
    "bruteForceProtected": true
  }')

if [ "$HTTP_CODE" = "201" ]; then
  echo "✓ Realm 'zero-trust' created"
elif [ "$HTTP_CODE" = "409" ]; then
  echo "✓ Realm 'zero-trust' already exists"
else
  echo "✗ Failed to create realm (HTTP $HTTP_CODE)"
  exit 1
fi

# Create manager role
echo "→ Creating 'manager' role..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "http://${KEYCLOAK_URL}/admin/realms/zero-trust/roles" \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "manager",
    "description": "Manager role with elevated access"
  }')

if [ "$HTTP_CODE" = "201" ]; then
  echo "✓ Role 'manager' created"
elif [ "$HTTP_CODE" = "409" ]; then
  echo "✓ Role 'manager' already exists"
else
  echo "✗ Failed to create manager role (HTTP $HTTP_CODE)"
fi

# Create employee role
echo "→ Creating 'employee' role..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "http://${KEYCLOAK_URL}/admin/realms/zero-trust/roles" \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "employee",
    "description": "Standard employee role"
  }')

if [ "$HTTP_CODE" = "201" ]; then
  echo "✓ Role 'employee' created"
elif [ "$HTTP_CODE" = "409" ]; then
  echo "✓ Role 'employee' already exists"
else
  echo "✗ Failed to create employee role (HTTP $HTTP_CODE)"
fi

# Create Alice user
echo "→ Creating user 'alice'..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "http://${KEYCLOAK_URL}/admin/realms/zero-trust/users" \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "username": "alice",
    "email": "alice@zero-trust.local",
    "firstName": "Alice",
    "lastName": "Manager",
    "enabled": true,
    "emailVerified": true,
    "credentials": [{
      "type": "password",
      "value": "alice123",
      "temporary": false
    }]
  }')

if [ "$HTTP_CODE" = "201" ]; then
  echo "✓ User 'alice' created"

  # Get Alice's user ID
  ALICE_ID=$(curl -s -X GET "http://${KEYCLOAK_URL}/admin/realms/zero-trust/users?username=alice" \
    -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    | jq -r '.[0].id')

  # Get manager role ID
  MANAGER_ROLE=$(curl -s -X GET "http://${KEYCLOAK_URL}/admin/realms/zero-trust/roles/manager" \
    -H "Authorization: Bearer ${ADMIN_TOKEN}")

  # Assign manager role to Alice
  curl -s -X POST "http://${KEYCLOAK_URL}/admin/realms/zero-trust/users/${ALICE_ID}/role-mappings/realm" \
    -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "[${MANAGER_ROLE}]"

  echo "✓ Assigned 'manager' role to alice"

elif [ "$HTTP_CODE" = "409" ]; then
  echo "✓ User 'alice' already exists"
else
  echo "✗ Failed to create user alice (HTTP $HTTP_CODE)"
fi

# Create Bob user
echo "→ Creating user 'bob'..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "http://${KEYCLOAK_URL}/admin/realms/zero-trust/users" \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "username": "bob",
    "email": "bob@zero-trust.local",
    "firstName": "Bob",
    "lastName": "Employee",
    "enabled": true,
    "emailVerified": true,
    "credentials": [{
      "type": "password",
      "value": "bob123",
      "temporary": false
    }]
  }')

if [ "$HTTP_CODE" = "201" ]; then
  echo "✓ User 'bob' created"

  # Get Bob's user ID
  BOB_ID=$(curl -s -X GET "http://${KEYCLOAK_URL}/admin/realms/zero-trust/users?username=bob" \
    -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    | jq -r '.[0].id')

  # Get employee role
  EMPLOYEE_ROLE=$(curl -s -X GET "http://${KEYCLOAK_URL}/admin/realms/zero-trust/roles/employee" \
    -H "Authorization: Bearer ${ADMIN_TOKEN}")

  # Assign employee role to Bob
  curl -s -X POST "http://${KEYCLOAK_URL}/admin/realms/zero-trust/users/${BOB_ID}/role-mappings/realm" \
    -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "[${EMPLOYEE_ROLE}]"

  echo "✓ Assigned 'employee' role to bob"

elif [ "$HTTP_CODE" = "409" ]; then
  echo "✓ User 'bob' already exists"
else
  echo "✗ Failed to create user bob (HTTP $HTTP_CODE)"
fi

# Create frontend-app client
echo "→ Creating 'frontend-app' client..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "http://${KEYCLOAK_URL}/admin/realms/zero-trust/clients" \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "clientId": "frontend-app",
    "enabled": true,
    "protocol": "openid-connect",
    "publicClient": true,
    "directAccessGrantsEnabled": true,
    "redirectUris": ["http://localhost:3000/*"],
    "webOrigins": ["http://localhost:3000"],
    "standardFlowEnabled": true,
    "serviceAccountsEnabled": false
  }')

if [ "$HTTP_CODE" = "201" ]; then
  echo "✓ Client 'frontend-app' created (public client - no secret required)"

elif [ "$HTTP_CODE" = "409" ]; then
  echo "✓ Client 'frontend-app' already exists"
else
  echo "✗ Failed to create client (HTTP $HTTP_CODE)"
fi

echo ""
echo "===================================="
echo "Keycloak configuration complete!"
echo "===================================="
echo ""
echo "Realm: zero-trust"
echo "Users:"
echo "  - alice / alice123 (manager role)"
echo "  - bob / bob123 (employee role)"
echo "Client: frontend-app"
echo ""
echo "Test login:"
echo "curl -X POST \"http://${KEYCLOAK_URL}/realms/zero-trust/protocol/openid-connect/token\" \\"
echo "  -d \"username=alice\" \\"
echo "  -d \"password=alice123\" \\"
echo "  -d \"grant_type=password\" \\"
echo "  -d \"client_id=frontend-app\""
echo ""
