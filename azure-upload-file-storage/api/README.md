# API v2 - Fastify with Managed Identity

This is the v2 API using Fastify instead of Azure Functions, with managed identity authentication.

## Prerequisites

- Node.js 22 or later
- Azure CLI (`az login` for local development)
- Azure Storage Account with RBAC roles assigned

## Local Development

1. **Install dependencies**:
   ```bash
   npm install
   ```

2. **Set up environment variables**:
   ```bash
   cp .env.sample .env
   # Edit .env and set AZURE_STORAGE_ACCOUNT_NAME
   ```

3. **Authenticate with Azure CLI** (for local dev):
   ```bash
   az login
   az account show
   ```

4. **Start development server**:
   ```bash
   npm run dev
   ```

   The server will start on http://localhost:3000

## Environment Variables

- `NODE_ENV` - Environment (development/production)
- `PORT` - Server port (default: 3000)
- `AZURE_STORAGE_ACCOUNT_NAME` - Azure Storage account name (required)
- `FRONTEND_URL` - Frontend URL for CORS (default: *)

**Note**: No storage account keys required! Uses DefaultAzureCredential.

## Endpoints

- `GET /health` - Health check
- `GET /api/status` - Status and configuration info
- `GET /api/sas?container=upload&file=test.txt` - Generate SAS token
- `GET /api/list?container=upload` - List files in container

## Testing

```bash
# Test health endpoint
curl http://localhost:3000/health

# Test status endpoint
curl http://localhost:3000/api/status

# Test SAS generation
curl "http://localhost:3000/api/sas?container=upload&file=test.txt"

# Test file listing
curl "http://localhost:3000/api/list?container=upload"
```

## Build

```bash
npm run build
npm start
```

## Authentication

This API uses **DefaultAzureCredential** which automatically detects:
- **Local development**: Azure CLI credentials (from `az login`)
- **Container Apps**: System-assigned managed identity

No keys or secrets needed in configuration!

## Required RBAC Roles

The API's managed identity needs these roles on the Storage Account:
- **Storage Blob Data Contributor** (ba92f5b4-2d11-453d-a403-e96b0029c9fe)
- **Storage Blob Delegator** (db58b8e5-c6ad-4a2a-8342-4190687cbf4a)

These are already configured in `infra/main.bicep`.

## Documentation

- **[QUICKSTART.md](./QUICKSTART.md)** - Quick start guide (TL;DR)
- **[CONFIGURATION.md](./CONFIGURATION.md)** - Detailed configuration guide
- **[MIGRATION.md](./MIGRATION.md)** - Migration guide from v1 to v2
- **[SAS-TOKENS.md](./SAS-TOKENS.md)** - User delegation SAS tokens guide
- **[setup-local-dev.sh](./setup-local-dev.sh)** - Automated setup script
- **[tests/test-sas-generation.sh](./tests/test-sas-generation.sh)** - SAS token test suite
