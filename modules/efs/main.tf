################################################################################
# https://kubernetes.io/docs/concepts/storage/storage-classes/
# https://github.com/kubernetes-sigs/aws-efs-csi-driver#storage-class-parameters-for-dynamic-provisioning
# https://docs.aws.amazon.com/efs/latest/ug/efs-access-points.html#enforce-root-directory-access-point
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

################################################################################
# EFS
################################################################################
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
# EFS CSI Driver Add-on
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
        sa_namespace      = "kube-system"
        sa_name           = "efs-csi-controller-sa"
    })
    managed_policy_arns = [aws_iam_policy.efs_csi_driver.arn]
}

resource "aws_eks_addon" "efs-csi-driver" {
    cluster_name = var.cluster_name
    addon_name   = "aws-efs-csi-driver"
    service_account_role_arn = aws_iam_role.efs_csi_driver.arn
    resolve_conflicts_on_create = "OVERWRITE"
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