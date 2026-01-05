terraform {
  required_version = ">=1.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2"
    }
  }
}

resource "azurerm_resource_group" "renku-environment" {
  #ts:skip=AC_AZURE_0389 needed to skip this policy: https://runterrascan.io/docs/policies/azure/#azurerm_resource_group
  # Locking resources is not a bad idea, but when applied to a resource group, all resources inside the resource group inherit the lock. This means that `terraform destroy` has no effect.
  name     = var.environment_name
  location = var.location
}

resource "azurerm_user_assigned_identity" "renku-environment" {
  resource_group_name = azurerm_resource_group.renku-environment.name
  location            = var.location

  name = var.user_assigned_identity_name != null ? var.user_assigned_identity_name : var.environment_name
}

resource "azurerm_kubernetes_cluster" "renku-environment" {
  name                      = var.cluster_name != null ? var.cluster_name : var.environment_name
  location                  = var.location
  resource_group_name       = azurerm_resource_group.renku-environment.name
  dns_prefix                = var.dns_prefix != null ? var.dns_prefix : "${var.environment_name}-${var.location}"
  workload_identity_enabled = true
  oidc_issuer_enabled       = true
  kubernetes_version        = var.kubernetes_version
  sku_tier                  = var.sku_tier

  # # Workaround for bug: https://github.com/hashicorp/terraform-provider-azurerm/issues/27119
  dynamic "api_server_access_profile" {
    for_each = length(var.api_server_authorized_ip_ranges) > 0 ? [1] : []
    content {
      # There is a limit of maximum 200 CIDR entries in the list.
      authorized_ip_ranges = var.api_server_authorized_ip_ranges
    }
  }

  auto_scaler_profile {
    balance_similar_node_groups      = var.auto_scaler_profile.balance_similar_node_groups
    expander                         = var.auto_scaler_profile.expander
    max_graceful_termination_sec     = var.auto_scaler_profile.max_graceful_termination_sec
    max_node_provisioning_time       = var.auto_scaler_profile.max_node_provisioning_time
    max_unready_nodes                = var.auto_scaler_profile.max_unready_nodes
    max_unready_percentage           = var.auto_scaler_profile.max_unready_percentage
    new_pod_scale_up_delay           = var.auto_scaler_profile.new_pod_scale_up_delay
    scale_down_delay_after_add       = var.auto_scaler_profile.scale_down_delay_after_add
    scale_down_delay_after_delete    = var.auto_scaler_profile.scale_down_delay_after_delete
    scale_down_delay_after_failure   = var.auto_scaler_profile.scale_down_delay_after_failure
    scan_interval                    = var.auto_scaler_profile.scan_interval
    scale_down_unneeded              = var.auto_scaler_profile.scale_down_unneeded
    scale_down_unready               = var.auto_scaler_profile.scale_down_unready
    scale_down_utilization_threshold = var.auto_scaler_profile.scale_down_utilization_threshold
    skip_nodes_with_local_storage    = var.auto_scaler_profile.skip_nodes_with_local_storage
    skip_nodes_with_system_pods      = var.auto_scaler_profile.skip_nodes_with_system_pods
  }

  default_node_pool {
    name                 = var.default_node_pool.name
    vm_size              = var.default_node_pool.vm_size
    auto_scaling_enabled = var.default_node_pool.auto_scaling_enabled
    scale_down_mode      = var.default_node_pool.scale_down_mode
    min_count            = var.default_node_pool.min_count
    max_count            = var.default_node_pool.max_count

    upgrade_settings {
      max_surge = var.default_node_pool.max_surge
    }
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.renku-environment.id]
  }

  maintenance_window_node_os {
    day_of_week = var.maintenance_window_node_os.day_of_week
    duration    = var.maintenance_window_node_os.duration
    frequency   = var.maintenance_window_node_os.frequency
    interval    = var.maintenance_window_node_os.interval
    start_time  = var.maintenance_window_node_os.start_time
    utc_offset  = var.maintenance_window_node_os.utc_offset
  }

  network_profile {
    network_plugin    = "kubenet"
    load_balancer_sku = "standard"
  }

  storage_profile {
    blob_driver_enabled = true
  }

  web_app_routing {
    dns_zone_ids = [data.azurerm_dns_zone.azure.id]
  }
}

data "azurerm_dns_zone" "azure" {
  name                = var.dns_zone_name
  resource_group_name = var.dns_resource_group_name
}

data "azurerm_resource_group" "dns" {
  name = var.dns_resource_group_name
}

# This correspond to what is documented here:
# https://learn.microsoft.com/en-us/azure/aks/app-routing-dns-ssl#attach-azure-dns-zone-to-the-application-routing-add-on
resource "azurerm_role_assignment" "web_app_dns_access" {
  scope                = data.azurerm_resource_group.dns.id
  role_definition_name = "DNS Zone Contributor"
  principal_id         = azurerm_kubernetes_cluster.renku-environment.web_app_routing[0].web_app_routing_identity[0].object_id
}

resource "azurerm_role_assignment" "aks_admin" {
  for_each = toset(var.aks_admins)

  scope                = azurerm_kubernetes_cluster.renku-environment.id
  role_definition_name = "Azure Kubernetes Service RBAC Cluster Admin"
  principal_id         = each.value
}

resource "azurerm_role_assignment" "aks_reader" {
  for_each = toset(var.aks_readers)

  scope                = azurerm_kubernetes_cluster.renku-environment.id
  role_definition_name = "Azure Kubernetes Service RBAC Reader"
  principal_id         = each.value
}

resource "local_file" "kubeconfig" {
  content  = azurerm_kubernetes_cluster.renku-environment.kube_config_raw
  filename = "kubeconfig"

  # cleanup cluster before destruction
  # solves problem where "user-session" node pool does not get destructed
  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      export KUBECONFIG=./kubeconfig
      for i in `kubectl get ns -o custom-columns=NAME:.metadata.name | grep -v kube-system`; do
      kubectl delete jobs,statefulsets,daemonsets,replicasets,services,deployments,pods,rc,ingress --all -n $i --grace-period=0
      done
    EOT
  }
}

