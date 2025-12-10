import Fastify from 'fastify';
import cors from '@fastify/cors';
import { getSasToken } from './src/routes/sas.js';
import { listFiles } from './src/routes/list.js';
import { getStatus } from './src/routes/status.js';

const fastify = Fastify({ 
  logger: true,
  disableRequestLogging: process.env.NODE_ENV === 'production'
});

// CORS configuration
await fastify.register(cors, {
  origin: process.env.FRONTEND_URL || '*',
  methods: ['GET', 'POST', 'OPTIONS'],
  credentials: true
});

// Routes
fastify.get('/api/sas', getSasToken);
fastify.get('/api/list', listFiles);
fastify.get('/api/status', getStatus);

// Health check endpoint
fastify.get('/health', async () => ({ 
  status: 'healthy',
  timestamp: new Date().toISOString()
}));

// Start server
const start = async () => {
  try {
    const port = parseInt(process.env.PORT || '3000');
    const host = '0.0.0.0';
    
    await fastify.listen({ port, host });
    
    fastify.log.info(`Server listening on ${host}:${port}`);
    fastify.log.info(`Environment: ${process.env.NODE_ENV || 'development'}`);
    fastify.log.info(`Storage Account: ${process.env.AZURE_STORAGE_ACCOUNT_NAME || 'not set'}`);
    fastify.log.info(`Frontend URL: ${process.env.FRONTEND_URL || '*'}`);
  } catch (err) {
    fastify.log.error(err);
    process.exit(1);
  }
};

start();
