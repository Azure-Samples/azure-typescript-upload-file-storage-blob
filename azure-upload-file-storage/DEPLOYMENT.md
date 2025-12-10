# Deployment Guide - v2 Application

This guide covers deploying the v2 application (Fastify API + React frontend) to Azure.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                     Azure Cloud                          │
│                                                           │
│  ┌──────────────────────┐     ┌────────────────────┐   │
│  │ Azure Static Web App │────▶│ Azure Container App │   │
│  │  (React Frontend)    │     │   (Fastify API)     │   │
│  └──────────────────────┘     └────────────────────┘   │
│                                        │                  │
│                                        ▼                  │
│                              ┌──────────────────┐        │
│                              │ Azure Blob       │        │
│                              │ Storage          │        │
│                              └──────────────────┘        │
│                                                           │
│  Authentication: Managed Identity + RBAC                 │
│  - No keys or secrets in configuration                   │
│  - User delegation SAS tokens                            │
└─────────────────────────────────────────────────────────┘
```

## Prerequisites

- Azure subscription
- Azure CLI installed and authenticated: `az login`
- Docker installed (for local testing)
- Node.js 18+ installed

## Option 1: One-Command Deployment with Azure Developer CLI (Recommended)

### 1. Install Azure Developer CLI

```bash
# Windows (PowerShell)
powershell -ex AllSigned -c "Invoke-RestMethod 'https://aka.ms/install-azd.ps1' | Invoke-Expression"

# macOS/Linux
curl -fsSL https://aka.ms/install-azd.sh | bash
```

### 2. Initialize and Deploy

```bash
# From project root
cd /workspaces/file-upload

# Initialize (if not already done)
azd init

# Deploy everything
azd up
```

This single command will:
1. Create all Azure resources (Container Apps, Storage, Static Web App)
2. Assign RBAC roles (Storage Blob Data Contributor, Storage Blob Delegator)
3. Build and deploy the API container
4. Build and deploy the frontend
5. Configure all connections and environment variables

### 3. Verify Deployment

```bash
# Get deployment endpoints
azd show

# Test API
curl https://your-api.azurecontainerapps.io/health

# Test frontend
open https://your-app.azurestaticapps.net
```

## Option 2: Manual Deployment

### Step 1: Create Azure Resources

```bash
# Set variables
RESOURCE_GROUP="rg-upload-app"
LOCATION="eastus"
STORAGE_ACCOUNT="stuploadstorage$(openssl rand -hex 4)"
CONTAINER_APPS_ENV="env-upload"
API_APP="api-upload"
STATIC_WEB_APP="app-upload"

# Create resource group
az group create --name $RESOURCE_GROUP --location $LOCATION

# Create storage account
az storage account create \
  --name $STORAGE_ACCOUNT \
  --resource-group $RESOURCE_GROUP \
  --location $LOCATION \
  --sku Standard_LRS \
  --kind StorageV2 \
  --allow-blob-public-access false

# Create upload container
az storage container create \
  --name upload \
  --account-name $STORAGE_ACCOUNT \
  --auth-mode login

# Create Container Apps environment
az containerapp env create \
  --name $CONTAINER_APPS_ENV \
  --resource-group $RESOURCE_GROUP \
  --location $LOCATION
```

### Step 2: Build and Deploy API Container

```bash
# Build API Docker image
cd azure-upload-file-storage/api
docker build -t $API_APP:latest .

# Create Azure Container Registry (optional, for hosting images)
ACR_NAME="acrupload$(openssl rand -hex 4)"
az acr create \
  --name $ACR_NAME \
  --resource-group $RESOURCE_GROUP \
  --sku Basic \
  --admin-enabled true

# Login to ACR
az acr login --name $ACR_NAME

# Tag and push image
docker tag $API_APP:latest $ACR_NAME.azurecr.io/$API_APP:latest
docker push $ACR_NAME.azurecr.io/$API_APP:latest

# Create Container App
az containerapp create \
  --name $API_APP \
  --resource-group $RESOURCE_GROUP \
  --environment $CONTAINER_APPS_ENV \
  --image $ACR_NAME.azurecr.io/$API_APP:latest \
  --target-port 3000 \
  --ingress external \
  --registry-server $ACR_NAME.azurecr.io \
  --query properties.configuration.ingress.fqdn \
  --system-assigned

# Get Container App identity
API_IDENTITY=$(az containerapp show \
  --name $API_APP \
  --resource-group $RESOURCE_GROUP \
  --query identity.principalId -o tsv)

# Assign RBAC roles
STORAGE_ACCOUNT_ID=$(az storage account show \
  --name $STORAGE_ACCOUNT \
  --resource-group $RESOURCE_GROUP \
  --query id -o tsv)

az role assignment create \
  --role "Storage Blob Data Contributor" \
  --assignee $API_IDENTITY \
  --scope $STORAGE_ACCOUNT_ID

az role assignment create \
  --role "Storage Blob Delegator" \
  --assignee $API_IDENTITY \
  --scope $STORAGE_ACCOUNT_ID

# Set environment variables
az containerapp update \
  --name $API_APP \
  --resource-group $RESOURCE_GROUP \
  --set-env-vars \
    AZURE_STORAGE_ACCOUNT_NAME=$STORAGE_ACCOUNT \
    NODE_ENV=production
```

### Step 3: Deploy Frontend to Static Web Apps

```bash
# Build frontend
cd ../app
npm install

# Set API URL for production
export VITE_API_URL=$(az containerapp show \
  --name $API_APP \
  --resource-group $RESOURCE_GROUP \
  --query properties.configuration.ingress.fqdn -o tsv)

npm run build

# Create Static Web App
az staticwebapp create \
  --name $STATIC_WEB_APP \
  --resource-group $RESOURCE_GROUP \
  --location $LOCATION \
  --source ./dist \
  --branch main \
  --app-location "/" \
  --output-location "dist"

# Configure API proxy (optional, for CORS)
# Edit staticwebapp.config.json to add reverse proxy rules
```

### Step 4: Configure CORS

Update API CORS settings to allow frontend:

```bash
FRONTEND_URL=$(az staticwebapp show \
  --name $STATIC_WEB_APP \
  --resource-group $RESOURCE_GROUP \
  --query defaultHostname -o tsv)

az containerapp update \
  --name $API_APP \
  --resource-group $RESOURCE_GROUP \
  --set-env-vars FRONTEND_URL=https://$FRONTEND_URL
```

## Local Testing with Docker Compose

Before deploying to Azure, test locally:

```bash
# Set environment variable
export AZURE_STORAGE_ACCOUNT_NAME=your-storage-account

# Start both services
docker-compose up --build

# Test in browser
open http://localhost:8080

# API available at http://localhost:3000
# Frontend available at http://localhost:8080
```

## Deployment Verification

### API Health Check

```bash
API_URL=$(az containerapp show \
  --name $API_APP \
  --resource-group $RESOURCE_GROUP \
  --query properties.configuration.ingress.fqdn -o tsv)

curl https://$API_URL/health
# Expected: {"status":"healthy","timestamp":"..."}
```

### Test SAS Token Generation

```bash
curl "https://$API_URL/api/sas?container=upload&file=test.txt"
# Expected: {"url":"https://storage.blob.core.windows.net/upload/test.txt?..."}
```

### Test Frontend

```bash
FRONTEND_URL=$(az staticwebapp show \
  --name $STATIC_WEB_APP \
  --resource-group $RESOURCE_GROUP \
  --query defaultHostname -o tsv)

open https://$FRONTEND_URL
```

## Environment Variables

### API Container App

| Variable | Required | Description | Example |
|----------|----------|-------------|---------|
| `AZURE_STORAGE_ACCOUNT_NAME` | Yes | Storage account name | `stuploadstorage` |
| `NODE_ENV` | No | Environment | `production` |
| `PORT` | No | Server port | `3000` |
| `FRONTEND_URL` | Yes | Frontend URL for CORS | `https://app.azurestaticapps.net` |

### Frontend Static Web App

| Variable | Required | Description | Example |
|----------|----------|-------------|---------|
| `VITE_API_URL` | Yes | API endpoint URL | `https://api.azurecontainerapps.io` |

**Note**: Frontend environment variables must be set at **build time**, not runtime.

## Monitoring and Logs

### View API Logs

```bash
# Stream logs
az containerapp logs show \
  --name $API_APP \
  --resource-group $RESOURCE_GROUP \
  --follow

# Query logs
az monitor log-analytics query \
  --workspace $(az containerapp env show \
    --name $CONTAINER_APPS_ENV \
    --resource-group $RESOURCE_GROUP \
    --query properties.appLogsConfiguration.logAnalyticsConfiguration.customerId -o tsv) \
  --analytics-query "ContainerAppConsoleLogs_CL | where ContainerAppName_s == '$API_APP' | top 20 by TimeGenerated"
```

### View Static Web App Logs

```bash
# View deployment logs
az staticwebapp show \
  --name $STATIC_WEB_APP \
  --resource-group $RESOURCE_GROUP
```

## Scaling Configuration

### API Auto-Scaling

```bash
# Configure scaling rules
az containerapp update \
  --name $API_APP \
  --resource-group $RESOURCE_GROUP \
  --min-replicas 1 \
  --max-replicas 10 \
  --scale-rule-name http-rule \
  --scale-rule-type http \
  --scale-rule-http-concurrency 100
```

## Cost Optimization

### Container Apps

- Set `--min-replicas 0` for dev/test environments (scale to zero)
- Use `--min-replicas 1` for production (avoid cold starts)
- Set appropriate `--max-replicas` based on expected load

### Static Web Apps

- Free tier: 100 GB bandwidth/month
- Standard tier: Custom domains, SLA

### Storage Account

- Use "Cool" access tier for infrequently accessed files
- Enable lifecycle management to move/delete old files

## Security Best Practices

### API Security

- ✅ Managed identity (no keys)
- ✅ RBAC roles (least privilege)
- ✅ User delegation SAS tokens
- ✅ CORS configured (not wildcard `*`)
- ✅ HTTPS only

### Storage Security

- ✅ Disable public blob access
- ✅ Require HTTPS
- ✅ Enable SAS expiration policy
- ✅ Enable blob versioning (optional)
- ✅ Enable soft delete (optional)

### Network Security (Optional)

Enable VNet integration for production:

```bash
# Create VNet and subnet
az network vnet create \
  --name vnet-upload \
  --resource-group $RESOURCE_GROUP \
  --address-prefix 10.0.0.0/16 \
  --subnet-name subnet-containerapp \
  --subnet-prefix 10.0.0.0/23

# Update Container Apps environment
az containerapp env update \
  --name $CONTAINER_APPS_ENV \
  --resource-group $RESOURCE_GROUP \
  --infrastructure-subnet-resource-id $(az network vnet subnet show \
    --name subnet-containerapp \
    --vnet-name vnet-upload \
    --resource-group $RESOURCE_GROUP \
    --query id -o tsv)
```

## Troubleshooting

### API Returns 403 Forbidden

**Cause**: Missing RBAC roles

**Solution**:
```bash
# Verify role assignments
az role assignment list \
  --assignee $API_IDENTITY \
  --scope $STORAGE_ACCOUNT_ID

# Re-assign roles if missing
az role assignment create \
  --role "Storage Blob Data Contributor" \
  --assignee $API_IDENTITY \
  --scope $STORAGE_ACCOUNT_ID

az role assignment create \
  --role "Storage Blob Delegator" \
  --assignee $API_IDENTITY \
  --scope $STORAGE_ACCOUNT_ID
```

### Frontend Cannot Connect to API

**Cause**: CORS not configured or wrong API URL

**Solution**:
1. Verify `VITE_API_URL` in frontend build
2. Check API CORS configuration:
   ```bash
   az containerapp env-var list \
     --name $API_APP \
     --resource-group $RESOURCE_GROUP
   ```
3. Update FRONTEND_URL in API environment

### Container App Crash Loop

**Cause**: Missing environment variables or invalid configuration

**Solution**:
```bash
# Check logs
az containerapp logs show \
  --name $API_APP \
  --resource-group $RESOURCE_GROUP \
  --follow

# Verify environment variables
az containerapp show \
  --name $API_APP \
  --resource-group $RESOURCE_GROUP \
  --query properties.template.containers[0].env
```

## Cleanup

Remove all resources:

```bash
# Delete entire resource group
az group delete --name $RESOURCE_GROUP --yes --no-wait
```

Or remove individual resources:

```bash
az staticwebapp delete --name $STATIC_WEB_APP --resource-group $RESOURCE_GROUP
az containerapp delete --name $API_APP --resource-group $RESOURCE_GROUP
az storage account delete --name $STORAGE_ACCOUNT --resource-group $RESOURCE_GROUP
```

## CI/CD Pipeline (Optional)

Use GitHub Actions for automated deployment:

```yaml
# .github/workflows/deploy.yml
name: Deploy to Azure

on:
  push:
    branches: [main]

jobs:
  deploy-api:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: azure/login@v1
        with:
          creds: ${{ secrets.AZURE_CREDENTIALS }}
      - name: Build and push API
        run: |
          cd azure-upload-file-storage/api
          az acr build --registry ${{ secrets.ACR_NAME }} --image api:${{ github.sha }} .
      - name: Deploy to Container Apps
        run: |
          az containerapp update \
            --name ${{ secrets.API_APP_NAME }} \
            --resource-group ${{ secrets.RESOURCE_GROUP }} \
            --image ${{ secrets.ACR_NAME }}.azurecr.io/api:${{ github.sha }}

  deploy-frontend:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: actions/setup-node@v3
        with:
          node-version: 18
      - name: Build frontend
        run: |
          cd azure-upload-file-storage/app
          npm ci
          npm run build
        env:
          VITE_API_URL: ${{ secrets.API_URL }}
      - uses: Azure/static-web-apps-deploy@v1
        with:
          azure_static_web_apps_api_token: ${{ secrets.AZURE_STATIC_WEB_APPS_API_TOKEN }}
          repo_token: ${{ secrets.GITHUB_TOKEN }}
          action: "upload"
          app_location: "azure-upload-file-storage/app"
          output_location: "dist"
```

## Additional Resources

- [Azure Container Apps Documentation](https://learn.microsoft.com/azure/container-apps/)
- [Azure Static Web Apps Documentation](https://learn.microsoft.com/azure/static-web-apps/)
- [Azure Storage RBAC](https://learn.microsoft.com/azure/storage/blobs/assign-azure-role-data-access)
- [User Delegation SAS](https://learn.microsoft.com/azure/storage/common/storage-sas-overview#user-delegation-sas)
- [Azure Developer CLI](https://learn.microsoft.com/azure/developer/azure-developer-cli/)
