#!/bin/bash
set -e

NAMESPACE="dotstat"

echo "--- Starting DotStat Suite Deployment ---"

# 1. Create Namespace
echo "[1/7] Creating namespace..."
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

# 2. Storage & Config
echo "[2/7] Applying storage and configuration..."
kubectl apply -f storage/
kubectl apply -f config/

# 3. Infrastructure
echo "[3/7] Deploying infrastructure (Databases, Keycloak, Solr)..."
kubectl apply -f deployments/infra.yaml

echo "Waiting for SQL Server and Keycloak to be ready..."
kubectl wait --for=condition=ready pod -l app=sqlserver -n $NAMESPACE --timeout=300s
kubectl wait --for=condition=ready pod -l app=keycloak -n $NAMESPACE --timeout=300s

# 4. Database Initialization
echo "[4/7] Running database initialization jobs..."
# Delete old jobs to ensure they re-run
kubectl delete job dbup-common dbup-data dbup-mapping -n $NAMESPACE --ignore-not-found
kubectl apply -f jobs/dbup-common.yaml
kubectl apply -f jobs/dbup-data.yaml
kubectl apply -f jobs/dbup-mapping.yaml

echo "Waiting for DB init jobs to complete..."
kubectl wait --for=condition=complete job/dbup-common -n $NAMESPACE --timeout=300s
kubectl wait --for=condition=complete job/dbup-data -n $NAMESPACE --timeout=300s
kubectl wait --for=condition=complete job/dbup-mapping -n $NAMESPACE --timeout=300s

# 4.1 Grant Permissions (Required for NSI to create tables)
echo "[4.1/7] Granting permissions..."
kubectl delete job grant-permissions -n $NAMESPACE --ignore-not-found
kubectl apply -f jobs/grant-permissions.yaml
kubectl wait --for=condition=complete job/grant-permissions -n $NAMESPACE --timeout=60s

# 5. Asset Initialization
echo "[5/7] Initializing assets..."
kubectl delete job init-assets -n $NAMESPACE --ignore-not-found
kubectl apply -f jobs/init-assets.yaml
# We don't strictly need to wait for this as apps will just 404 until it's done, but it's cleaner to wait.
kubectl wait --for=condition=complete job/init-assets -n $NAMESPACE --timeout=60s || echo "Asset init job timed out or failed, check logs. Continuing..."

# 6. Applications
echo "[6/7] Deploying applications..."
kubectl apply -f deployments/apps.yaml

# 7. Ingress
echo "[7/7] Configuring ingress..."
kubectl apply -f ingress/

echo "--- Deployment Complete! ---"
echo "Access the services at:"
echo "- Data Explorer: http://explorer.local"
echo "- Lifecycle Manager: http://lifecycle.local"
echo "- Keycloak: http://keycloak.local"
