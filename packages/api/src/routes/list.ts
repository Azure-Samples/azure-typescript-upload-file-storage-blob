import { FastifyRequest, FastifyReply } from 'fastify';
import { BlobSASPermissions, generateBlobSASQueryParameters } from '@azure/storage-blob';
import { getBlobServiceClient } from '../lib/azure-storage.js';

// Default SAS token expiration time for read tokens in minutes
// These tokens are used to display images in the frontend
const LIST_SAS_TOKEN_EXPIRATION_MINUTES = 60;

// SAS token permission for viewing/downloading files
// Uses 'r' (read-only) - most restrictive permission for displaying content
// This prevents list tokens from modifying or deleting blobs
const LIST_SAS_TOKEN_PERMISSION = 'r';

interface ListQueryParams {
  container?: string;
}

/**
 * List all files in a container with read-only SAS tokens
 * Generates a separate 'r' (read) token for each blob to allow frontend display
 * Container is NOT public - these tokens provide temporary read access
 */
export async function listFiles(
  request: FastifyRequest<{ Querystring: ListQueryParams }>,
  reply: FastifyReply
) {
  const { container = 'upload' } = request.query;

  request.log.info({ container }, 'Listing files in container');

  const accountName = process.env.AZURE_STORAGE_ACCOUNT_NAME;
  if (!accountName) {
    request.log.error('AZURE_STORAGE_ACCOUNT_NAME environment variable not set');
    return reply.status(500).send({
      error: 'Storage configuration missing'
    });
  }

  try {
    const blobServiceClient = getBlobServiceClient(accountName);
    const containerClient = blobServiceClient.getContainerClient(container);

    // IMPORTANT: Always set both startsOn and expiresOn for SAS expiration policy compliance
    // Tokens are valid starting NOW and expire after the specified number of minutes
    const startsOn = new Date();
    const expiresOn = new Date(startsOn.valueOf() + LIST_SAS_TOKEN_EXPIRATION_MINUTES * 60 * 1000);
    
    request.log.info({
      startsOn: startsOn.toISOString(),
      expiresOn: expiresOn.toISOString(),
      durationMinutes: LIST_SAS_TOKEN_EXPIRATION_MINUTES
    }, `Read tokens valid from ${startsOn.toISOString()} and expire at ${expiresOn.toISOString()} (${LIST_SAS_TOKEN_EXPIRATION_MINUTES} minutes from now)`);
    
    request.log.info('Requesting user delegation key for read SAS tokens...');
    const userDelegationKey = await blobServiceClient.getUserDelegationKey(
      startsOn,
      expiresOn
    );

    const fileList: string[] = [];

    // List blobs with pagination (20 per page for performance)
    for await (const response of containerClient.listBlobsFlat().byPage({ maxPageSize: 20 })) {
      for (const blob of response.segment.blobItems) {
        const blobClient = containerClient.getBlobClient(blob.name);
        
        // Generate read-only SAS token for each blob
        // Uses LIST_SAS_TOKEN_PERMISSION ('r') for secure read-only access
        const sasToken = generateBlobSASQueryParameters(
          {
            containerName: container,
            blobName: blob.name,
            permissions: BlobSASPermissions.parse(LIST_SAS_TOKEN_PERMISSION),
            startsOn,    // REQUIRED for expiration policy
            expiresOn    // REQUIRED for expiration policy
          },
          userDelegationKey,
          accountName
        ).toString();

        const sasUrl = `${blobClient.url}?${sasToken}`;
        fileList.push(sasUrl);
      }
    }

    request.log.info({ count: fileList.length }, 'Retrieved file list with SAS tokens');

    return reply.send({
      list: fileList
    });
  } catch (error) {
    request.log.error(error, 'Failed to list files');
    
    return reply.status(500).send({
      error: 'Failed to list files',
      details: error instanceof Error ? error.message : 'Unknown error'
    });
  }
}
