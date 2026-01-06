@description('Name of the Redis cache')
param name string

@description('Location for the cache')
param location string = resourceGroup().location

@description('Tags for the resource')
param tags object = {}

@description('Log Analytics Workspace ID for diagnostics')
param logAnalyticsWorkspaceId string

@description('SKU name for Redis cache')
@allowed(['Basic', 'Standard', 'Premium'])
param skuName string = 'Standard'

@description('SKU family for Redis cache')
@allowed(['C', 'P'])
param skuFamily string = 'C'

@description('SKU capacity for Redis cache')
@allowed([0, 1, 2, 3, 4, 5, 6])
param skuCapacity int = 1

resource redis 'Microsoft.Cache/redis@2023-08-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    sku: {
      name: skuName
      family: skuFamily
      capacity: skuCapacity
    }
    enableNonSslPort: false
    minimumTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
    redisConfiguration: {
      'maxmemory-policy': 'allkeys-lru'
    }
  }
}

// Diagnostic settings for Redis
resource redisDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: '${name}-diagnostics'
  scope: redis
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

output id string = redis.id
output name string = redis.name
output hostName string = redis.properties.hostName
output port int = redis.properties.sslPort

@description('Primary access key for Redis')
output primaryKey string = redis.listKeys().primaryKey
