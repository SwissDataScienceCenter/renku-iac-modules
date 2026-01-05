variable "aks_admins" {
  type        = list(string)
  description = "List of Azure Active Directory user object IDs that should be granted admin access to the AKS cluster."
}

variable "aks_readers" {
  type        = list(string)
  description = "List of Azure Active Directory user object IDs that should be granted read access to the AKS cluster."
}

variable "auto_scaler_profile" {
  type = object({
    balance_similar_node_groups      = optional(bool, false)
    expander                         = optional(string, "least-waste")
    max_graceful_termination_sec     = optional(number, 600)
    max_node_provisioning_time       = optional(string, "15m")
    max_unready_nodes                = optional(number, 3)
    max_unready_percentage           = optional(number, 45)
    new_pod_scale_up_delay           = optional(string, "0s")
    scale_down_delay_after_add       = optional(string, "10m")
    scale_down_delay_after_delete    = optional(string, "10s")
    scale_down_delay_after_failure   = optional(string, "3m")
    scan_interval                    = optional(string, "10s")
    scale_down_unneeded              = optional(string, "2m")
    scale_down_unready               = optional(string, "5m")
    scale_down_utilization_threshold = optional(number, 0.5)
    skip_nodes_with_local_storage    = optional(bool, false)
    skip_nodes_with_system_pods      = optional(bool, true)
  })
  description = "Configuration for the cluster autoscaler."
  default = {
    balance_similar_node_groups      = false
    expander                         = "least-waste"
    max_graceful_termination_sec     = 600
    max_node_provisioning_time       = "15m"
    max_unready_nodes                = 3
    max_unready_percentage           = 45
    new_pod_scale_up_delay           = "0s"
    scale_down_delay_after_add       = "10m"
    scale_down_delay_after_delete    = "10s"
    scale_down_delay_after_failure   = "3m"
    scan_interval                    = "10s"
    scale_down_unneeded              = "2m"
    scale_down_unready               = "5m"
    scale_down_utilization_threshold = 0.5
    skip_nodes_with_local_storage    = false
    skip_nodes_with_system_pods      = true
  }
}

variable "default_node_pool" {
  type = object({
    name                 = optional(string, "default")
    vm_size              = optional(string, "Standard_D4as_v5")
    auto_scaling_enabled = optional(bool, true)
    min_count            = optional(number, 3)
    max_count            = optional(number, 10)
    scale_down_mode      = optional(string, "Delete")
    max_surge            = optional(string, "10%")
  })
  description = "Configuration for the default node pool."
  default = {
    name                 = "default"
    vm_size              = "Standard_D4as_v5"
    auto_scaling_enabled = true
    min_count            = 3
    max_count            = 10
    scale_down_mode      = "Delete"
    max_surge            = "10%"
  }
}

variable "dns_resource_group_name" {
  type        = string
  description = "Name of the resource group where the DNS zone is located."
}

variable "dns_zone_name" {
  type        = string
  description = "Name of the DNS zone to use for the web app routing add-on."
}

variable "environment_name" {
  type        = string
  description = "Name of the environment, e.g. 'development', 'staging', 'production'."
}

variable "cluster_name" {
  type        = string
  description = "Name of the AKS cluster. If not provided, defaults to environment_name."
  default     = null
}

variable "dns_prefix" {
  type        = string
  description = "DNS prefix for the AKS cluster. If not provided, defaults to environment_name-location."
  default     = null
}

variable "kubernetes_version" {
  type        = string
  description = "Kubernetes version to use for the AKS cluster. If not specified, the latest version will be used."
  default     = null
}

variable "location" {
  type        = string
  description = "Azure region where resources should be deployed to."
  default     = "switzerlandnorth"
}

variable "maintenance_window_node_os" {
  type = object({
    day_of_week = optional(string, "Sunday") # Day of the week for the maintenance window, valid values are: Monday, Tuesday, Wednesday, Thursday, Friday, Saturday and Sunday.
    duration    = number                     # Duration in hours for the maintenance window.
    frequency   = string                     # Unit of time the <interval> is measured in, valid values are: Daily, Weekly, AbsoluteMonthly and RelativeMonthly.
    interval    = number                     # Maintenance happens every <interval> <frequency> (e.g. every 3 weeks/ 2 days / 1 month)
    start_time  = string                     # HH:mm
    utc_offset  = optional(string, "+02:00") # UTC offset for the start time, defaults to +02:00
  })
  description = "Maintenance window configuration for node OS updates."
  default = {
    day_of_week = "Sunday"
    duration    = 4
    frequency   = "Weekly"
    interval    = 1 # every `n` days/weeks/months
    start_time  = "03:00"
    utc_offset  = "+02:00" # UTC offset for the start time
  }
}

variable "node_pools" {
  type = list(object({
    name          = string
    sizes         = list(string)
    user_sessions = bool # Whether this node pool is intended for user sessions.

    auto_scaling_enabled = optional(bool, true)
    min_count            = optional(number, 0)
    max_count            = optional(number, 6)
    scale_down_mode      = optional(string, "Delete")
    additional_taints    = optional(list(string), [])
    additional_labels    = optional(map(string), {})
    max_surge            = optional(string, "10%")   # Optional max surge for the node pool upgrade.
    gpu_instance         = optional(string, null)    # Optional GPU MIG profiles, valid values are: MIG1g, MIG2g, MIG3g, MIG4g and MIG7g
    expiration           = optional(string, "")      # Optional expiration time for the node pool in the format "YYYY-MM-DD"
    renku_resource_id    = optional(string, "")      # Optional Renku resource ID to associate with the node pool.
    additional_tags      = optional(map(string), {}) # Optional additional tags to associate with the node pool.
    ignore_all_changes   = optional(bool, false)     # Optional flag to ignore all external changes to this node pool.
  }))
  description = "List of additional node pools to create for user sessions."
  default     = []
  validation {
    condition     = alltrue([for pool in var.node_pools : pool.user_sessions ? (timecmp("${pool.expiration}T00:00:00Z", timestamp()) > 0) : true])
    error_message = "The expiration date must be in the future and in the format 'YYYY-MM-DD'."
  }
  validation {
    condition     = alltrue([for pool in var.node_pools : pool.user_sessions ? (pool.expiration != "" && pool.renku_resource_id != "") : true])
    error_message = "For user session node pools, 'expiration' and 'renku_resource_id' must be provided."
  }
}

variable "permanent_disks" {
  type = list(object({
    name = string
    size = number # Size in GB
  }))
  description = "List of permanent disks to create for the AKS cluster. These disks will not be deleted when the cluster is destroyed."
  default     = []
}

variable "user_assigned_identity_name" {
  type        = string
  description = "Name of the user assigned identity. If not provided, defaults to environment_name."
  default     = null
}

variable "api_server_authorized_ip_ranges" {
  type        = list(string)
  description = "(Optional) List of authorized IP ranges to allow access to API server, e.g. [\"198.51.100.0/24\"]."
  default     = []
}

variable "sku_tier" {
  type        = string
  description = "The SKU Tier that should be used for this Kubernetes Cluster."
  default     = "Free"
}

variable "service_resources" {
  type = list(object({
    name               = string
    namespace          = string
    buckets            = optional(list(string), [])
    create_storage     = optional(bool, false)
    k8s_secret_name    = optional(string, "azure-storage-access-key")
    k8s_secret_env_key = string
  }))
  description = "List of services requiring azure resources"
  default     = []
}
