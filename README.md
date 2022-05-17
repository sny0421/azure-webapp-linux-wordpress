# WordPress with Azure App Service (Linux / PHP8)
This is the template for deploy WordPress based PHP 8 with Linux on Azure App Service.
WordPress files are some custom for this environment.
Source repositry is [HERE](https://github.com/sny0421/azure-webapp-linux-wordpress-code).

## Architecture

- App Service (at least Basic plan)
- Azure Database for MySQL flexible server
- Virtual Network
- Key Vault
- Storage Account

![Architecture](https://github.com/sny0421/azure-webapp-linux-wordpress/blob/main/azure-webapp-linux-wordpress-architecture.png?raw=true)

## Setup
Deploy to Azure !!

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fsny0421%2Fazure-webapp-linux-wordpress%2Fmain%2Fmain.json)

Or, if use Azure CLI.
### 1. Create resource group
Create resource group for deploy some resources (App Service, Virtual Network, and so on.)

```
az group create -n rg-wptest220517 -l japaneast
```

###　2. Deploy to Azure
Deploy to Azure with some parameters.

```
az deployment group create --name Deploy-Test-202205172039 --resource-group rg-wptest220517 --template-file main.bicep --parameters site_name=wptest220517 db_password='Password'
```

## License
This software is released under the GPL License, see LICENSE.

## Authors
@sny0421

- [Site](https://www.ether-zone.com/)

## References
- [Enable virtual network integration in Azure App Service - Azure App Service | Microsoft Docs](https://docs.microsoft.com/ja-jp/azure/app-service/configure-vnet-integration-enable)
