#!/bin/bash
# setup-local-dev.sh
# Helper script to configure local development environment for v2 API

set -e  # Exit on error

echo "🚀 Setting up v2 API local development environment"
echo ""

# Check if .env already exists
if [ -f .env ]; then
    echo "⚠️  .env file already exists"
    read -p "Do you want to overwrite it? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "❌ Setup cancelled"
        exit 1
    fi
fi

# Copy sample env file
echo "📝 Creating .env file from template..."
cp .env.sample .env
echo "✅ .env file created"
echo ""

# Check Azure CLI installation
echo "🔍 Checking Azure CLI..."
if ! command -v az &> /dev/null; then
    echo "❌ Azure CLI is not installed"
    echo "Install from: https://docs.microsoft.com/cli/azure/install-azure-cli"
    exit 1
fi
echo "✅ Azure CLI found"
echo ""

# Check Azure CLI authentication
echo "🔐 Checking Azure CLI authentication..."
if ! az account show &> /dev/null; then
    echo "❌ Not logged in to Azure CLI"
    echo "Running 'az login'..."
    az login
else
    echo "✅ Already authenticated to Azure CLI"
    CURRENT_SUB=$(az account show --query name -o tsv)
    echo "   Current subscription: $CURRENT_SUB"
fi
echo ""

# Get storage account name
echo "📦 Looking for storage account in current subscription..."
STORAGE_ACCOUNTS=$(az storage account list --query "[].name" -o tsv)

if [ -z "$STORAGE_ACCOUNTS" ]; then
    echo "⚠️  No storage accounts found in current subscription"
    read -p "Enter storage account name manually: " STORAGE_NAME
else
    echo "Found storage accounts:"
    select STORAGE_NAME in $STORAGE_ACCOUNTS "Enter manually"; do
        if [ "$STORAGE_NAME" = "Enter manually" ]; then
            read -p "Enter storage account name: " STORAGE_NAME
        fi
        break
    done
fi

# Update .env file
echo "📝 Updating .env with storage account: $STORAGE_NAME"
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    sed -i '' "s/your-storage-account-name/$STORAGE_NAME/" .env
else
    # Linux
    sed -i "s/your-storage-account-name/$STORAGE_NAME/" .env
fi
echo "✅ .env updated"
echo ""

# Check RBAC permissions
echo "🔒 Checking RBAC permissions..."
USER_ID=$(az account show --query user.name -o tsv)
STORAGE_RG=$(az storage account list --query "[?name=='$STORAGE_NAME'].resourceGroup | [0]" -o tsv)
STORAGE_ID=$(az storage account list --query "[?name=='$STORAGE_NAME'].id | [0]" -o tsv)

if [ -z "$STORAGE_ID" ]; then
    echo "⚠️  Could not find storage account. Skipping permission check."
else
    echo "   Checking permissions for: $USER_ID"
    
    # Check for required roles
    HAS_CONTRIBUTOR=$(az role assignment list --assignee "$USER_ID" --scope "$STORAGE_ID" --query "[?roleDefinitionName=='Storage Blob Data Contributor'].roleDefinitionName" -o tsv)
    HAS_DELEGATOR=$(az role assignment list --assignee "$USER_ID" --scope "$STORAGE_ID" --query "[?roleDefinitionName=='Storage Blob Delegator'].roleDefinitionName" -o tsv)
    
    if [ -n "$HAS_CONTRIBUTOR" ]; then
        echo "   ✅ Storage Blob Data Contributor role assigned"
    else
        echo "   ⚠️  Missing 'Storage Blob Data Contributor' role"
        echo "   Ask admin to run: az role assignment create --role 'Storage Blob Data Contributor' --assignee '$USER_ID' --scope '$STORAGE_ID'"
    fi
    
    if [ -n "$HAS_DELEGATOR" ]; then
        echo "   ✅ Storage Blob Delegator role assigned"
    else
        echo "   ⚠️  Missing 'Storage Blob Delegator' role"
        echo "   Ask admin to run: az role assignment create --role 'Storage Blob Delegator' --assignee '$USER_ID' --scope '$STORAGE_ID'"
    fi
fi
echo ""

# Install dependencies if needed
if [ ! -d "node_modules" ]; then
    echo "📦 Installing npm dependencies..."
    npm install
    echo "✅ Dependencies installed"
else
    echo "✅ Dependencies already installed"
fi
echo ""

# Build TypeScript
echo "🔨 Building TypeScript..."
npm run build
echo "✅ Build complete"
echo ""

# Test the configuration
echo "🧪 Testing configuration..."
echo "   Starting server for 3 seconds..."
timeout 3 node dist/server.js &> /dev/null &
sleep 2

if curl -s http://localhost:3000/health > /dev/null 2>&1; then
    echo "   ✅ Server started successfully"
    HEALTH_RESPONSE=$(curl -s http://localhost:3000/health)
    echo "   Response: $HEALTH_RESPONSE"
else
    echo "   ⚠️  Could not connect to server"
fi

# Cleanup
pkill -f "node dist/server.js" &> /dev/null || true
echo ""

echo "✅ Setup complete!"
echo ""
echo "📋 Configuration summary:"
cat .env
echo ""
echo "🚀 Next steps:"
echo "   1. Start development server: npm run dev"
echo "   2. Test health endpoint: curl http://localhost:3000/health"
echo "   3. Test SAS endpoint: curl 'http://localhost:3000/api/sas?container=upload&file=test.txt'"
echo ""
echo "📖 For more information, see CONFIGURATION.md"
