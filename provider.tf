terraform {
    required_version = "~> 1.6"

    required_providers {
        aws = {
            source  = "hashicorp/aws"
            version = "~> 5.22"
        }
kubernetes = {
            source  = "hashicorp/kubernetes"
            version = "~> 2.23"
        }
        helm = {
            source  = "hashicorp/helm"
            version = "~> 2.11"
        }
        # Test
        kubectl = {
          source  = "gavinbunney/kubectl"
          version = "~> 1.14"
        }
    }
}

provider "aws" {
    shared_config_files      = ["~/.aws/config"]
    shared_credentials_files = ["~/.aws/credentials"]
    profile                  = local.aws_profile
    region                   = local.aws_region
}

data "aws_eks_cluster" "this" {
    name = module.eks.cluster_name
}

data "aws_eks_cluster_auth" "this" {
    name = module.eks.cluster_name
}

provider "kubernetes" {
    host                   = data.aws_eks_cluster.this.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.this.token
}

provider "helm" {
    kubernetes {
        host                   = data.aws_eks_cluster.this.endpoint
        cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
        token                  = data.aws_eks_cluster_auth.this.token
    }
}

# Test
provider "kubectl" {
    apply_retry_count      = 3
    host                   = data.aws_eks_cluster.this.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.this.token
    load_config_file       = false
}
