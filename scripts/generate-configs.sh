#!/bin/bash
set -e

# Validate required environment variables
required_vars=(
    "EKS_CLUSTER_NAME"
    "AWS_VPC_ID"
    "TRUST_DOMAIN"
    "SPIRE_NAMESPACE"
    "KEYCLOAK_NAMESPACE"
    "VAULT_NAMESPACE"
    "RDS_HOST"
    "RDS_PORT"
    "RDS_DATABASE"
    "RDS_USERNAME"
    "RDS_PASSWORD"
    "KEYCLOAK_ADMIN_USERNAME"
    "KEYCLOAK_ADMIN_PASSWORD"
    "AWS_ACCOUNT_ID"
    "AWS_REGION"
    "PROJECT_NAME"
)

missing_vars=()

for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
        missing_vars+=("$var")
    fi
done

if [ ${#missing_vars[@]} -gt 0 ]; then
    echo ""
    echo "Error: The following required environment variables are not set:"
    for var in "${missing_vars[@]}"; do
        echo "  - $var"
    done
    echo ""
    echo "Example values:"
    echo "  export EKS_CLUSTER_NAME=zero-trust-cluster"
    echo "  export AWS_VPC_ID=vpc-xxxxxxxxxxxxxxxxx"
    echo "  export TRUST_DOMAIN=zero-trust.local"
    echo "  export SPIRE_NAMESPACE=spire-system"
    echo "  export KEYCLOAK_NAMESPACE=zero-trust-infra"
    echo "  export VAULT_NAMESPACE=zero-trust-infra"
    echo "  export RDS_HOST=your-rds-endpoint.rds.amazonaws.com"
    echo "  export RDS_PORT=5432"
    echo "  export RDS_DATABASE=keycloak"
    echo "  export RDS_USERNAME=keycloak"
    echo "  export RDS_PASSWORD=your-secure-password"
    echo "  export KEYCLOAK_ADMIN_USERNAME=admin"
    echo "  export KEYCLOAK_ADMIN_PASSWORD=your-admin-password"
    echo ""
    exit 1
fi

echo ""
echo "Generating Kubernetes configuration files..."
echo ""

# Base directory for k8s manifests
K8S_DIR="infra/k8s"

# Function to generate config from template
generate_config() {
    local template_file=$1
    local output_file=$2

    # Construct the list of variables for envsubst
    local vars_string=""
    for var in "${required_vars[@]}"; do
        vars_string+="\$${var},"
    done
    # Remove trailing comma
    vars_string=${vars_string%,}

    if [ -f "$template_file" ]; then
        echo "  - $output_file"
        envsubst "$vars_string" < "$template_file" > "$output_file"
    fi
}

# Generate SPIRE configurations
echo "SPIRE:"
generate_config "$K8S_DIR/spire/namespace.template.yaml" "$K8S_DIR/spire/namespace.yaml"
generate_config "$K8S_DIR/spire/server-configmap.template.yaml" "$K8S_DIR/spire/server-configmap.yaml"
generate_config "$K8S_DIR/spire/server-rbac.template.yaml" "$K8S_DIR/spire/server-rbac.yaml"
generate_config "$K8S_DIR/spire/server-statefulset.template.yaml" "$K8S_DIR/spire/server-statefulset.yaml"
generate_config "$K8S_DIR/spire/server-service.template.yaml" "$K8S_DIR/spire/server-service.yaml"
generate_config "$K8S_DIR/spire/agent-configmap.template.yaml" "$K8S_DIR/spire/agent-configmap.yaml"
generate_config "$K8S_DIR/spire/agent-rbac.template.yaml" "$K8S_DIR/spire/agent-rbac.yaml"
generate_config "$K8S_DIR/spire/agent-daemonset.template.yaml" "$K8S_DIR/spire/agent-daemonset.yaml"
generate_config "$K8S_DIR/spire/csi-driver-rbac.template.yaml" "$K8S_DIR/spire/csi-driver-rbac.yaml"
generate_config "$K8S_DIR/spire/csi-driver.template.yaml" "$K8S_DIR/spire/csi-driver.yaml"
generate_config "$K8S_DIR/spire/csi-driver-daemonset.template.yaml" "$K8S_DIR/spire/csi-driver-daemonset.yaml"
generate_config "$K8S_DIR/spire/crds.template.yaml" "$K8S_DIR/spire/crds.yaml"

echo ""
echo "Vault:"
generate_config "$K8S_DIR/vault/serviceaccount.template.yaml" "$K8S_DIR/vault/serviceaccount.yaml"
generate_config "$K8S_DIR/vault/rbac.template.yaml" "$K8S_DIR/vault/rbac.yaml"
generate_config "$K8S_DIR/vault/configmap.template.yaml" "$K8S_DIR/vault/configmap.yaml"
generate_config "$K8S_DIR/vault/statefulset.template.yaml" "$K8S_DIR/vault/statefulset.yaml"
generate_config "$K8S_DIR/vault/service.template.yaml" "$K8S_DIR/vault/service.yaml"

echo ""
echo "Keycloak:"
generate_config "$K8S_DIR/keycloak/serviceaccount.template.yaml" "$K8S_DIR/keycloak/serviceaccount.yaml"
generate_config "$K8S_DIR/keycloak/secret.template.yaml" "$K8S_DIR/keycloak/secret.yaml"
generate_config "$K8S_DIR/keycloak/deployment.template.yaml" "$K8S_DIR/keycloak/deployment.yaml"
generate_config "$K8S_DIR/keycloak/service.template.yaml" "$K8S_DIR/keycloak/service.yaml"
generate_config "$K8S_DIR/keycloak/ingress.template.yaml" "$K8S_DIR/keycloak/ingress.yaml"

echo ""
echo "AWS Load Balancer Controller:"
generate_config "$K8S_DIR/aws-load-balancer-controller/deployment.template.yaml" "$K8S_DIR/aws-load-balancer-controller/deployment.yaml"
generate_config "$K8S_DIR/aws-load-balancer-controller/ingressclass.template.yaml" "$K8S_DIR/aws-load-balancer-controller/ingressclass.yaml"
generate_config "$K8S_DIR/aws-load-balancer-controller/rbac.template.yaml" "$K8S_DIR/aws-load-balancer-controller/rbac.yaml"
generate_config "$K8S_DIR/aws-load-balancer-controller/service.template.yaml" "$K8S_DIR/aws-load-balancer-controller/service.yaml"
generate_config "$K8S_DIR/aws-load-balancer-controller/webhook.template.yaml" "$K8S_DIR/aws-load-balancer-controller/webhook.yaml"
echo ""
echo "Cert Manager (for AWS LB):"
generate_config "$K8S_DIR/cert-manager/issuer.template.yaml" "$K8S_DIR/cert-manager/issuer.yaml"
generate_config "$K8S_DIR/cert-manager/certificate.template.yaml" "$K8S_DIR/cert-manager/certificate.yaml"

echo ""
echo "Storage:"
generate_config "$K8S_DIR/storage/storageclass.template.yaml" "$K8S_DIR/storage/storageclass.yaml"

echo ""
echo "OPA:"
generate_config "$K8S_DIR/opa/configmap.template.yaml" "$K8S_DIR/opa/configmap.yaml"

echo ""
echo "Envoy (Decoupled):"
# 1. Generate the raw envoy.yaml first from its template
generate_config "$K8S_DIR/envoy/envoy.template.yaml" "$K8S_DIR/envoy/envoy.yaml"

# 2. Generate the ConfigMap with embedded envoy.yaml content
if [ -f "$K8S_DIR/envoy/envoy.yaml" ]; then
    cat > "$K8S_DIR/envoy/envoy-config-with-opa.yaml" <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: envoy-config
  namespace: demo-apps
data:
  envoy.yaml: |
$(sed 's/^/    /' "$K8S_DIR/envoy/envoy.yaml")
EOF
    echo "  - $K8S_DIR/envoy/envoy-config-with-opa.yaml"
fi

echo ""
echo "Frontend Envoy (Egress):"
generate_config "$K8S_DIR/frontend/envoy-config.template.yaml" "$K8S_DIR/frontend/envoy-config.yaml"

echo ""
echo "Backend (with OPA):"
generate_config "$K8S_DIR/backend/serviceaccount.template.yaml" "$K8S_DIR/backend/serviceaccount.yaml"
generate_config "$K8S_DIR/backend/deployment-with-opa.template.yaml" "$K8S_DIR/backend/deployment-with-opa.yaml"

echo ""
echo "Frontend:"
generate_config "$K8S_DIR/frontend/serviceaccount.template.yaml" "$K8S_DIR/frontend/serviceaccount.yaml"
generate_config "$K8S_DIR/frontend/deployment.template.yaml" "$K8S_DIR/frontend/deployment.yaml"

echo ""
echo "✓ Configuration files generated successfully!"
echo ""
