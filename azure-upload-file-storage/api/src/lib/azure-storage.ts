import { BlobServiceClient } from '@azure/storage-blob';
import { DefaultAzureCredential } from '@azure/identity';

let _credential: DefaultAzureCredential | null = null;

/**
 * Get a singleton instance of DefaultAzureCredential
 * This credential automatically detects the environment:
 * - Local dev: Uses Azure CLI credentials (from az login)
 * - Container Apps: Uses user-assigned managed identity (via AZURE_CLIENT_ID env var)
 */
export function getCredential(): DefaultAzureCredential {
  if (!_credential) {
    _credential = new DefaultAzureCredential();
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
