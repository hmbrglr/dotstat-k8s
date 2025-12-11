# DotStat Suite Kubernetes Setup

This directory contains Kubernetes manifests for deploying the DotStat Suite.

## Prerequisites

- Docker installed and running
- kubectl installed
- k3d installed (for local development)
- Config data available in `./config-data/` (included in this directory)

## Setting up a Local k3d Cluster

### 1. Install k3d (if not already installed)

```bash
# Linux/macOS/WSL (Please note that on MacOS the SQL Server container image does not work. You will need to use `mcr.microsoft.com/azure-sql-edge:latest` because that only supports arm64)
wget -q -O - https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash

# Or using brew
brew install k3d

# Verify installation
k3d version
```

### 2. Start the Cluster

Use the provided script to create the cluster with the correct volume mappings for persistence:

```bash
./start-cluster.sh
```

This script creates a cluster named `dotstat` and maps `$HOME/dotstat-data` on your host to `/var/lib/dotstat` in the container.

### 3. Configure /etc/hosts

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

### 4. Delete the Cluster (when done)

```bash
k3d cluster delete dotstat
```

## Initial Setup & Deployment

The `deploy-all.sh` script handles the entire deployment process, including:
1. Creating the namespace
2. Applying storage and config
3. Deploying infrastructure (databases, Keycloak, Solr)
4. Initializing databases and granting permissions
5. Copying assets
6. Deploying applications and ingress

### 1. Run the deployment script

```bash
./deploy-all.sh
```

### 2. Import Keycloak realm

This step is still manual. Access the Keycloak admin console:

```bash
# Option 1: Via ingress (if configured)
# Open http://keycloak.local in your browser

# Option 2: Via port-forward
kubectl port-forward -n dotstat svc/keycloak 8080:8080
# Then open http://localhost:8080
```

Login with admin credentials (default: `admin` / `P@ssw0rd!`)

Import the realm:
1. Go to realm dropdown -> Create realm
2. Click "Browse" and select `demo-realm/keycloack-demo-realm.json`
3. Click "Create"

**Important**: After importing, go to **Clients** -> **stat-suite** -> **Settings** and ensure **Client authentication** is set to **OFF** (public client).

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

If you see 404 errors for assets in `/assets/siscc/`, the `init-assets` job may have failed or the volume mapping might be incorrect.
Check the logs of the asset initialization job:
```bash
kubectl logs job/init-assets -n dotstat
```
You can also manually copy assets if needed:
```bash
kubectl cp ./config-data/assets/siscc dotstat/$(kubectl get pod -n dotstat -l app=config-server -o jsonpath='{.items[0].metadata.name}'):/app/data/assets/
```

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
