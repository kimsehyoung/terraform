data "aws_partition" "current" {}
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

locals {
    aws_partition  = data.aws_partition.current.partition
    aws_region     = data.aws_region.current.name
    aws_account_id = data.aws_caller_identity.current.account_id
}

################################################################################
# EKS Cluster
################################################################################
resource "aws_iam_role" "eks_cluster" {
    name = "EKS_ClusterRole-${var.cluster_name}"
    assume_role_policy = templatefile("${path.module}/templates/assume_role.tftpl", {
        aws_service = "eks"
    })
}

resource "aws_iam_role_policy_attachment" "eks_cluster" {
    for_each = toset([
        "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy",
        "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController",
    ])
    policy_arn = each.key
    role       = aws_iam_role.eks_cluster.name
}

resource "aws_eks_cluster" "this" {
    name     = var.cluster_name
    version  = var.cluster_version
    role_arn = aws_iam_role.eks_cluster.arn

    vpc_config {
        endpoint_private_access = var.endpoint_private_access
        endpoint_public_access  = var.endpoint_public_access
        public_access_cidrs     = var.endpoint_public_access_cidrs
        subnet_ids              = var.intra_subnet_ids
    }

    depends_on = [aws_iam_role_policy_attachment.eks_cluster]
}

data "tls_certificate" "eks_cluster" {
    url = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks_cluster" {
    client_id_list  = ["sts.amazonaws.com"]
    thumbprint_list = [data.tls_certificate.eks_cluster.certificates[0].sha1_fingerprint]
    url             = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

################################################################################
# EKS Node Group
################################################################################
resource "aws_iam_role" "eks_node_group" {
    name = "KarpenterNodeGroupRole-${var.cluster_name}"
    assume_role_policy = templatefile("${path.module}/templates/assume_role.tftpl", {
        aws_service = "ec2"
    })
}

resource "aws_iam_role_policy_attachment" "eks_node_group" {
    for_each = toset([
        "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
        "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
        "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
        "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
    ])
    policy_arn = each.key
    role       = aws_iam_role.eks_node_group.name
}

resource "aws_eks_node_group" "this" {
    cluster_name    = aws_eks_cluster.this.name
    node_group_name = "${var.cluster_name}-ng"
    node_role_arn   = aws_iam_role.eks_node_group.arn
    subnet_ids      = var.private_subnet_ids

    instance_types  = var.node_group_instance_types
    ami_type        = var.node_group_ami_type
    disk_size       = var.node_group_disk_size

    scaling_config {
        desired_size = var.node_group_desired_size
        min_size     = var.node_group_min_size
        max_size     = var.node_group_max_size
    }

    labels = var.node_group_labels
    depends_on = [aws_iam_role_policy_attachment.eks_node_group]
}

################################################################################
# Karpenter
# https://gallery.ecr.aws/karpenter/karpenter
################################################################################
resource "aws_iam_role" "node_by_karpenter" {
    name = "KarpenterNodeRole-${var.cluster_name}"
    assume_role_policy = templatefile("${path.module}/templates/assume_role.tftpl", {
        aws_service = "ec2"
    })
}
resource "aws_iam_role_policy_attachment" "node_by_karpenter" {
    for_each = toset([
        "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
        "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
        "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
        "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
    ])
    policy_arn = each.key
    role       = aws_iam_role.node_by_karpenter.name
}

resource "aws_sqs_queue" "karpenter_interruption" {
    name                      = "KarpenterInterruption-${var.cluster_name}"
    message_retention_seconds = 300
    sqs_managed_sse_enabled   = true
}


data "aws_iam_policy_document" "karpenter_interruption" {
    statement {
        sid       = "EC2InterruptionPolicy"
        effect    = "Allow"
        actions   = ["sqs:SendMessage"]
        resources = [aws_sqs_queue.karpenter_interruption.arn]
        principals {
            type = "Service"
            identifiers = [
                "events.amazonaws.com",
                "sqs.amazonaws.com",
            ]
        }
    }
}

resource "aws_sqs_queue_policy" "karpenter_interruption" {
    queue_url = aws_sqs_queue.karpenter_interruption.url
    policy    = data.aws_iam_policy_document.karpenter_interruption.json
}

resource "aws_iam_policy" "karpenter_controller" {
    name = "KarpenterControllerPolicy-${var.cluster_name}"
    policy = templatefile("${path.module}/templates/karpenter_controller_policy.tftpl", {
        aws_partition  = local.aws_partition
        aws_region     = local.aws_region
        aws_account_id = local.aws_account_id
        cluster_name   = var.cluster_name
        karpenter_node_role_arn = aws_iam_role.node_by_karpenter.arn
        karpenter_interruption_queue_arn = aws_sqs_queue.karpenter_interruption.arn
    })
}

resource "aws_iam_role" "karpenter_controller" {
    name = "KarpenterControllerRole-${var.cluster_name}"
    assume_role_policy = templatefile("${path.module}/templates/assume_role_oidc.tftpl", {
        oidc_provider     = replace(aws_iam_openid_connect_provider.eks_cluster.url, "https://", "")
        oidc_provider_arn = aws_iam_openid_connect_provider.eks_cluster.arn
        sa_namespace      = var.karpenter_namespace
        sa_name           = "${var.karpenter_name}-sa"
    })
    managed_policy_arns = [aws_iam_policy.karpenter_controller.arn]
}

resource "helm_release" "karpenter_controller" {
    create_namespace = true
    namespace        = var.karpenter_namespace
    name             = var.karpenter_name

    repository = "oci://public.ecr.aws/karpenter"
    chart      = "karpenter"
    version    = var.karpenter_version

    values = [
        templatefile("${path.module}/templates/karpenter_values.tftpl", {
            sa_create           = true
            sa_namespace        = var.karpenter_namespace
            sa_name             = "${var.karpenter_name}-sa"
            sa_role_arn         = aws_iam_role.karpenter_controller.arn
            replicas            = var.karpenter_replicas
            node_group_name     = aws_eks_node_group.this.node_group_name
            karpenter_resources = var.karpenter_resources
            karpenter_batch     = var.karpenter_batch
            cluster_name        = var.cluster_name
            cluster_endpoint    = aws_eks_cluster.this.endpoint
            karpenter_interruption_queue_arn = aws_sqs_queue.karpenter_interruption.arn
        })
    ]
    depends_on = [aws_eks_node_group.this]
}

################################################################################
# AWS Load Balancer Controller
# https://github.com/kubernetes-sigs/aws-load-balancer-controller/blob/main/docs/install/iam_policy.json
# https://artifacthub.io/packages/helm/aws/aws-load-balancer-controller
################################################################################
resource "aws_iam_policy" "aws_load_balancer_controller" {
    name = "AWS_LoadBalancerControllerPolicy-${var.cluster_name}"
    policy = templatefile("${path.module}/templates/aws_load_balancer_controller_policy.tftpl", {})
}

resource "aws_iam_role" "aws_load_balancer_controller" {
    name = "AWS_LoadBalancerControllerRole-${var.cluster_name}"
    assume_role_policy = templatefile("${path.module}/templates/assume_role_oidc.tftpl", {
        oidc_provider     = replace(aws_iam_openid_connect_provider.eks_cluster.url, "https://", "")
        oidc_provider_arn = aws_iam_openid_connect_provider.eks_cluster.arn
        sa_namespace      = var.aws_load_balancer_controller_namespace
        sa_name           = "${var.aws_load_balancer_controller_name}-sa"
    })
    managed_policy_arns = [aws_iam_policy.aws_load_balancer_controller.arn]
}

resource "helm_release" "aws_load_balancer_controller" {
    namespace        = var.aws_load_balancer_controller_namespace
    create_namespace = true
    name             = var.aws_load_balancer_controller_name

    repository = "https://aws.github.io/eks-charts"
    chart      = "aws-load-balancer-controller"
    version    = var.aws_load_balancer_controller_version

    values = [
        templatefile("${path.module}/templates/aws_load_balancer_controller_values.tftpl", {
            image_repository = "602401143452.dkr.ecr.ap-northeast-2.amazonaws.com/amazon/aws-load-balancer-controller"
            replicas         = var.aws_load_balancer_controller_replicas
            sa_create        = true
            sa_namespace     = var.aws_load_balancer_controller_namespace
            sa_name          = "${var.aws_load_balancer_controller_name}-sa"
            sa_role_arn      = aws_iam_role.aws_load_balancer_controller.arn
            cluster_name     = var.cluster_name
        })
    ]
    depends_on = [helm_release.karpenter_controller]
}