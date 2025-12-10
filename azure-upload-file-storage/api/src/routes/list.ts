import { FastifyRequest, FastifyReply } from 'fastify';
import { getBlobServiceClient } from '../lib/azure-storage.js';

interface ListQueryParams {
  container?: string;
}

/**
 * List all files in a container using managed identity
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

    const fileList: string[] = [];

    // List blobs with pagination
    for await (const response of containerClient.listBlobsFlat().byPage({ maxPageSize: 20 })) {
      for (const blob of response.segment.blobItems) {
        const blobUrl = `${containerClient.url}/${blob.name}`;
        fileList.push(blobUrl);
      }
    }

    request.log.info({ count: fileList.length }, 'Retrieved file list');

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
