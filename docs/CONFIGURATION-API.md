# API Configuration Guide

## Environment Variables

The v2 API uses environment variables instead of `local.settings.json`. This provides better security and portability.

### Required Environment Variables

| Variable | Description | Example | Required |
|----------|-------------|---------|----------|
| `NODE_ENV` | Environment mode | `development` or `production` | No (defaults to development) |
| `PORT` | Server port | `3000` | No (defaults to 3000) |
| `AZURE_STORAGE_ACCOUNT_NAME` | Azure Storage account name | `mystorageaccount` | **Yes** |
| `WEB_URL` | Frontend URL for CORS | `http://localhost:8080` | No (defaults to `*`) |

### Setting Up Local Development

1. **Copy the sample environment file**:
   ```bash
   cp .env.sample .env
   ```

2. **Edit `.env` and update values**:
   ```env
   NODE_ENV=development
   PORT=3000
   AZURE_STORAGE_ACCOUNT_NAME=your-actual-storage-account-name
   WEB_URL=http://localhost:8080
   ```

3. **Authenticate with Azure CLI** (required for local development):
   ```bash
   az login
   az account show
   ```

   The API uses `DefaultAzureCredential` which automatically uses your Azure CLI credentials locally.

4. **Verify your user has required permissions** on the Storage Account:
   - Storage Blob Data Contributor
   - Storage Blob Delegator

   To check:
   ```bash
   az role assignment list --assignee $(az account show --query user.name -o tsv) --scope /subscriptions/YOUR_SUB/resourceGroups/YOUR_RG/providers/Microsoft.Storage/storageAccounts/YOUR_STORAGE
   ```

### Production Configuration (Container Apps)

In production, environment variables are set via:
1. **Bicep/ARM template** (preferred - already configured in `infra/main.bicep`)
2. **Azure Portal** - Container App → Settings → Environment variables
3. **Azure CLI**:
   ```bash
   az containerapp update \
     --name YOUR_API_APP \
     --resource-group YOUR_RG \
     --set-env-vars \
       NODE_ENV=production \
       PORT=3000 \
       AZURE_STORAGE_ACCOUNT_NAME=YOUR_STORAGE \
       WEB_URL=https://your-frontend-url
   ```

**Important**: No `AZURE_STORAGE_ACCOUNT_KEY` needed! The API uses system-assigned managed identity in production.

### Comparison: v1 vs v2

#### v1 (Azure Functions)
```json
{
  "Values": {
    "Azure_Storage_AccountName": "storage",
    "Azure_Storage_AccountKey": "SECRET_KEY_HERE",  // ❌ Security risk
    "AzureWebJobsStorage": "CONNECTION_STRING"       // ❌ Not needed
  }
}
```

#### v2 (Fastify)
```env
NODE_ENV=development
AZURE_STORAGE_ACCOUNT_NAME=storage  # ✅ Only account name
# No keys needed! Uses managed identity
```

### Authentication Flow

#### Local Development
```
DefaultAzureCredential
  ↓
Azure CLI Credential (from `az login`)
  ↓
Your Azure user identity
  ↓
Storage Account (via RBAC)
```

#### Production (Container Apps)
```
DefaultAzureCredential
  ↓
Managed Identity Credential
  ↓
System-assigned managed identity
  ↓
Storage Account (via RBAC)
```

### Troubleshooting

#### Error: "AZURE_STORAGE_ACCOUNT_NAME environment variable is required"
**Solution**: Set the variable in `.env` file

#### Error: "DefaultAzureCredential failed to retrieve a token"
**Causes**:
1. Not logged in to Azure CLI
   ```bash
   az login
   ```
2. Logged in to wrong subscription
   ```bash
   az account list --output table
   az account set --subscription YOUR_SUBSCRIPTION_ID
   ```
3. User lacks RBAC permissions on Storage Account
   ```bash
   # Have admin assign roles:
   az role assignment create \
     --role "Storage Blob Data Contributor" \
     --assignee YOUR_EMAIL \
     --scope /subscriptions/.../storageAccounts/YOUR_STORAGE
   ```

#### Error: "Status code 403 (Forbidden)" when generating SAS
**Cause**: Missing "Storage Blob Delegator" role for user delegation SAS

**Solution**:
```bash
az role assignment create \
  --role "Storage Blob Delegator" \
  --assignee YOUR_EMAIL \
  --scope /subscriptions/.../storageAccounts/YOUR_STORAGE
```

### Security Notes

✅ **DO**:
- Use `.env` for local development
- Add `.env` to `.gitignore`
- Use `DefaultAzureCredential` for authentication
- Use managed identity in production

❌ **DON'T**:
- Commit `.env` to git
- Store account keys in code
- Use connection strings
- Hard-code credentials

### Next Steps

After configuration:
1. Start the server: `npm run dev`
2. Test health endpoint: `curl http://localhost:3000/health`
3. Test authentication: `curl http://localhost:3000/api/status`
4. Proceed to Phase 1.4 (User Delegation SAS Tokens)
