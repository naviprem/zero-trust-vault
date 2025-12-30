# SPIRE Setup

This phase establishes the **Machine Identity** of your microservices and connects it to your **Secrets Management** layer.

**Components:**
- **SPIRE Server v1.14.0**: The trust authority that issues identities
- **SPIRE Agent v1.14.0**: DaemonSet that provides workload attestation
- **OIDC Discovery Provider v1.14.0**: Sidecar that enables JWT verification by Vault

**Important:** SPIRE 1.14.0+ requires using the gRPC Workload API via the `spire-agent` CLI tool. The HTTP/1.x REST endpoint has been removed.

---

## Step 1: Deploy SPIRE Infrastructure

Before registering workloads, we must deploy the SPIRE Server (the "Cerebellum") and the SPIRE Agents (the "Nervous System").

### 1.1 Deploy Namespace and CRDs
```bash
# Create namespace
kubectl apply -f infra/k8s/spire/namespace.yaml

# Apply CRDs
kubectl apply -f infra/k8s/spire/crds.yaml

# Create the trust bundle ConfigMap (must exist before SPIRE starts)
kubectl create configmap spire-bundle -n spire-system --from-literal=bundle.crt="" 2>/dev/null || true
```

### 1.2 Deploy Server and Agents
```bash
# Apply RBAC and ConfigMaps
kubectl apply -f infra/k8s/spire/server-rbac.yaml
kubectl apply -f infra/k8s/spire/agent-rbac.yaml
kubectl apply -f infra/k8s/spire/server-configmap.yaml
kubectl apply -f infra/k8s/spire/agent-configmap.yaml

# Deploy SPIRE Server (StatefulSet)
kubectl apply -f infra/k8s/spire/server-statefulset.yaml
kubectl apply -f infra/k8s/spire/server-service.yaml

# Deploy SPIRE Agent (DaemonSet)
kubectl apply -f infra/k8s/spire/agent-daemonset.yaml

# Wait for components to be ready
kubectl wait --for=condition=ready --timeout=120s -n spire-system pod -l app=spire-server
kubectl wait --for=condition=ready --timeout=120s -n spire-system pod -l app=spire-agent
```

---

## Step 2: Establish the Trust Plumbing

### Install SPIFFE CSI Driver

The SPIFFE CSI Driver is responsible for securely mounting the SPIRE Agent's Unix Domain Socket into our pods.

```bash
# Apply local SPIFFE CSI Driver manifests
kubectl apply -f infra/k8s/spire/csi-driver-rbac.yaml
kubectl apply -f infra/k8s/spire/csi-driver.yaml
kubectl apply -f infra/k8s/spire/csi-driver-daemonset.yaml

# Verify installation
kubectl get daemonset -n spire-system spire-csi-driver
```

## SPIRE Workload Registration

Workload registration is the process of telling SPIRE: *"If you see a pod with these specific characteristics, give it this specific SPIFFE ID."*

### The Registration Logic (Deep Dive)
When you register a service, you are defining:
*   **SPIFFE ID**: The cryptographic name of the service (e.g., `spiffe://zero-trust.local/backend`).
*   **Selectors**: The criteria for verification. We use `k8s:ns:demo-apps` and `k8s:sa:backend-service`. This means only a pod in the correct namespace with the correct ServiceAccount can claim this identity.

### Automated Registration
Instead of manually exec-ing into the server, use the provided helper script to register both the Frontend and Backend services at once.

```bash
# Ensure the script is executable
chmod +x scripts/spire-register.sh

# Run the registration
./scripts/spire-register.sh
```

**Success Verification:**
The script will list all entries at the end. You should see entries for both `backend` and `frontend`.

**Note:**
In this demo, we kept it simple with two selectors (Namespace and ServiceAccount). In production, you add DNA-level selectors to the registration:

```bash
# Production SPIRE registration entry
    -selector k8s:ns:demo-apps
    -selector k8s:sa:backend-service
    -selector k8s:container-image:<account-id>.dkr.ecr.us-east-1.amazonaws.com/<image-name>:<tag>
    -selector k8s:pod-label:app:production-backend
```
