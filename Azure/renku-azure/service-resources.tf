# Storage
resource "azurerm_storage_account" "accounts" {
  for_each = {
    for svc in var.service_resources : svc.name => {
      name                     = lower(substr("${svc.name}${replace(var.environment_name, "-", "")}", 0, 24))
      resource_group_name      = azurerm_resource_group.renku-environment.name
      location                 = var.location
      account_tier             = "Standard"
      account_replication_type = "LRS"
    } if svc.create_storage
  }

  name                     = each.value.name
  resource_group_name      = each.value.resource_group_name
  location                 = each.value.location
  account_tier             = each.value.account_tier
  account_replication_type = each.value.account_replication_type
}

resource "azurerm_storage_container" "buckets" {
  for_each = {
    for bucket in concat(flatten([
      for svc in var.service_resources : [
        for bucket in svc.buckets : {
          svc_name : svc.name
          name : "${svc.name}-${bucket}-${var.environment_name}"
          id : azurerm_storage_account.accounts[svc.name].id
        }
      ]]),
      [
        for svc in var.service_resources : {
          svc_name : svc.name
          name : "${svc.name}-${var.environment_name}"
          id : azurerm_storage_account.accounts[svc.name].id
        } if length(svc.buckets) == 0
      ]
    ) : bucket.name => bucket
  }

  name                  = each.value.name
  storage_account_id    = each.value.id
  container_access_type = "private"
}

resource "kubernetes_secret" "azure_storage_access_keys" {
  for_each = {
    for svc in var.service_resources : svc.name => {
      namespace          = coalesce(svc.namespace, svc.name)
      access_key         = azurerm_storage_account.accounts[svc.name].primary_access_key
      k8s_secret_name    = svc.k8s_secret_name
      k8s_secret_env_key = svc.k8s_secret_env_key
    } if svc.create_storage
  }

  metadata {
    name      = each.value.k8s_secret_name
    namespace = each.value.namespace
  }

  data = {
    (each.value.k8s_secret_env_key) = each.value.access_key
  }
}
