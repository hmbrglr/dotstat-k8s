# DotStat Suite: Docker Compose to Kubernetes Migration Notes

This document outlines the changes, fixes, and configurations required to migrate from the docker-compose setup to Kubernetes.

## Overview

The DotStat Suite was successfully migrated from Docker Compose to Kubernetes (k3d). The core functionality is working including authentication, data browsing, and data import. Search functionality requires additional configuration (see Known Issues).

## Key Differences from Docker Compose

### 1. Service Discovery & Networking

**Docker Compose:**
- Services communicate using service names directly (e.g., `http://keycloak:8080`)
- Automatic DNS resolution within the compose network

**Kubernetes:**
- Services use ClusterIP services for internal communication
- DNS format: `servicename.namespace.svc.cluster.local`
- External access via Ingress with custom domains (*.local)

### 2. Storage

**Docker Compose:**
- Volumes mounted directly from host filesystem
- Config data at `./config-data` (sibling to compose.yaml)

**Kubernetes:**
- PersistentVolumeClaims (PVCs) for databases and config-data
- Config data at `./config-data` (within k8s directory)
- Assets must be manually copied into PVC after initial deployment
- Local path provisioner used for k3d

### 3. Configuration Management

**Docker Compose:**
- Environment variables in `.env` file
- Loaded automatically by compose

**Kubernetes:**
- ConfigMaps for non-sensitive configuration
- Secrets for passwords, API keys, and database credentials
- Environment variables injected via `valueFrom` references

## Issues Encountered & Fixes Applied

### Issue 1: Brotli Content Encoding Errors

**Problem:**
- Frontend applications (data-explorer, lifecycle-manager) serve pre-compressed `.br` (Brotli) files
- Browser received `Content-Encoding: br` header but couldn't decode the content
- Error: `net::ERR_CONTENT_DECODING_FAILED`

**Root Cause:**
- The Node.js static file server automatically serves `.br` files when they exist
- Traefik ingress and middleware weren't properly handling content encoding headers

**Solution:**
1. Added middleware to strip `Content-Encoding` header:
   ```yaml
   apiVersion: traefik.io/v1alpha1
   kind: Middleware
   metadata:
     name: no-encoding
   spec:
     headers:
       customRequestHeaders:
         Accept-Encoding: ""
       customResponseHeaders:
         Content-Encoding: ""
   ```

2. Added postStart lifecycle hooks to deployments to remove `.br` files after container starts:
   ```yaml
   containers:
     - name: data-explorer
       image: siscc/dotstatsuite-data-explorer:causality
       lifecycle:
         postStart:
           exec:
             command: ["/bin/sh", "-c", "rm -f /opt/build/static/js/*.br || true"]
   ```
   
   **Note:** Initial implementation used init containers, but these run before the container filesystem is populated. PostStart hooks run after the container starts, ensuring `.br` files from the image are removed.

### Issue 2: Keycloak Authentication Failures

**Problem:**
- Applications showed login dialog but authentication failed
- Error: `unauthorized_client - Invalid client or Invalid client credentials`

**Root Cause:**
- Keycloak realm configuration had `stat-suite` client set as public client (`"publicClient": true`) but also defined a client secret
- This contradiction caused authentication to fail

**Solution:**
1. Removed client secret from realm JSON configuration
2. Configured client as truly public in Keycloak admin console:
   - Clients → stat-suite → Settings
   - Set "Client authentication" to OFF

**Note:** Public clients don't use secrets as they run in browsers where secrets cannot be kept secure.

### Issue 3: Missing Assets (404 Errors)

**Problem:**
- Images, CSS, logos not loading in data-explorer and lifecycle-manager
- 404 errors for `/assets/siscc/data-explorer/images/*`

**Root Cause:**
- Assets directory in PVC was empty
- Config-data was mounted but assets weren't copied during deployment

**Solution:**
Manual copy command required after deployment:
```bash
kubectl cp ./config-data/assets/siscc \
  dotstat/$(kubectl get pod -n dotstat -l app=config-server -o jsonpath='{.items[0].metadata.name}'):/app/data/assets/
```

### Issue 4: Database Login Failures

**Problem:**
- NSI service couldn't connect to databases
- Error: `Login failed for user 'common'`

**Root Cause:**
- SQL Server logins (common, data, mapping) weren't created during initial dbup job execution

**Solution:**
1. Re-ran database initialization jobs to create logins
2. Granted proper permissions to database users:
   ```sql
   USE [dotstat-mapping];
   ALTER ROLE db_ddladmin ADD MEMBER [mapping];
   ALTER ROLE db_datawriter ADD MEMBER [mapping];
   ALTER ROLE db_datareader ADD MEMBER [mapping];
   -- (repeated for data and common databases...)
   ```

### Issue 5: CREATE TABLE Permission Denied

**Problem:**
- NSI logs showed: `CREATE TABLE permission denied in database 'dotstat-mapping'`

**Root Cause:**
- Database users only had basic read/write permissions
- Mapping store requires DDL permissions for dynamic table creation

**Solution:**
Added `db_ddladmin` role membership to all database users to allow schema modifications.

## Configuration Changes

### 1. Keycloak Client Secret

**Added but not used (for reference):**
- `KEYCLOAK_CLIENT_SECRET` added to secrets
- Value: `VgBhOwwEmvbgaQWRcwJYaiO75zP1PS5H`
- Not actually used since stat-suite is a public client

### 2. Middleware Configuration

**Modified:** `k8s/ingress/middlewares.yaml`
- Enhanced `no-encoding` middleware to strip both request and response encoding headers
- Prevents Brotli-related content decoding issues

### 3. Application Deployments

**Modified:** `k8s/deployments/apps.yaml`
- Added postStart lifecycle hooks to data-explorer and lifecycle-manager
- Hooks remove `.br` files after container starts
- Ensures uncompressed JavaScript is served
- Runs automatically on every pod restart/recreation

### 4. Realm Configuration

**Modified:** `k8s/demo-realm/keycloack-demo-realm.json`
- Removed `secret` field from stat-suite client
- Ensures consistency with public client configuration

## Manual Steps Required After Deployment

### 1. Copy Assets
```bash
kubectl cp ./config-data/assets/siscc \
  dotstat/$(kubectl get pod -n dotstat -l app=config-server -o jsonpath='{.items[0].metadata.name}'):/app/data/assets/
```

### 2. Import Keycloak Realm
1. Access Keycloak admin console (http://keycloak.local)
2. Login with admin/P@ssw0rd!
3. Create realm from `k8s/demo-realm/keycloack-demo-realm.json`
4. Verify stat-suite client has "Client authentication" set to OFF

### 3. Create Solr Collection (for search)
```bash
kubectl exec -n dotstat deployment/solr -- \
  curl "http://localhost:8983/solr/admin/collections?action=CREATE&name=demo&numShards=1&replicationFactor=1"
```

### 4. Grant Database Permissions
```bash
kubectl exec -n dotstat deployment/sqlserver -- \
  /opt/mssql-tools18/bin/sqlcmd -C -S localhost -U sa -P 'P@ssw0rd!' \
  -Q "USE [dotstat-mapping]; ALTER ROLE db_ddladmin ADD MEMBER [mapping]; ALTER ROLE db_datawriter ADD MEMBER [mapping]; ALTER ROLE db_datareader ADD MEMBER [mapping];"
```

Repeat for data and common databases.

## Known Issues & Limitations

### 1. Search Functionality

**Status:** Partially working

**Issue:**
- Search endpoint returns 500 errors
- Solr collection exists but lacks proper schema
- Fields like `type_s`, `sname`, `lorder_d`, `gorder_d` are missing

**Workaround:**
- Core data browsing works without search
- Search can be populated by publishing dataflows via Lifecycle Manager
- Or disable search in data-explorer settings.json

**Future Fix:**
- Configure Solr schema for SFS
- Add automated collection initialization job
- Document search indexing workflow

### 2. Asset Persistence

**Issue:**
- Assets must be manually copied after deployment
- Not automatically persisted across pod restarts

**Future Fix:**
- Create init job to check and copy assets
- Or build assets into container image
- Or use an init container that copies from a sidecar

### 3. Data-Viewer

**Clarification:**
- No separate data-viewer component needed
- Data-viewer is a configuration profile within data-explorer
- Used for embedded visualizations
- Configuration exists at `config-data/configs/demo/data-viewer/settings.json`

## Testing & Verification

### Verified Working Components

**Infrastructure:**
- SQL Server with databases (common, data, mapping)
- PostgreSQL for Keycloak
- MongoDB for SFS metadata
- Solr for search (collection exists)

**Authentication:**
- Keycloak realm imported
- User login working
- OIDC flow functional

**Data Services:**
- NSI (SDMX web service) responding
- Transfer service operational
- Auth service functional
- Data import via NSI working

**Frontend Applications:**
- Data Explorer accessible and functional
- Lifecycle Manager accessible and functional
- Assets (images, CSS) loading correctly
- Data browsing and visualization working

**Data Import:**
- SDMX structure import successful
- Example data imported
- Dataflows visible in explorer

### Known Non-Working Features

**Search:**
- Returns 500 errors due to missing Solr schema
- Needs data indexing via lifecycle manager

## Recommendations

### Immediate Actions
1. Document search indexing workflow for users
2. Add Solr collection initialization to deployment pipeline
3. Create automated asset copying mechanism

### Future Improvements
1. Externalize all hardcoded values to ConfigMap/Secrets - DONE on 17/11/25
2. Add health checks to all services
3. Implement proper backup/restore for PVCs
4. Add monitoring and logging aggregation
5. Create Helm chart for easier deployment
6. Automate Keycloak realm import on first start
7. Implement Kustomize & add to/test with FluxCD

### Production Considerations
1. Use proper SSL/TLS certificates (not self-signed)
2. Replace passwords with strong, generated values
3. Implement proper secret management (e.g., Sealed Secrets, External Secrets)
4. Configure resource limits and requests
5. Set up horizontal pod autoscaling for stateless services
6. Implement network policies for security
7. Use external database services (managed services) instead of in-cluster
8. Configure proper backup strategy for persistent data

## Files Modified/Created

### Created:
- `k8s/README.md` - Setup and deployment instructions
- `k8s/MIGRATION_NOTES.md` - This document
- `k8s/jobs/init-assets.yaml` - Asset initialization job template

### Modified:
- `k8s/config/config-and-secrets.yaml` - Added KEYCLOAK_CLIENT_SECRET
- `k8s/ingress/middlewares.yaml` - Enhanced no-encoding middleware
- `k8s/deployments/apps.yaml` - Added init containers for br file removal
- `k8s/demo-realm/keycloack-demo-realm.json` - Removed client secret

## References

- DotStat Suite Documentation: https://gitlab.com/sis-cc/.stat-suite
- Keycloak Documentation: https://www.keycloak.org/docs/
- SDMX Standards: https://sdmx.org/
- Traefik Middleware: https://doc.traefik.io/traefik/middlewares/overview/

---
**Last Updated:** 2025-11-17