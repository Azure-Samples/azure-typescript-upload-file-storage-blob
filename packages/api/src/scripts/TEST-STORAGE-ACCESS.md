# Testing Storage Access

This guide explains how to test storage permissions with both your local user account and the managed identity.

## Prerequisites

1. Ensure you're logged into Azure CLI:
   ```bash
   az login
   ```

2. Set your subscription:
   ```bash
   az account set --subscription <subscription-id>
   ```

3. Build the API:
   ```bash
   cd packages/api
   npm run build
   ```

## Test 1: Local User Credentials

This tests if **your Azure user account** has the necessary permissions.

### Step 1: Get the storage account name
```bash
# From the workspace root
azd env get-values | grep AZURE_STORAGE_ACCOUNT_NAME
```

### Step 2: Export the variable
```bash
export AZURE_STORAGE_ACCOUNT_NAME="<your-storage-account-name>"
```

### Step 3: Run the test
```bash
cd packages/api
npm run test:storage
```

**What's being tested:**
- Uses `DefaultAzureCredential` which picks up your Azure CLI credentials
- Tests if YOUR user has the required RBAC roles on the storage account
- Required roles for your user:
  - Storage Blob Data Contributor
  - Storage Blob Delegator

**Note:** The Bicep file conditionally assigns these roles to your user if you provided a `principalId` during `azd provision`.

---

## Test 2: Managed Identity (Container App)

This tests if the **managed identity** created by Bicep has the necessary permissions.

### Option A: Check Container App Logs (Recommended)

The API server runs the same verification on startup, so you can check the logs:

```bash
# Get the resource group and container app name
azd env get-values | grep AZURE_RESOURCE_GROUP
azd env get-values | grep AZURE_CONTAINER_APP_API_NAME

# View recent logs
az containerapp logs show \
  --name <api-app-name> \
  --resource-group <resource-group-name> \
  --follow
```

Look for the verification output that starts with:
```
🔐 Verifying storage permissions for account: ...
```

### Option B: Execute Command in Container (Advanced)

Run the test script directly inside the running container:

```bash
# Get container app details
RESOURCE_GROUP=$(azd env get-values | grep AZURE_RESOURCE_GROUP | cut -d'=' -f2 | tr -d '"')
API_APP_NAME=$(azd env get-values | grep AZURE_CONTAINER_APP_API_NAME | cut -d'=' -f2 | tr -d '"')

# Execute the test in the container
az containerapp exec \
  --name "$API_APP_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --command "node dist/scripts/test-storage-access.js"
```

**What's being tested:**
- Uses the user-assigned managed identity attached to the container app
- Tests the managed identity's RBAC roles
- Required roles (assigned in Bicep):
  - Storage Blob Data Contributor
  - Storage Blob Delegator

---

## Test 3: Simulate Managed Identity Locally (Advanced)

You can test with the managed identity locally using Azure CLI:

```bash
# Get the managed identity client ID
MANAGED_IDENTITY_CLIENT_ID=$(azd env get-values | grep AZURE_CLIENT_ID | cut -d'=' -f2 | tr -d '"')

# Set the environment variable
export AZURE_CLIENT_ID="$MANAGED_IDENTITY_CLIENT_ID"

# Run the test - DefaultAzureCredential will try to use this managed identity
cd packages/api
npm run test:storage
```

**Note:** This only works if:
1. You're running on an Azure VM with the managed identity assigned, OR
2. You're testing in a container with managed identity access

Otherwise, it will fall back to Azure CLI credentials.

---

## Troubleshooting

### "Cannot access storage account"

**Cause:** Missing Reader role or RBAC propagation delay

**Fix:**
```bash
# Re-run provision to ensure roles are assigned
azd provision

# Wait 5-10 minutes for RBAC propagation
```

### "Missing required role: Storage Blob Delegator"

**Cause:** The identity doesn't have permission to generate user delegation keys

**Fix:** Check that the role is assigned in `infra/main.bicep`:
```bicep
roleAssignments: [
  {
    principalId: managedIdentity.outputs.principalId
    roleDefinitionIdOrName: 'db58b8e5-c6ad-4a2a-8342-4190687cbf4a' // Storage Blob Delegator
    principalType: 'ServicePrincipal'
  }
]
```

### "Missing required role: Storage Blob Data Contributor"

**Cause:** The identity can't read/write blob data

**Fix:** Check that the role is assigned in `infra/main.bicep`:
```bicep
roleAssignments: [
  {
    principalId: managedIdentity.outputs.principalId
    roleDefinitionIdOrName: 'ba92f5b4-2d11-453d-a403-e96b0029c9fe' // Storage Blob Data Contributor
    principalType: 'ServicePrincipal'
  }
]
```

---

## Understanding RBAC Propagation

Azure RBAC role assignments can take **5-10 minutes** to propagate. If tests fail immediately after `azd provision`:

1. ✅ This is expected behavior
2. ⏰ Wait 5-10 minutes
3. 🔄 Run the test again
4. 📊 The verification script has built-in retry logic (3 attempts, 2-second delays)

---

## Quick Reference

```bash
# Test with your local user
export AZURE_STORAGE_ACCOUNT_NAME="<storage-account-name>"
cd packages/api
npm run test:storage

# View container app logs (managed identity test)
az containerapp logs show \
  --name <api-app-name> \
  --resource-group <resource-group-name> \
  --follow

# Get all environment values
azd env get-values
```
