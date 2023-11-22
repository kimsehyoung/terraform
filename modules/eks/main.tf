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
    # 'cluster_security_group_rules' will be added to 'Cluster security group', and nodes(by node group) use the SG.
    # This list of rules doesn't be added because the 'cluster_security_group' is shared between 'control plane' and nodes(by node group).
    # - Karpenter webhook: 8443/tcp
    # - AWS Load Balancer Controller: 9443/tcp
    # - Kubernetes metrics server: 4443/tcp
    cluster_security_group_rules = {
        ingress_coredns_tcp = {
            description = "Allow CoreDNS TCP from nodes(by karpenter) to nodes(by node group) for service discovery"
            type        = "ingress"
            from_port   = 53
            to_port     = 53
            protocol    = "tcp"
        }
        ingress_coredns_udp = {
            description = "Allow CoreDNS UDP from nodes(by karpenter) to nodes(by node group) for service discovery"
            type        = "ingress"
            from_port   = 53
            to_port     = 53
            protocol    = "udp"
        }
    }
    control_plane_security_group_rules = {
        ingress_nodes_api_server = {
            description = "Allow the kubelets to communicate with k8s API server from worker nodes"
            type = "ingress"
            from_port = 443
            to_port = 443
            protocol = "tcp"
        }
    }
    # 'node_security_group_additional_rules' is needed for communication using protocol such as HTTP(depends on your case) between pods in other nodes(by karpenter).
    # The default of 'node_security_group_additional_rules' is '1025 ~ 65535' range that can cover most of cases. You can restrict the traffic using this variable. 
    node_security_group_essential_rules = {
        ingress_cluster_kubelet = {
            description = "Allow kubelet API from controlplane API Server to nodes(by karpenter)"
            type = "ingress"
            from_port = 10250
            to_port = 10250
            protocol = "tcp"
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

    source_security_group_id = aws_security_group.node.id
}

resource "aws_security_group" "node" {
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

resource "aws_security_group_rule" "node" {
    for_each = { for k, v in (merge(local.node_security_group_essential_rules, var.node_security_group_additional_rules)) : k => v }
    security_group_id = aws_security_group.node.id

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
        aws_security_group_rule.node
    ]
}

resource "aws_security_group_rule" "eks_cluster" {
    for_each = { for k, v in local.cluster_security_group_rules : k => v }

    security_group_id = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id

    description       = lookup(each.value, "description", null)
    type              = each.value.type
    from_port         = each.value.from_port
    to_port           = each.value.to_port
    protocol          = each.value.protocol

    source_security_group_id = aws_security_group.node.id
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
# Service Mesh Linkerd2
# https://linkerd.io/2.14/tasks/automatically-rotating-control-plane-tls-credentials/
################################################################################
resource "tls_private_key" "ca" {
    algorithm   = "ECDSA"
    ecdsa_curve = "P256"
}

resource "tls_self_signed_cert" "ca" {
    private_key_pem         = tls_private_key.ca.private_key_pem
    validity_period_hours   = 48
    early_renewal_hours     = 25
    is_ca_certificate       = true

    allowed_uses = [
        "cert_signing",
        "crl_signing",
        "server_auth",
        "client_auth"
    ]
    subject {
        common_name = "identity.linkerd.cluster.local"
    }
}

resource "tls_private_key" "issuer" {
    algorithm   = "ECDSA"
    ecdsa_curve = "P256"
}

resource "tls_cert_request" "issuer" {
    private_key_pem = tls_private_key.issuer.private_key_pem
    subject {
        common_name = "identity.linkerd.cluster.local"
    }
}

resource "tls_locally_signed_cert" "issuer" {
    cert_request_pem      = tls_cert_request.issuer.cert_request_pem
    ca_private_key_pem    = tls_private_key.ca.private_key_pem
    ca_cert_pem           = tls_self_signed_cert.ca.cert_pem
    is_ca_certificate     = true
    validity_period_hours = 4

    allowed_uses = [
        "cert_signing",
        "crl_signing",
        "server_auth",
        "client_auth"
    ]
}

resource "helm_release" "linkerd_crds" {
    name       = "linkerd-crds"

    repository = "https://helm.linkerd.io/stable"
    chart      = "linkerd-crds"
    version    = var.linkerd_crds_version

    depends_on = [aws_eks_node_group.this]
}

resource "helm_release" "linkerd_control_plane" {
    create_namespace = true
    namespace        = "linkerd"
    name             = "linkerd-control-plane"

    repository = "https://helm.linkerd.io/stable"
    chart      = "linkerd-control-plane"
    version    = var.linkerd_control_plane_version

    set_sensitive {
        name = "identityTrustAnchorsPEM"
        value = tls_self_signed_cert.ca.cert_pem
    }
    set {
        name  = "identity.issuer.tls.crtPEM"
        value = tls_locally_signed_cert.issuer.cert_pem
    }
    set {
        name  = "identity.issuer.tls.keyPEM"
        value = tls_private_key.issuer.private_key_pem
    }

    values = [
        templatefile("${path.module}/templates/linkerd_control_plane_values.tftpl", {
            replicas            = var.linkerd_control_plane_replicas
            node_group_name     = aws_eks_node_group.this.node_group_name
        })
    ]
    depends_on = [helm_release.linkerd_crds]
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

    capacity_type   = "ON_DEMAND"
    instance_types  = [var.node_group_instance_types]
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
# Kubernetes Metrics Server
# https://artifacthub.io/packages/helm/metrics-server/metrics-server
################################################################################
resource "helm_release" "metrics_server" {
    create_namespace = true
    namespace        = "kube-system"
    name             = "metrics-server"

    repository = "https://kubernetes-sigs.github.io/metrics-server/"
    chart      = "metrics-server"
    version    = var.metrics_server_version

    values = [
        templatefile("${path.module}/templates/metrics_server_values.tftpl", {
            replicas        = var.metrics_server_replicas
            node_group_name = aws_eks_node_group.this.node_group_name
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