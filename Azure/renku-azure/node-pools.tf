locals {
  size = {
    "2"     = "Standard_D2_v5"
    "4"     = "Standard_D4_v5"
    "8"     = "Standard_D8_v5"
    "16"    = "Standard_D16_v5"
    "32"    = "Standard_D32_v5"
    "48"    = "Standard_D48_v5"
    "64"    = "Standard_D64_v5"
    "96"    = "Standard_D96_v5"
    "GPU10" = "Standard_NC24ads_A100_v4"
    "GPU20" = "Standard_NC24ads_A100_v4"
    "NV6"   = "Standard_NV6ads_A10_v5"
    "NV12"  = "Standard_NV12ads_A10_v5"
    "ARM4"  = "Standard_D4ps_v6"
    "ARM8"  = "Standard_D8ps_v6"
  }
  gpu_type_nvidia = ["GPU10", "GPU20", "NV6", "NV12"]
  gpu_instance = {
    "GPU10" = "MIG1g"
    "GPU20" = "MIG2g"
  }
  pools = flatten([
    for pool in var.node_pools : [
      for s in pool.sizes : {
        name    = "${pool.name}${lower(s)}",
        vm_size = local.size[s]
        taints = concat(
          pool.additional_taints,
          pool.user_sessions ? ["renku.io/dedicated=user:NoSchedule"] : [],
        )
        labels = merge(
          pool.additional_labels,
          {
            "renku.io/node-purpose" = pool.user_sessions ? "user" : "renku-services",
            "renku.io/expiration"   = pool.expiration,
            "gputype"               = contains(local.gpu_type_nvidia, s) ? "nvidia" : null,
            "gpuA100-parted"        = contains(["GPU10", "GPU20"], s) ? "true" : null
        })
        max_surge            = pool.max_surge
        auto_scaling_enabled = pool.auto_scaling_enabled
        min_count            = pool.min_count
        max_count            = pool.max_count
        scale_down_mode      = pool.scale_down_mode
        renku_resource_id    = pool.renku_resource_id
        gpu_instance         = lookup(local.gpu_instance, s, null)
        ignore_all_changes   = pool.ignore_all_changes
        tags = merge(
          {
            Expiration       = pool.expiration
            ResourcePoolId   = pool.renku_resource_id
            ResourcePoolName = pool.name
          },
          pool.additional_tags
        )
      }
    ]
  ])

  pools_without_ignore = {
    for pool in local.pools : pool.name => pool
    if !pool.ignore_all_changes
  }

  pools_with_ignore = {
    for pool in local.pools : pool.name => pool
    if pool.ignore_all_changes
  }
}

resource "azurerm_kubernetes_cluster_node_pool" "node_pool" {
  for_each = local.pools_without_ignore

  name = each.value.name

  kubernetes_cluster_id = azurerm_kubernetes_cluster.renku-environment.id
  node_taints           = each.value.taints
  node_labels           = each.value.labels
  vm_size               = each.value.vm_size
  auto_scaling_enabled  = each.value.auto_scaling_enabled
  min_count             = each.value.auto_scaling_enabled ? each.value.min_count : null
  max_count             = each.value.auto_scaling_enabled ? each.value.max_count : null
  node_count            = each.value.auto_scaling_enabled ? null : each.value.max_count
  scale_down_mode       = each.value.scale_down_mode
  gpu_instance          = each.value.gpu_instance
  upgrade_settings {
    max_surge = each.value.max_surge
  }

  tags = each.value.tags
}

resource "azurerm_kubernetes_cluster_node_pool" "node_pool_ignore_all" {
  for_each = local.pools_with_ignore

  name = each.value.name

  kubernetes_cluster_id = azurerm_kubernetes_cluster.renku-environment.id
  node_taints           = each.value.taints
  node_labels           = each.value.labels
  vm_size               = each.value.vm_size
  auto_scaling_enabled  = each.value.auto_scaling_enabled
  min_count             = each.value.auto_scaling_enabled ? each.value.min_count : null
  max_count             = each.value.auto_scaling_enabled ? each.value.max_count : null
  node_count            = each.value.auto_scaling_enabled ? null : each.value.max_count
  scale_down_mode       = each.value.scale_down_mode
  gpu_instance          = each.value.gpu_instance
  upgrade_settings {
    max_surge = each.value.max_surge
  }

  tags = each.value.tags

  lifecycle {
    ignore_changes = all
  }
}
