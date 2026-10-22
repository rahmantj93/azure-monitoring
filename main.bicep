param location string = resourceGroup().location
param alertEmail string

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: 'law-monitoring'
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: 'ag-ops'
  location: 'global'
  properties: {
    groupShortName: 'ops'
    enabled: true
    emailReceivers: [
      {
        name: 'ops-email'
        emailAddress: alertEmail
        useCommonAlertSchema: true
      }
    ]
  }
}

resource cpuAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'alert-vm-high-cpu'
  location: 'global'
  properties: {
    description: 'Average CPU above 80% for 15 minutes on any VM in this resource group'
    severity: 2
    enabled: true
    scopes: [
      resourceGroup().id
    ]
    targetResourceType: 'Microsoft.Compute/virtualMachines'
    targetResourceRegion: location
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.MultipleResourceMultipleMetricCriteria'
      allOf: [
        {
          criterionType: 'StaticThresholdCriterion'
          name: 'HighCpu'
          metricName: 'Percentage CPU'
          metricNamespace: 'Microsoft.Compute/virtualMachines'
          operator: 'GreaterThan'
          threshold: 80
          timeAggregation: 'Average'
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

resource vmDeleteAlert 'Microsoft.Insights/activityLogAlerts@2020-10-01' = {
  name: 'alert-vm-deleted'
  location: 'global'
  properties: {
    description: 'A virtual machine was deleted in this resource group'
    enabled: true
    scopes: [
      resourceGroup().id
    ]
    condition: {
      allOf: [
        {
          field: 'category'
          equals: 'Administrative'
        }
        {
          field: 'operationName'
          equals: 'Microsoft.Compute/virtualMachines/delete'
        }
       {
          field: 'status'
          equals: 'Succeeded'
        }
      ]
    }
    actions: {
      actionGroups: [
        {
          actionGroupId: actionGroup.id
        }
      ]
    }
  }
}

resource vault 'Microsoft.RecoveryServices/vaults@2024-02-01' = {
  name: 'rsv-monitoring'
  location: location
  sku: {
    name: 'RS0'
    tier: 'Standard'
  }
  properties: {
    publicNetworkAccess: 'Enabled'
    redundancySettings: {
      standardTierStorageRedundancy: 'LocallyRedundant'
      crossRegionRestore: 'Disabled'
    }
  }
}

resource vmPolicy 'Microsoft.RecoveryServices/vaults/backupPolicies@2024-02-01' = {
  parent: vault
  name: 'policy-vm-enhanced-4h'
  properties: {
    backupManagementType: 'AzureIaasVM'
    policyType: 'V2'
    instantRpRetentionRangeInDays: 7
    timeZone: 'UTC'
    schedulePolicy: {
      schedulePolicyType: 'SimpleSchedulePolicyV2'
      scheduleRunFrequency: 'Hourly'
      hourlySchedule: {
        interval: 4
        scheduleWindowStartTime: '2026-01-01T22:00:00Z'
        scheduleWindowDuration: 24
      }
    }
    retentionPolicy: {
      retentionPolicyType: 'LongTermRetentionPolicy'
      dailySchedule: {
        retentionTimes: [
          '2026-01-01T22:00:00Z'
        ]
        retentionDuration: {
          count: 30
          durationType: 'Days'
        }
      }
    }
  }
}

var backupLogCategories = [
  'CoreAzureBackup'
  'AddonAzureBackupJobs'
  'AddonAzureBackupPolicy'
  'AddonAzureBackupStorage'
  'AddonAzureBackupProtectedInstance'
  'AzureBackupOperations'
]

resource vaultDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag-vault-to-law'
  scope: vault
  properties: {
    workspaceId: workspace.id
    logAnalyticsDestinationType: 'Dedicated'
    logs: [for category in backupLogCategories: {
      category: category
      enabled: true
    }]
  }
}
