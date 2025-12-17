import { FastifyRequest, FastifyReply } from 'fastify';
import { BlobSASPermissions } from '@azure/storage-blob';
import { getBlobServiceClient } from '../lib/azure-storage.js';

// Default SAS token expiration time in minutes
// The token will expire this many minutes after it is generated
const DEFAULT_SAS_TOKEN_EXPIRATION_MINUTES = 10;

// Default SAS token permission for file upload
// SECURITY: Use 'w' (write-only) for uploads - most restrictive permission that still allows upload
// Available permissions (can be combined):
//   'r' = Read - allows downloading/reading blob content
//   'a' = Add - allows appending to append blobs only
//   'c' = Create - allows creating new blobs
//   'w' = Write - allows uploading/overwriting blobs (RECOMMENDED FOR UPLOADS)
//   'd' = Delete - allows deleting blobs
//
// Examples of combined permissions:
//   'w'   = Write-only (MOST SECURE for uploads - use this)
//   'rw'  = Read + Write (allows upload AND download)
//   'rwd' = Read + Write + Delete (full control - NOT RECOMMENDED)
//   'r'   = Read-only (for displaying/downloading files)
//
// IMPORTANT: Container is NOT public (publicAccess: 'None' in infrastructure)
// How viewing works with write-only ('w') upload tokens:
//   1. Upload uses 'w' token (write-only, no read access)
//   2. List API (list.ts) generates separate 'r' tokens for each blob
//   3. Frontend displays images using these read-only SAS tokens
//   4. This separation ensures: upload tokens can't read data, view tokens can't modify data
//
// For upload scenarios, 'w' is most secure as it:
//   - Allows file upload without granting read access (prevents data leakage)
//   - Prevents delete operations (protects existing data)
//   - Limits token to single operation (principle of least privilege)
const DEFAULT_SAS_TOKEN_PERMISSION = 'w';

interface SasQueryParams {
  container?: string;
  file?: string;
  permission?: string;
  timerange?: string;
}

/**
 * Generate a user delegation SAS token for blob upload
 * Uses managed identity (no account keys)
 */
export async function getSasToken(
  request: FastifyRequest<{ Querystring: SasQueryParams }>,
  reply: FastifyReply
) {
  const { container = 'upload', file, permission = DEFAULT_SAS_TOKEN_PERMISSION, timerange = String(DEFAULT_SAS_TOKEN_EXPIRATION_MINUTES) } = request.query;

  request.log.info({
    method: request.method,
    url: request.url,
    origin: request.headers.origin,
    referer: request.headers.referer,
    container,
    file,
    permission,
    timerange
  }, 'Incoming SAS token request');

  // Validate required parameters
  if (!file) {
    return reply.status(400).send({
      error: 'Missing required parameter: file'
    });
  }

  const accountName = process.env.AZURE_STORAGE_ACCOUNT_NAME;
  if (!accountName) {
    request.log.error('AZURE_STORAGE_ACCOUNT_NAME environment variable not set');
    return reply.status(500).send({
      error: 'Storage configuration missing'
    });
  }

  try {
    request.log.info({ accountName }, 'Creating BlobServiceClient');
    const blobServiceClient = getBlobServiceClient(accountName);

    // IMPORTANT: Always set both startsOn and expiresOn for SAS expiration policy compliance
    // Token is valid starting NOW and expires after the specified number of minutes
    const startsOn = new Date();
    const timerangeMinutes = parseInt(timerange, 10);
    const expiresOn = new Date(startsOn.valueOf() + timerangeMinutes * 60 * 1000);

    request.log.info({
      startsOn: startsOn.toISOString(),
      expiresOn: expiresOn.toISOString(),
      durationMinutes: timerangeMinutes
    }, `Token valid from ${startsOn.toISOString()} and expires at ${expiresOn.toISOString()} (${timerangeMinutes} minutes from now)`);

    request.log.info('Requesting user delegation key...');
    // Get user delegation key (Microsoft Entra ID-based, not account key)
    const userDelegationKey = await blobServiceClient.getUserDelegationKey(
      startsOn,
      expiresOn
    );
    request.log.info('User delegation key obtained successfully');

    // Generate SAS token using user delegation key
    const containerClient = blobServiceClient.getContainerClient(container);
    const blobClient = containerClient.getBlobClient(file);

    // Use generateSasUrl with user delegation key
    const { generateBlobSASQueryParameters } = await import('@azure/storage-blob');
    
    const sasToken = generateBlobSASQueryParameters(
      {
        containerName: container,
        blobName: file,
        permissions: BlobSASPermissions.parse(permission),
        startsOn,    // REQUIRED for expiration policy
        expiresOn    // REQUIRED for expiration policy
      },
      userDelegationKey,
      accountName
    ).toString();

    const sasUrl = `${blobClient.url}?${sasToken}`;

    request.log.info({
      container,
      file,
      blobUrl: blobClient.url,
      sasUrlLength: sasUrl.length,
      hasToken: sasToken.length > 0
    }, `Successfully generated SAS token for ${container}/${file}`);

    const response = { url: sasUrl };
    request.log.info({ response }, 'Sending SAS response to client');

    return reply.send(response);
  } catch (error) {
    request.log.error({
      error,
      errorMessage: error instanceof Error ? error.message : 'Unknown error',
      errorStack: error instanceof Error ? error.stack : undefined,
      container,
      file,
      accountName
    }, 'Failed to generate SAS token');
    
    const errorResponse = {
      error: 'Failed to generate SAS token',
      details: error instanceof Error ? error.message : 'Unknown error'
    };
    
    request.log.error({ errorResponse }, 'Sending error response to client');
    
    return reply.status(500).send(errorResponse);
  }
}
