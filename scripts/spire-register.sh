#!/bin/bash
set -e

SPIRE_SERVER_POD=$(kubectl get pod -n spire-system -l app=spire-server -o jsonpath='{.items[0].metadata.name}')

echo "Registering workloads in SPIRE..."
echo "SPIRE Server Pod: $SPIRE_SERVER_POD"
echo ""

# Backend service
echo "→ Registering backend service..."
kubectl exec -n spire-system $SPIRE_SERVER_POD -c spire-server -- \
  /opt/spire/bin/spire-server entry create \
  -socketPath /run/spire/data/server.sock \
  -spiffeID spiffe://zero-trust.local/backend \
  -parentID spiffe://zero-trust.local/ns/spire-system/sa/spire-agent \
  -selector k8s:ns:demo-apps \
  -selector k8s:sa:backend-service \
  -dns backend \
  -dns backend.demo-apps \
  -dns backend.demo-apps.svc.cluster.local

echo "✓ Backend service registered"
echo ""

# Frontend service
echo "→ Registering frontend service..."
kubectl exec -n spire-system $SPIRE_SERVER_POD -c spire-server -- \
  /opt/spire/bin/spire-server entry create \
  -socketPath /run/spire/data/server.sock \
  -spiffeID spiffe://zero-trust.local/frontend \
  -parentID spiffe://zero-trust.local/ns/spire-system/sa/spire-agent \
  -selector k8s:ns:demo-apps \
  -selector k8s:sa:frontend-service \
  -dns frontend \
  -dns frontend.demo-apps \
  -dns frontend.demo-apps.svc.cluster.local

echo "✓ Frontend service registered"
echo ""

# List all entries
echo "→ Listing all SPIRE entries..."
kubectl exec -n spire-system $SPIRE_SERVER_POD -c spire-server -- \
  /opt/spire/bin/spire-server entry show \
  -socketPath /run/spire/data/server.sock

echo ""
echo "✓ SPIRE registration complete!"
