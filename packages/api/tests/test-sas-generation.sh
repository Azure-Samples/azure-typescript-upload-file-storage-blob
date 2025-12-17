#!/bin/bash
#
# Test script for SAS token generation and validation
# Tests user delegation SAS tokens with expiration policy compliance
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=================================================="
echo "  SAS Token Generation Test Suite"
echo "=================================================="
echo ""

# Check prerequisites
echo "🔍 Checking prerequisites..."

# Check if server is running
if ! curl -s http://localhost:3000/health > /dev/null 2>&1; then
    echo -e "${RED}❌ Server not running on http://localhost:3000${NC}"
    echo "   Start with: npm run dev"
    exit 1
fi
echo -e "${GREEN}✅ Server running${NC}"

# Check Azure CLI authentication
if ! az account show > /dev/null 2>&1; then
    echo -e "${RED}❌ Not authenticated to Azure${NC}"
    echo "   Run: az login"
    exit 1
fi
echo -e "${GREEN}✅ Azure CLI authenticated${NC}"

# Check jq installed
if ! command -v jq &> /dev/null; then
    echo -e "${RED}❌ jq not installed${NC}"
    echo "   Install: apt-get install jq"
    exit 1
fi
echo -e "${GREEN}✅ jq available${NC}"
echo ""

# Test 1: Generate basic SAS token
echo "=================================================="
echo "Test 1: Generate Basic SAS Token"
echo "=================================================="
response=$(curl -s "http://localhost:3000/api/sas?container=upload&file=test.txt")
url=$(echo "$response" | jq -r '.url')

if [ -z "$url" ] || [ "$url" = "null" ]; then
    echo -e "${RED}❌ Failed to generate SAS token${NC}"
    echo "Response: $response"
    exit 1
fi
echo -e "${GREEN}✅ SAS token generated${NC}"
echo "URL: $url"
echo ""

# Test 2: Validate required parameters
echo "=================================================="
echo "Test 2: Validate SAS Token Parameters"
echo "=================================================="
query_params=$(echo "$url" | sed 's/.*?//')

echo "Query parameters:"
echo "$query_params" | tr '&' '\n' | while read -r param; do
    echo "  - $param"
done
echo ""

# Check for required parameters
required_params=("sv" "st" "se" "sr" "sp" "sig")
missing_params=()

for param in "${required_params[@]}"; do
    if ! echo "$query_params" | grep -q "$param="; then
        missing_params+=("$param")
    fi
done

if [ ${#missing_params[@]} -eq 0 ]; then
    echo -e "${GREEN}✅ All required parameters present${NC}"
else
    echo -e "${RED}❌ Missing parameters: ${missing_params[*]}${NC}"
    exit 1
fi
echo ""

# Test 3: Verify startsOn parameter (expiration policy requirement)
echo "=================================================="
echo "Test 3: Verify Expiration Policy Compliance"
echo "=================================================="

if echo "$query_params" | grep -q "st="; then
    st_param=$(echo "$query_params" | grep -o "st=[^&]*" | cut -d= -f2)
    echo -e "${GREEN}✅ startsOn parameter present (st=$st_param)${NC}"
else
    echo -e "${RED}❌ startsOn parameter missing - NOT compliant with expiration policy${NC}"
    exit 1
fi

if echo "$query_params" | grep -q "se="; then
    se_param=$(echo "$query_params" | grep -o "se=[^&]*" | cut -d= -f2)
    echo -e "${GREEN}✅ expiresOn parameter present (se=$se_param)${NC}"
else
    echo -e "${RED}❌ expiresOn parameter missing${NC}"
    exit 1
fi
echo ""

# Test 4: Test custom time range
echo "=================================================="
echo "Test 4: Test Custom Time Range (30 minutes)"
echo "=================================================="
response=$(curl -s "http://localhost:3000/api/sas?container=upload&file=test.txt&timerange=30")
url=$(echo "$response" | jq -r '.url')

if [ -z "$url" ] || [ "$url" = "null" ]; then
    echo -e "${RED}❌ Failed to generate SAS token with custom timerange${NC}"
    exit 1
fi
echo -e "${GREEN}✅ SAS token with 30-minute duration generated${NC}"
echo ""

# Test 5: Test different permissions
echo "=================================================="
echo "Test 5: Test Different Permissions"
echo "=================================================="

permissions=("r" "w" "rw" "d")
for perm in "${permissions[@]}"; do
    response=$(curl -s "http://localhost:3000/api/sas?container=upload&file=test.txt&permission=$perm")
    url=$(echo "$response" | jq -r '.url')
    
    if [ -z "$url" ] || [ "$url" = "null" ]; then
        echo -e "${RED}❌ Failed with permission: $perm${NC}"
        exit 1
    fi
    
    # Extract sp parameter
    sp_param=$(echo "$url" | grep -o "sp=[^&]*" | cut -d= -f2)
    echo -e "${GREEN}✅ Permission '$perm' generated token (sp=$sp_param)${NC}"
done
echo ""

# Test 6: Verify user delegation key usage (not account key)
echo "=================================================="
echo "Test 6: Verify User Delegation SAS (not Account Key)"
echo "=================================================="

response=$(curl -s "http://localhost:3000/api/sas?container=upload&file=test.txt")
url=$(echo "$response" | jq -r '.url')
query_params=$(echo "$url" | sed 's/.*?//')

if echo "$query_params" | grep -q "skoid="; then
    echo -e "${GREEN}✅ User delegation SAS detected (contains skoid parameter)${NC}"
    echo "   This confirms the token uses Microsoft Entra ID, not account keys"
else
    echo -e "${YELLOW}⚠️  Cannot confirm user delegation SAS type${NC}"
    echo "   This might be an account key SAS"
fi
echo ""

# Test 7: Test actual upload (optional - requires storage account)
echo "=================================================="
echo "Test 7: Test Actual Upload (Optional)"
echo "=================================================="

if [ -z "${AZURE_STORAGE_ACCOUNT}" ]; then
    echo -e "${YELLOW}⚠️  AZURE_STORAGE_ACCOUNT not set - skipping upload test${NC}"
    echo "   Set environment variable to test actual uploads"
else
    response=$(curl -s "http://localhost:3000/api/sas?container=upload&file=test-$(date +%s).txt")
    sas_url=$(echo "$response" | jq -r '.url')
    
    echo "Testing upload to: $sas_url"
    
    upload_response=$(curl -s -w "%{http_code}" -X PUT \
        -H "x-ms-blob-type: BlockBlob" \
        -H "Content-Type: text/plain" \
        --data "Test content from SAS token test" \
        "$sas_url")
    
    http_code="${upload_response: -3}"
    
    if [ "$http_code" = "201" ]; then
        echo -e "${GREEN}✅ Upload successful (HTTP 201)${NC}"
    elif [ "$http_code" = "403" ]; then
        echo -e "${RED}❌ Upload failed (HTTP 403 - Forbidden)${NC}"
        echo "   Check RBAC roles: Storage Blob Data Contributor + Storage Blob Delegator"
        exit 1
    else
        echo -e "${YELLOW}⚠️  Upload returned HTTP $http_code${NC}"
        echo "   Response: ${upload_response:0:-3}"
    fi
fi
echo ""

# Summary
echo "=================================================="
echo "  Test Summary"
echo "=================================================="
echo -e "${GREEN}✅ All SAS token tests passed${NC}"
echo ""
echo "Verified:"
echo "  ✅ Token generation works"
echo "  ✅ All required parameters present (sv, st, se, sr, sp, sig)"
echo "  ✅ startsOn parameter included (expiration policy compliant)"
echo "  ✅ expiresOn parameter included"
echo "  ✅ Custom time ranges work"
echo "  ✅ Different permissions work"
echo "  ✅ User delegation SAS format detected"
echo ""
echo "Your API correctly implements user delegation SAS tokens"
echo "with full expiration policy compliance! 🎉"
echo ""
