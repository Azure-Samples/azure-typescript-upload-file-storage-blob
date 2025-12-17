# Azure Container Apps Deployment

This repository contains a file upload sample application with:
- **Frontend**: React + Vite static web app served via nginx
- **Backend API**: Express-wrapped Azure Functions for Azure Storage operations
- **Infrastructure**: Deployed to Azure Container Apps using Bicep and Azure Developer CLI (azd)

## Prerequisites

- [Azure CLI](https://docs.microsoft.com/cli/azure/install-azure-cli)
- [Azure Developer CLI (azd)](https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd)
- [Docker Desktop](https://www.docker.com/products/docker-desktop/)
- [Node.js 22+](https://nodejs.org/)
- An Azure subscription

## Architecture

```
┌─────────────────┐      ┌──────────────────┐      ┌──────────────────┐
│  React Frontend │─────▶│   Express API    │─────▶│  Azure Storage   │
│  (nginx:8080)   │      │   (Node:3000)    │      │  Blob Container  │
└─────────────────┘      └──────────────────┘      └──────────────────┘
         │                        │
         └────────────────────────┘
                   │
         Azure Container Apps
```

## Project Structure

```
├── azure.yaml                          # Azure Developer CLI configuration
├── docker-compose.yml                  # Local development with Docker
├── infra/                              # Infrastructure as Code
│   ├── main.bicep                      # Main Bicep template
│   ├── main.parameters.bicepparam      # Bicep parameters
│   └── abbreviations.json              # Azure resource naming
├── azure-upload-file-to-storage/
│   ├── api/                            # Backend API
│   │   ├── Dockerfile                  # Multi-stage build for API
│   │   ├── .dockerignore
│   │   ├── server.ts                   # Express wrapper
│   │   ├── package.json
│   │   └── src/
│   │       ├── functions/              # Azure Functions handlers
│   │       └── lib/                    # Storage utilities
│   └── app/                            # Frontend
│       ├── Dockerfile                  # Multi-stage build for React app
│       ├── .dockerignore
│       ├── nginx.conf                  # nginx configuration
│       ├── package.json
│       └── src/                        # React components
```

## Local Development

### Using Docker Compose (Recommended)

1. **Set environment variables:**
   ```bash
   export AZURE_STORAGE_ACCOUNT_NAME="your-storage-account"
   export AZURE_STORAGE_ACCOUNT_KEY="your-storage-key"
   ```

2. **Start all services:**
   ```bash
   docker compose up
   ```

3. **Access the application:**
   - Frontend: http://localhost:8080
   - API: http://localhost:3000
   - API Health: http://localhost:3000/health

### Using Node.js Directly

**API:**
```bash
cd azure-upload-file-to-storage/api
npm install
npm run dev
```

**Frontend:**
```bash
cd azure-upload-file-to-storage/app
npm install
npm run dev
```

## Azure Deployment

### One-Command Deployment with azd

```bash
# Login and initialize
azd auth login
azd init

# Deploy everything (infrastructure + apps)
azd up

# Get service URLs
azd env get-values
```

### Manual Step-by-Step

1. **Provision infrastructure:**
   ```bash
   azd provision
   ```

2. **Build and deploy containers:**
   ```bash
   azd deploy
   ```

3. **View logs:**
   ```bash
   azd monitor
   ```

## Configuration

### Environment Variables

**API Container:**
- `NODE_ENV`: production/development
- `Azure_Storage_AccountName`: Storage account name (auto-injected)
- `FRONTEND_URL`: Frontend URL for CORS (auto-injected)

**Frontend Container:**
- `VITE_API_URL`: Backend API URL (auto-injected)

### Azure Resources Created

The deployment creates:
- **Resource Group**: Contains all resources
- **Container Registry**: Stores container images
- **Container Apps Environment**: Hosts both containers
- **Log Analytics Workspace**: Centralized logging
- **Storage Account**: Blob storage with "upload" container
- **API Container App**: Express API with managed identity
- **Web Container App**: nginx serving React SPA

### Security Features

- **Managed Identity**: API uses system-assigned identity for keyless storage access
- **RBAC**: API granted Storage Blob Data Contributor and Storage Blob Delegator roles
- **CORS**: Configured for cross-origin requests
- **Health Checks**: Both containers have liveness/readiness probes
- **TLS**: All traffic over HTTPS in production

## Costs

Estimated monthly cost (East US, minimal usage):
- Container Apps: ~$10-20/month (with auto-scaling to zero)
- Container Registry (Basic): ~$5/month
- Storage Account: <$1/month (for small amounts of data)
- Log Analytics: ~$5/month

**Total: ~$20-30/month**

## Cleanup

```bash
# Delete all Azure resources
azd down

# Or delete manually
az group delete --name <resource-group-name>
```

## Troubleshooting

### Check Container Logs
```bash
# API logs
az containerapp logs show --name <api-app-name> --resource-group <rg-name> --follow

# Web logs
az containerapp logs show --name <web-app-name> --resource-group <rg-name> --follow
```

### Verify Health
```bash
curl https://<api-url>/health
curl https://<web-url>/health
```

### Common Issues

1. **Container fails to start**: Check environment variables and image build
2. **Storage access denied**: Verify managed identity role assignments
3. **CORS errors**: Ensure FRONTEND_URL is correctly set in API container

## Development Notes

- The API wraps Azure Functions in Express for Container Apps compatibility
- Frontend uses nginx for efficient static file serving
- Both services use multi-stage Docker builds for optimization
- Health checks ensure zero-downtime deployments
- Auto-scaling configured based on HTTP requests

## Contributing

When making changes:
1. Test locally with Docker Compose
2. Build containers: `docker compose build`
3. Test deployed version: `azd deploy`
4. Monitor: `azd monitor`

## License

MIT
