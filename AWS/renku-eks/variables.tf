variable "access_entries" {
  type        = list(map(string))
  description = "values for the access_entries map"
}

variable "dns_zone" {
  type        = string
  description = "The base DNS domain."
}

variable "essential_nodes" {
  type        = number
  default     = 3
  description = "Number of essential nodes."
}

variable "kubernetes_version" {
  type        = string
  description = "Version of Kubernetes to use."
}

variable "subdomain" {
  type        = string
  description = "Arbitrary subdomain to distinguish a development environment from all others."
}

variable "region" {
  type        = string
  description = "Region where the resources are deployed."
  default     = "eu-central-1"
}
