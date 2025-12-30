# Application Deployment

This final setup phase deploys the core microservices (Frontend and Backend) along with their Zero Trust sidecars.

---

## 1. Frontend Setup

The Frontend is a React-based security dashboard that demonstrates real-time identity and access control metrics.

### Build and Push Docker Image
```bash
# Set variables
FRONTEND_ECR_REPO_NAME="${PROJECT_NAME}-frontend"
FRONTEND_ECR_IMAGE_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${FRONTEND_ECR_REPO_NAME}"

# Build and Push
docker build --platform linux/amd64 -f services/frontend/Dockerfile -t ${FRONTEND_ECR_IMAGE_URI}:latest services/frontend
docker push ${FRONTEND_ECR_IMAGE_URI}:latest
```

### Deploy Frontend
```bash
# Create the identity
kubectl apply -f infra/k8s/frontend/serviceaccount.yaml

# Deploy the application
kubectl apply -f infra/k8s/frontend/deployment.yaml
```

---

## 2. Backend Setup (Sidecar Architecture)

The Backend is the "Protected Vault." It runs with two sidecars: **Envoy** (for mTLS/SVID) and **OPA** (for authorization).

### Build and Push Docker Image
```bash

# Login to ECR
aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com

# Create ECR repository (if not exists)
aws ecr create-repository --repository-name ${BACKEND_ECR_REPO_NAME} || true

# Create ECR repository (if not exists)
aws ecr create-repository --repository-name ${FRONTEND_ECR_REPO_NAME} || true


# Set variables
BACKEND_ECR_REPO_NAME="${PROJECT_NAME}-backend"
BACKEND_ECR_IMAGE_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${BACKEND_ECR_REPO_NAME}"

# Build and Push
docker build --platform linux/amd64 -f services/backend/Dockerfile -t ${BACKEND_ECR_IMAGE_URI}:latest services/backend
docker push ${BACKEND_ECR_IMAGE_URI}:latest

# Set variables
FRONTEND_ECR_REPO_NAME="${PROJECT_NAME}-frontend"
FRONTEND_ECR_IMAGE_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${FRONTEND_ECR_REPO_NAME}"

# Build and Push
docker build --platform linux/amd64 -f services/frontend/Dockerfile -t ${FRONTEND_ECR_IMAGE_URI}:latest services/frontend
docker push ${FRONTEND_ECR_IMAGE_URI}:latest

```

### Deploy Sidecar Configurations
Before the pod can start, we must apply the configuration files that the sidecars will read.

```bash



# 1. Apply Envoy Configuration (mTLS + SDS Logic)
kubectl apply -f infra/k8s/envoy/envoy-config-with-opa.yaml

# 2. Apply OPA Policy (RBAC Rules for Alice/Bob)
kubectl apply -f infra/k8s/opa/configmap.yaml

# 3. Create the identity
kubectl apply -f infra/k8s/backend/serviceaccount.yaml

# 4. Deploy the application with sidecars
kubectl apply -f infra/k8s/backend/deployment-with-opa.yaml

# 5. Restart Deployments
kubectl rollout restart deployment backend -n demo-apps
kubectl rollout status deployment backend -n demo-apps

# Create the identity
kubectl apply -f infra/k8s/frontend/serviceaccount.yaml

# Deploy the application
kubectl apply -f infra/k8s/frontend/deployment.yaml

# Restart Deployments
kubectl rollout restart deployment frontend -n demo-apps
kubectl rollout status deployment frontend -n demo-apps

# Frontend port forward
kubectl port-forward -n demo-apps svc/frontend 8000:80
lsof -ti:8000

```

---

## 3. Verification

Once deployed, you should see three containers running inside each backend pod:

```bash
kubectl get pods -n demo-apps
```

**Wait for Ready status: `3/3` containers running.**
The three containers are:
1. `backend`: The Node.js application.
2. `envoy`: The security data plane.
3. `opa`: The policy decision engine.

---

## 4. Access the Dashboard

To view the Zero Trust Dashboard and test identity headers:

```bash
# Port-forward the frontend service
kubectl port-forward -n demo-apps svc/frontend 8080:80
```

**Open in your browser:** [http://localhost:8080](http://localhost:8080)
- Login with Alice (`alice` / `alice123`) to see confidential documents.
- Login with Bob (`bob` / `bob123`) to see only public documents.
- Check the **Identity Debug Panel** to see the SPIFFE ID being passed as `x-forwarded-client-cert`.