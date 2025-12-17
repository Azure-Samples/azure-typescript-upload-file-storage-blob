import { FastifyRequest, FastifyReply } from 'fastify';
import { BlobSASPermissions, generateBlobSASQueryParameters } from '@azure/storage-blob';
import { getBlobServiceClient } from '../lib/azure-storage.js';

interface ListQueryParams {
  container?: string;
}

/**
 * List all files in a container with read SAS tokens
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

    // Get user delegation key for SAS tokens (valid for 1 hour)
    const startsOn = new Date();
    const expiresOn = new Date(startsOn.valueOf() + 60 * 60 * 1000); // 1 hour
    
    request.log.info('Requesting user delegation key for read SAS tokens...');
    const userDelegationKey = await blobServiceClient.getUserDelegationKey(
      startsOn,
      expiresOn
    );

    const fileList: string[] = [];

    // List blobs with pagination
    for await (const response of containerClient.listBlobsFlat().byPage({ maxPageSize: 20 })) {
      for (const blob of response.segment.blobItems) {
        const blobClient = containerClient.getBlobClient(blob.name);
        
        // Generate read SAS token for each blob
        const sasToken = generateBlobSASQueryParameters(
          {
            containerName: container,
            blobName: blob.name,
            permissions: BlobSASPermissions.parse('r'), // read permission
            startsOn,
            expiresOn
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
