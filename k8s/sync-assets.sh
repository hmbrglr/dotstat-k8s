#!/bin/bash
set -e

echo "Syncing assets to k3d container..."

# Copy assets from local config-data to k3d container's hostPath
docker cp config-data/assets k3d-dotstat-server-0:/var/lib/dotstat/config-data/

echo "Assets synced successfully!"
echo ""
echo "Restarting application pods to pick up assets..."
kubectl rollout restart deployment/data-explorer deployment/lifecycle-manager deployment/data-viewer -n dotstat

echo ""
echo "Waiting for pods to be ready..."
kubectl wait --for=condition=ready pod -l app=data-explorer -n dotstat --timeout=60s
kubectl wait --for=condition=ready pod -l app=lifecycle-manager -n dotstat --timeout=60s
kubectl wait --for=condition=ready pod -l app=data-viewer -n dotstat --timeout=60s

echo ""
echo "Assets synced and applications restarted!"
echo "You can now access:"
echo "  - Data Explorer: http://explorer.local"
echo "  - Lifecycle Manager: http://lifecycle.local"
