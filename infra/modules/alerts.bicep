@description('Name of the AKS cluster')
param aksClusterName string

@description('Resource ID of the AKS cluster')
param aksClusterId string

@description('Log Analytics Workspace ID')
param logAnalyticsWorkspaceId string

@description('Location for alert rules')
param location string = resourceGroup().location

@description('Tags for resources')
param tags object = {}

var abbrs = loadJsonContent('../abbreviations.json')

// Action Group for alerts (email/webhook notifications)
resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: '${abbrs.insightsActionGroups}sre-alerts'
  location: 'global'
  tags: tags
  properties: {
    groupShortName: 'SREAlerts'
    enabled: true
    emailReceivers: [
      {
        name: 'SRE Team'
        emailAddress: 'sre-team@contoso.com'
        useCommonAlertSchema: true
      }
    ]
  }
}

// Alert: High CPU Usage on AKS nodes
resource cpuAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: '${abbrs.insightsMetricAlerts}aks-high-cpu'
  location: 'global'
  tags: tags
  properties: {
    description: 'Alert when AKS node CPU usage exceeds 80%'
    severity: 2
    enabled: true
    scopes: [aksClusterId]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'HighCPU'
          metricName: 'node_cpu_usage_percentage'
          metricNamespace: 'Insights.Container/nodes'
          operator: 'GreaterThan'
          threshold: 80
          timeAggregation: 'Average'
          criterionType: 'StaticThresholdCriterion'
          skipMetricValidation: true
        }
      ]
    }
    actions: [
      {
        actionGroupId: actionGroup.id
      }
    ]
  }
}

// Alert: High Memory Usage on AKS nodes
resource memoryAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: '${abbrs.insightsMetricAlerts}aks-high-memory'
  location: 'global'
  tags: tags
  properties: {
    description: 'Alert when AKS node memory usage exceeds 80%'
    severity: 2
    enabled: true
    scopes: [aksClusterId]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'HighMemory'
          metricName: 'node_memory_working_set_percentage'
          metricNamespace: 'Insights.Container/nodes'
          operator: 'GreaterThan'
          threshold: 80
          timeAggregation: 'Average'
          criterionType: 'StaticThresholdCriterion'
          skipMetricValidation: true
        }
      ]
    }
    actions: [
      {
        actionGroupId: actionGroup.id
      }
    ]
  }
}

// Alert: Pod restart count
resource podRestartAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: '${abbrs.insightsMetricAlerts}aks-pod-restarts'
  location: 'global'
  tags: tags
  properties: {
    description: 'Alert when pods restart frequently'
    severity: 3
    enabled: true
    scopes: [aksClusterId]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'PodRestarts'
          metricName: 'restarting_container_count'
          metricNamespace: 'Insights.Container/pods'
          operator: 'GreaterThan'
          threshold: 3
          timeAggregation: 'Total'
          criterionType: 'StaticThresholdCriterion'
          skipMetricValidation: true
        }
      ]
    }
    actions: [
      {
        actionGroupId: actionGroup.id
      }
    ]
  }
}

// Log-based Alert: Container Errors in Log Analytics
resource containerErrorAlert 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: '${abbrs.insightsMetricAlerts}container-errors'
  location: location
  tags: tags
  properties: {
    displayName: 'Container Error Logs Alert'
    description: 'Alert when container logs contain errors'
    severity: 2
    enabled: true
    evaluationFrequency: 'PT5M'
    scopes: [logAnalyticsWorkspaceId]
    windowSize: 'PT15M'
    criteria: {
      allOf: [
        {
          query: '''
            ContainerLogV2
            | where LogLevel == "error" or LogMessage contains "error" or LogMessage contains "exception"
            | summarize ErrorCount = count() by ContainerName, PodName, bin(TimeGenerated, 5m)
          '''
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 10
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: {
      actionGroups: [actionGroup.id]
    }
  }
}

// Log-based Alert: OOMKilled containers
resource oomKilledAlert 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: '${abbrs.insightsMetricAlerts}oom-killed'
  location: location
  tags: tags
  properties: {
    displayName: 'OOMKilled Container Alert'
    description: 'Alert when containers are killed due to Out of Memory'
    severity: 1
    enabled: true
    evaluationFrequency: 'PT5M'
    scopes: [logAnalyticsWorkspaceId]
    windowSize: 'PT15M'
    criteria: {
      allOf: [
        {
          query: '''
            KubeEvents
            | where Reason == "OOMKilled"
            | summarize OOMCount = count() by Name, Namespace, bin(TimeGenerated, 5m)
          '''
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: {
      actionGroups: [actionGroup.id]
    }
  }
}

// Log-based Alert: Failed Kubernetes Jobs
resource jobFailureAlert 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: '${abbrs.insightsMetricAlerts}job-failures'
  location: location
  tags: tags
  properties: {
    displayName: 'Kubernetes Job Failure Alert'
    description: 'Alert when Kubernetes jobs fail'
    severity: 2
    enabled: true
    evaluationFrequency: 'PT5M'
    scopes: [logAnalyticsWorkspaceId]
    windowSize: 'PT30M'
    criteria: {
      allOf: [
        {
          query: '''
            KubeEvents
            | where Reason == "BackoffLimitExceeded" or Reason == "Failed"
            | where ObjectKind == "Job"
            | summarize FailureCount = count() by Name, Namespace, bin(TimeGenerated, 5m)
          '''
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: {
      actionGroups: [actionGroup.id]
    }
  }
}

output actionGroupId string = actionGroup.id
