import { FastifyRequest, FastifyReply } from 'fastify';

/**
 * Simple status endpoint for health checks and debugging
 */
export async function getStatus(
  request: FastifyRequest,
  reply: FastifyReply
) {
  const status = {
    status: 'ok',
    timestamp: new Date().toISOString(),
    environment: process.env.NODE_ENV || 'development',
    storageAccount: process.env.AZURE_STORAGE_ACCOUNT_NAME || 'not configured',
    frontendUrl: process.env.FRONTEND_URL || 'not configured',
    request: {
      method: request.method,
      url: request.url,
      headers: Object.fromEntries(
        Object.entries(request.headers).filter(([key]) => 
          !key.toLowerCase().includes('authorization')
        )
      )
    }
  };

  return reply.send(status);
}
