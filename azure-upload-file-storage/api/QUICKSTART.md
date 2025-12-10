# Quick Start - v2 API Configuration

## TL;DR
```bash
# 1. Copy environment template
cd azure-upload-file-storage/api
cp .env.sample .env

# 2. Edit .env with your storage account name
# (No keys needed!)

# 3. Login to Azure
az login

# 4. Install and run
npm install
npm run dev

# 5. Test
curl http://localhost:3000/health
```

## Environment Variables

```env
NODE_ENV=development                          # development | production
PORT=3000                                     # Server port
AZURE_STORAGE_ACCOUNT_NAME=your-storage-name  # REQUIRED
FRONTEND_URL=http://localhost:8080            # For CORS
```

## Key Differences from v1

| v1 (Functions) | v2 (Fastify) |
|----------------|--------------|
| `local.settings.json` | `.env` |
| Needs `Azure_Storage_AccountKey` ❌ | No keys needed ✅ |
| Uses `StorageSharedKeyCredential` | Uses `DefaultAzureCredential` |
| Port 7071 | Port 3000 |

## Authentication

**Local Development**: Uses Azure CLI (`az login`)  
**Production**: Uses system-assigned managed identity

## Required RBAC Roles

Your user or managed identity needs:
- **Storage Blob Data Contributor** (ba92f5b4-2d11-453d-a403-e96b0029c9fe)
- **Storage Blob Delegator** (db58b8e5-c6ad-4a2a-8342-4190687cbf4a)

## Endpoints

- `GET /health` - Health check
- `GET /api/status` - Configuration info
- `GET /api/sas?container=upload&file=test.txt` - Generate SAS token
- `GET /api/list?container=upload` - List files

## Troubleshooting

**Error: "DefaultAzureCredential failed"**
```bash
az login
az account show  # Verify subscription
```

**Error: "Status code 403"**
```bash
# Check RBAC roles
az role assignment list --assignee $(az account show --query user.name -o tsv)
```

## More Information

- **Full guide**: See `CONFIGURATION.md`
- **Migration**: See `MIGRATION.md`  
- **Automated setup**: Run `./setup-local-dev.sh`
