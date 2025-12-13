# SAS Token Architecture: User Delegation Pattern

## Overview

### What are SAS Tokens?

**Shared Access Signatures (SAS)** are URL-based tokens that grant limited, time-bound access to Azure Storage resources without exposing account keys.

### Why Use User Delegation SAS?

Traditional SAS tokens are signed with **storage account keys**, which:
- ❌ Are permanent credentials (like passwords)
- ❌ Have unlimited access to the entire storage account
- ❌ Cannot be easily rotated without breaking existing tokens
- ❌ Bypass Azure RBAC and audit trails
- ❌ Violate zero-trust security principles

**User Delegation SAS tokens** are signed with **Microsoft Entra ID credentials**, which:
- ✅ Use temporary, identity-based authentication
- ✅ Respect Azure RBAC permissions
- ✅ Provide full audit trail in Azure Activity Log
- ✅ Auto-expire with identity token (no long-lived secrets)
- ✅ Follow principle of least privilege
- ✅ Enable keyless (passwordless) architecture

### This Application's Approach

This project implements **User Delegation SAS with Managed Identity**, the most secure SAS pattern available:

```
Container App → Managed Identity → User Delegation Key → SAS Token
        ↓              ↓                    ↓                ↓
   No secrets    Azure RBAC          Temp token      Time-limited access
```

## Architecture Details

### Component Flow Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                         User Request                            │
│                                                                  │
│  Frontend          API Server        Azure Storage              │
│    │                  │                    │                     │
│    │──① Request SAS───▶│                    │                     │
│    │                  │──② Request User─────▶│                     │
│    │                  │    Delegation Key    │                     │
│    │                  │                    │                     │
│    │                  │◀──③ Return Key──────│                     │
│    │                  │                    │                     │
│    │                  │──④ Generate SAS────▶│                     │
│    │                  │    (signed with key)│                     │
│    │                  │                    │                     │
│    │◀─⑤ Return SAS URL─│                    │                     │
│    │                  │                    │                     │
│    │────────────⑥ Upload File (with SAS)────────────▶│           │
│    │                  │                    │                     │
│    │◀───────────⑦ 201 Created ─────────────│                     │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘

Authentication:
Step ②: API uses Managed Identity (DefaultAzureCredential)
Step ③: Azure validates identity has "Storage Blob Delegator" role
Step ⑥: Azure validates SAS signature matches User Delegation Key
```

### Component Responsibilities

#### Frontend (React)
**Role**: SAS token consumer

**Responsibilities**:
1. Request SAS token from API with file metadata
2. Receive time-limited SAS URL
3. Upload file directly to Azure Storage using SAS URL
4. Handle token expiration (request new token if needed)

**Does NOT**:
- Authenticate with Azure directly
- Store or manage Azure credentials
- Generate SAS tokens

#### API Server (Fastify)
**Role**: SAS token generator and gatekeeper

**Responsibilities**:
1. Authenticate to Azure using Managed Identity
2. Validate user requests (file name, container, permissions)
3. Request User Delegation Key from Azure
4. Generate SAS token signed with User Delegation Key
5. Return SAS URL to frontend
6. Log all SAS generation operations

**Does NOT**:
- Perform file uploads (frontend uploads directly)
- Store files
- Manage long-lived credentials

#### Azure Blob Storage
**Role**: Storage provider and SAS validator

**Responsibilities**:
1. Issue User Delegation Keys to authorized identities
2. Validate SAS token signatures
3. Enforce SAS permissions (read/write/delete)
4. Enforce SAS time bounds (startTime/expiryTime)
5. Store uploaded blobs
6. Log all operations for audit

**Does NOT**:
- Generate SAS tokens (API does this)
- Validate application logic (API does this)

#### Managed Identity
**Role**: Azure-managed service principal

**Responsibilities**:
1. Provide cryptographic identity to Container App
2. Eliminate need for secrets/keys in application
3. Enable RBAC-based access control
4. Automatically rotate underlying credentials

**Does NOT**:
- Require configuration in application code
- Store credentials in environment variables
- Need manual rotation

## Design Decisions

### Why User Delegation SAS Instead of Account Key SAS?

| Aspect | Account Key SAS | User Delegation SAS |
|--------|-----------------|---------------------|
| **Signing Credential** | Storage account key (permanent) | User delegation key (temporary, 7 days max) |
| **Authentication** | Account key (like a password) | Microsoft Entra ID (identity-based) |
| **RBAC Integration** | No - bypasses RBAC | Yes - respects RBAC |
| **Audit Trail** | Limited | Full Azure Activity Log |
| **Credential Rotation** | Manual, breaks existing SAS | Automatic, no impact |
| **Principle of Least Privilege** | No - account key has full access | Yes - limited to identity's RBAC roles |
| **Zero Trust Compliance** | No - permanent secrets | Yes - temporary, identity-based |
| **Recommended by Microsoft** | ⚠️ Legacy approach | ✅ Best practice |

**Decision**: Use User Delegation SAS for security, compliance, and operational simplicity.

### Why Managed Identity Instead of Service Principal?

| Aspect | Service Principal | Managed Identity |
|--------|-------------------|------------------|
| **Credential Management** | Manual - store client secret | Automatic - no secrets |
| **Credential Rotation** | Manual - rotate before expiry | Automatic - Azure handles |
| **Environment Variables** | AZURE_CLIENT_ID, AZURE_CLIENT_SECRET, AZURE_TENANT_ID | AZURE_CLIENT_ID (optional) |
| **Secret Storage** | Key Vault or environment | None needed |
| **Attack Surface** | Client secret can leak | No credential to leak |
| **Setup Complexity** | Register app, create secret, assign roles | Create identity, assign roles |

**Decision**: Use Managed Identity to eliminate secret management burden and attack surface.

### Why Generate SAS on Backend Instead of Frontend?

| Aspect | Frontend SAS Generation | Backend SAS Generation |
|--------|------------------------|------------------------|
| **Security** | ❌ Exposes Azure credentials to browser | ✅ Credentials stay server-side |
| **Control** | ❌ Users could modify permissions/duration | ✅ Server enforces policies |
| **Audit** | ❌ Client-side actions not logged centrally | ✅ All SAS generation logged |
| **Flexibility** | ❌ Hard to change logic without redeploying frontend | ✅ Backend can evolve independently |

**Decision**: Generate SAS tokens server-side to maintain security and control.

### Why Direct Upload Instead of Proxy Upload?

| Aspect | Upload Through API | Direct Upload with SAS |
|--------|-------------------|------------------------|
| **Network Path** | Client → API → Storage (2 hops) | Client → Storage (1 hop) |
| **API Bandwidth** | High (receives full file) | Low (only generates SAS) |
| **Latency** | Higher (double transfer) | Lower (single transfer) |
| **API Resources** | High memory, CPU for buffering | Minimal (just SAS generation) |
| **Scalability** | API becomes bottleneck | Storage scales independently |
| **Cost** | Higher (API data transfer + compute) | Lower (minimal API usage) |

**Decision**: Use direct upload with SAS to reduce latency, cost, and API load.

### Tradeoffs Made

#### ✅ Benefits
1. **Security**: Keyless, identity-based, RBAC-enforced
2. **Scalability**: Direct uploads don't burden API
3. **Cost**: Lower API compute and bandwidth
4. **Compliance**: Full audit trail, zero-trust aligned
5. **Operational**: No secrets to rotate or manage

#### ⚠️ Tradeoffs
1. **Complexity**: Requires understanding SAS tokens and Managed Identity
2. **Latency**: Two-step process (get SAS, then upload) vs single API call
3. **Client Logic**: Frontend must handle SAS tokens and retries
4. **CORS**: Storage account must allow CORS from frontend domains

#### 📊 Cost/Performance Implications

**Cost Savings**:
- **API Container Apps**: Lower CPU/memory requirements (0.5 CPU, 1Gi memory sufficient)
- **Data Transfer**: No egress from API to storage (direct upload)
- **Scaling**: API can scale to zero when idle

**Performance Gains**:
- **Upload Speed**: Single-hop vs double-hop (50% faster)
- **API Latency**: <100ms for SAS generation vs multi-second file upload
- **Concurrency**: Storage handles uploads directly (no API queueing)

**Example**: 1000 users uploading 1MB files daily
- **Proxy Upload**: 1GB API ingress + 1GB egress + 10-30 minutes API runtime
- **Direct Upload**: 10-50 SAS requests (~1 second API runtime total)
- **Savings**: ~$5-15/month in API costs

## Implementation Patterns

### Pattern 1: Azure SDK with DefaultAzureCredential (Recommended)

**Languages**: TypeScript, Python, C#, Java

**TypeScript Example** (This Project):
```typescript
import { DefaultAzureCredential } from '@azure/identity';
import { BlobServiceClient, BlobSASPermissions, generateBlobSASQueryParameters } from '@azure/storage-blob';

// Credential automatically finds Managed Identity in Azure
// or Azure CLI credentials locally
const credential = new DefaultAzureCredential({
  managedIdentityClientId: process.env.AZURE_CLIENT_ID
});

const accountName = process.env.AZURE_STORAGE_ACCOUNT_NAME;
const blobServiceClient = new BlobServiceClient(
  `https://${accountName}.blob.core.windows.net`,
  credential
);

// Generate User Delegation SAS
const startsOn = new Date();
const expiresOn = new Date(startsOn.valueOf() + 10 * 60 * 1000); // 10 minutes

// Get user delegation key (requires "Storage Blob Delegator" role)
const userDelegationKey = await blobServiceClient.getUserDelegationKey(
  startsOn,
  expiresOn
);

// Generate SAS token
const sasToken = generateBlobSASQueryParameters(
  {
    containerName: 'upload',
    blobName: 'photo.jpg',
    permissions: BlobSASPermissions.parse('w'), // write
    startsOn,
    expiresOn
  },
  userDelegationKey,
  accountName
).toString();

const sasUrl = `https://${accountName}.blob.core.windows.net/upload/photo.jpg?${sasToken}`;
```

**Python Example**:
```python
from azure.identity import DefaultAzureCredential
from azure.storage.blob import BlobServiceClient, BlobSasPermissions, generate_blob_sas
from datetime import datetime, timedelta

credential = DefaultAzureCredential(
    managed_identity_client_id=os.getenv('AZURE_CLIENT_ID')
)

account_name = os.getenv('AZURE_STORAGE_ACCOUNT_NAME')
blob_service_client = BlobServiceClient(
    account_url=f"https://{account_name}.blob.core.windows.net",
    credential=credential
)

# Get user delegation key
starts_on = datetime.utcnow()
expires_on = starts_on + timedelta(minutes=10)

user_delegation_key = blob_service_client.get_user_delegation_key(
    key_start_time=starts_on,
    key_expiry_time=expires_on
)

# Generate SAS
sas_token = generate_blob_sas(
    account_name=account_name,
    container_name='upload',
    blob_name='photo.jpg',
    user_delegation_key=user_delegation_key,
    permission=BlobSasPermissions(write=True),
    start=starts_on,
    expiry=expires_on
)

sas_url = f"https://{account_name}.blob.core.windows.net/upload/photo.jpg?{sas_token}"
```

**C# Example**:
```csharp
using Azure.Identity;
using Azure.Storage.Blobs;
using Azure.Storage.Sas;

var credential = new DefaultAzureCredential(new DefaultAzureCredentialOptions
{
    ManagedIdentityClientId = Environment.GetEnvironmentVariable("AZURE_CLIENT_ID")
});

var accountName = Environment.GetEnvironmentVariable("AZURE_STORAGE_ACCOUNT_NAME");
var blobServiceClient = new BlobServiceClient(
    new Uri($"https://{accountName}.blob.core.windows.net"),
    credential
);

// Get user delegation key
var startsOn = DateTimeOffset.UtcNow;
var expiresOn = startsOn.AddMinutes(10);

var userDelegationKey = await blobServiceClient.GetUserDelegationKeyAsync(
    startsOn,
    expiresOn
);

// Generate SAS
var sasBuilder = new BlobSasBuilder
{
    BlobContainerName = "upload",
    BlobName = "photo.jpg",
    Resource = "b", // blob
    StartsOn = startsOn,
    ExpiresOn = expiresOn
};
sasBuilder.SetPermissions(BlobSasPermissions.Write);

var sasToken = sasBuilder.ToSasQueryParameters(
    userDelegationKey.Value,
    accountName
).ToString();

var sasUrl = $"https://{accountName}.blob.core.windows.net/upload/photo.jpg?{sasToken}";
```

### Pattern 2: REST API Direct (Low-Level)

For languages without Azure SDK, use Azure Storage REST API directly:

**1. Get User Delegation Key**
```http
POST https://{account}.blob.core.windows.net/?restype=service&comp=userdelegationkey
Authorization: Bearer {AAD_TOKEN}
Content-Type: application/xml

<?xml version="1.0" encoding="utf-8"?>
<KeyInfo>
    <Start>2025-12-13T18:00:00Z</Start>
    <Expiry>2025-12-13T18:10:00Z</Expiry>
</KeyInfo>
```

**2. Sign SAS Token**
- Construct string-to-sign from SAS parameters
- HMAC-SHA256 signature using user delegation key
- Base64-encode signature
- Append to blob URL as query string

**Complexity**: High - must implement HMAC signing, XML parsing, OAuth token acquisition.

**Recommendation**: Use SDK if available for your language.

## Prompt Engineering / Configuration

### SAS Token Configuration

This pattern uses the following SAS parameters:

| Parameter | Value | Purpose | Configurable? |
|-----------|-------|---------|---------------|
| **Signed Version (sv)** | `2025-11-05` | API version | No (SDK sets) |
| **Signed Resource (sr)** | `b` (blob) | Resource type | No |
| **Signed Permissions (sp)** | `w` (write) | Allowed operations | Yes (query param) |
| **Signed Start (st)** | Current time | Token valid from | Yes (calculated) |
| **Signed Expiry (se)** | Start + 10 min | Token valid until | Yes (timerange param) |
| **Signing Key** | User delegation key | Cryptographic signature | No (Azure provides) |

### API Request Configuration

**Query Parameter Schema**:
```typescript
interface SasRequestParams {
  file: string;           // Required: blob name
  container?: string;     // Optional: default "upload"
  permission?: string;    // Optional: default "w" (write)
  timerange?: number;     // Optional: default 10 minutes
}
```

**Permission Values**:
- `r` - Read
- `w` - Write (upload)
- `d` - Delete
- `c` - Create
- `rw` - Read and write
- `rwdc` - Full access

**Timerange Recommendations**:
- **Short files (< 10MB)**: 5-10 minutes
- **Large files (> 100MB)**: 30-60 minutes
- **Production**: Minimum viable duration (reduce exposure window)

### CORS Configuration

Storage account CORS rules must allow frontend domain:

```bicep
corsRules: [
  {
    allowedOrigins: ['https://your-frontend.azurecontainerapps.io']
    allowedMethods: ['GET', 'POST', 'PUT', 'DELETE', 'HEAD', 'OPTIONS']
    allowedHeaders: ['*']
    exposedHeaders: ['*']
    maxAgeInSeconds: 86400  // 24 hours (reduces preflight requests)
  }
]
```

**Local Development**: Use `allowedOrigins: ['*']` or add `http://localhost:5173`.

## Data Flow and Context Passing

### Request Context

```typescript
// 1. Frontend initiates request
const request = {
  fileName: 'photo.jpg',
  container: 'upload',
  permission: 'w',
  timerange: 10
};

// 2. API receives request
// Fastify automatically parses query params:
const { file, container, permission, timerange } = request.query;

// 3. API authenticates with Azure
// DefaultAzureCredential looks up Managed Identity from:
// - Environment variables (AZURE_CLIENT_ID)
// - Azure Instance Metadata Service (IMDS)
// - Returns token automatically

// 4. API requests user delegation key
// Passes:
//   - startsOn (current time)
//   - expiresOn (current + 10 minutes)
// Receives:
//   - User delegation key object with signature key

// 5. API generates SAS
// Combines:
//   - Container name
//   - Blob name
//   - Permissions
//   - Time bounds
//   - User delegation key
// Returns:
//   - SAS query string

// 6. API returns SAS URL
const response = {
  url: `https://${account}.blob.core.windows.net/${container}/${file}?${sasToken}`
};

// 7. Frontend uploads to Azure
// Uses SAS URL directly - no additional context needed
```

### Context Preservation

**Managed Identity Context** (automatic):
- Injected by Azure Container Apps platform
- Available via IMDS endpoint: `http://169.254.169.254/metadata/identity`
- SDK queries IMDS transparently
- No application code needed

**Request ID Context** (for logging):
```typescript
fastify.addHook('onRequest', (request, reply, done) => {
  request.log = request.log.child({
    requestId: request.id,
    origin: request.headers.origin
  });
  done();
});
```

**SAS Token Context** (embedded in URL):
- All SAS parameters in query string
- Stateless - no server-side session needed
- Self-contained authorization

### Error Propagation

```
Azure Error → SDK Exception → API Error Response → Frontend Error Display
```

**Example Flow**:
1. Azure rejects user delegation key request (403 Forbidden)
2. SDK throws `RestError` with status code and message
3. API catches exception, logs details, returns 500
4. Frontend receives JSON error, displays to user

**Error Details Preserved**:
```typescript
try {
  const userDelegationKey = await blobServiceClient.getUserDelegationKey(...);
} catch (error) {
  request.log.error({
    error,
    errorMessage: error.message,
    errorStack: error.stack,
    accountName
  }, 'Failed to get user delegation key');
  
  return reply.status(500).send({
    error: 'Failed to generate SAS token',
    details: error.message  // Propagate Azure error message
  });
}
```

## Error Handling and Debugging

### Common Failure Modes

#### 1. "This request is not authorized to perform this operation"

**Cause**: Missing RBAC roles on Managed Identity

**Debug**:
```bash
# Check role assignments
az role assignment list \
  --assignee <MANAGED_IDENTITY_OBJECT_ID> \
  --scope /subscriptions/<SUB>/resourceGroups/<RG>/providers/Microsoft.Storage/storageAccounts/<ACCOUNT>

# Should show:
# - Storage Blob Data Contributor
# - Storage Blob Delegator
```

**Fix**: Assign missing roles in Bicep:
```bicep
roleAssignments: [
  {
    principalId: managedIdentity.outputs.principalId
    roleDefinitionIdOrName: 'Storage Blob Data Contributor'
    principalType: 'ServicePrincipal'
  }
  {
    principalId: managedIdentity.outputs.principalId
    roleDefinitionIdOrName: 'Storage Blob Delegator'
    principalType: 'ServicePrincipal'
  }
]
```

#### 2. "AuthenticationFailed: Server failed to authenticate the request"

**Cause**: Managed Identity not configured on Container App

**Debug**:
```bash
# Check Container App identity
az containerapp show -n api-<token> -g rg-<env> --query identity

# Should show:
# {
#   "type": "UserAssigned",
#   "userAssignedIdentities": { "...": {} }
# }
```

**Fix**: Add identity to Container App:
```bicep
managedIdentities: {
  userAssignedResourceIds: [managedIdentity.outputs.resourceId]
}
```

#### 3. "CORS policy: No 'Access-Control-Allow-Origin' header"

**Cause**: Storage CORS not configured or wrong origin

**Debug**:
```bash
# Check storage CORS rules
az storage cors list --account-name <ACCOUNT> --services b

# Test preflight request
curl -X OPTIONS https://<ACCOUNT>.blob.core.windows.net/upload/test.jpg \
  -H "Origin: https://your-frontend.com" \
  -H "Access-Control-Request-Method: PUT" \
  -v
```

**Fix**: Add CORS to storage account in Bicep:
```bicep
corsRules: [
  {
    allowedOrigins: ['https://your-frontend.com']
    allowedMethods: ['GET', 'POST', 'PUT']
    allowedHeaders: ['*']
    exposedHeaders: ['*']
    maxAgeInSeconds: 86400
  }
]
```

#### 4. "SAS token expired"

**Cause**: Upload took longer than SAS validity period

**Debug**: Check SAS `se` (expiry) parameter in URL

**Fix**: Request new SAS token with longer `timerange` parameter

#### 5. Network firewall blocks requests

**Cause**: Storage account `networkAcls.defaultAction: "Deny"`

**Debug**:
```bash
# Check network rules
az storage account show -n <ACCOUNT> -g <RG> --query networkRuleSet

# Should show defaultAction: "Allow" or specific IP allowlist
```

**Fix**: Update Bicep:
```bicep
networkAcls: {
  defaultAction: 'Allow'  // or add specific IPs
  bypass: 'AzureServices'
}
```

### Debug Logging Strategy

**Enable Verbose Logging**:
```typescript
const fastify = Fastify({
  logger: {
    level: 'debug',  // or 'trace' for maximum verbosity
    prettyPrint: process.env.NODE_ENV !== 'production'
  }
});
```

**Log Key Operations**:
```typescript
request.log.info({
  accountName,
  container,
  file,
  permission,
  timerange
}, 'Generating SAS token');

request.log.debug({
  startsOn: startsOn.toISOString(),
  expiresOn: expiresOn.toISOString()
}, 'Token validity period');

request.log.info({ sasUrlLength: sasUrl.length }, 'SAS generation successful');
```

**Log Azure SDK Operations**:
```typescript
import { setLogLevel } from '@azure/logger';

setLogLevel('info');  // Logs all Azure SDK HTTP requests
```

### Troubleshooting Guide

| Symptom | Likely Cause | Solution |
|---------|--------------|----------|
| 403 on user delegation key | Missing "Storage Blob Delegator" role | Assign role to Managed Identity |
| 403 on list blobs | Missing "Storage Blob Data Contributor" role | Assign role to Managed Identity |
| 404 on container | Container doesn't exist | Create container or check name |
| CORS error in browser | Storage CORS rules don't allow origin | Add origin to CORS rules |
| "DefaultAzureCredential failed" | No identity context available | Run `az login` locally or configure Managed Identity |
| Upload fails with valid SAS | SAS expired during upload | Increase `timerange` parameter |
| API can't connect to storage | Network firewall blocks access | Allow access in `networkAcls` |

## Framework Implementation Patterns

### Comparison Across Frameworks

| Aspect | Azure SDK (TypeScript/Python/C#) | LangChain | Semantic Kernel | Custom REST |
|--------|----------------------------------|-----------|-----------------|-------------|
| **Credential Handling** | `DefaultAzureCredential` | Manual token provider | Azure connector built-in | Manual OAuth |
| **SAS Generation** | `generateBlobSASQueryParameters` | Not supported | Not supported | Manual signing |
| **Managed Identity** | Automatic discovery | Manual configuration | Automatic | Manual IMDS |
| **Complexity** | Low | High | Medium | Very High |
| **Best For** | Production APIs | AI agent pipelines | AI copilot apps | Legacy systems |

### Translation Guide: Key Concepts

| Concept | TypeScript | Python | C# | Java |
|---------|-----------|--------|-----|------|
| **Default Credential** | `DefaultAzureCredential` | `DefaultAzureCredential` | `DefaultAzureCredential` | `DefaultAzureCredentialBuilder` |
| **Blob Service Client** | `BlobServiceClient` | `BlobServiceClient` | `BlobServiceClient` | `BlobServiceClientBuilder` |
| **User Delegation Key** | `getUserDelegationKey()` | `get_user_delegation_key()` | `GetUserDelegationKeyAsync()` | `getUserDelegationKey()` |
| **SAS Generator** | `generateBlobSASQueryParameters` | `generate_blob_sas` | `BlobSasBuilder` | `BlobServiceSasSignatureValues` |
| **Environment Variable** | `process.env.VAR_NAME` | `os.getenv('VAR_NAME')` | `Environment.GetEnvironmentVariable("VAR_NAME")` | `System.getenv("VAR_NAME")` |

---

## Summary

The **User Delegation SAS pattern with Managed Identity** is the gold standard for secure, scalable Azure Blob Storage access:

- ✅ **Zero secrets** in application code or config
- ✅ **RBAC-enforced** access control
- ✅ **Full audit trail** for compliance
- ✅ **Direct uploads** for performance and cost efficiency
- ✅ **Language-agnostic** - works in any Azure SDK

This architecture provides a blueprint for building production-ready file upload systems that meet enterprise security and operational requirements.
