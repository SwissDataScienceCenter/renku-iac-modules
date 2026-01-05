terraform {
  required_version = ">=1.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = "<YOUR_AZURE_SUBSCRIPTION_ID>"
}

locals {
  aks_admins = [
    "00000000-0000-0000-0000-000000000000", # Foo Bar
  ]

  aks_readers = [
    "00000000-0000-0000-0000-000000000000", # Bar Foo
  ]
}

module "renku-azure" {
  source = "../../../modules/renku-azure"

  aks_admins              = local.aks_admins
  aks_readers             = local.aks_readers
  dns_resource_group_name = "<YOUR_DNS_RESOURCE_GROUP_NAME>"
  dns_zone_name           = "<YOUR_DNS_ZONE"
  environment_name        = "<YOUR_ENVIRONMENT_NAME>"
  location                = var.location

  cluster_name                = "<YOUR_AKS_CLUSTER_NAME>"
  dns_prefix                  = "<YOUR_AKS_DNS_PREFIX>"
  user_assigned_identity_name = "<YOUR_USER_ASSIGNED_IDENTITY_NAME>"

  # Optional
  default_node_pool = {
    name                 = "<YOUR_DEFAULT_NODE_POOL_NAME>"
    vm_size              = "Standard_D4as_v5"
    auto_scaling_enabled = true
    min_count            = 2
    max_count            = 20
    scale_down_mode      = "Delete"
    max_surge            = "20%"
  }

  service_resources = [
    {
      name               = "harbor"
      namespace          = "harbor"
      create_storage     = true
      k8s_secret_env_key = "AZURE_STORAGE_ACCESS_KEY"
      k8s_secret_name    = "azure-storage-access-key"
    },
    {
      name               = "loki"
      namespace          = "monitoring"
      buckets            = ["admin", "chunks", "ruler"]
      create_storage     = true
      k8s_secret_env_key = "AZURE_ACCOUNT_KEY"
      k8s_secret_name    = "azure-storage-access-key"
    }
  ]

  maintenance_window_node_os = {
    frequency   = "Weekly"
    duration    = "4"
    start_time  = "03:00"
    day_of_week = "Saturday"
    interval    = 1        # Every 1 week
    utc_offset  = "+02:00" # UTC offset for the start time
  }

  node_pools = concat(
    yamldecode(file("user-sessions-node-pools.yaml")).pools,
    [
      {
        name          = "renkusvcs"
        sizes         = ["2", "4", "8"]
        max_count     = 5
        user_sessions = false
      }
    ]
  )

  # Optional
  auto_scaler_profile = {
    max_unready_nodes = 7
  }
}