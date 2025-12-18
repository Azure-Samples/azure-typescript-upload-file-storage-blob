# User Delegation SAS Tokens Guide

## Overview

The v2 API uses **user delegation SAS tokens** instead of account key-based SAS tokens. This is a critical security improvement that aligns with Azure best practices.

## What are User Delegation SAS Tokens?

User delegation SAS tokens are Shared Access Signatures that are secured with **Microsoft Entra ID (Azure AD) credentials** instead of storage account keys.

### Key Differences

| Feature | Account Key SAS (v1) | User Delegation SAS (v2) |
|---------|---------------------|-------------------------|
| **Authentication** | Storage account key | Microsoft Entra ID |
| **Security** | ❌ Requires managing keys | ✅ No keys needed |
| **Audit Trail** | Limited | ✅ Full Azure AD logs |
| **Rotation** | Manual key rotation | ✅ Automatic |
| **Permissions** | Account-level | ✅ RBAC-based |
| **Best Practice** | ❌ Deprecated | ✅ Recommended |

## Implementation Details

### Code Location

`src/routes/sas.ts` - SAS token generation endpoint

### How It Works

```typescript
// 1. Get BlobServiceClient using managed identity
const blobServiceClient = getBlobServiceClient(accountName);

// 2. Define token validity period (REQUIRED for expiration policy)
const startsOn = new Date();
const expiresOn = new Date(startsOn.valueOf() + 10 * 60 * 1000); // 10 minutes

// 3. Get user delegation key from Azure AD
const userDelegationKey = await blobServiceClient.getUserDelegationKey(
  startsOn,
  expiresOn
);

// 4. Generate SAS token using the delegation key
const sasToken = generateBlobSASQueryParameters(
  {
    containerName: 'upload',
    blobName: 'file.txt',
    permissions: BlobSASPermissions.parse('w'), // write only
    startsOn,    // REQUIRED for expiration policy compliance
    expiresOn    // REQUIRED for expiration policy compliance
  },
  userDelegationKey,
  accountName
).toString();
```

### Required RBAC Roles

To generate user delegation SAS tokens, the identity needs:

1. **Storage Blob Data Contributor** (ba92f5b4-2d11-453d-a403-e96b0029c9fe)
   - Required for blob operations
   - Already assigned in `infra/main.bicep`

2. **Storage Blob Delegator** (db58b8e5-c6ad-4a2a-8342-4190687cbf4a)
   - Required specifically for `getUserDelegationKey()` operation
   - Already assigned in `infra/main.bicep`

## SAS Expiration Policy Compliance

### What is SAS Expiration Policy?

Azure Storage now supports **SAS expiration policies** that enforce maximum token lifetimes to improve security.

**Policy Types**:
- **Warn**: Logs warnings but allows tokens
- **Log**: Logs violations for audit
- **Block**: Rejects non-compliant tokens ❌

### Compliance Requirements

To comply with SAS expiration policies, tokens MUST include:

1. **`startsOn`** - Token start time (required, not optional)
2. **`expiresOn`** - Token expiry time
3. **Duration** - `expiresOn - startsOn` must be within policy limit

### Our Implementation

✅ **Compliant by default**:

```typescript
// Always includes startsOn (required)
const startsOn = new Date();

// Configurable duration (default 10 minutes)
const timerangeMinutes = parseInt(timerange, 10);
const expiresOn = new Date(startsOn.valueOf() + timerangeMinutes * 60 * 1000);

// Both parameters passed to SAS generation
const sasToken = generateBlobSASQueryParameters({
  startsOn,    // ✅ Included
  expiresOn,   // ✅ Included
  // ...
}, userDelegationKey, accountName);
```

### Recommended Durations

| Use Case | Recommended Duration | Notes |
|----------|---------------------|-------|
| **File Upload** | 5-15 minutes | Short-lived, single operation |
| **Batch Upload** | 30 minutes - 1 hour | Multiple files |
| **Download** | 15-30 minutes | User-facing downloads |
| **Development** | 10 minutes | Default for testing |

**Best Practice**: Use the shortest duration that satisfies your use case.

## API Usage

### Endpoint

```
GET /api/sas?container={container}&file={filename}&permission={perms}&timerange={minutes}
```

### Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `container` | string | `upload` | Container name |
| `file` | string | **required** | Blob name |
| `permission` | string | `w` | Permissions (r/w/d/l/a/c) |
| `timerange` | number | `10` | Token duration in minutes |

### Permission Codes

- `r` - Read
- `w` - Write
- `d` - Delete
- `l` - List
- `a` - Add (append)
- `c` - Create

**Example**: `w` = write only (most secure for upload)

### Example Requests

#### Generate Upload Token (10 minutes)
```bash
curl "http://localhost:3000/api/sas?container=upload&file=image.png"
```

**Response**:
```json
{
  "url": "https://storage.blob.core.windows.net/upload/image.png?sv=2021-06-08&se=2025-12-10T16%3A20%3A00Z&sr=b&sp=w&sig=..."
}
```

#### Generate Upload Token (30 minutes)
```bash
curl "http://localhost:3000/api/sas?container=upload&file=document.pdf&timerange=30"
```

#### Generate Read Token
```bash
curl "http://localhost:3000/api/sas?container=upload&file=image.png&permission=r"
```

### Verifying SAS Token Parameters

Parse the SAS URL to verify it includes required parameters:

```bash
# Extract query parameters
curl -s "http://localhost:3000/api/sas?container=upload&file=test.txt" | \
  jq -r '.url' | \
  sed 's/.*?//' | \
  tr '&' '\n'
```

**Expected output includes**:
```
sv=2021-06-08         # API version
st=2025-12-10T16:10:00Z   # Start time (✅ required)
se=2025-12-10T16:20:00Z   # Expiry time (✅ required)
sr=b                   # Resource type (blob)
sp=w                   # Permissions (write)
sig=...                # Signature
skoid=...              # Delegation key info
```

## Security Benefits

### 1. No Keys in Code or Configuration

**v1 (Account Key SAS)**:
```typescript
// ❌ Account key exposed
const credential = new StorageSharedKeyCredential(
  accountName,
  process.env.AZURE_STORAGE_ACCOUNT_KEY  // Key in config!
);
```

**v2 (User Delegation SAS)**:
```typescript
// ✅ No keys needed
const credential = new DefaultAzureCredential();
// Uses managed identity automatically
```

### 2. Better Audit Trail

- ✅ All operations logged in Azure AD
- ✅ Can track which identity generated tokens
- ✅ Can track which identity accessed blobs
- ✅ Compliance-ready audit logs

### 3. Automatic Credential Rotation

- ✅ User delegation keys are short-lived (max 7 days)
- ✅ No manual key rotation required
- ✅ Reduced risk of key compromise

### 4. Granular Permissions

- ✅ RBAC-based access control
- ✅ Can assign different roles to different identities
- ✅ Follows principle of least privilege

## Testing

### Local Development Testing

```bash
# 1. Ensure authenticated
az login
az account show

# 2. Start server
cd packages/api
npm run dev

# 3. Generate SAS token
curl -s "http://localhost:3000/api/sas?container=upload&file=test.txt" | jq

# 4. Use the SAS URL to upload
curl -X PUT \
  -H "x-ms-blob-type: BlockBlob" \
  -H "Content-Type: text/plain" \
  --data "Hello, World!" \
  "$(curl -s 'http://localhost:3000/api/sas?container=upload&file=test.txt' | jq -r '.url')"
```

### Automated Testing

See `tests/sas.test.ts` for comprehensive tests including:
- ✅ Token generation
- ✅ Parameter validation
- ✅ Expiration policy compliance
- ✅ Permission verification
- ✅ Error handling

## Troubleshooting

### Error: "Status code 403 (Forbidden)"

**Cause**: Missing "Storage Blob Delegator" role

**Solution**:
```bash
# For local dev
az role assignment create \
  --role "Storage Blob Delegator" \
  --assignee $(az account show --query user.name -o tsv) \
  --scope /subscriptions/SUB/resourceGroups/RG/providers/Microsoft.Storage/storageAccounts/STORAGE

# For Container Apps (already configured in Bicep)
# Role is assigned to system-assigned managed identity
```

### Error: "getUserDelegationKey operation failed"

**Causes**:
1. Not authenticated to Azure
2. Missing Storage Blob Delegator role
3. Storage account doesn't support user delegation

**Solutions**:
1. Run `az login`
2. Assign required roles (see above)
3. Ensure Storage Account kind is `StorageV2` or `BlobStorage`

### Token Validation Fails

**Cause**: Missing `startsOn` parameter (expiration policy requirement)

**Solution**: Already implemented in v2 - both `startsOn` and `expiresOn` are always included

## References

- [User delegation SAS documentation](https://learn.microsoft.com/azure/storage/common/storage-sas-overview#user-delegation-sas)
- [SAS expiration policy](https://learn.microsoft.com/azure/storage/common/sas-expiration-policy)
- [RBAC roles for Storage](https://learn.microsoft.com/azure/storage/blobs/assign-azure-role-data-access)
- [Storage Blob Delegator role](https://learn.microsoft.com/azure/role-based-access-control/built-in-roles#storage-blob-delegator)

## Summary

✅ **v2 API implements secure user delegation SAS tokens**:
- No storage account keys required
- Microsoft Entra ID-based authentication
- Full compliance with SAS expiration policies
- Better audit trail and security
- Automatic credential rotation
- RBAC-based access control

This is the recommended approach for all new Azure Storage applications.
