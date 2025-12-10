import { FastifyRequest, FastifyReply } from 'fastify';
import { BlobSASPermissions } from '@azure/storage-blob';
import { getBlobServiceClient } from '../lib/azure-storage.js';

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
  const { container = 'upload', file, permission = 'w', timerange = '10' } = request.query;

  request.log.info({
    container,
    file,
    permission,
    timerange
  }, 'Generating SAS token');

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
    const blobServiceClient = getBlobServiceClient(accountName);

    // IMPORTANT: Always set both startsOn and expiresOn for SAS expiration policy compliance
    const startsOn = new Date();
    const timerangeMinutes = parseInt(timerange, 10);
    const expiresOn = new Date(startsOn.valueOf() + timerangeMinutes * 60 * 1000);

    request.log.info({
      startsOn: startsOn.toISOString(),
      expiresOn: expiresOn.toISOString(),
      durationMinutes: timerangeMinutes
    }, 'Token validity period');

    // Get user delegation key (Microsoft Entra ID-based, not account key)
    const userDelegationKey = await blobServiceClient.getUserDelegationKey(
      startsOn,
      expiresOn
    );

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

    request.log.info(`Generated SAS token for ${container}/${file}`);

    return reply.send({
      url: sasUrl
    });
  } catch (error) {
    request.log.error(error, 'Failed to generate SAS token');
    
    return reply.status(500).send({
      error: 'Failed to generate SAS token',
      details: error instanceof Error ? error.message : 'Unknown error'
    });
  }
}
