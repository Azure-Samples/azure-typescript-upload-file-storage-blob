# Development Guide

This guide provides comprehensive information for local development, testing, and deployment workflows.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Getting Started](#getting-started)
- [Development Workflows](#development-workflows)
- [Authentication](#authentication)
- [Project Structure](#project-structure)
- [Available Scripts](#available-scripts)
- [Environment Configuration](#environment-configuration)
- [Testing](#testing)
- [Debugging](#debugging)
- [Common Issues](#common-issues)
- [Development Tips](#development-tips)

## Prerequisites

Before you begin, ensure you have:

### Required Tools

- **Azure Subscription**: Active subscription with permissions to create resources
- **Azure Developer CLI (azd)**: v1.5.0 or later
  ```bash
  # Install azd
  curl -fsSL https://aka.ms/install-azd.sh | bash
  ```
- **Node.js**: v18 or later with npm
- **Docker**: For running containers locally
- **Git**: For version control

### Azure Permissions

Your Azure account needs:
- Ability to create resource groups
- Permissions to create Container Apps, Storage Accounts, and Container Registries
- Ability to assign RBAC roles (Owner or User Access Administrator)

## Getting Started

### Option 1: GitHub Codespaces (Recommended)

1. **Open in Codespaces**
   - Click the "Code" button on GitHub
   - Select "Create codespace on main"
   - Wait for the environment to initialize

2. **Authenticate with Azure**
   ```bash
   azd auth login
   ```

3. **Deploy Everything**
   ```bash
   azd up
   ```
   This single command will:
   - Provision all Azure resources
   - Build and deploy both API and frontend
   - Configure authentication and permissions
   - Set up environment variables

4. **Access Your Application**
   - After deployment completes, azd will display the frontend URL
   - Open the URL in your browser to test file uploads

### Option 2: Local Development with Containers

1. **Clone the Repository**
   ```bash
   git clone <repository-url>
   cd azure-typescript-upload-file-storage-blob
   ```

2. **Start Docker Compose**
   ```bash
   docker-compose up
   ```

3. **Authenticate and Deploy**
   ```bash
   azd auth login
   azd up
   ```

### Option 3: Native Local Development

1. **Install Dependencies**
   ```bash
   # Install workspace dependencies
   npm install
   
   # Install API dependencies
   cd azure-upload-file-storage/api
   npm install
   
   # Install frontend dependencies
   cd ../app
   npm install
   ```

2. **Set Up Environment Variables**
   ```bash
   # In azure-upload-file-storage/api directory
   cp .env.example .env
   
   # Edit .env with your Azure Storage account details
   nano .env
   ```

3. **Run Development Servers**
   ```bash
   # Terminal 1: API server
   cd azure-upload-file-storage/api
   npm run dev
   
   # Terminal 2: Frontend server
   cd azure-upload-file-storage/app
   npm run dev
   ```

## Development Workflows

### Workflow 1: Develop Locally, Deploy to Azure

Best for: Testing integration with Azure services

```bash
# 1. Make code changes locally
# 2. Test with local dev servers
npm run dev

# 3. Deploy to Azure when ready
azd deploy

# 4. Test in production environment
```

### Workflow 2: Full Local Development

Best for: Rapid iteration without Azure dependencies

```bash
# 1. Use local storage emulator or mock services
# 2. Run both API and frontend locally
npm run dev

# 3. Deploy to Azure periodically
azd up
```

### Workflow 3: Container-Based Development

Best for: Consistent environment across team

```bash
# 1. Start containers
docker-compose up

# 2. Make changes (hot reload enabled)
# 3. Test in containerized environment
# 4. Deploy when ready
azd deploy
```

## Authentication

### Local Development Authentication

The application uses `DefaultAzureCredential` which tries authentication methods in this order:

1. **Environment Variables** (`AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_CLIENT_SECRET`)
2. **Managed Identity** (when running in Azure Container Apps)
3. **Azure CLI** (when running locally after `az login`)
4. **Azure Developer CLI** (when running locally after `azd auth login`)

### Setting Up Local Authentication

**Option A: Using Azure CLI**
```bash
az login
az account set --subscription <subscription-id>
```

**Option B: Using Azure Developer CLI**
```bash
azd auth login
```

**Option C: Using Service Principal**
```bash
# Create service principal
az ad sp create-for-rbac --name "dev-app-sp" --role Contributor

# Set environment variables
export AZURE_CLIENT_ID="<client-id>"
export AZURE_TENANT_ID="<tenant-id>"
export AZURE_CLIENT_SECRET="<client-secret>"
```

### Required Azure Permissions

The authenticated identity needs these RBAC roles on the Storage Account:

- **Storage Blob Data Contributor**: Upload and manage blobs
- **Storage Blob Delegator**: Generate User Delegation SAS tokens

Grant permissions:
```bash
# Get your user object ID
USER_ID=$(az ad signed-in-user show --query id -o tsv)

# Get storage account resource ID
STORAGE_ID=$(az storage account show \
  --name <storage-account-name> \
  --resource-group <resource-group> \
  --query id -o tsv)

# Assign roles
az role assignment create \
  --assignee $USER_ID \
  --role "Storage Blob Data Contributor" \
  --scope $STORAGE_ID

az role assignment create \
  --assignee $USER_ID \
  --role "Storage Blob Delegator" \
  --scope $STORAGE_ID
```

## Project Structure

```
azure-upload-file-storage/
├── api/                          # Backend API (Fastify + TypeScript)
│   ├── src/
│   │   ├── server.ts            # Main server entry point
│   │   ├── lib/
│   │   │   └── azure-storage.ts # Azure Storage client configuration
│   │   └── routes/
│   │       ├── status.ts        # Health check endpoint
│   │       ├── sas.ts          # SAS token generation endpoint
│   │       └── list.ts         # Blob listing endpoint
│   ├── tests/                   # HTTP test files
│   ├── package.json
│   ├── tsconfig.json
│   └── Dockerfile
├── app/                         # Frontend (React + TypeScript + Vite)
│   ├── src/
│   │   ├── App.tsx             # Main application component
│   │   ├── components/
│   │   │   └── error-boundary.tsx
│   │   └── lib/
│   │       └── convert-file-to-arraybuffer.ts
│   ├── public/                 # Static assets
│   ├── package.json
│   ├── vite.config.ts
│   └── Dockerfile
└── docker-compose.yml          # Local container orchestration

infra/                          # Infrastructure as Code
├── main.bicep                 # Azure resource definitions
├── main.parameters.json       # Deployment parameters
└── abbreviations.json         # Azure resource naming

docs/                          # Documentation
├── FUNCTIONAL-SPEC.md        # Technical specification
├── SAS-TOKEN-ARCHITECTURE.md # Security architecture
├── DIAGRAMS.md               # Visual diagrams
└── *.mermaid                 # Diagram source files
```

## Available Scripts

### Workspace-Level Scripts

Run from the root directory:

| Command | Description |
|---------|-------------|
| `npm run dev` | Start both API and frontend in development mode |
| `npm run build` | Build both API and frontend for production |
| `npm run test` | Run tests for both projects |
| `npm run lint` | Lint both API and frontend code |
| `npm run format` | Format code with Prettier |
| `npm run clean` | Remove all node_modules and build artifacts |

### API Scripts

Run from `azure-upload-file-storage/api`:

| Command | Description |
|---------|-------------|
| `npm run dev` | Start API server with hot reload (port 3100) |
| `npm run build` | Compile TypeScript to JavaScript |
| `npm start` | Start production API server |
| `npm run lint` | Run ESLint on API code |
| `npm run format` | Format API code with Prettier |
| `npm test` | Run API tests |
| `npm run type-check` | Check TypeScript types without building |

### Frontend Scripts

Run from `azure-upload-file-storage/app`:

| Command | Description |
|---------|-------------|
| `npm run dev` | Start Vite dev server with hot reload (port 5173) |
| `npm run build` | Build optimized production bundle |
| `npm run preview` | Preview production build locally |
| `npm run lint` | Run ESLint on frontend code |
| `npm run format` | Format frontend code with Prettier |
| `npm test` | Run frontend tests |
| `npm run type-check` | Check TypeScript types |

### Azure Deployment Scripts

| Command | Description |
|---------|-------------|
| `azd up` | Provision and deploy everything |
| `azd deploy` | Deploy code without provisioning |
| `azd provision` | Provision Azure resources only |
| `azd down` | Delete all Azure resources |
| `azd env list` | List all azd environments |
| `azd env set <env-name>` | Switch to a different environment |

## Environment Configuration

### API Environment Variables

Create `azure-upload-file-storage/api/.env`:

```bash
# Azure Storage Configuration
AZURE_STORAGE_ACCOUNT_NAME=<your-storage-account-name>
AZURE_STORAGE_CONTAINER_NAME=<your-container-name>

# Optional: Authentication (if not using DefaultAzureCredential)
AZURE_CLIENT_ID=<service-principal-client-id>
AZURE_TENANT_ID=<azure-tenant-id>
AZURE_CLIENT_SECRET=<service-principal-secret>

# Server Configuration
PORT=3100
NODE_ENV=development

# CORS Configuration
ALLOWED_ORIGINS=http://localhost:5173,http://localhost:4280
```

### Frontend Environment Variables

Create `azure-upload-file-storage/app/.env`:

```bash
# API Configuration
VITE_API_URL=http://localhost:3100

# Optional: Feature Flags
VITE_ENABLE_DEBUG=true
```

### Azure Deployment Environment

During `azd up`, these are automatically configured:

- `AZURE_STORAGE_ACCOUNT_NAME`: Auto-generated storage account name
- `AZURE_STORAGE_CONTAINER_NAME`: Set to "uploads"
- `AZURE_CLIENT_ID`: Managed Identity client ID
- `API_URL`: Backend Container App URL

## Testing

### Manual Testing with HTTP Files

The API includes `.http` files for testing with the REST Client extension:

```bash
cd azure-upload-file-storage/api/tests

# Test health check
# Open status.http in VS Code and click "Send Request"

# Test SAS token generation
# Open sas.http and modify the filename, then click "Send Request"

# Test blob listing
# Open list.http and click "Send Request"
```

### Testing SAS Token Generation

Use the provided shell script:

```bash
cd azure-upload-file-storage/api/tests
./test-sas-generation.sh
```

This script:
1. Requests a SAS token from the API
2. Validates the token format
3. Tests uploading a file using the SAS URL
4. Verifies the file was uploaded successfully

### End-to-End Testing

1. **Start Local Services**
   ```bash
   # Terminal 1: API
   cd azure-upload-file-storage/api
   npm run dev
   
   # Terminal 2: Frontend
   cd azure-upload-file-storage/app
   npm run dev
   ```

2. **Test File Upload Flow**
   - Open http://localhost:5173 in browser
   - Click "Select File" and choose a file
   - Click "Upload"
   - Verify file appears in the list below

3. **Verify in Azure Storage**
   ```bash
   az storage blob list \
     --account-name <storage-account-name> \
     --container-name uploads \
     --auth-mode login
   ```

### Performance Testing

Test upload performance with different file sizes:

```bash
# Create test files
dd if=/dev/zero of=test-1mb.bin bs=1M count=1
dd if=/dev/zero of=test-10mb.bin bs=1M count=10
dd if=/dev/zero of=test-100mb.bin bs=1M count=100

# Test upload speed
time curl -X PUT \
  -H "x-ms-blob-type: BlockBlob" \
  --data-binary @test-10mb.bin \
  "<sas-url>"
```

## Debugging

### Debugging the API

**VS Code Launch Configuration** (`.vscode/launch.json`):

```json
{
  "version": "0.2.0",
  "configurations": [
    {
      "type": "node",
      "request": "launch",
      "name": "Debug API",
      "skipFiles": ["<node_internals>/**"],
      "program": "${workspaceFolder}/azure-upload-file-storage/api/src/server.ts",
      "preLaunchTask": "npm: build",
      "outFiles": ["${workspaceFolder}/azure-upload-file-storage/api/dist/**/*.js"],
      "env": {
        "NODE_ENV": "development"
      }
    }
  ]
}
```

**Enable Debug Logging**:

```typescript
// In api/src/server.ts
const server = Fastify({
  logger: {
    level: 'debug',
    transport: {
      target: 'pino-pretty',
      options: {
        colorize: true
      }
    }
  }
});
```

### Debugging Authentication

```typescript
// Add to api/src/lib/azure-storage.ts
import { DefaultAzureCredential } from '@azure/identity';

const credential = new DefaultAzureCredential({
  loggingOptions: {
    allowLoggingAccountIdentifiers: true,
    logLevel: 'verbose'
  }
});
```

### Debugging the Frontend

1. **Enable React DevTools**
   - Install React Developer Tools browser extension
   - Open browser DevTools → Components tab

2. **Enable Vite Debug Mode**
   ```bash
   DEBUG=vite:* npm run dev
   ```

3. **Browser DevTools**
   - Network tab: Monitor API requests
   - Console: View application logs
   - Application → Storage: Inspect local storage

## Common Issues

### Issue: "Failed to authenticate with Azure"

**Symptoms**: API returns 401 or authentication errors

**Solutions**:
1. Verify you're logged in: `azd auth login` or `az login`
2. Check RBAC permissions on Storage Account
3. Verify environment variables are set correctly
4. Try clearing Azure credential cache: `rm -rf ~/.azure`

### Issue: "CORS Error" in Browser Console

**Symptoms**: Frontend can't reach API

**Solutions**:
1. Check API is running: `curl http://localhost:3100/status`
2. Verify CORS configuration in `api/src/server.ts`:
   ```typescript
   await server.register(cors, {
     origin: ['http://localhost:5173', 'http://localhost:4280'],
     credentials: true
   });
   ```
3. Ensure `VITE_API_URL` matches actual API URL

### Issue: "Storage account not found"

**Symptoms**: API can't connect to Azure Storage

**Solutions**:
1. Verify storage account exists: `az storage account show --name <name>`
2. Check environment variable: `echo $AZURE_STORAGE_ACCOUNT_NAME`
3. Ensure storage account is in the correct region
4. Verify firewall rules allow access

### Issue: "SAS token generation fails"

**Symptoms**: `/api/sas` endpoint returns errors

**Solutions**:
1. Verify "Storage Blob Delegator" role is assigned
2. Check storage account allows User Delegation SAS:
   ```bash
   az storage account show \
     --name <account-name> \
     --query allowBlobPublicAccess
   ```
3. Ensure credential has Key Vault access (if using Key Vault)

### Issue: Docker build fails

**Symptoms**: `docker-compose up` errors

**Solutions**:
1. Ensure Docker daemon is running
2. Check Docker has enough resources (4GB+ RAM)
3. Clear Docker cache: `docker system prune -a`
4. Verify Dockerfile syntax

### Issue: "azd up" fails

**Symptoms**: Deployment errors during provisioning

**Solutions**:
1. Check Azure subscription is active
2. Verify you have necessary permissions
3. Review azd logs: `azd show`
4. Try deploying step-by-step:
   ```bash
   azd provision
   azd deploy
   ```

## Development Tips

### Hot Reload

Both API and frontend support hot reload:
- **API**: Uses `tsx watch` - changes to `.ts` files trigger restart
- **Frontend**: Uses Vite HMR - changes appear instantly without page reload

### Code Quality

Run before committing:
```bash
# Format all code
npm run format

# Lint all code
npm run lint

# Type check
npm run type-check
```

### Environment Switching

Manage multiple Azure environments:
```bash
# Create new environment
azd env new staging

# List environments
azd env list

# Switch environments
azd env set production

# View current environment
azd env get-values
```

### Faster Deployment

Skip building unchanged services:
```bash
# Deploy only API
azd deploy api

# Deploy only frontend
azd deploy app
```

### Local Testing with Azure Resources

Test locally with deployed Azure resources:
```bash
# Get environment variables from Azure
azd env get-values > .env

# Start local API with Azure resources
cd azure-upload-file-storage/api
npm run dev
```

### Monitoring Logs

**View API logs**:
```bash
azd logs --service api --follow
```

**View frontend logs**:
```bash
azd logs --service app --follow
```

**View all logs**:
```bash
azd logs --follow
```

### Cost Optimization

For development environments:
- Use Azure Free Tier storage accounts
- Scale Container Apps to 0 when not in use
- Delete resources when not needed: `azd down`
- Use Azure Developer subscription

### Security Best Practices

1. **Never commit secrets**
   - Use `.env.example` for templates
   - Add `.env` to `.gitignore`

2. **Use Managed Identity**
   - Preferred over service principals
   - Automatically configured in Azure

3. **Rotate SAS tokens**
   - Set short expiration times (1 hour max)
   - Never store tokens in frontend

4. **Network Security**
   - Use HTTPS in production
   - Configure proper CORS origins
   - Enable Azure Storage firewall

## Additional Resources

- [FUNCTIONAL-SPEC.md](./FUNCTIONAL-SPEC.md) - Complete technical specification
- [SAS-TOKEN-ARCHITECTURE.md](./SAS-TOKEN-ARCHITECTURE.md) - Security architecture deep dive
- [DIAGRAMS.md](./DIAGRAMS.md) - Visual architecture diagrams
- [Azure Developer CLI Documentation](https://learn.microsoft.com/azure/developer/azure-developer-cli/)
- [Fastify Documentation](https://fastify.dev/)
- [React Documentation](https://react.dev/)
- [Azure Storage Documentation](https://learn.microsoft.com/azure/storage/)
