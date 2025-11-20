# DotStat Suite Kubernetes Setup

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
# Create namespace
kubectl create namespace dotstat

# Apply storage, config, and secrets
kubectl apply -f storage/
kubectl apply -f config/

# Apply infrastructure (databases, keycloak, etc.)
kubectl apply -f deployments/infra.yaml

# Wait for databases to be ready
kubectl wait --for=condition=ready pod -l app=sqlserver -n dotstat --timeout=300s
kubectl wait --for=condition=ready pod -l app=keycloak -n dotstat --timeout=300s
```

### 2. Initialize database schemas

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

### 3. Copy assets to persistent storage

The config-data assets need to be copied into the persistent volume:

```bash
kubectl cp ./config-data/assets/siscc dotstat/$(kubectl get pod -n dotstat -l app=config-server -o jsonpath='{.items[0].metadata.name}'):/app/data/assets/
```

### 4. Import Keycloak realm

Access the Keycloak admin console:

```bash
# Option 1: Via ingress (if configured)
# Open http://keycloak.local in your browser

# Option 2: Via port-forward
kubectl port-forward -n dotstat svc/keycloak 8080:8080
# Then open http://localhost:8080
```

Login with admin credentials (default: `admin` / `P@ssw0rd!`)

Import the realm:
1. Go to realm dropdown → Create realm
2. Click "Browse" and select `demo-realm/keycloack-demo-realm.json`
3. Click "Create"

**Important**: After importing, go to **Clients** → **stat-suite** → **Settings** and ensure **Client authentication** is set to **OFF** (public client).

### 5. Deploy applications

```bash
# Deploy application services
kubectl apply -f deployments/apps.yaml

# Apply ingress rules
kubectl apply -f ingress/
```

### 6. Verify deployment

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
- **Keycloak realm**: Modify `demo-realm/keycloack-demo-realm.json` before importing

## Clean Up

```bash
# Delete all resources
kubectl delete namespace dotstat

# Note: Persistent volumes may need to be manually deleted depending on storage class
```
