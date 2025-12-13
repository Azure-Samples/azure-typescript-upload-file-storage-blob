import Fastify from 'fastify';
import cors from '@fastify/cors';
import { getSasToken } from './routes/sas.js';
import { listFiles } from './routes/list.js';
import { getStatus } from './routes/status.js';
import { verifyStoragePermissions } from './lib/verify-permissions.js';

console.log('Starting Azure File Upload API Server...');
console.log(process.env);
const fastify = Fastify({ 
  logger: true,
  disableRequestLogging: process.env.NODE_ENV === 'production'
});

// CORS configuration
await fastify.register(cors, {
  origin: process.env.WEB_URL || '*',
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
    
    // Verify storage permissions before starting the server
    const accountName = process.env.AZURE_STORAGE_ACCOUNT_NAME;
    if (accountName) {
      const verification = await verifyStoragePermissions(accountName);
      if (!verification.success) {
        console.error('\n❌ Storage permission verification failed!');
        console.error(`   ${verification.message}`);
        if (verification.details) {
          console.error(`   Details: ${verification.details}`);
        }
        console.error('\n💡 Required Azure RBAC roles:');
        console.error('   - Storage Blob Data Contributor');
        console.error('   - Storage Blob Delegator');
        console.error('\n   Run: azd provision (to assign roles automatically)');
        console.error('   Or wait 5-10 minutes if roles were just assigned.\n');
        
        // Don't exit in development mode to allow debugging
        if (process.env.NODE_ENV === 'production') {
          process.exit(1);
        } else {
          console.warn('⚠️  Continuing in development mode despite permission issues...\n');
        }
      }
    } else {
      console.warn('⚠️  AZURE_STORAGE_ACCOUNT_NAME not set, skipping permission verification\n');
    }
    
    await fastify.listen({ port, host });
    console.log('Azure File Upload API Server started successfully.');
    fastify.log.info(`Server listening on ${host}:${port}`);
    fastify.log.info(`Environment: ${process.env.NODE_ENV || 'development'}`);
    fastify.log.info(`Storage Account: ${process.env.AZURE_STORAGE_ACCOUNT_NAME || 'not set'}`);
    fastify.log.info(`Frontend URL: ${process.env.WEB_URL || '*'}`);
  } catch (err) {
    fastify.log.error(err);
    console.log('Failed to start Azure File Upload API Server.');
    process.exit(1);
  }
};

start();
