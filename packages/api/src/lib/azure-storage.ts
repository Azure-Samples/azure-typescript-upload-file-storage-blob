import { BlobServiceClient } from '@azure/storage-blob';
import { ChainedTokenCredential, ManagedIdentityCredential, AzureCliCredential } from '@azure/identity';

let _credential: ChainedTokenCredential | null = null;

/**
 * Get a singleton instance of Azure credential
 * Uses ChainedTokenCredential to try authentication methods in order:
 * 1. ManagedIdentityCredential (for Azure Container Apps) - tries first
 * 2. AzureCliCredential (for local development with az login) - falls back
 */
export function getCredential(): ChainedTokenCredential {
  if (!_credential) {
    const clientId = process.env.AZURE_CLIENT_ID;
    
    // Create credential chain with ManagedIdentity first
    const credentials = [
      new ManagedIdentityCredential(clientId ? { clientId } : undefined),
      new AzureCliCredential()
    ];
    
    _credential = new ChainedTokenCredential(...credentials);
    console.log(`🔑 Using ChainedTokenCredential (ManagedIdentity → AzureCLI)${clientId ? ` with client ID: ${clientId}` : ''}`);
  }
  return _credential;
}

/**
 * Get BlobServiceClient using managed identity
 */
export function getBlobServiceClient(accountName: string): BlobServiceClient {
  if (!accountName) {
    throw new Error('AZURE_STORAGE_ACCOUNT_NAME environment variable is required');
  }
  
  const credential = getCredential();
  const url = `https://${accountName}.blob.core.windows.net`;
  
  return new BlobServiceClient(url, credential);
}
