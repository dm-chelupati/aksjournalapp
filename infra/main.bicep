targetScope = 'subscription'

@description('Name of the environment (used for resource naming)')
param environmentName string

@description('Primary location for all resources')
param location string

@description('Name of the AKS cluster')
param aksClusterName string = ''

@description('Name of the Redis cache')
param redisCacheName string = ''

@description('Name of the Log Analytics workspace')
param logAnalyticsName string = ''

@description('Name of the Container Registry')
param containerRegistryName string = ''

@description('Tags for all resources')
param tags object = {}

// Generate unique names if not provided
var abbrs = loadJsonContent('./abbreviations.json')
var resourceToken = toLower(uniqueString(subscription().id, environmentName, location))
var finalAksClusterName = !empty(aksClusterName) ? aksClusterName : '${abbrs.containerServiceManagedClusters}${resourceToken}'
var finalRedisCacheName = !empty(redisCacheName) ? redisCacheName : '${abbrs.cacheRedis}${resourceToken}'
var finalLogAnalyticsName = !empty(logAnalyticsName) ? logAnalyticsName : '${abbrs.operationalInsightsWorkspaces}${resourceToken}'
var finalContainerRegistryName = !empty(containerRegistryName) ? containerRegistryName : '${abbrs.containerRegistries}${resourceToken}'

var defaultTags = union(tags, {
  'azd-env-name': environmentName
})

// Resource Group
resource rg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: '${abbrs.resourcesResourceGroups}${environmentName}'
  location: location
  tags: defaultTags
}

// Log Analytics Workspace for Azure Monitor
module logAnalytics './modules/log-analytics.bicep' = {
  name: 'log-analytics'
  scope: rg
  params: {
    name: finalLogAnalyticsName
    location: location
    tags: defaultTags
  }
}

// Azure Container Registry
module acr './modules/acr.bicep' = {
  name: 'acr'
  scope: rg
  params: {
    name: finalContainerRegistryName
    location: location
    tags: defaultTags
  }
}

// Azure Cache for Redis
module redis './modules/redis.bicep' = {
  name: 'redis'
  scope: rg
  params: {
    name: finalRedisCacheName
    location: location
    tags: defaultTags
    logAnalyticsWorkspaceId: logAnalytics.outputs.id
  }
}

// AKS Cluster with Container Insights
module aks './modules/aks.bicep' = {
  name: 'aks'
  scope: rg
  params: {
    name: finalAksClusterName
    location: location
    tags: defaultTags
    logAnalyticsWorkspaceId: logAnalytics.outputs.id
  }
}

// Grant AKS access to ACR
module aksAcrRole './modules/aks-acr-role.bicep' = {
  name: 'aks-acr-role'
  scope: rg
  params: {
    aksKubeletIdentityId: aks.outputs.kubeletIdentityObjectId
    acrName: acr.outputs.name
  }
}

// Alert Rules for SRE Agent Demo
module alerts './modules/alerts.bicep' = {
  name: 'alerts'
  scope: rg
  params: {
    aksClusterName: aks.outputs.name
    aksClusterId: aks.outputs.id
    logAnalyticsWorkspaceId: logAnalytics.outputs.id
    location: location
    tags: defaultTags
  }
}

// Outputs for azd
output AZURE_LOCATION string = location
output AZURE_RESOURCE_GROUP string = rg.name
output AZURE_AKS_CLUSTER_NAME string = aks.outputs.name
output AZURE_CONTAINER_REGISTRY_ENDPOINT string = acr.outputs.loginServer
output AZURE_CONTAINER_REGISTRY_NAME string = acr.outputs.name
output AZURE_REDIS_HOST string = redis.outputs.hostName
output AZURE_REDIS_PORT int = redis.outputs.port

@description('Redis primary key for authentication')
output AZURE_REDIS_PASSWORD string = redis.outputs.primaryKey

output AZURE_LOG_ANALYTICS_WORKSPACE_ID string = logAnalytics.outputs.id
output AZURE_LOG_ANALYTICS_WORKSPACE_NAME string = logAnalytics.outputs.name
