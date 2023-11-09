data "aws_partition" "current" {}
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

locals {
    aws_partition  = data.aws_partition.current.partition
    aws_region     = data.aws_region.current.name
    aws_account_id = data.aws_caller_identity.current.account_id

    addons = {
        kube-proxy = {}
        vpc-cni = {}
        coredns = {
            configuration_values = templatefile("${path.module}/templates/addon_core_dns.tftpl", {
                replicas  = var.coredns_replicas
                resources = var.coredns_resources
                node_group_name = aws_eks_node_group.this.node_group_name
            })
        }
    }

    control_plane_security_group_rules = {
        ingress_nodes_443 = {
            description = "Allows the kubelets to communicate with the Kubernetes API server from worker node SG."
            type = "ingress"
            from_port = 443
            to_port = 443
            protocol = "tcp"
        }
        ingress_nodes_ephemeral_ports_tcp = {
            description                = "Nodes on ephemeral ports"
            protocol                   = "tcp"
            from_port                  = 1025
            to_port                    = 65535
            type                       = "ingress"
        }
    }
    worker_node_security_group_rules = {
        ingress_self_all = {
            description = "Node to node all ports/protocols"
            protocol    = "-1"
            from_port   = 0
            to_port     = 0
            type        = "ingress"
            self        = true
        } 
        ingress_cluster_443 = {
            description                   = "Cluster API to node groups"
            type                          = "ingress"
            from_port                     = 443
            to_port                       = 443
            protocol                      = "tcp"
        }
        ingress_cluster_kubelet = {
            description = "Cluster API to node kubelets"
            type = "ingress"
            from_port = 10250
            to_port = 10250
            protocol = "tcp"
        }
        ingress_self_coredns_tcp = {
            description = "Node to node CoreDNS"
            type        = "ingress"
            from_port   = 53
            to_port     = 53
            protocol    = "tcp"
            self        = true
        }
        ingress_self_coredns_udp = {
            description = "Node to node CoreDNS UDP"
            type        = "ingress"
            from_port   = 53
            to_port     = 53
            protocol    = "udp"
            self        = true
        }
        ingress_nodes_ephemeral = {
            description = "Node to node ingress on ephemeral ports"
            type        = "ingress"
            from_port   = 1025
            to_port     = 65535
            protocol    = "tcp"
            self        = true
        }
        # metrics-server
        ingress_cluster_4443_webhook = {
            description = "Cluster API to node 4443/tcp webhook"
            type        = "ingress"
            from_port   = 4443
            to_port     = 4443
            protocol    = "tcp"
        }
        # prometheus-adapter
        ingress_cluster_6443_webhook = {
            description                   = "Cluster API to node 6443/tcp webhook"
            protocol                      = "tcp"
            from_port                     = 6443
            to_port                       = 6443
            type                          = "ingress"
        }
        # Karpenter
        ingress_cluster_8443_webhook = {
            description = "Cluster API to node 8443/tcp webhook"
            type        = "ingress"
            from_port   = 8443
            to_port     = 8443
            protocol    = "tcp"
        }
        # ALB controller
        ingress_cluster_9443_webhook = {
            description = "Cluster API to node 9443/tcp webhook"
            type        = "ingress"
            from_port   = 9443
            to_port     = 9443
            protocol    = "tcp"
        }
        egress_all = {
            description = "Allow all egress"
            type        = "egress"
            from_port   = 0
            to_port     = 0
            protocol    = "-1"
            cidr_blocks = ["0.0.0.0/0"]
        }
    }
}

################################################################################
# EKS Cluster
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_cluster
################################################################################
resource "aws_iam_role" "eks_cluster" {
    name = "EKS_ClusterRole-${var.cluster_name}"
    assume_role_policy = templatefile("${path.module}/templates/assume_role.tftpl", {
        sid         = "EKSClusterAssumeRole"
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

# Additional security groups
resource "aws_security_group" "control_plane" {
    name = "${var.cluster_name}-controlplane-sg"
	description = "Restricting cluster traffic between the control plane and worker nodes. (The cluster SG is created automatically allows unfettered traffic.)"
	vpc_id = var.vpc_id

    lifecycle {
        create_before_destroy = true
    }

    tags = var.additional_tags
}

resource "aws_security_group_rule" "control_plane" {
    for_each = { for k, v in local.control_plane_security_group_rules : k => v }

    security_group_id = aws_security_group.control_plane.id

    description = each.value.description
    type        = each.value.type
    from_port   = each.value.from_port
    to_port     = each.value.to_port
    protocol    = each.value.protocol

    source_security_group_id = aws_security_group.worker_node.id
}

resource "aws_security_group" "worker_node" {
    name = "${var.cluster_name}-node-sg"
    description = "Shared security group of worker nodes"
    vpc_id      = var.vpc_id

    lifecycle {
        create_before_destroy = true
    }

    tags = merge(
        {"karpenter.sh/discovery" = var.cluster_name},
        var.additional_tags
    )
}

resource "aws_security_group_rule" "worker_node" {
    for_each = { for k, v in local.worker_node_security_group_rules : k => v }
    security_group_id = aws_security_group.worker_node.id

    description = each.value.description
    type        = each.value.type
    from_port   = each.value.from_port
    to_port     = each.value.to_port
    protocol    = each.value.protocol

    cidr_blocks = lookup(each.value, "cidr_blocks", null)
    self = lookup(each.value, "self", null)
    source_security_group_id = try(each.value.self, false) ? null : contains(keys(each.value), "cidr_blocks") ? null : aws_security_group.control_plane.id
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
        security_group_ids      = [aws_security_group.control_plane.id]
    }
    depends_on = [
        aws_iam_role_policy_attachment.eks_cluster,
        aws_security_group_rule.control_plane,
        aws_security_group_rule.worker_node
    ]
}

data "tls_certificate" "eks_cluster" {
    url = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks_cluster" {
    client_id_list  = ["sts.amazonaws.com"]
    thumbprint_list = [data.tls_certificate.eks_cluster.certificates[0].sha1_fingerprint]
    url             = aws_eks_cluster.this.identity[0].oidc[0].issuer

    tags = merge(
        { Name = "${var.cluster_name}-eks-irsa" },
        var.additional_tags
    )
}

################################################################################
# EKS Node Group
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_node_group
################################################################################
resource "aws_iam_role" "eks_node_group" {
    name = "KarpenterNodeGroupRole-${var.cluster_name}"
    description = "EKS managed node group IAM role"
    assume_role_policy = templatefile("${path.module}/templates/assume_role.tftpl", {
        sid         = "EKSNodeAssumeRole"
        aws_service = "ec2"
    })
}

resource "aws_iam_role_policy_attachment" "eks_node_group" {
    for_each = toset([
        "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
        "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
        "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
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
        desired_size = var.scaling_config.desired_size
        min_size     = var.scaling_config.min_size
        max_size     = var.scaling_config.max_size
    }
    dynamic "taint" {
        for_each = var.node_group_taints
        content {
          key    = taint.value.key
          value  = try(taint.value.value, null)
          effect = taint.value.effect
        }
}
    labels = var.node_group_labels

    depends_on = [aws_iam_role_policy_attachment.eks_node_group]
}

################################################################################
# Add-ons
# https://docs.aws.amazon.com/cli/latest/reference/eks/describe-addon-configuration.html
################################################################################
resource "aws_eks_addon" "essentials" {
    for_each = local.addons

    cluster_name         = aws_eks_cluster.this.name
    addon_name           = each.key
    configuration_values = try(each.value.configuration_values, null)

    resolve_conflicts_on_create = "OVERWRITE"
    depends_on = [aws_eks_node_group.this]
}

################################################################################
# aws-auth
# https://karpenter.sh/docs/getting-started/migrating-from-cas/#update-aws-auth-configmap
################################################################################
resource "kubernetes_config_map_v1" "aws_auth" {
    metadata {
        name      = "aws-auth"
        namespace = "kube-system"
    }
    data = {
        mapRoles = yamlencode([
            for arn in [aws_iam_role.eks_node_group.arn, aws_iam_role.node_by_karpenter.arn] : {
                rolearn  = arn
                username = "system:node:{{EC2PrivateDNSName}}"
                groups   = [
                    "system:bootstrappers",
                    "system:nodes",
                ]}
        ])
    }
    }

################################################################################
# Karpenter
# https://gallery.ecr.aws/karpenter/karpenter
################################################################################\
resource "aws_iam_role" "node_by_karpenter" {
    name = "KarpenterNodeRole-${var.cluster_name}"
    assume_role_policy = templatefile("${path.module}/templates/assume_role.tftpl", {
        sid         = "EKSNodeAssumeRole"
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
        oidc_provider = replace(aws_iam_openid_connect_provider.eks_cluster.url, "https://", "")
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
            sa_create        = true
            sa_namespace     = var.aws_load_balancer_controller_namespace
            sa_name          = "${var.aws_load_balancer_controller_name}-sa"
            sa_role_arn      = aws_iam_role.aws_load_balancer_controller.arn
            replicas         = var.aws_load_balancer_controller_replicas
            node_group_name  = aws_eks_node_group.this.node_group_name
            cluster_name     = var.cluster_name
        })
    ]
    depends_on = [helm_release.karpenter_controller]
}