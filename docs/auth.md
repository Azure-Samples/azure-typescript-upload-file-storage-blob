# Azure Storage Authentication & Authorization Troubleshooting

## Problem Summary

When running the API server locally against Azure Storage, SAS token generation was failing with the error:

```
"This request is not authorized to perform this operation."
RequestId: 8dc151ad-301e-0092-324f-6ce161000000
```

The API uses **User Delegation SAS tokens** (Azure AD-based) instead of account keys for better security.

## Investigation Process

### Step 1: Verify RBAC Role Assignments

First, we checked if the required Azure RBAC roles were assigned to the user.

**Required roles for User Delegation SAS:**
- **Storage Blob Data Contributor** - Read/write blob data
- **Storage Blob Delegator** - Generate user delegation keys

**Check role assignments:**
```bash
STORAGE_ACCOUNT=$(azd env get-value AZURE_STORAGE_ACCOUNT_NAME)
RESOURCE_GROUP=$(azd env get-value AZURE_RESOURCE_GROUP)
USER_ID=$(az ad signed-in-user show --query id -o tsv)

az role assignment list \
  --assignee $USER_ID \
  --scope "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Storage/storageAccounts/$STORAGE_ACCOUNT" \
  --output table
```

**Result:** ✅ Both roles were correctly assigned via Bicep automation

### Step 2: Check Role Assignment Timing

RBAC role assignments can take 5-10 minutes to propagate across Azure's distributed systems.

**Check when roles were assigned:**
```bash
az role assignment list \
  --assignee $(az ad signed-in-user show --query id -o tsv) \
  --scope "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Storage/storageAccounts/$STORAGE_ACCOUNT" \
  --query "[?roleDefinitionName=='Storage Blob Delegator'].{Role:roleDefinitionName,CreatedOn:createdOn}" \
  --output table
```

**Result:** Roles were assigned 4 hours ago, so propagation delay was not the issue.

### Step 3: Refresh Azure CLI Token

Sometimes cached credentials can cause issues.

**Clear and re-authenticate:**
```bash
az account clear
az login --tenant 888d76fa-54b2-4ced-8ee5-aac1585adee7
```

**Force storage token refresh:**
```bash
az account get-access-token --resource https://storage.azure.com/ --query accessToken -o tsv
```

**Result:** Token was refreshed but issue persisted.

### Step 4: Test with Azure CLI Directly

To isolate if this was a Node.js SDK issue or an Azure permissions issue:

```bash
STORAGE_ACCOUNT=$(azd env get-value AZURE_STORAGE_ACCOUNT_NAME)

az storage blob generate-sas \
  --account-name "$STORAGE_ACCOUNT" \
  --container-name upload \
  --name test.txt \
  --permissions r \
  --expiry $(date -u -d '+10 minutes' '+%Y-%m-%dT%H:%MZ') \
  --auth-mode login \
  --as-user
```

**Result:** 🎯 Error revealed: "The request may be blocked by network rules of storage account."

### Step 5: Check Storage Account Network Rules

**THE ROOT CAUSE WAS FOUND HERE:**

```bash
STORAGE_ACCOUNT=$(azd env get-value AZURE_STORAGE_ACCOUNT_NAME)
RESOURCE_GROUP=$(azd env get-value AZURE_RESOURCE_GROUP)

az storage account show \
  --name "$STORAGE_ACCOUNT" \
  --resource-group "$RESOURCE_GROUP" \
  --query "networkRuleSet" \
  --output json
```

**Result:**
```json
{
  "bypass": "AzureServices",
  "defaultAction": "Deny",      // ❌ BLOCKING ALL ACCESS
  "ipRules": [],                 // No IPs allowed
  "ipv6Rules": [],
  "resourceAccessRules": null,
  "virtualNetworkRules": []
}
```

## Root Cause

The storage account firewall was configured with `"defaultAction": "Deny"`, blocking all access by default. Since no IP rules were configured, the local development machine couldn't access the storage account API to generate user delegation keys.

**This is a network-level block, not an authorization issue.**

## Solution

### Option 1: Update Bicep (Recommended)

Modified `infra/main.bicep` to allow network access:

```bicep
module storage 'br/public:avm/res/storage/storage-account:0.30.0' = {
  name: 'storage'
  scope: rg
  params: {
    name: '${abbrs.storageStorageAccounts}${resourceToken}'
    location: location
    tags: tags
    kind: 'StorageV2'
    skuName: 'Standard_LRS'
    allowBlobPublicAccess: true
    networkAcls: {
      defaultAction: 'Allow'  // Allow access from all networks
      bypass: 'AzureServices'
    }
    roleAssignments: [
      // ... role assignments
    ]
  }
}
```

**Deploy the change:**
```bash
azd up
```

### Option 2: Quick Manual Fix (For Testing)

```bash
STORAGE_ACCOUNT=$(azd env get-value AZURE_STORAGE_ACCOUNT_NAME)
RESOURCE_GROUP=$(azd env get-value AZURE_RESOURCE_GROUP)

az storage account update \
  --name "$STORAGE_ACCOUNT" \
  --resource-group "$RESOURCE_GROUP" \
  --default-action Allow
```

### Option 3: Production-Ready (Specific IP Rules)

For production, use specific IP allowlists instead of allowing all:

```bicep
networkAcls: {
  defaultAction: 'Deny'
  bypass: 'AzureServices'
  ipRules: [
    {
      value: '203.0.113.42'  // Your office IP
      action: 'Allow'
    }
  ]
}
```

Or via CLI:
```bash
az storage account network-rule add \
  --account-name "$STORAGE_ACCOUNT" \
  --resource-group "$RESOURCE_GROUP" \
  --ip-address 203.0.113.42
```

## Testing the Fix

After updating network rules, restart the API server to verify:

```bash
npm run start:api
```

You should see:
```
🔐 Verifying storage permissions for account: stv2daytfgtvjwm
  ✓ Testing storage account access...
  ✓ Storage account access: OK
  ✓ Testing user delegation key generation...
  ✓ User delegation key: OK
  ✓ Storage Blob Delegator role: VERIFIED
  ✓ Testing blob data access...
  ✓ Blob data access: OK
  ✓ Storage Blob Data Contributor role: VERIFIED

✅ All storage permissions verified successfully!
```

## Key Learnings

1. **RBAC roles alone are not sufficient** - Network rules must also allow access
2. **Test with Azure CLI first** - Helps isolate SDK vs. Azure configuration issues
3. **Check network rules** - Often overlooked when troubleshooting auth issues
4. **Use startup verification** - The added permission checks in `server.ts` immediately identify issues
5. **DefaultAzureCredential is correct** - No special configuration needed for user-assigned managed identities

## Environment Variable Configuration

The API requires these environment variables:

```bash
# Storage Account (required)
AZURE_STORAGE_ACCOUNT_NAME=stv2xxxxx

# Managed Identity (for Container Apps in production)
AZURE_CLIENT_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx

# Application Settings
NODE_ENV=development
PORT=3000
```

## How Bicep Automation Works

The `azure.yaml` includes a `preprovision` hook that:

1. Gets your user's principal ID: `az ad signed-in-user show --query id -o tsv`
2. Sets it as an environment variable: `azd env set AZURE_PRINCIPAL_ID "$PRINCIPAL_ID"`
3. Passes it to Bicep via `main.parameters.json`: `"principalId": { "value": "${AZURE_PRINCIPAL_ID}" }`
4. Bicep conditionally assigns RBAC roles if `principalId` is provided

This ensures developers automatically get the necessary permissions when running `azd provision`.

## Troubleshooting Commands Reference

### Check your Azure login status
```bash
az account show
```

### Get your user principal ID
```bash
az ad signed-in-user show --query id -o tsv
```

### List all role assignments on a storage account
```bash
az role assignment list \
  --scope "/subscriptions/SUBSCRIPTION_ID/resourceGroups/RESOURCE_GROUP/providers/Microsoft.Storage/storageAccounts/STORAGE_ACCOUNT" \
  --output table
```

### Check storage account authentication settings
```bash
az storage account show \
  --name STORAGE_ACCOUNT \
  --resource-group RESOURCE_GROUP \
  --query "{allowSharedKeyAccess:allowSharedKeyAccess,networkRuleSet:networkRuleSet}"
```

### Test blob access with Azure AD
```bash
az storage blob list \
  --account-name STORAGE_ACCOUNT \
  --container-name upload \
  --auth-mode login
```

### View storage account firewall rules
```bash
az storage account show \
  --name STORAGE_ACCOUNT \
  --resource-group RESOURCE_GROUP \
  --query "networkRuleSet"
```

## Related Documentation

- [Azure Storage User Delegation SAS](https://learn.microsoft.com/azure/storage/common/storage-sas-overview#user-delegation-sas)
- [Storage Blob Delegator Role](https://learn.microsoft.com/azure/role-based-access-control/built-in-roles#storage-blob-delegator)
- [Storage Account Firewalls and Virtual Networks](https://learn.microsoft.com/azure/storage/common/storage-network-security)
- [DefaultAzureCredential Documentation](https://learn.microsoft.com/javascript/api/@azure/identity/defaultazurecredential)
