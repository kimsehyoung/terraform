locals {
    aws_profile = "profile"
    aws_region  = "ap-northeast-2"
    name        = "Hello"
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
    
    node_group_instance_types = ["t4g.medium"]
    node_group_ami_type       = "AL2_ARM_64"

    karpenter_version = "v0.32.1"
    aws_load_balancer_controller_version = "1.6.2"

    additional_tags   = local.additional_tags
}

################################################################################
# Test
resource "kubectl_manifest" "karpenter_nodeclass" {
    yaml_body = templatefile("./templates/karpenter_nodeclass.tftpl", {
        name = "${local.name}-node"
        ami_family = "AL2"
        role = module.eks.node_role_name
        selector_tag = module.eks.cluster_name
    })
}

resource "kubectl_manifest" "karpenter_nodepool" {
    yaml_body = templatefile("./templates/karpenter_nodepool.tftpl", {
        name = "${local.name}-general"
        nodeclass_name = kubectl_manifest.karpenter_nodeclass.name
        limit_cpu = "30"
        limit_memory = "64Gi"
    })
}

resource "kubectl_manifest" "deployment_test" {
    yaml_body = templatefile("./templates/deployment_test.tftpl", {
        replicas = 0
        label_key = "type"
        label_value = kubectl_manifest.karpenter_nodepool.name
    })
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
}

module "efs" {
    source = "./modules/efs"

    name = local.name
    cluster_name = module.eks.cluster_name

    vpc_id             = module.vpc.vpc_id
    vpc_cidr           = local.vpc_cidr
    private_subnet_ids = module.vpc.private_subnets.ids

    node_group_name          = module.eks.node_group_name
    oidc_provider            = module.eks.oidc_provider
    oidc_provider_arn        = module.eks.oidc_provider_arn
}