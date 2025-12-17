targetScope = 'subscription'

@minLength(1)
@maxLength(64)
@description('Name of the environment for resource naming')
param environmentName string

@minLength(1)
@description('Primary location for all resources')
param location string

// Load abbreviations for Azure resource naming
var abbrs = loadJsonContent('./abbreviations.json')
var resourceToken = toLower(uniqueString(subscription().id, environmentName, location))
var tags = { 'azd-env-name': environmentName }
var prefix = '${environmentName}${resourceToken}'

var principalType = 'User'
@description('Id of the user or app to assign application roles')
param principalId string = ''

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


// RBAC: Grant managed identity AcrPull role on Container Registry
module acrPullRoleAssignment 'br/public:avm/ptn/authorization/resource-role-assignment:0.1.1' = {
  name: 'acrPullRole'
  scope: rg
  params: {
    principalId: managedIdentity.outputs.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d') // AcrPull role
    resourceId: containerRegistry.outputs.resourceId
    principalType: 'ServicePrincipal'
  }
}
// Log Analytics Workspace for Container Apps
module logAnalytics 'br/public:avm/res/operational-insights/workspace:0.14.2' = {
  name: 'logAnalytics'
  scope: rg
  params: {
    name: '${abbrs.operationalInsightsWorkspaces}${resourceToken}'
    location: location
    tags: tags
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
    allowBlobPublicAccess: false  // Use RBAC and SAS tokens instead
    allowSharedKeyAccess: true     // Needed for some operations
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'  // Initially open, postprovision hook will lock it down with your IP
      bypass: 'AzureServices'
    }
    roleAssignments: [
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
    ]
    blobServices: {
      containers: [
        {
          name: 'upload'
          publicAccess: 'None'  // Use SAS tokens for access
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

// Container Registry
module containerRegistry 'br/public:avm/res/container-registry/registry:0.9.3' = {
  name: 'acr'
  scope: rg
  params: {
    name: '${abbrs.containerRegistryRegistries}${resourceToken}'
    location: location
    tags: tags
    acrSku: 'Basic'
    acrAdminUserEnabled: true
    roleAssignments: [
      {
        principalId: managedIdentity.outputs.principalId
        roleDefinitionIdOrName: '7f951dda-4ed3-4680-a7ca-43fe172d538d' // AcrPull
        principalType: 'ServicePrincipal'
      }
    ]
  }
}

// Container Apps Environment
module containerAppsEnvironment 'br/public:avm/res/app/managed-environment:0.8.1' = {
  name: 'acaEnvironment'
  scope: rg
  params: {
    name: '${abbrs.appManagedEnvironments}${resourceToken}'
    location: location
    tags: tags
    logAnalyticsWorkspaceResourceId: logAnalytics.outputs.resourceId
    zoneRedundant: false
  }
}

// API Container App
module apiContainerApp 'br/public:avm/res/app/container-app:0.11.0' = {
  name: 'apiApp'
  scope: rg
  dependsOn: [
    storage  // Ensure storage and its role assignments are complete before deploying the container
  ]
  params: {
    name: 'api-${resourceToken}'
    location: location
    tags: union(tags, { 'azd-service-name': 'api' })
    environmentResourceId: containerAppsEnvironment.outputs.resourceId
    managedIdentities: {
      userAssignedResourceIds: [managedIdentity.outputs.resourceId]
    }
    containers: [
      {
        name: 'api'
        image: 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'
        resources: {
          cpu: json('0.5')
          memory: '1Gi'
        }
        env: [
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
          {
            name: 'FRONTEND_URL'
            value: 'https://${webContainerApp.outputs.fqdn}'
          }
        ]
        // probes: [
        //   {
        //     type: 'liveness'
        //     httpGet: {
        //       path: '/health'
        //       port: 3000
        //       scheme: 'HTTP'
        //     }
        //     initialDelaySeconds: 30
        //     periodSeconds: 30
        //     failureThreshold: 3
        //   }
        //   {
        //     type: 'readiness'
        //     httpGet: {
        //       path: '/health'
        //       port: 3000
        //       scheme: 'HTTP'
        //     }
        //     initialDelaySeconds: 10
        //     periodSeconds: 10
        //     failureThreshold: 3
        //   }
        // ]
      }
    ]
    ingressTargetPort: 3000
    ingressExternal: true
    ingressTransport: 'http'
    ingressAllowInsecure: false
    corsPolicy: {
      allowedOrigins: [
        'https://${webContainerApp.outputs.fqdn}'
      ]
      allowedMethods: ['*']
      allowedHeaders: ['*']
      allowCredentials: true
    }
    scaleMinReplicas: 1
    scaleMaxReplicas: 1
    registries: [
      {
        server: containerRegistry.outputs.loginServer
        identity: managedIdentity.outputs.resourceId
      }
    ]
  }
}

// Web/Frontend Container App
// Provision overwrites the image so must - just change with config with azd provision
// deploy (package + deploy) to deploy image
// avm: consider using container app upsert found in https://github.com/Azure-Samples/todo-nodejs-mongo-aca
module webContainerApp 'br/public:avm/res/app/container-app:0.11.0' = {
  name: 'webApp'
  scope: rg
  params: {
    name: 'app-${resourceToken}'
    location: location
    tags: union(tags, { 'azd-service-name': 'app' })
    environmentResourceId: containerAppsEnvironment.outputs.resourceId
    managedIdentities: {
      userAssignedResourceIds: [managedIdentity.outputs.resourceId]
    }
    containers: [
      {
        name: 'app'
        image: 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'
        resources: {
          cpu: json('0.25')
          memory: '0.5Gi'
        }
        env: [
          {
            name: 'VITE_API_URL'
            value: ''
          }
        ]
        // probes: [
        //   {
        //     type: 'liveness'
        //     httpGet: {
        //       path: '/health'
        //       port: 8080
        //       scheme: 'HTTP'
        //     }
        //     initialDelaySeconds: 30
        //     periodSeconds: 30
        //     failureThreshold: 3
        //   }
        //   {
        //     type: 'readiness'
        //     httpGet: {
        //       path: '/health'
        //       port: 8080
        //       scheme: 'HTTP'
        //     }
        //     initialDelaySeconds: 10
        //     periodSeconds: 10
        //     failureThreshold: 3
        //   }
        // ]
      }
    ]
    ingressTargetPort: 8080
    ingressExternal: true
    ingressTransport: 'http'
    scaleMinReplicas: 1
    scaleMaxReplicas: 1
    registries: [
      {
        server: containerRegistry.outputs.loginServer
        identity: managedIdentity.outputs.resourceId
      }
    ]
  }
}

// User role assignments (conditional - only if principalId is provided)
module userStorageBlobContributorRole 'br/public:avm/ptn/authorization/resource-role-assignment:0.1.1' = if (!empty(principalId)) {
  name: 'userStorageBlobContributor'
  scope: rg
  params: {
    principalId: principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe') // Storage Blob Data Contributor
    resourceId: storage.outputs.resourceId
    principalType: principalType
  }
}

module userStorageBlobDelegatorRole 'br/public:avm/ptn/authorization/resource-role-assignment:0.1.1' = if (!empty(principalId)) {
  name: 'userStorageBlobDelegator'
  scope: rg
  params: {
    principalId: principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'db58b8e5-c6ad-4a2a-8342-4190687cbf4a') // Storage Blob Delegator
    resourceId: storage.outputs.resourceId
    principalType: principalType
  }
}

module userAcrPullRole 'br/public:avm/ptn/authorization/resource-role-assignment:0.1.1' = if (!empty(principalId)) {
  name: 'userAcrPull'
  scope: rg
  params: {
    principalId: principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d') // AcrPull
    resourceId: containerRegistry.outputs.resourceId
    principalType: principalType
  }
}

// Outputs
output AZURE_LOCATION string = location
output AZURE_TENANT_ID string = tenant().tenantId
output AZURE_RESOURCE_GROUP string = rg.name

// Container Registry and Container Apps
output AZURE_CONTAINER_REGISTRY_ENDPOINT string = containerRegistry.outputs.loginServer
output AZURE_CONTAINER_REGISTRY_NAME string = containerRegistry.outputs.name
output AZURE_CONTAINER_ENVIRONMENT_NAME string = containerAppsEnvironment.outputs.name

// Apps
output AZURE_CONTAINER_APP_API_NAME string = apiContainerApp.outputs.name
output AZURE_CONTAINER_APP_WEB_NAME string = webContainerApp.outputs.name

output API_URL string = 'https://${apiContainerApp.outputs.fqdn}'
output VITE_API_URL string = 'https://${apiContainerApp.outputs.fqdn}'
output WEB_URL string = 'https://${webContainerApp.outputs.fqdn}'

// Storage Account
output AZURE_STORAGE_ACCOUNT_NAME string = storage.outputs.name
output AZURE_STORAGE_BLOB_ENDPOINT string = '${storage.outputs.primaryBlobEndpoint}upload'
