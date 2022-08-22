// Parameters
@description('Location for all resources.')
param region string = resourceGroup().location

@description('Site URL host name (ex. wordpress-test).')
param site_name string = ''

@description('User name of MySQL database server.')
param db_username string = 'dbadmin'

@description('Password of MySQL database server.')
@secure()
param db_password string

@description('SKU of App Service Plan.')
@allowed([
  'B1'
  'B2'
  'B3'
  'S1'
  'S2'
  'S3'
  'P1V2'
])
param selected_sku string = 'B1'

@description('Unique string seed for WordPress auth keys and salts.')
param unique_seed_string string = utcNow()

@description('Source WordPress repositry.')
param repo_url string = 'https://github.com/sny0421/azure-webapp-linux-wordpress-code'
@description('Source brunch.')
param branch string = 'main'

// Variables
var storage_account_name = replace(toLower(site_name), '-', '')
var virtual_network_name = 'vnet-${site_name}'
var private_dns_zone_mysql_flexible_name = '${mysql_flexible_server_name}.private.mysql.database.azure.com'
var mysql_flexible_server_name = 'dbsv-${site_name}'
var db_name = 'db_${replace(site_name, '-', '_')}'
var key_vault_name = 'kv-${site_name}'
var app_service_plan_name = 'asp-${site_name}'
var app_service_site_name = site_name

var asp_sku = {
  B1: {
    name: 'B1'
    tier: 'Basic'
    size: 'B1'
    family: 'B'
    capacity: 1
  }
  B2: {
    name: 'B2'
    tier: 'Basic'
    size: 'B2'
    family: 'B'
    capacity: 2
  }
  B3: {
    name: 'B3'
    tier: 'Basic'
    size: 'B3'
    family: 'B'
    capacity: 3
  }
  S1: {
    name: 'S1'
    tier: 'Standard'
    size: 'S1'
    family: 'S'
    capacity: 1
  }
  S2: {
    name: 'S2'
    tier: 'Standard'
    size: 'S2'
    family: 'S'
    capacity: 2
  }
  S3: {
    name: 'S3'
    tier: 'Standard'
    size: 'S3'
    family: 'S'
    capacity: 3
  }
}

var wp_secret_auth_key = uniqueString(unique_seed_string, 'auth-key')
var wp_secret_secure_auth_key = uniqueString(unique_seed_string, 'secure-auth-key')
var wp_secret_logged_in_key = uniqueString(unique_seed_string, 'logged-in-key')
var wp_secret_nonce_key = uniqueString(unique_seed_string, 'nonce-key')
var wp_secret_auth_salt = uniqueString(unique_seed_string, 'auth-salt')
var wp_secret_secure_auth_salt = uniqueString(unique_seed_string, 'secure-auth-salt')
var wp_secret_logged_in_salt = uniqueString(unique_seed_string, 'logged-in-salt')
var wp_secret_nonce_salt = uniqueString(unique_seed_string, 'nonce-salt')

// Resources
/// Virtual Network
resource virtual_network 'Microsoft.Network/virtualNetworks@2020-11-01' = {
  name: virtual_network_name
  location: region
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.140.0/24'
      ]
    }
    virtualNetworkPeerings: []
    enableDdosProtection: false
  }

  resource subnet_webapp 'subnets' = {
    name: 'snet-webapp'
    properties: {
      addressPrefix: '10.0.140.0/28'
      serviceEndpoints: [
        {
          service: 'Microsoft.Web'
        }
        {
          service: 'Microsoft.Storage'
        }
        {
          service: 'Microsoft.KeyVault'
        }
      ]
      delegations: [
        {
          name: 'delegation'
          properties: {
            serviceName: 'Microsoft.Web/serverfarms'
          }
        }
      ]
      privateEndpointNetworkPolicies: 'Enabled'
      privateLinkServiceNetworkPolicies: 'Enabled'
    }
  }
  resource subnet_mysql 'subnets' = {
    name: 'snet-mysql'
    properties: {
      addressPrefix: '10.0.140.16/28'
      serviceEndpoints: []
      delegations: [
        {
          name: 'Microsoft.DBforMySQL.flexibleServers'
          properties: {
            serviceName: 'Microsoft.DBforMySQL/flexibleServers'
          }
        }
      ]
      privateEndpointNetworkPolicies: 'Enabled'
      privateLinkServiceNetworkPolicies: 'Enabled'
    }
    dependsOn: [
      subnet_webapp
    ]
  }
}

// Private DNS Zone
resource private_dns_zone_mysql_flexible 'Microsoft.Network/privateDnsZones@2018-09-01' = {
  name: private_dns_zone_mysql_flexible_name
  location: 'global'
}

resource private_dns_zone_mysql_flexible_soa 'Microsoft.Network/privateDnsZones/SOA@2018-09-01' = {
  parent: private_dns_zone_mysql_flexible
  name: '@'
  properties: {
    ttl: 3600
    soaRecord: {
      email: 'azureprivatedns-host.microsoft.com'
      expireTime: 2419200
      host: 'azureprivatedns.net'
      minimumTtl: 10
      refreshTime: 3600
      retryTime: 300
      serialNumber: 1
    }
  }
}

resource private_dns_zone_mysql_flexible_associate 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2018-09-01' = {
  parent: private_dns_zone_mysql_flexible
  name: 'private_dns_zone_mysql_flexible_${replace(site_name, '-', '_')}_associate'
  location: 'global'
  properties: {
    registrationEnabled: true
    virtualNetwork: {
      id: virtual_network.id
    }
  }
}

/// Azure DB for MySQL
resource mysql_flexible_server 'Microsoft.DBforMySQL/flexibleServers@2021-05-01' = {
  name: mysql_flexible_server_name
  location: region
  sku: {
    name: 'Standard_B1s'
    tier: 'Burstable'
  }
  properties: {
    administratorLogin: db_username
    administratorLoginPassword: db_password
    createMode: 'Default'
    storage: {
      storageSizeGB: 20
      iops: 360
      autoGrow: 'Disabled'
    }
    version: '8.0.21'
    availabilityZone: '1'
    replicationRole: 'None'
    network: {
      delegatedSubnetResourceId: virtual_network::subnet_mysql.id
      privateDnsZoneResourceId: private_dns_zone_mysql_flexible.id
    }
    backup: {
      backupRetentionDays: 7
      geoRedundantBackup: 'Disabled'
    }
    highAvailability: {
      mode: 'Disabled'
    }
  }
  resource mysql_flexible_server_database_wordpress 'databases' = {
    name: db_name
    properties: {
      charset: 'utf8'
      collation: 'utf8_general_ci'
    }
  }
  dependsOn: [
    private_dns_zone_mysql_flexible_associate
    virtual_network
  ]
}

/// Storage Accounts
resource storage_account 'Microsoft.Storage/storageAccounts@2021-08-01' = {
  name: storage_account_name
  location: region
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    defaultToOAuthAuthentication: false
    publicNetworkAccess: 'Enabled'
    allowCrossTenantReplication: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: true
    allowSharedKeyAccess: true
    networkAcls: {
      bypass: 'AzureServices'
      virtualNetworkRules: []
      ipRules: []
      defaultAction: 'Allow'
    }
    supportsHttpsTrafficOnly: true
    encryption: {
      requireInfrastructureEncryption: true
      services: {
        blob: {
          keyType: 'Account'
          enabled: true
        }
      }
      keySource: 'Microsoft.Storage'
    }
    accessTier: 'Hot'
  }

  resource storage_account_blob 'blobServices@2021-08-01' = {
    name: 'default'
    properties: {
      changeFeed: {
        enabled: true
      }
      restorePolicy: {
        enabled: true
        days: 6
      }
      containerDeleteRetentionPolicy: {
        enabled: true
        days: 7
      }
      cors: {
        corsRules: []
      }
      deleteRetentionPolicy: {
        enabled: true
        days: 35
      }
      isVersioningEnabled: true
    }

    resource storage_account_blob_blog_media 'containers' = {
      name: 'blog-media'
      properties: {
        defaultEncryptionScope: '$account-encryption-key'
        denyEncryptionScopeOverride: false
        publicAccess: 'None'
      }
    }
  }
}

/// Key Vaylt
resource key_vault 'Microsoft.KeyVault/vaults@2021-11-01-preview' = {
  name: key_vault_name
  location: region
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Deny'
      ipRules: []
      virtualNetworkRules: [
        {
          id: virtual_network::subnet_webapp.id
          ignoreMissingVnetServiceEndpoint: false
        }
      ]
    }
    accessPolicies: [
      {
        tenantId: subscription().tenantId
        objectId: app_service_site.identity.principalId
        permissions: {
          secrets: [
            'get'
          ]
        }
      }
    ]
    enabledForDeployment: false
    enabledForDiskEncryption: false
    enabledForTemplateDeployment: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
    enableRbacAuthorization: false
    publicNetworkAccess: 'Enabled'
  }

  resource key_vault_secret_sc_mysql 'secrets' = {
    name: 'secret-sc-mysql'
    properties: {
      attributes: {
        enabled: true
      }
      value: 'Server="${mysql_flexible_server_name}.mysql.database.azure.com";UserID="${db_username}";Password="${db_password}";Database="${db_name}";SslMode=MySqlSslMode.Required;'
    }
  }

  resource key_vault_secret_db_password 'secrets' = {
    name: 'secret-db-password'
    properties: {
      attributes: {
        enabled: true
      }
      value: db_password
    }
  }

  resource key_vault_secret_wp_secret_auth_key 'secrets' = {
    name: 'secret-wp-secret-auth-key'
    properties: {
      attributes: {
        enabled: true
      }
      value: wp_secret_auth_key
    }
  }

  resource key_vault_secret_wp_secret_secure_auth_key 'secrets' = {
    name: 'secret-wp-secret-secure-auth-key'
    properties: {
      attributes: {
        enabled: true
      }
      value: wp_secret_secure_auth_key
    }
  }

  resource key_vault_secret_wp_secret_logged_in_key 'secrets' = {
    name: 'secret-wp-secret-logged-in-key'
    properties: {
      attributes: {
        enabled: true
      }
      value: wp_secret_logged_in_key
    }
  }

  resource key_vault_secret_wp_secret_nonce_key 'secrets' = {
    name: 'secret-wp-secret-nonce-key'
    properties: {
      attributes: {
        enabled: true
      }
      value: wp_secret_nonce_key
    }
  }

  resource key_vault_secret_wp_secret_auth_salt 'secrets' = {
    name: 'secret-wp-secret-auth-salt'
    properties: {
      attributes: {
        enabled: true
      }
      value: wp_secret_auth_salt
    }
  }

  resource key_vault_secret_wp_secret_secure_auth_salt 'secrets' = {
    name: 'secret-wp-secret-secure-auth-salt'
    properties: {
      attributes: {
        enabled: true
      }
      value: wp_secret_secure_auth_salt
    }
  }

  resource key_vault_secret_wp_secret_logged_in_salt 'secrets' = {
    name: 'secret-wp-secret-logged-in-salt'
    properties: {
      attributes: {
        enabled: true
      }
      value: wp_secret_logged_in_salt
    }
  }

  resource key_vault_secret_wp_secret_nonce_salt 'secrets' = {
    name: 'secret-wp-secret-nonce-salt'
    properties: {
      attributes: {
        enabled: true
      }
      value: wp_secret_nonce_salt
    }
  }
}

/// App Service Plan
resource app_service_plan 'Microsoft.Web/serverfarms@2021-03-01' = {
  name: app_service_plan_name
  location: region
  sku: {
    name: asp_sku[selected_sku].name
    tier: asp_sku[selected_sku].tier
    size: asp_sku[selected_sku].size
    family: asp_sku[selected_sku].family
    capacity: asp_sku[selected_sku].capacity
  }
  kind: 'linux'
  properties: {
    perSiteScaling: false
    elasticScaleEnabled: false
    maximumElasticWorkerCount: 1
    isSpot: false
    reserved: true
    isXenon: false
    hyperV: false
    targetWorkerCount: 0
    targetWorkerSizeId: 0
    zoneRedundant: false
  }
}

/// App Service
resource app_service_site 'Microsoft.Web/sites@2021-03-01' = {
  name: app_service_site_name
  location: region
  kind: 'app,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    enabled: true
    hostNameSslStates: [
      {
        name: '${site_name}.azurewebsites.net'
        sslState: 'Disabled'
        hostType: 'Standard'
      }
      {
        name: '${site_name}.scm.azurewebsites.net'
        sslState: 'Disabled'
        hostType: 'Repository'
      }
    ]
    serverFarmId: app_service_plan.id
    reserved: true
    isXenon: false
    hyperV: false
    siteConfig: {
      numberOfWorkers: 1
      linuxFxVersion: 'PHP|8.0'
      acrUseManagedIdentityCreds: false
      alwaysOn: false
      http20Enabled: true
      functionAppScaleLimit: 0
      minimumElasticInstanceCount: 0
      virtualApplications: [
        {
          virtualPath: '/'
          physicalPath: 'site\\wwwroot'
          preloadEnabled: false
        }
      ]
      vnetRouteAllEnabled: true
    }
    scmSiteAlsoStopped: false
    clientAffinityEnabled: false
    clientCertEnabled: false
    clientCertMode: 'Required'
    hostNamesDisabled: false
    containerSize: 0
    dailyMemoryTimeQuota: 0
    httpsOnly: true
    redundancyMode: 'None'
    storageAccountRequired: false
    virtualNetworkSubnetId: virtual_network::subnet_webapp.id
    keyVaultReferenceIdentity: 'SystemAssigned'
  }

  resource site_config_appsettings 'config' = {
    name: 'appsettings'
    properties: {
      DATABASE_HOST: '${mysql_flexible_server_name}.mysql.database.azure.com'
      DATABASE_NAME: db_name
      DATABASE_USERNAME: db_username
      DATABASE_PASSWORD: '@Microsoft.KeyVault(VaultName=${key_vault_name};SecretName=${key_vault::key_vault_secret_db_password.name})'
      SC_MYSQL: '@Microsoft.KeyVault(VaultName=${key_vault_name};SecretName=${key_vault::key_vault_secret_sc_mysql.name})'
      WP_SECRET_AUTH_KEY: '@Microsoft.KeyVault(VaultName=${key_vault_name};SecretName=${key_vault::key_vault_secret_wp_secret_auth_key.name})'
      WP_SECRET_SECURE_AUTH_KEY: '@Microsoft.KeyVault(VaultName=${key_vault_name};SecretName=${key_vault::key_vault_secret_wp_secret_secure_auth_key.name})'
      WP_SECRET_LOGGED_IN_KEY: '@Microsoft.KeyVault(VaultName=${key_vault_name};SecretName=${key_vault::key_vault_secret_wp_secret_logged_in_key.name})'
      WP_SECRET_NONCE_KEY: '@Microsoft.KeyVault(VaultName=${key_vault_name};SecretName=${key_vault::key_vault_secret_wp_secret_nonce_key.name})'
      WP_SECRET_AUTH_SALT: '@Microsoft.KeyVault(VaultName=${key_vault_name};SecretName=${key_vault::key_vault_secret_wp_secret_auth_salt.name})'
      WP_SECRET_SECURE_AUTH_SALT: '@Microsoft.KeyVault(VaultName=${key_vault_name};SecretName=${key_vault::key_vault_secret_wp_secret_secure_auth_salt.name})'
      WP_SECRET_LOGGED_IN_SALT: '@Microsoft.KeyVault(VaultName=${key_vault_name};SecretName=${key_vault::key_vault_secret_wp_secret_logged_in_salt.name})'
      WP_SECRET_NONCE_SALT: '@Microsoft.KeyVault(VaultName=${key_vault_name};SecretName=${key_vault::key_vault_secret_wp_secret_nonce_salt.name})'
      WEBSITES_ENABLE_APP_SERVICE_STORAGE: 'true'
    }
    dependsOn: [
      site_sourcecontrols
    ]
  }

  resource site_sourcecontrols 'sourcecontrols' = {
    name: 'web'
    properties: {
      repoUrl: repo_url
      branch: branch
      isManualIntegration: true
    }
  }

  resource sites_wordpress_draft_name_f5ba2aeb_44b4_4b5b_97fe_3f6049f97a55_snet_webapp 'virtualNetworkConnections' = {
    name: '${app_service_site_name}_${virtual_network_name}_snet-webapp'
    properties: {
      vnetResourceId: virtual_network::subnet_webapp.id
      isSwift: true
    }
  }

  resource app_service_site_hostname 'hostNameBindings' = {
    name: '${site_name}.azurewebsites.net'
  }

  dependsOn: [
    mysql_flexible_server
  ]
}
