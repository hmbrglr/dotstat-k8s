#!/bin/bash
set -e

CLUSTER_NAME="dotstat"
# Use a directory in the user's home for persistence
HOST_DATA_DIR="$HOME/dotstat-data"
CONTAINER_DATA_DIR="/var/lib/dotstat"

# Ensure host data directory exists
mkdir -p "$HOST_DATA_DIR"
echo "Data directory: $HOST_DATA_DIR"

# Check if cluster exists
if k3d cluster list | grep -q "$CLUSTER_NAME"; then
    echo "Cluster '$CLUSTER_NAME' exists."
    # Check if it's running
    if ! k3d cluster list | grep "$CLUSTER_NAME" | grep -q "running"; then
        echo "Starting cluster '$CLUSTER_NAME'..."
        k3d cluster start "$CLUSTER_NAME"
    else
        echo "Cluster '$CLUSTER_NAME' is already running."
    fi
else
    echo "Creating cluster '$CLUSTER_NAME' with volume mapping..."
    k3d cluster create "$CLUSTER_NAME" \
      --servers 1 \
      --agents 0 \
      --port "80:80@loadbalancer" \
      --port "443:443@loadbalancer" \
      --volume "$HOST_DATA_DIR:$CONTAINER_DATA_DIR@server:0" \
      --wait
      
    echo "Cluster created."
fi

echo "Cluster is ready. You can now apply manifests."
