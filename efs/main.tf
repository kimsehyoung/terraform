################################################################################
# EFS
################################################################################
resource "aws_security_group" "efs" {
    name   = "${var.name}-efs-sg"
    vpc_id = var.vpc_id

    ingress {
        from_port        = 2049
        to_port          = 2049
        protocol         = "tcp"
        cidr_blocks      = [var.vpc_cidr]
    }
    egress {
        from_port   = 0
        to_port     = 0
        protocol    = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }
}

resource "aws_efs_file_system" "this" {
	creation_token = "${var.name}-aws-efs"
}

resource "aws_efs_mount_target" "this" {
    count = length(var.private_subnet_ids)

	subnet_id       = var.private_subnet_ids[count.index]
	file_system_id  = aws_efs_file_system.this.id
	security_groups = [aws_security_group.efs.id]
}

################################################################################
# EFS CSI Driver
################################################################################
resource "aws_iam_policy" "efs_csi_driver" {
    name = "EKS_EFS_CSI_DriverPolicy-${var.name}"
    policy = templatefile("${path.module}/templates/eks_efs_csi_driver_policy.tftpl", {})
}

resource "aws_iam_role" "efs_csi_driver" {
    name = "EKS_EFS_CSI_DriverRole-${var.name}"
    assume_role_policy = templatefile("${path.module}/templates/assume_role_oidc.tftpl", {
        oidc_provider     = var.oidc_provider
        oidc_provider_arn = var.oidc_provider_arn
        sa_namespace      = var.efs_csi_driver_namespace
        sa_name           = "${var.efs_csi_driver_name}-sa"
    })
    managed_policy_arns = [aws_iam_policy.efs_csi_driver.arn]
}

resource "helm_release" "efs_csi_driver" {
    create_namespace = true
    namespace        = var.efs_csi_driver_namespace
    name             = var.efs_csi_driver_name

    repository = "https://kubernetes-sigs.github.io/aws-efs-csi-driver/"
    chart      = "aws-efs-csi-driver"
    version    = var.efs_csi_driver_version

    values = [
        templatefile("${path.module}/templates/efs_csi_driver_values.tftpl", {
            image_repository = "602401143452.dkr.ecr.ap-northeast-2.amazonaws.com/eks/aws-efs-csi-driver"
            replicas         = var.efs_csi_driver_replicas
            sa_create        = true
            sa_namespace     = var.efs_csi_driver_namespace
            sa_name          = "${var.efs_csi_driver_name}-sa"
            sa_role_arn      = aws_iam_role.efs_csi_driver.arn
        })
    ]
}

################################################################################
# Storage Class
################################################################################
resource "kubernetes_storage_class" "efs" {
    metadata {
        name = "${var.name}-efs-sc"
    }
    storage_provisioner = "efs.csi.aws.com"
    reclaim_policy      = var.storage_class_reclaim_policy

    parameters = merge(
        {
            provisioningMode = "efs-ap"
            fileSystemId     = aws_efs_file_system.this.id
        },
        var.storage_class_parameters
    )
}