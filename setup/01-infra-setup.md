# Comprehensive Zero Trust Vault Setup Guide

This guide includes all lessons learned from troubleshooting to ensure a smooth deployment.

## Prerequisites

1. AWS CLI configured with appropriate credentials
2. kubectl installed and configured
3. eksctl installed
4. Terraform installed (if using Terraform for infrastructure)
5. Make sure you have admin access to your AWS account

## Step 1: AWS Authentication

```bash
# Login to AWS SSO
make aws-login

# Export AWS credentials
eval $(make aws-export)
```

## Step 2: Deploy EKS Cluster with Terraform

```bash
cd infra/terraform

# Initialize Terraform
terraform init

# Plan the deployment
terraform plan

# Apply the configuration
terraform apply

# Get cluster credentials
aws eks update-kubeconfig --name zero-trust-cluster --region us-east-1 --profile $AWS_PROFILE
```

## Create Namespaces

```bash
# Create namespaces
kubectl create namespace zero-trust-infra
kubectl create namespace demo-apps
kubectl create namespace spire-system

# Label namespaces
kubectl label namespace zero-trust-infra name=zero-trust-infra
kubectl label namespace demo-apps name=demo-apps
kubectl label namespace spire-system name=spire-system


# Verify
kubectl get namespaces --show-labels
```

## Step 3: Install Required EKS Addons

### 3.1 Install EBS CSI Driver

The EBS CSI driver is required for persistent volume provisioning:

```bash
# Delete the EBS CSI driver even if it is not installed but the CloudFormation stack exists
aws cloudformation delete-stack --stack-name eksctl-zero-trust-cluster-addon-aws-ebs-csi-driver \
--profile $AWS_PROFILE --region us-east-1

# Create IAM service account and install addon
eksctl create addon \
  --name aws-ebs-csi-driver \
  --cluster zero-trust-cluster \
  --profile $AWS_PROFILE

# Wait for addon to be ready (takes ~2 minutes)
kubectl wait --for=condition=available --timeout=300s -n kube-system deployment/ebs-csi-controller

# Verify EBS CSI driver is running
kubectl -n kube-system get pods | grep ebs-csi

# Create gp2-csi storage class
kubectl apply -f infra/k8s/storage/storageclass.yaml

# Set gp2-csi as default storage class
kubectl patch storageclass gp2-csi -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
kubectl patch storageclass gp2 -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'
```

### 3.2 Install AWS Load Balancer Controller CRDs

```bash
# Install CRDs first
kubectl apply -f https://raw.githubusercontent.com/aws/eks-charts/master/stable/aws-load-balancer-controller/crds/crds.yaml
```

## Step 4: Install cert-manager

The `cert-manager` is the automated "Security Plumber" for the cluster. It is required by the AWS Load Balancer Controller to manage certificates for its internal webhooks.

```bash
# Install cert-manager components
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.3/cert-manager.yaml

# Wait for cert-manager to be fully ready
kubectl wait --for=condition=available --timeout=300s -n cert-manager \
  deployment/cert-manager \
  deployment/cert-manager-webhook \
  deployment/cert-manager-cainjector

# Verify pods are running
kubectl get pods -n cert-manager
```

## Step 5: Get VPC ID

You'll need the VPC ID for the AWS Load Balancer Controller:

```bash
# Get VPC ID from EKS cluster
export AWS_VPC_ID=$(aws eks describe-cluster --name zero-trust-cluster --query 'cluster.resourcesVpcConfig.vpcId' --output text --profile $AWS_PROFILE)

echo "VPC ID: $AWS_VPC_ID"
```

## Step 6: Set Environment Variables

# Copy the VPC id from the output of the previous step to makefile
# Export AWS credentials
```bash
eval $(make aws-export)
```

## Step 7: Generate Kubernetes Manifests

```bash
# Generate all manifests from templates
./scripts/generate-configs.sh

# Verify manifests were generated
ls -la infra/k8s/**/*.yaml | grep -v template
```

## Step 8: Deploy AWS Load Balancer Controller

```bash
# Delete service account cloud formation stacks if they exist

# Create service accounts
eksctl create iamserviceaccount \
  --cluster=$EKS_CLUSTER_NAME \
  --namespace=kube-system \
  --name=$LB_SA_NAME \
  --attach-policy-arn=$LB_POLICY_ARN \
  --override-existing-serviceaccounts \
  --region us-east-1 \
  --approve

eksctl create iamserviceaccount \
    --cluster=$EKS_CLUSTER_NAME \
    --namespace=kube-system \
    --name=$EBS_SA_NAME \
    --attach-policy-arn=$EBS_POLICY_ARN \
    --override-existing-serviceaccounts \
    --region us-east-1 \
    --approve

# Create certificate for webhook
kubectl apply -f infra/k8s/cert-manager/issuer.yaml
kubectl apply -f infra/k8s/cert-manager/certificate.yaml

# Wait for certificate to be ready
kubectl wait --for=condition=ready --timeout=60s -n kube-system certificate/aws-load-balancer-serving-cert

# Apply all AWS Load Balancer Controller manifests
kubectl apply -f infra/k8s/aws-load-balancer-controller/rbac.yaml
kubectl apply -f infra/k8s/aws-load-balancer-controller/service.yaml
kubectl apply -f infra/k8s/aws-load-balancer-controller/webhook.yaml
kubectl apply -f infra/k8s/aws-load-balancer-controller/ingressclass.yaml

# Deploy the controller
kubectl apply -f infra/k8s/aws-load-balancer-controller/deployment.yaml

# Verify controller is running
kubectl -n kube-system get deployment aws-load-balancer-controller
kubectl -n kube-system get pods -l app.kubernetes.io/name=aws-load-balancer-controller
```

## Step 9: Deploy SPIRE

```bash
# Create namespace
kubectl apply -f infra/k8s/spire/namespace.yaml

# Apply CRDs
kubectl apply -f infra/k8s/spire/crds.yaml

# Create bundle ConfigMap (required by SPIRE server)
kubectl create configmap spire-bundle -n spire-system --from-literal=bundle.crt=""

# Apply RBAC
kubectl apply -f infra/k8s/spire/server-rbac.yaml
kubectl apply -f infra/k8s/spire/agent-rbac.yaml

# Apply ConfigMaps
kubectl apply -f infra/k8s/spire/server-configmap.yaml
kubectl apply -f infra/k8s/spire/agent-configmap.yaml

# Deploy SPIRE Server
kubectl apply -f infra/k8s/spire/server-statefulset.yaml
kubectl apply -f infra/k8s/spire/server-service.yaml

# Wait for SPIRE server to be ready
kubectl wait --for=condition=ready --timeout=120s -n spire-system pod -l app=spire-server

# Deploy SPIRE Agent
kubectl apply -f infra/k8s/spire/agent-daemonset.yaml

# Wait for agents to be ready
kubectl wait --for=condition=ready --timeout=120s -n spire-system pod -l app=spire-agent

# Deploy SPIRE CSI Driver
kubectl apply -f infra/k8s/spire/csi-driver-rbac.yaml
kubectl apply -f infra/k8s/spire/csi-driver.yaml
kubectl apply -f infra/k8s/spire/csi-driver-daemonset.yaml

# Wait for CSI driver to be ready
kubectl wait --for=condition=ready --timeout=120s -n spire-system pod -l app=spire-csi-driver

# Verify SPIRE deployment
kubectl -n spire-system get pods
```

## Step 10: Deploy Vault

```bash
# Apply Vault components
kubectl apply -f infra/k8s/vault/serviceaccount.yaml
kubectl apply -f infra/k8s/vault/rbac.yaml
kubectl apply -f infra/k8s/vault/configmap.yaml
kubectl apply -f infra/k8s/vault/statefulset.yaml
kubectl apply -f infra/k8s/vault/service.yaml

# Wait for Vault to be ready
kubectl wait --for=condition=ready --timeout=120s -n zero-trust-infra pod -l app.kubernetes.io/name=vault

# Verify Vault is running
kubectl -n zero-trust-infra get pods -l app.kubernetes.io/name=vault
kubectl -n zero-trust-infra logs vault-0 --tail=20
```

## Step 11: Deploy Keycloak

```bash
# Apply Keycloak components
kubectl apply -f infra/k8s/keycloak/serviceaccount.yaml
kubectl apply -f infra/k8s/keycloak/secret.yaml
kubectl apply -f infra/k8s/keycloak/deployment.yaml
kubectl apply -f infra/k8s/keycloak/service.yaml
kubectl apply -f infra/k8s/keycloak/ingress.yaml

# Wait for Keycloak to be ready (this takes 2-3 minutes)
kubectl wait --for=condition=ready --timeout=300s -n zero-trust-infra pod -l app.kubernetes.io/name=keycloak

# Get ingress URL
kubectl -n zero-trust-infra get ingress keycloak

# Verify Keycloak deployment
kubectl -n zero-trust-infra get pods -l app.kubernetes.io/name=keycloak
kubectl -n zero-trust-infra logs -l app.kubernetes.io/name=keycloak --tail=20
```



## Step 12: Verify All Components

```bash
# Check all pods in spire-system namespace
kubectl -n spire-system get pods

# Check all pods in zero-trust-infra namespace
kubectl -n zero-trust-infra get pods

# Check services
kubectl -n spire-system get svc
kubectl -n zero-trust-infra get svc

# Check ingress
kubectl -n zero-trust-infra get ingress

# Check PVCs
kubectl -n spire-system get pvc
kubectl -n zero-trust-infra get pvc
```

## Troubleshooting Tips

### EBS CSI Driver Issues

If PVCs are stuck in Pending:
- Ensure EBS CSI driver pods are running: `kubectl -n kube-system get pods | grep ebs-csi`
- Check EBS CSI controller logs: `kubectl -n kube-system logs deployment/ebs-csi-controller -c csi-provisioner`
- Verify IAM role is properly configured with the service account

### AWS Load Balancer Controller Issues

If pods are crash looping:
- Ensure CRDs are installed: `kubectl get crd | grep elbv2`
- Check if cert-manager is running: `kubectl -n cert-manager get pods`
- Verify webhook certificate exists: `kubectl -n kube-system get certificate`
- Check VPC ID is correct in deployment args

### SPIRE Issues

If SPIRE server is crash looping:
- Ensure spire-bundle ConfigMap exists: `kubectl -n spire-system get configmap spire-bundle`
- Check PVC is bound: `kubectl -n spire-system get pvc`
- Verify fsGroup securityContext is set correctly

### Vault Issues

If Vault is failing with "address already in use":
- Ensure listener configuration is not duplicated in configmap for dev mode
- Check if VAULT_DEV_LISTEN_ADDRESS env var matches listener config

### Keycloak Issues

If Keycloak keeps restarting:
- **Health probe 404 errors**: In Keycloak 25+, health endpoints are on the management port (9000), not the main HTTP port (8080). Update probes to use port 9000.
- Increase liveness/readiness probe initialDelaySeconds (120s/90s recommended) - Keycloak takes time to rebuild on first start
- Remove unsupported flags like `--hostname-strict-https` (not available in Keycloak 25+)
- Ensure RDS database is accessible and credentials are correct
- Check resource limits are sufficient (1CPU/1Gi RAM minimum)
- First startup takes 2-3 minutes as Keycloak rebuilds the server image

## Cleanup

When you're done testing:

```bash
# Delete Kubernetes resources
kubectl delete namespace spire-system
kubectl delete namespace zero-trust-infra

# Delete EKS cluster with Terraform
cd infra/terraform
terraform destroy

# Or using eksctl
eksctl delete cluster --name zero-trust-cluster --profile $AWS_PROFILE
```

## Key Lessons Learned

1. **Storage**: EKS requires EBS CSI driver addon for PVC provisioning - the in-tree provisioner is deprecated
2. **Cert-manager**: Required for AWS Load Balancer Controller webhook certificates
3. **VPC ID**: Must be explicitly provided to AWS Load Balancer Controller when EC2 metadata is not accessible
4. **SPIRE Bundle**: The spire-bundle ConfigMap must exist before SPIRE server starts
5. **Security Context**: Use fsGroup for volume permissions instead of init containers with chmod
6. **Keycloak Startup**: First run rebuilds the server image, which takes time - increase probe delays accordingly
7. **Keycloak Health Probes**: In Keycloak 25+, health endpoints (/health/live, /health/ready) are on port 9000 (management interface), not port 8080
8. **Vault Dev Mode**: Don't duplicate listener configuration when running in dev mode
9. **Init Containers**: Distroless images don't have /bin/sh - use busybox or remove unnecessary init containers
10. **Keycloak Arguments**: Remove deprecated flags like `--hostname-strict-https` which don't exist in Keycloak 25+

## Next Steps

After all components are running:
1. Configure SPIRE to issue identities to workloads
2. Initialize and unseal Vault (if not in dev mode)
3. Configure Keycloak realms and clients
4. Set up integration between SPIRE, Vault, and Keycloak
5. Deploy your applications with SPIFFE identities
