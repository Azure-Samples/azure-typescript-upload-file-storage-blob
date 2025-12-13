# Configuration Migration: v1 → v2

## Overview

This document shows how to migrate from v1 (Azure Functions with keys) to v2 (Fastify with managed identity).

## Configuration File Changes

### v1: `local.settings.json`
```json
{
  "IsEncrypted": false,
  "Values": {
    "FUNCTIONS_WORKER_RUNTIME": "node",
    "AzureWebJobsStorage": "UseDevelopmentStorage=true",
    "Azure_Storage_AccountName": "mystorageaccount",
    "Azure_Storage_AccountKey": "Eby8vdM02xNOcqFlqUwJPLlmEtlCDXJ1OUzFT50uSRZ6IFsuFq2UVErCz4I6tq/K1SZFPTOtr/KBHBeksoGMGw=="
  },
  "Host": {
    "LocalHttpPort": 7071,
    "CORS": "*"
  }
}
```

### v2: `.env`
```env
NODE_ENV=development
PORT=3000
AZURE_STORAGE_ACCOUNT_NAME=mystorageaccount
WEB_URL=http://localhost:8080
```

## Environment Variable Mapping

| v1 Variable | v2 Variable | Notes |
|-------------|-------------|-------|
| `FUNCTIONS_WORKER_RUNTIME` | ❌ Removed | Not needed (not using Azure Functions) |
| `AzureWebJobsStorage` | ❌ Removed | Not needed (not using Azure Functions) |
| `Azure_Storage_AccountName` | `AZURE_STORAGE_ACCOUNT_NAME` | Renamed for consistency |
| `Azure_Storage_AccountKey` | ❌ **REMOVED** | **Uses managed identity instead** |
| `Host.LocalHttpPort` | `PORT` | Standardized to `PORT` |
| `Host.CORS` | `WEB_URL` | More explicit CORS configuration |
| N/A | `NODE_ENV` | New - for environment detection |

## Security Improvements

### v1: Key-Based Authentication
```typescript
// v1 - Uses account keys
const credential = new StorageSharedKeyCredential(
  process.env.Azure_Storage_AccountName,
  process.env.Azure_Storage_AccountKey  // ❌ Security risk
);
```

**Issues**:
- ❌ Keys stored in config files
- ❌ Keys can be exposed in logs
- ❌ Manual key rotation required
- ❌ No audit trail for key usage
- ❌ Violates least privilege principle

### v2: Managed Identity
```typescript
// v2 - Uses managed identity
const credential = new DefaultAzureCredential();
// ✅ No keys needed!
```

**Benefits**:
- ✅ No secrets in configuration
- ✅ Automatic credential rotation
- ✅ Azure AD audit logs
- ✅ RBAC-based access control
- ✅ Follows zero-trust principles

## Local Development Setup

### v1 Setup
```bash
# Copy configuration template
cp local.settings.sample.json local.settings.json

# Edit and add ACCOUNT KEY ❌
vim local.settings.json

# Start Azure Functions runtime
npm run start:functions
```

### v2 Setup
```bash
# Copy configuration template
cp .env.sample .env

# Edit - NO KEYS NEEDED ✅
vim .env

# Authenticate with Azure CLI
az login

# Start Fastify server
npm run dev
```

## Production Deployment

### v1: Manual Configuration
```bash
# Set app settings with keys ❌
az functionapp config appsettings set \
  --name myapp \
  --settings \
    Azure_Storage_AccountName=storage \
    Azure_Storage_AccountKey="SECRET_KEY_HERE"
```

### v2: Infrastructure as Code
```bicep
// infra/main.bicep - Already configured ✅

// Container App with system-assigned managed identity
managedIdentities: {
  systemAssigned: true
}

// RBAC role assignments (no keys)
roleAssignments: [
  {
    principalId: apiContainerApp.outputs.systemAssignedMIPrincipalId
    roleDefinitionIdOrName: 'Storage Blob Data Contributor'
  }
]

// Environment variables (no secrets)
env: [
  {
    name: 'AZURE_STORAGE_ACCOUNT_NAME'
    value: storage.outputs.name
  }
]
```

## Testing Configuration

### v1: Test with Keys
```bash
# Test SAS generation (uses keys)
curl -X POST http://localhost:7071/api/sas \
  -H "Content-Type: application/json" \
  -d '{"container":"upload","file":"test.txt"}'
```

### v2: Test with Managed Identity
```bash
# Ensure authenticated
az account show

# Test SAS generation (uses managed identity)
curl "http://localhost:3000/api/sas?container=upload&file=test.txt"
```

## Migration Checklist

- [ ] Install Azure CLI: `az --version`
- [ ] Authenticate: `az login`
- [ ] Create `.env` from `.env.sample`
- [ ] Update `AZURE_STORAGE_ACCOUNT_NAME` in `.env`
- [ ] **Remove** `Azure_Storage_AccountKey` from environment
- [ ] Assign RBAC roles to your user (for local dev):
  - [ ] Storage Blob Data Contributor
  - [ ] Storage Blob Delegator
- [ ] Install dependencies: `npm install`
- [ ] Build project: `npm run build`
- [ ] Test server: `npm run dev`
- [ ] Test health endpoint: `curl http://localhost:3000/health`
- [ ] Test authentication: Check `/api/status` shows correct storage account

## Troubleshooting

### Issue: "Missing required app configuration"
**v1**: Check `local.settings.json` has account key
**v2**: Not applicable - uses managed identity

### Issue: "DefaultAzureCredential failed"
**v2 Only**:
1. Run `az login`
2. Check subscription: `az account show`
3. Verify RBAC roles assigned

### Issue: "Status code 403 (Forbidden)"
**v1**: Check account key is correct
**v2**: Check RBAC roles assigned to user/identity

## Best Practices

### v1 (Legacy - Not Recommended)
- Store keys in Azure Key Vault
- Rotate keys regularly
- Never commit `local.settings.json` to git

### v2 (Recommended)
- Use managed identity everywhere
- Assign least-privilege RBAC roles
- Use `DefaultAzureCredential` pattern
- Never store secrets in code or config
- Use Infrastructure as Code (Bicep)

## Summary

| Aspect | v1 | v2 |
|--------|----|----|
| **Authentication** | Storage account keys | Managed identity |
| **Security** | ❌ Keys in config | ✅ No secrets |
| **Setup** | Manual key management | `az login` |
| **Deployment** | Manual config | Infrastructure as Code |
| **Audit** | Limited | Full Azure AD logs |
| **Rotation** | Manual | Automatic |
| **Best Practice** | ❌ Deprecated pattern | ✅ Recommended |

**Recommendation**: Migrate to v2 for better security, easier maintenance, and Azure best practices compliance.
