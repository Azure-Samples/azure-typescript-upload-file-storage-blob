#!/bin/bash
# chmod +x packages/api/test-with-managed-identity.sh

echo "⚠️  Note: Testing managed identity locally is not possible"
echo "   DefaultAzureCredential will use Azure CLI credentials instead."
echo ""
echo "   To test actual managed identity:"
echo "   1. Check container app logs: az containerapp logs show --name <api-name> --resource-group <rg-name> --follow"
echo "   2. Or use: az containerapp exec --name <api-name> --resource-group <rg-name> --command \"node dist/scripts/test-storage-access.js\""
echo ""
echo "   Running test with Azure CLI credentials..."
echo ""

npm run test:storage