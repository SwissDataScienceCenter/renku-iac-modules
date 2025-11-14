terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
    }
  }
  backend "s3" {
    bucket  = "foobar"
    encrypt = true
    key     = "bar-foo"
    region  = "eu-north-1"
  }
}

# Most of the code below is taken from: https://github.com/terraform-aws-modules/terraform-aws-eks/blob/v19.21.0/examples/eks_managed_node_group/main.tf

provider "aws" {
  region = var.region
}

# These are the IAM roles generated automatically by AWS SSO for the groups defined in `environments-aws/global/main.tf`
# Whenever a human user logs in AWS SSO, they are assigned to one of these IAM roles, which in turn can be used to grant
# access to the EKS cluster.
data "aws_iam_roles" "Administrators" {
  name_regex  = "AWSReservedSSO_AdministratorAccess_.*"
  path_prefix = "/aws-reserved/sso.amazonaws.com/"
}

data "aws_iam_roles" "PowerUsers" {
  name_regex  = "AWSReservedSSO_PowerUserAccess_.*"
  path_prefix = "/aws-reserved/sso.amazonaws.com/"
}

module "renku-eks" {
  source = "../../../modules/renku-eks"

  access_entries = [
    { name   = "PowerUsers",
      arn    = tolist(data.aws_iam_roles.PowerUsers.arns)[0],
      policy = "AmazonEKSClusterAdminPolicy"
    },
    {
      name   = "Administrators",
      arn    = tolist(data.aws_iam_roles.Administrators.arns)[0],
      policy = "AmazonEKSClusterAdminPolicy"
    }
  ]
  dns_zone           = "example.com"
  kubernetes_version = "1.32"
  subdomain          = "renkulab"
  region             = "eu-central-1"
}
