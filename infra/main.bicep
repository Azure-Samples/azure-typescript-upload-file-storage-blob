targetScope = 'subscription'

@minLength(1)
@maxLength(64)
@description('Name of the environment for resource naming')
param environmentName string

@minLength(1)
@description('Primary location for all resources')
param location string

param webAppExists bool = false
param apiAppExists bool = false

// Load abbreviations for Azure resource naming
var abbrs = loadJsonContent('./abbreviations.json')
var resourceToken = toLower(uniqueString(subscription().id, environmentName, location))
var tags = { 'azd-env-name': environmentName }
var prefix = '${environmentName}${resourceToken}'

var principalType = 'User'
@description('Id of the user or app to assign application roles')
param principalId string = ''

var apiContainerAppNameOrDefault = 'api-${resourceToken}'

// Resource group
resource rg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: '${abbrs.resourcesResourceGroups}${environmentName}'
  location: location
  tags: tags
}

// User-assigned managed identity for the container app
module managedIdentity 'br/public:avm/res/managed-identity/user-assigned-identity:0.4.0' = {
  name: 'containerAppIdentity'
  scope: rg
  params: {
    name: '${prefix}-identity'
    location: location
    tags: tags
  }
}

// Monitor application with Azure Monitor
module monitoring 'br/public:avm/ptn/azd/monitoring:0.1.0' = {
  name: 'monitoring'
  scope: rg
  params: {
    applicationInsightsName: 'insight${resourceToken}'
    logAnalyticsName: 'log${resourceToken}'
    applicationInsightsDashboardName : 'dash${resourceToken}'
    location: location
    tags: tags
  }
}

// Container registry, host environment for apps
module containerApps 'br/public:avm/ptn/azd/container-apps-stack:0.1.0' = {
  name: 'container-apps'
  scope: rg
  params: {
    containerAppsEnvironmentName: 'acaEnvironment'
    containerRegistryName: 'acr${resourceToken}'
    logAnalyticsWorkspaceResourceId: monitoring.outputs.logAnalyticsWorkspaceResourceId
    appInsightsConnectionString: monitoring.outputs.applicationInsightsConnectionString
    acrSku: 'Basic'
    location: location
    acrAdminUserEnabled: true
    zoneRedundant: false
    tags: tags
  }
}

var corsAcaUrl = 'https://${apiContainerAppNameOrDefault}.${containerApps.outputs.defaultDomain}'

// Web frontend
module app 'br/public:avm/ptn/azd/container-app-upsert:0.1.1' = {
  name: 'web-container-app'
  scope: rg
  params: {
    name: 'app-${resourceToken}'
    tags: union(tags, { 'azd-service-name': 'app' })
    location: location
    containerAppsEnvironmentName: containerApps.outputs.environmentName
    containerRegistryName: containerApps.outputs.registryName
    ingressEnabled: true
    identityType: 'UserAssigned'
    exists: webAppExists
    containerName: 'main'
    targetPort: 8080
    identityName: managedIdentity.name
    userAssignedIdentityResourceId: managedIdentity.outputs.resourceId
    containerMinReplicas: 1
    identityPrincipalId: managedIdentity.outputs.principalId
  }
}

// Api backend
module api 'br/public:avm/ptn/azd/container-app-upsert:0.1.1' = {
  name: 'apiApp'
  scope: rg
  params: {
    name: 'api-${resourceToken}'
    tags: union(tags, { 'azd-service-name': 'api' })
    location: location
    env: [
      {
        name: 'AZURE_CLIENT_ID'
        value: managedIdentity.outputs.clientId
      }
      {
        name: 'WEB_URL'
        value: corsAcaUrl
      }
      {
        name: 'NODE_ENV'
        value: 'production'
      }
      {
        name: 'PORT'
        value: '3000'
      }
      {
        name: 'AZURE_STORAGE_ACCOUNT_NAME'
        value: storage.outputs.name
      }
      {
        name: 'AZURE_CLIENT_ID'
        value: managedIdentity.outputs.clientId
      }
    ]
    containerAppsEnvironmentName: containerApps.outputs.environmentName
    containerRegistryName: containerApps.outputs.registryName
    exists: apiAppExists
    identityType: 'UserAssigned'
    identityName: managedIdentity.name
    targetPort: 3000
    containerMinReplicas: 1
    ingressEnabled: true
    containerName: 'main'
    userAssignedIdentityResourceId: managedIdentity.outputs.resourceId
    identityPrincipalId: managedIdentity.outputs.principalId
  }
}


// Storage Account with upload container
module storage 'br/public:avm/res/storage/storage-account:0.30.0' = {
  name: 'storage'
  scope: rg
  params: {
    name: '${abbrs.storageStorageAccounts}${resourceToken}'
    location: location
    tags: tags
    kind: 'StorageV2'
    skuName: 'Standard_LRS'
    allowBlobPublicAccess: false // Use RBAC and SAS tokens instead
    allowSharedKeyAccess: true // Needed for some operations
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow' // Initially open, postprovision hook will lock it down with your IP
      bypass: 'AzureServices'
    }
    roleAssignments: union(
      [
        {
          principalId: managedIdentity.outputs.principalId
          roleDefinitionIdOrName: 'ba92f5b4-2d11-453d-a403-e96b0029c9fe' // Storage Blob Data Contributor
          principalType: 'ServicePrincipal'
        }
        {
          principalId: managedIdentity.outputs.principalId
          roleDefinitionIdOrName: 'db58b8e5-c6ad-4a2a-8342-4190687cbf4a' // Storage Blob Delegator
          principalType: 'ServicePrincipal'
        }
        {
          principalId: managedIdentity.outputs.principalId
          roleDefinitionIdOrName: 'acdd72a7-3385-48ef-bd42-f606fba81ae7' // Reader (for service properties)
          principalType: 'ServicePrincipal'
        }
      ],
      !empty(principalId) ? [
        {
          principalId: principalId
          roleDefinitionIdOrName: 'ba92f5b4-2d11-453d-a403-e96b0029c9fe' // Storage Blob Data Contributor
          principalType: principalType
        }
        {
          principalId: principalId
          roleDefinitionIdOrName: 'db58b8e5-c6ad-4a2a-8342-4190687cbf4a' // Storage Blob Delegator
          principalType: principalType
        }
      ] : []
    )
    blobServices: {
      containers: [
        {
          name: 'upload'
          publicAccess: 'None' // Use SAS tokens for access
        }
      ]
      corsRules: [
        {
          allowedOrigins: ['*']
          allowedMethods: ['GET', 'POST', 'PUT', 'DELETE', 'HEAD', 'OPTIONS']
          allowedHeaders: ['*']
          exposedHeaders: ['*']
          maxAgeInSeconds: 86400
        }
      ]
    }
  }
}

// Outputs
output AZURE_LOCATION string = location
output AZURE_TENANT_ID string = tenant().tenantId
output AZURE_RESOURCE_GROUP string = rg.name

// // Container Registry and Container Apps
// output API_CORS_ACA_URL string = corsAcaUrl

// // Apps
// output AZURE_CONTAINER_APP_API_NAME string = apiContainerApp.outputs.name
// output AZURE_CONTAINER_APP_WEB_NAME string = webContainerApp.outputs.name

// Container Registry and environment
output AZURE_CONTAINER_ENVIRONMENT_NAME string = containerApps.outputs.environmentName
output AZURE_CONTAINER_REGISTRY_ENDPOINT string = containerApps.outputs.registryLoginServer
output AZURE_CONTAINER_REGISTRY_NAME string = containerApps.outputs.registryName

output API_URL string = api.outputs.uri
output VITE_API_URL string = api.outputs.uri
 output WEB_URL string = app.outputs.uri

// Monitoring
output APPLICATIONINSIGHTS_CONNECTION_STRING string = monitoring.outputs.applicationInsightsConnectionString
output APPLICATIONINSIGHTS_NAME string = monitoring.outputs.applicationInsightsName

// Storage Account
output AZURE_STORAGE_ACCOUNT_NAME string = storage.outputs.name
output AZURE_STORAGE_BLOB_ENDPOINT string = '${storage.outputs.primaryBlobEndpoint}upload'
