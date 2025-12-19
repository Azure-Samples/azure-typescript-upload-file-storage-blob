# Authentication and SAS Token Generation

This document explains how this application authenticates to Azure Storage and generates SAS (Shared Access Signature) tokens for secure file operations.

## What are SAS Tokens?

SAS tokens are time-limited URLs that grant specific permissions to Azure Storage resources without exposing your storage account keys. They work like temporary, permission-scoped passwords for individual files or containers.

**Key benefits:**
- Time-limited access (tokens expire automatically)
- Permission-scoped (read, write, delete, etc.)
- No storage account keys in client code
- Revocable through expiration policies

## Authentication Method: Managed Identity

This application uses **User Delegation Keys** with **Managed Identity** for authentication - the most secure approach for Azure applications.

### Why Managed Identity?

Traditional methods use storage account keys (like passwords), but managed identities eliminate keys entirely:
- No secrets to store or rotate
- Azure manages authentication automatically
- Works seamlessly in Azure Container Apps and locally with Azure CLI

### How It Works

The application uses a **ChainedTokenCredential** that tries authentication methods in order:

```typescript
// From: packages/api/src/lib/azure-storage.ts
export function getCredential(): ChainedTokenCredential {
  if (!_credential) {
    const clientId = process.env.AZURE_CLIENT_ID;
    
    // Create credential chain with ManagedIdentity first
    const credentials = [
      new ManagedIdentityCredential(clientId ? { clientId } : undefined),
      new AzureCliCredential()
    ];
    
    _credential = new ChainedTokenCredential(...credentials);
  }
  return _credential;
}
```

**Authentication flow:**
1. **In Azure**: Uses `ManagedIdentityCredential` (Container Apps identity)
2. **Local development**: Falls back to `AzureCliCredential` (your `az login` session)

### Connecting to Storage

Once authenticated, create a `BlobServiceClient`:

```typescript
// From: packages/api/src/lib/azure-storage.ts
export function getBlobServiceClient(accountName: string): BlobServiceClient {
  const credential = getCredential();
  const url = `https://${accountName}.blob.core.windows.net`;
  
  return new BlobServiceClient(url, credential);
}
```

## Generating SAS Tokens

This application generates two types of SAS tokens with different permissions:

### 1. Upload Tokens (Write-Only)

For file uploads, the API generates **write-only** tokens that cannot read or delete data:

```typescript
// From: packages/api/src/routes/sas.ts
const DEFAULT_SAS_TOKEN_PERMISSION = 'w';  // Write-only
const DEFAULT_SAS_TOKEN_EXPIRATION_MINUTES = 10;

// Step 1: Get a user delegation key
const startsOn = new Date();
const expiresOn = new Date(startsOn.valueOf() + timerangeMinutes * 60 * 1000);

const userDelegationKey = await blobServiceClient.getUserDelegationKey(
  startsOn,
  expiresOn
);

// Step 2: Generate SAS token
const sasToken = generateBlobSASQueryParameters(
  {
    containerName: container,
    blobName: file,
    permissions: BlobSASPermissions.parse(permission),
    startsOn,    // Token validity start time
    expiresOn    // Token expiration time
  },
  userDelegationKey,
  accountName
).toString();

const sasUrl = `${blobClient.url}?${sasToken}`;
```

**Permission levels available:**
- `'r'` - Read (download/view)
- `'w'` - Write (upload/overwrite) ← **Used for uploads**
- `'d'` - Delete
- `'c'` - Create
- `'a'` - Add (append blobs)

### 2. View Tokens (Read-Only)

For listing and displaying files, the API generates **read-only** tokens:

```typescript
// From: packages/api/src/routes/list.ts
const LIST_SAS_TOKEN_PERMISSION = 'r';  // Read-only
const LIST_SAS_TOKEN_EXPIRATION_MINUTES = 60;

// Generate read-only SAS token for each blob
const sasToken = generateBlobSASQueryParameters(
  {
    containerName: container,
    blobName: blob.name,
    permissions: BlobSASPermissions.parse(LIST_SAS_TOKEN_PERMISSION),
    startsOn,
    expiresOn
  },
  userDelegationKey,
  accountName
).toString();

const sasUrl = `${blobClient.url}?${sasToken}`;
```

## Token Separation Strategy

The application uses **principle of least privilege** by separating token types:

| Operation | Permission | Expiration | Purpose |
|-----------|-----------|------------|---------|
| Upload | `'w'` (write) | 10 minutes | Client can only upload, cannot view others' files |
| View/List | `'r'` (read) | 60 minutes | Client can only view, cannot modify or delete |

This prevents:
- Upload tokens from reading sensitive data
- View tokens from modifying or deleting files
- Token misuse through minimal permission grants

## User Delegation Keys

User delegation keys are the foundation of secure SAS tokens:

```typescript
// Request a delegation key valid for the token lifetime
const userDelegationKey = await blobServiceClient.getUserDelegationKey(
  startsOn,   // When the key becomes valid
  expiresOn   // When the key expires
);
```

**Why user delegation keys?**
- Based on Microsoft Entra ID (formerly Azure AD) identity
- No storage account keys involved
- Can be revoked by changing identity permissions
- Audit trail tied to identity, not anonymous keys

## Token Expiration Policy

Both `startsOn` and `expiresOn` are **required** for Azure Storage expiration policies:

```typescript
const startsOn = new Date();  // Valid immediately
const expiresOn = new Date(startsOn.valueOf() + minutes * 60 * 1000);  // Expires after N minutes
```

**Default expirations:**
- Upload tokens: 10 minutes (quick operations)
- View tokens: 60 minutes (longer browsing sessions)

## Summary

1. **Authenticate** using Managed Identity (no keys required)
2. **Request** a user delegation key for the token lifetime
3. **Generate** SAS tokens with specific permissions and expiration
4. **Return** time-limited URLs to clients

This approach ensures secure, auditable, and manageable access to Azure Storage without exposing credentials.
