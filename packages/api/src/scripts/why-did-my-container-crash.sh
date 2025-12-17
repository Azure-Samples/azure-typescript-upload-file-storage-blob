#!/bin/bash
# chmod +x why-did-my-container-crash.sh
# Usage: 
#   ./why-did-my-container-crash.sh [resource-group-name]
#   or run without args to use azd environment

echo "🔍 Azure Container Apps Inspector"
echo ""

# Get resource group from argument or azd environment
if [ -n "$1" ]; then
  RESOURCE_GROUP="$1"
  echo "📦 Using provided resource group: $RESOURCE_GROUP"
else
  # Navigate to workspace root to run azd commands
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
  cd "$WORKSPACE_ROOT"
  
  RESOURCE_GROUP=$(azd env get-values 2>/dev/null | grep AZURE_RESOURCE_GROUP | cut -d'=' -f2 | tr -d '"')
  
  if [ -z "$RESOURCE_GROUP" ]; then
    echo "❌ Error: No resource group provided and could not retrieve from azd environment."
    echo ""
    echo "Usage:"
    echo "  $0 <resource-group-name>"
    echo ""
    echo "Or ensure you've run 'azd provision' or 'azd up' first."
    exit 1
  fi
  
  echo "📦 Using azd resource group: $RESOURCE_GROUP"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🐳 Container Apps in Resource Group"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# List all container apps in the resource group
CONTAINER_APPS=$(az containerapp list --resource-group "$RESOURCE_GROUP" --query "[].name" -o tsv 2>/dev/null)

if [ -z "$CONTAINER_APPS" ]; then
  echo "❌ No container apps found in resource group: $RESOURCE_GROUP"
  echo ""
  echo "💡 Verify the resource group name or check if container apps have been deployed."
  exit 1
fi

echo "Found $(echo "$CONTAINER_APPS" | wc -l) container app(s)"
echo ""

# Show status for each container app
for APP_NAME in $CONTAINER_APPS; do
  echo "╔════════════════════════════════════════════════════════════════╗"
  echo "║  📱 Container App: $APP_NAME"
  echo "╚════════════════════════════════════════════════════════════════╝"
  echo ""
  
  # Get app details
  echo "📊 Status & Configuration:"
  az containerapp show \
    --name "$APP_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --query "{Name:name, ProvisioningState:properties.provisioningState, RunningStatus:properties.runningStatus, FQDN:properties.configuration.ingress.fqdn, MinReplicas:properties.template.scale.minReplicas, MaxReplicas:properties.template.scale.maxReplicas, Image:properties.template.containers[0].image}" \
    -o table 2>/dev/null
  
  echo ""
  echo "🔄 Revisions:"
  az containerapp revision list \
    --name "$APP_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --query "[].{Revision:name, Active:properties.active, Traffic:properties.trafficWeight, Replicas:properties.replicas, RunningState:properties.runningState, Health:properties.healthState, Created:properties.createdTime}" \
    -o table 2>/dev/null
  
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
done

echo ""
echo "💡 To view logs for a specific container app:"
echo "   • Azure Portal: Navigate to the app → Monitoring → Log stream"
echo "   • Log Analytics: Query ContainerAppConsoleLogs_CL"
echo ""