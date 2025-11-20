# DotStat Suite Kubernetes Setup

!!Note: this is still in development so it might not be perfect. It is however a great way to get started with the dotstatsuite. I would also like to thank the folks at SIS-CC for developing the dotstatsuite. For reference, the original repository is located [here](https://gitlab.com/sis-cc/.stat-suite). 

This directory contains Kubernetes manifests for deploying the DotStat Suite.

## Prerequisites

- Docker installed and running
- kubectl installed
- k3d installed (for local development)
- Config data available in `./config-data/` (included in this directory)

## Setting up a Local k3d Cluster

### Install k3d (if not already installed)

```bash
# Linux/macOS
wget -q -O - https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash

# Or using brew
brew install k3d

# Verify installation
k3d version
```

### Create the k3d Cluster

```bash
# Create a cluster named 'dotstat' with a single server node
k3d cluster create dotstat \
  --servers 1 \
  --agents 0 \
  --port "80:80@loadbalancer" \
  --port "443:443@loadbalancer"

# Verify cluster is running
kubectl cluster-info
kubectl get nodes
```

### Configure /etc/hosts

Add entries for the DotStat services to access them via domain names:

```bash
sudo tee -a /etc/hosts << EOF
127.0.0.1 explorer.local
127.0.0.1 lifecycle.local
127.0.0.1 keycloak.local
127.0.0.1 nsi.local
127.0.0.1 transfer.local
127.0.0.1 auth.local
127.0.0.1 sfs.local
127.0.0.1 maildev.local
EOF
```

Additionally, add these values to the Windows Hosts file if applicable for WSL systems:

```
127.0.0.1 config.local keycloak.local explorer.local lifecycle.local sfs.local nsi.local mongo.local maildev.local auth.local
127.0.0.1 viewer.local
127.0.0.1 share.local
127.0.0.1 transfer.local
```

### Delete the Cluster (when done)

```bash
k3d cluster delete dotstat
```

## Initial Setup

### 1. Create namespace and apply base resources

```bash
./deploy-all.sh
```

### 2. Initialize database schemas (if not run with `deploy-all.sh`)

```bash
# Run database initialization jobs
kubectl apply -f jobs/dbup-common.yaml
kubectl apply -f jobs/dbup-data.yaml
kubectl apply -f jobs/dbup-mapping.yaml

# Wait for jobs to complete
kubectl wait --for=condition=complete job/dbup-common -n dotstat --timeout=300s
kubectl wait --for=condition=complete job/dbup-data -n dotstat --timeout=300s
kubectl wait --for=condition=complete job/dbup-mapping -n dotstat --timeout=300s
```

Login with admin credentials (default: `admin` / `P@ssw0rd!`)

Import the realm:
1. Go to realm dropdown → Create realm
2. Click "Browse" and select `demo-realm/keycloak-demo-realm.json`
3. Click "Create"

**Important**: After importing, go to **Clients** → **stat-suite** → **Settings** and ensure **Client authentication** is set to **OFF** (public client).

### 3. Verify deployment

```bash
# Check all pods are running
kubectl get pods -n dotstat

# Check ingresses
kubectl get ingress -n dotstat
```

## Accessing the Applications

Add the following entries to your `/etc/hosts`:

```
127.0.0.1 explorer.local
127.0.0.1 lifecycle.local
127.0.0.1 keycloak.local
127.0.0.1 nsi.local
127.0.0.1 transfer.local
127.0.0.1 auth.local
127.0.0.1 sfs.local
127.0.0.1 maildev.local
```

Then access:
- Data Explorer: http://explorer.local
- Lifecycle Manager: http://lifecycle.local
- Keycloak: http://keycloak.local

## Default Credentials

- **Keycloak Admin**: `admin` / `P@ssw0rd!`
- **Demo User**: `test-admin` / (password set during realm import or reset via Keycloak admin console)

## Troubleshooting

### Assets not loading (404 errors for images/styles)

If you see 404 errors for assets in `/assets/siscc/`, ensure you've copied the assets as described in step 3.

### Content decoding errors for JavaScript files

The init containers in data-explorer and lifecycle-manager deployments automatically remove problematic `.br` (Brotli) files on startup. If you still see issues, restart the deployments:

```bash
kubectl rollout restart deployment/data-explorer -n dotstat
kubectl rollout restart deployment/lifecycle-manager -n dotstat
```

### Authentication errors

Ensure the `stat-suite` client in Keycloak is configured as a public client (Client authentication = OFF).

## Configuration

- **Secrets**: Modify `config/config-and-secrets.yaml` to change passwords and API keys
- **Ingress hosts**: Modify files in `ingress/` to change domain names
- **Keycloak realm**: Modify `demo-realm/keycloak-demo-realm.json` before importing

## Clean Up

```bash
# Delete all resources
kubectl delete namespace dotstat

# Note: Persistent volumes may need to be manually deleted depending on storage class
```
