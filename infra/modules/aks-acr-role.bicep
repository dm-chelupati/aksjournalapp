@description('AKS Kubelet Identity Object ID')
param aksKubeletIdentityId string

@description('Name of the ACR')
param acrName string

// Reference existing ACR
resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = {
  name: acrName
}

// AcrPull role definition
var acrPullRoleId = '7f951dda-4ed3-4680-a7ca-43fe172d538d'

// Assign AcrPull role to AKS kubelet identity
resource acrPullRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acr.id, aksKubeletIdentityId, acrPullRoleId)
  scope: acr
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', acrPullRoleId)
    principalId: aksKubeletIdentityId
    principalType: 'ServicePrincipal'
  }
}
