#!/usr/bin/env node
/**
 * Manual test script to validate Azure Storage access
 * Uses the same verification logic as the API server
 * 
 * Usage:
 *   npm run test:storage
 * 
 * Required environment variables:
 *   - AZURE_STORAGE_ACCOUNT_NAME
 *   - AZURE_CLIENT_ID (optional, for managed identity)
 */

import { verifyStoragePermissions } from '../lib/verify-permissions.js';

const accountName = process.env.AZURE_STORAGE_ACCOUNT_NAME;

if (!accountName) {
  console.error('❌ Error: AZURE_STORAGE_ACCOUNT_NAME environment variable is required');
  console.error('   Set it in your .env file or run:');
  console.error('   export AZURE_STORAGE_ACCOUNT_NAME=<your-storage-account-name>');
  process.exit(1);
}

console.log('╔════════════════════════════════════════════════════════════════╗');
console.log('║       Azure Storage Access Validation Test                    ║');
console.log('╚════════════════════════════════════════════════════════════════╝');

console.log(`\n📦 Storage Account: ${accountName}`);
console.log(`🔑 Client ID: ${process.env.AZURE_CLIENT_ID || '(using default Azure credential)'}`);

async function runTest(storageAccountName: string) {
  try {
    const result = await verifyStoragePermissions(storageAccountName);
    
    console.log('╔════════════════════════════════════════════════════════════════╗');
    console.log('║                        Test Summary                            ║');
    console.log('╚════════════════════════════════════════════════════════════════╝\n');

    if (result.success) {
      console.log('🎉 All tests passed! Storage access is properly configured.\n');
      process.exit(0);
    } else {
      console.log(`❌ Verification failed: ${result.message}`);
      if (result.details) {
        console.log(`   Details: ${result.details}`);
      }
      console.log('\n💡 Required Azure RBAC roles:');
      console.log('   - Storage Blob Data Contributor');
      console.log('   - Storage Blob Delegator');
      console.log('\n🔧 To fix:');
      console.log('   1. Run: azd provision (to assign roles automatically)');
      console.log('   2. Wait 5-10 minutes for RBAC propagation');
      console.log('   3. Run this test again\n');
      process.exit(1);
    }
  } catch (error: any) {
    console.error('\n❌ Unexpected error during test:');
    console.error(error);
    process.exit(1);
  }
}

runTest(accountName);
