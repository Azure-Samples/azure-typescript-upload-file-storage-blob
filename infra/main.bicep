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

// Resource group
resource rg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: '${abbrs.resourcesResourceGroups}${environmentName}'
  location: location
  tags: tags
}

// Log Analytics Workspace for Container Apps
module logAnalytics 'br/public:avm/res/operational-insights/workspace:0.14.2' = {
  name: 'logs-deployment'
  scope: rg
  params: {
    name: '${abbrs.operationalInsightsWorkspaces}${resourceToken}'
    location: location
    tags: tags
  }
}

// Storage Account with upload container
module storage 'br/public:avm/res/storage/storage-account:0.30.0' = {
  name: 'storage-deployment'
  scope: rg
  params: {
    name: '${abbrs.storageStorageAccounts}${resourceToken}'
    location: location
    tags: tags
    kind: 'StorageV2'
    skuName: 'Standard_LRS'
    allowBlobPublicAccess: true
    blobServices: {
      containers: [
        {
          name: 'upload'
          publicAccess: 'Blob'
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
  name: 'acr-deployment'
  scope: rg
  params: {
    name: '${abbrs.containerRegistryRegistries}${resourceToken}'
    location: location
    tags: tags
    acrSku: 'Basic'
    acrAdminUserEnabled: true
  }
}

// Container Apps Environment
module containerAppsEnvironment 'br/public:avm/res/app/managed-environment:0.11.3' = {
  name: 'containerenv-deployment'
  scope: rg
  params: {
    name: '${abbrs.appManagedEnvironments}${resourceToken}'
    location: location
    tags: tags
  }
}

// API Container App
module apiContainerApp 'br/public:avm/res/app/container-app:0.19.0' = {
  name: 'api-deployment'
  scope: rg
  params: {
    name: '${abbrs.appContainerApps}api-${resourceToken}'
    location: location
    tags: union(tags, { 'azd-service-name': 'api' })
    environmentResourceId: containerAppsEnvironment.outputs.resourceId
    managedIdentities: {
      systemAssigned: true
    }
    registries: [
      {
        server: containerRegistry.outputs.loginServer
        identity: 'system'
      }
    ]
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
            name: 'Azure_Storage_AccountName'
            value: storage.outputs.name
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
    ingressTransport: 'auto'
    scaleSettings: {
      minReplicas: 0
      maxReplicas: 1
      rules: [
        {
          name: 'http-scale'
          http: {
            metadata: {
              concurrentRequests: '50'
            }
          }
        }
      ]
    }
  }
}

// Web/Frontend Container App
module webContainerApp 'br/public:avm/res/app/container-app:0.19.0' = {
  name: 'web-deployment'
  scope: rg
  params: {
    name: '${abbrs.appContainerApps}web-${resourceToken}'
    location: location
    tags: union(tags, { 'azd-service-name': 'web' })
    environmentResourceId: containerAppsEnvironment.outputs.resourceId
    registries: [
      {
        server: containerRegistry.outputs.loginServer
        username: containerRegistry.outputs.name
        passwordSecretRef: 'registry-password'
      }
    ]
    secrets: [
      {
        name: 'registry-password'
        value: containerRegistry.outputs.loginServer
      }
    ]
    containers: [
      {
        name: 'web'
        image: 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'
        resources: {
          cpu: json('0.25')
          memory: '0.5Gi'
        }
        env: [
          {
            name: 'VITE_API_URL'
            value: 'https://${apiContainerApp.outputs.fqdn}'
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
    ingressTransport: 'auto'
    scaleSettings: {
      minReplicas: 0
      maxReplicas: 1
    }
  }
}

// Grant API Container App Storage Blob Data Contributor role
module apiStorageBlobRole 'br/public:avm/res/authorization/role-assignment/rg-scope:0.1.1' = {
  name: 'api-storage-blob-role'
  scope: rg
  params: {
    principalId: apiContainerApp.outputs.?systemAssignedMIPrincipalId ?? ''
    roleDefinitionIdOrName: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe') // Storage Blob Data Contributor
    principalType: 'ServicePrincipal'
  }
}

// Grant API Container App Storage Blob Delegator role
module apiStorageDelegatorRole 'br/public:avm/res/authorization/role-assignment/rg-scope:0.1.1' = {
  name: 'api-storage-delegator-role'
  scope: rg
  params: {
    principalId: apiContainerApp.outputs.?systemAssignedMIPrincipalId ?? ''
    roleDefinitionIdOrName: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'db58b8e5-c6ad-4a2a-8342-4190687cbf4a') // Storage Blob Delegator
    principalType: 'ServicePrincipal'
  }
}

// Grant Container Apps ACR Pull role
module apiAcrPullRole 'br/public:avm/res/authorization/role-assignment/rg-scope:0.1.1' = {
  name: 'api-acr-pull-role'
  scope: rg
  params: {
    principalId: apiContainerApp.outputs.?systemAssignedMIPrincipalId ?? ''
    roleDefinitionIdOrName: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d') // AcrPull
    principalType: 'ServicePrincipal'
  }
}

// Outputs
output AZURE_LOCATION string = location
output AZURE_TENANT_ID string = tenant().tenantId
output AZURE_RESOURCE_GROUP string = rg.name
output AZURE_CONTAINER_REGISTRY_ENDPOINT string = containerRegistry.outputs.loginServer
output AZURE_CONTAINER_REGISTRY_NAME string = containerRegistry.outputs.name
output AZURE_CONTAINER_ENVIRONMENT_NAME string = containerAppsEnvironment.outputs.name
output AZURE_CONTAINER_APP_API_NAME string = apiContainerApp.outputs.name
output API_URL string = 'https://${apiContainerApp.outputs.fqdn}'
output WEB_URL string = 'https://${webContainerApp.outputs.fqdn}'
output AZURE_STORAGE_ACCOUNT_NAME string = storage.outputs.name
output AZURE_STORAGE_BLOB_ENDPOINT string = storage.outputs.primaryBlobEndpoint
