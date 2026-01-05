output "kubeconfig" {
  value = azurerm_kubernetes_cluster.renku-environment.kube_config[0]
}

output "kube_config_raw" {
  value = azurerm_kubernetes_cluster.renku-environment.kube_config_raw
}

output "cluster_id" {
  value = azurerm_kubernetes_cluster.renku-environment.id
}

output "resource_group_name" {
  value = azurerm_resource_group.renku-environment.name
}

output "oidc_issuer_url" {
  value = azurerm_kubernetes_cluster.renku-environment.oidc_issuer_url
}

output "user_assigned_identity_id" {
  value = azurerm_user_assigned_identity.renku-environment.id
}

output "user_assigned_identity_principal_id" {
  value = azurerm_user_assigned_identity.renku-environment.principal_id
}
