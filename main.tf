locals {
    aws_profile = "profile"
    aws_region  = "ap-northeast-2"
    name        = "dongle"
    vpc_cidr    = "10.0.0.0/16"
    
    additional_tags = {
        environment = "Test"
        owner       = "SeHyoung"
        team        = "DevOps"
        project     = "Dongle"
        automation  = "Terraform"
    }
}

module "vpc" {
    source = "./modules/vpc"

    name               = local.name
    vpc_cidr           = local.vpc_cidr
    azs_count          = 3
    enalbe_dns         = true
    single_nat_gateway = true

    additional_tags    = local.additional_tags
}

module "eks" {
    source = "./modules/eks"

    cluster_name       = local.name
    cluster_version    = "1.28"

    vpc_id             = module.vpc.vpc_id
    intra_subnet_ids   = module.vpc.intra_subnets.ids
    private_subnet_ids = module.vpc.private_subnets.ids
    
    node_group_labels         = { "nodegroup-name" = "${local.name}-ng" }

    karpenter_version = "v0.32.1"
    aws_load_balancer_controller_version = "1.6.2"

    additional_tags   = local.additional_tags
    depends_on = [module.vpc]
}

################################################################################
# Test
resource "helm_release" "karpenter_node" {
    create_namespace = true
    namespace        = "karpenter"
    name             = "karpenter-node"

    repository = "https://kimsehyoung.github.io/helm-charts/karpenter-node"
    chart      = "karpenter-node"
    version    = "0.32.2"

    values = [
        templatefile("${path.module}/templates/karpenter_node_values.tftpl", {
            cluster_name = module.eks.cluster_name
            nodepool_name = "multi-arch-general"
        })
    ]
}

resource "helm_release" "whisper" {
    create_namespace = true
    namespace        = "dongle"
    name             = "whisper"

    repository = "https://kimsehyoung.github.io/whisper/helm-charts"
    chart      = "whisper"
    version    = "1.0.0"

    values = [
        templatefile("${path.module}/templates/whisper_values.tftpl", {
            nodepool_name = "multi-arch-general"
        })
    ]
}
################################################################################

module "rds" {
    source = "./modules/rds"

    identifier     = local.name
    engine         = "postgres"
    engine_version = "15.4"
    
    username = "postgres"
    password = "12345678"
    db_name  = "postgres"
    port     = "5432"

    vpc_id               = module.vpc.vpc_id
    vpc_cidr             = local.vpc_cidr
    db_subnet_group_name = module.vpc.database_subnet_group_name

    skip_final_snapshot = true
    depends_on = [module.vpc]
}

module "efs" {
    source = "./modules/efs"

    cluster_name       = module.eks.cluster_name
    vpc_id             = module.vpc.vpc_id
    vpc_cidr           = local.vpc_cidr
    private_subnet_ids = module.vpc.private_subnets.ids

    oidc_provider            = module.eks.oidc_provider
    oidc_provider_arn        = module.eks.oidc_provider_arn

    depends_on = [module.eks]
}