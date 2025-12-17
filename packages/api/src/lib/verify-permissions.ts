import { getBlobServiceClient } from './azure-storage.js';

/**
 * Verify that the current identity has the necessary permissions
 * to generate user delegation SAS tokens
 */
export async function verifyStoragePermissions(accountName: string): Promise<{
  success: boolean;
  message: string;
  details?: any;
}> {
  try {
    console.log(`\n🔐 Verifying storage permissions for account: ${accountName}`);
    
    const blobServiceClient = getBlobServiceClient(accountName);
    
    // Test 1: Can we get service properties? (requires read access)
    console.log('  ✓ Testing storage account access...');
    let retries = 3;
    let lastError: any;
    
    while (retries > 0) {
      try {
        await blobServiceClient.getProperties();
        console.log('  ✓ Storage account access: OK');
        break;
      } catch (error: any) {
        lastError = error;
        console.error(`  ⚠️  Error details: ${JSON.stringify({
          message: error.message,
          statusCode: error.statusCode,
          code: error.code,
          name: error.name
        })}`);
        retries--;
        if (retries > 0) {
          console.log(`  ⏳ Retrying... (${retries} attempts remaining)`);
          await new Promise(resolve => setTimeout(resolve, 2000)); // Wait 2 seconds
        }
      }
    }
    
    if (retries === 0) {
      const message = lastError instanceof Error ? lastError.message : 'Unknown error';
      console.error('  ✗ Storage account access: FAILED after retries');
      return {
        success: false,
        message: 'Cannot access storage account. RBAC roles may need time to propagate (5-10 minutes).',
        details: message
      };
    }
    
    // Test 2: Can we get a user delegation key? (requires Storage Blob Delegator role)
    console.log('  ✓ Testing user delegation key generation...');
    try {
      const startsOn = new Date();
      const expiresOn = new Date(startsOn.valueOf() + 10 * 60 * 1000); // 10 minutes
      
      await blobServiceClient.getUserDelegationKey(startsOn, expiresOn);
      console.log('  ✓ User delegation key: OK');
      console.log('  ✓ Storage Blob Delegator role: VERIFIED');
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Unknown error';
      console.error('  ✗ User delegation key: FAILED');
      console.error('  ✗ Missing role: Storage Blob Delegator');
      return {
        success: false,
        message: 'Missing required role: Storage Blob Delegator',
        details: message
      };
    }
    
    // Test 3: Can we list containers? (requires Storage Blob Data Contributor)
    console.log('  ✓ Testing blob data access...');
    try {
      const iterator = blobServiceClient.listContainers({ prefix: 'upload' });
      await iterator.next();
      console.log('  ✓ Blob data access: OK');
      console.log('  ✓ Storage Blob Data Contributor role: VERIFIED');
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Unknown error';
      console.error('  ✗ Blob data access: FAILED');
      console.error('  ✗ Missing role: Storage Blob Data Contributor');
      return {
        success: false,
        message: 'Missing required role: Storage Blob Data Contributor',
        details: message
      };
    }
    
    console.log('\n✅ All storage permissions verified successfully!\n');
    return {
      success: true,
      message: 'All required storage permissions are configured correctly'
    };
    
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Unknown error';
    console.error('  ✗ Permission verification failed:', message);
    return {
      success: false,
      message: 'Permission verification failed',
      details: message
    };
  }
}
