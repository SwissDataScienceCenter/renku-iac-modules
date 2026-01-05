###
# NOTE! Disk resizing requires them to be detached
# because of: https://github.com/hashicorp/terraform-provider-azurerm/issues/26651
###

resource "azurerm_managed_disk" "permanent_disk" {
  name                 = "disk-${var.environment_name}-${each.key}"
  location             = var.location
  resource_group_name  = azurerm_resource_group.renku-environment.name
  storage_account_type = "StandardSSD_LRS"
  create_option        = "Empty"
  disk_size_gb         = each.value

  lifecycle {
    prevent_destroy = true
  }

  tags = {
    environment = var.environment_name
    component   = each.key
  }

  for_each = { for disk in var.permanent_disks : disk.name => disk.size }
}

resource "azurerm_role_assignment" "aks_disk_access" {
  scope                = each.value
  role_definition_name = "Contributor"
  principal_id         = azurerm_user_assigned_identity.renku-environment.principal_id

  for_each = { for disk in azurerm_managed_disk.permanent_disk : disk.name => disk.id }
}
