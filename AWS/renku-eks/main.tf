
data "aws_caller_identity" "current" {}
data "aws_availability_zones" "available" {}

locals {
  name            = var.subdomain
  cluster_version = var.kubernetes_version
  region          = var.region

  access_entries = { for access in var.access_entries : access.name =>
    {
      principal_arn = access.arn
      policy_associations = {
        cluster_admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/${access.policy}"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  }

  vpc_cidr = "10.0.0.0/16"
  # Fetch the availability zones for the region and use them all
  azs = slice(data.aws_availability_zones.available.names, 0, 3)

  tags = {
    "Environment"            = "development"
    "karpenter.sh/discovery" = local.name
    "ManagedBy"              = "Terraform"
    "ManagedFor"             = data.aws_caller_identity.current.account_id
    "Name"                   = local.name
  }
}

################################################################################
# EKS Module
################################################################################

data "aws_iam_session_context" "current" {
  arn = data.aws_caller_identity.current.arn
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.4"

  authentication_mode            = "API_AND_CONFIG_MAP" //API access is required to give Karpenter the ability to join the nodes it spawns to the cluster
  cluster_name                   = local.name
  cluster_version                = local.cluster_version
  cluster_endpoint_public_access = true

  # IPV6
  cluster_ip_family = "ipv4"

  cluster_addons = {
    aws-ebs-csi-driver = {
      most_recent = true
    }
    coredns = {
      most_recent = true
      # The following tolerations allow core-dns pods to be scheduled on the 'essential' nodes
      configuration_values = "{\"tolerations\": [{\"key\": \"dedicated\",\"operator\": \"Equal\",\"value\": \"essential\",\"effect\": \"NoSchedule\"}]}"
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }
  }

  enable_cluster_creator_admin_permissions = false

  access_entries = local.access_entries

  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.private_subnets
  control_plane_subnet_ids = module.vpc.intra_subnets

  eks_managed_node_group_defaults = {
    ami_type       = "BOTTLEROCKET_x86_64"
    instance_types = ["m7i-flex.large"] # 2 vCPU, 8 GB RAM

    # We are using the IRSA created below for permissions
    # However, we have to deploy with the policy attached FIRST (when creating a fresh cluster)
    # and then turn this off after the cluster/node group is created. Without this initial policy,
    # the VPC CNI fails to assign IPs and nodes cannot join the cluster
    # See https://github.com/aws/containers-roadmap/issues/1666 for more context
    iam_role_attach_cni_policy = true
  }

  eks_managed_node_groups = {
    # Essential node group: this nodes hosts the essential services, including karpenter that will take care of adding more nodes as needed by all the other services.
    essential = {
      name          = "essential"
      ami_type      = "BOTTLEROCKET_ARM_64"
      desired_size  = var.essential_nodes
      min_size      = var.essential_nodes
      max_size      = var.essential_nodes
      capacity_type = "SPOT"

      instance_types = ["t4g.small", "t4g.medium", "t4g.large"]

      labels = {
        "dedicated" = "essential"
      }

      taints = [
        {
          key    = "dedicated"
          value  = "essential"
          effect = "NO_SCHEDULE"
        }
      ]
    }
  }

  tags = local.tags
}

################################################################################
# Supporting Resources
################################################################################

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 4.0"

  name = local.name
  cidr = local.vpc_cidr

  azs             = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 4, k)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 48)]
  intra_subnets   = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 52)]

  enable_nat_gateway     = true
  single_nat_gateway     = true
  enable_ipv6            = false
  create_egress_only_igw = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }

  tags = local.tags
}

# IRSA: IAM role for service accounts is a system that simplifies the management of IAM roles for
# Kubernetes service accounts. With IRSA, you can associate an IAM role with a Kubernetes service,
# then use that service account to perform actions on AWS resources.

module "vpc_cni_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name_prefix      = "VPC-CNI-IRSA"
  attach_vpc_cni_policy = true
  vpc_cni_enable_ipv6   = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-node"]
    }
  }

  tags = local.tags
}

# Here we use IRSA to create a service account which will be used by the AWS Load Balancer Controller, deployed
# through Helm/Gitops, to manage the AWS Load Balancers for the cluster.

module "load_balancer_controller_irsa_role" {
  source = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"

  role_name                              = "load-balancer-controller-${local.name}"
  attach_load_balancer_controller_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }

  tags = local.tags
}

resource "kubernetes_service_account" "aws-load-balancer-controller" {
  metadata {
    annotations = {
      "eks.amazonaws.com/role-arn" = module.load_balancer_controller_irsa_role.iam_role_arn
    }
    labels = {
      "app.kubernetes.io/component" = "controller"
      "app.kubernetes.io/name"      = "aws-load-balancer-controller"
    }
    name      = "aws-load-balancer-controller"
    namespace = "kube-system"
  }
}

# Create IAM role and K8S SA for the external-dns deployment

module "external_dns_irsa_role" {
  source = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"

  role_name                  = "external-dns-${local.name}"
  attach_external_dns_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-external-dns"]
    }
  }

  tags = local.tags
}

resource "kubernetes_service_account" "aws-external-dns" {
  metadata {
    annotations = {
      "eks.amazonaws.com/role-arn" = module.external_dns_irsa_role.iam_role_arn
    }
    labels = {
      "app.kubernetes.io/component" = "controller"
      "app.kubernetes.io/name"      = "aws-external-dns"
    }
    name      = "aws-external-dns"
    namespace = "kube-system"
  }
}

resource "aws_acm_certificate" "subdomain" {
  domain_name               = "*.${var.subdomain}.${var.dns_zone}"
  subject_alternative_names = ["${var.subdomain}.${var.dns_zone}"]
  validation_method         = "DNS"
}

data "aws_route53_zone" "zone" {
  name         = var.dns_zone
  private_zone = false
}

resource "aws_route53_record" "certificate_validation" {
  for_each = {
    for dvo in aws_acm_certificate.subdomain.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 15
  type            = each.value.type
  zone_id         = data.aws_route53_zone.zone.zone_id
}

resource "aws_acm_certificate_validation" "subdomain" {
  certificate_arn         = aws_acm_certificate.subdomain.arn
  validation_record_fqdns = [for record in aws_route53_record.certificate_validation : record.fqdn]
}

# Karpenter

module "karpenter" {
  source = "terraform-aws-modules/eks/aws//modules/karpenter"

  cluster_name                      = module.eks.cluster_name
  enable_irsa                       = true
  enable_spot_termination           = true
  node_iam_role_name                = "karpenter-${local.name}"
  node_iam_role_use_name_prefix     = false
  node_iam_role_additional_policies = { "AmazonEBSCSIDriverPolicy" = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy" }

  irsa_oidc_provider_arn          = module.eks.oidc_provider_arn
  irsa_namespace_service_accounts = ["kube-system:aws-karpenter"]

  create_access_entry = true

  tags = local.tags
}

resource "kubernetes_service_account" "aws-karpenter" {
  metadata {
    annotations = {
      "eks.amazonaws.com/role-arn" = module.karpenter.iam_role_arn
    }
    labels = {
      "app.kubernetes.io/component" = "controller"
      "app.kubernetes.io/name"      = "aws-karpenter"
    }
    name      = "aws-karpenter"
    namespace = "kube-system"
  }
}

resource "null_resource" "cleanup_on_destroy" {
  triggers = {
    region          = var.region
    cluster_name    = module.eks.cluster_name
    essential_nodes = var.essential_nodes
  }
  provisioner "local-exec" {
    when    = destroy
    command = <<EOT
set -ex
TMP_KUBE=$(mktemp)
aws eks update-kubeconfig --region ${self.triggers.region} --name ${self.triggers.cluster_name} --dry-run > $TMP_KUBE
KUBECONFIG=$TMP_KUBE kubectl delete poddisruptionbudget --all --all-namespaces=true
KUBECONFIG=$TMP_KUBE kubectl delete ingress --all --all-namespaces=true
KUBECONFIG=$TMP_KUBE kubectl delete NodePool --all --all-namespaces=true
while KUBECONFIG=$TMP_KUBE NODES=$(kubectl get nodes --no-headers | wc -l) && (( $NODES > ${self.triggers.essential_nodes} )); do echo "Awaiting deletion of non essential nodes." && sleep 2; done
rm -rf $TMP_KUBE
EOT
  }
  depends_on = [aws_acm_certificate_validation.subdomain]
}

output "cluster_green_light" {
  value = null_resource.cleanup_on_destroy.id
}

output "cluster" {
  value = {
    cluster_endpoint                   = module.eks.cluster_endpoint
    cluster_name                       = module.eks.cluster_name
    cluster_certificate_authority_data = module.eks.cluster_certificate_authority_data
  }
}
