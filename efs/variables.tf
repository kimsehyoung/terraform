variable "name" {
    description = "Name to be used on all the resources as identifier"
    type        = string
    default     = ""
}

variable "vpc_id" {
    description = "VPC ID"
    type        = string
}

variable "vpc_cidr" {
    description = "VPC CIDR"
    type        = string
}

variable "private_subnet_ids" {
    description = "A list of subnet IDs for mount target"
    type        = list(string)
    default     = []
}

variable "oidc_provider" {
    description = "The OpenID Connect identity provider (issuer URL without leading `https://`)"
    type        = string
}

variable "oidc_provider_arn" {
    description = "The ARN of the OIDC Provider if `enable_irsa = true`"
    type        = string
}

variable "efs_csi_driver_replicas" {
    description = "The number of efs csi driver replicas"
    type        = number
    default     = 2
}

variable "efs_csi_driver_namespace" {
    description = "The namespace of the efs csi driver"
    type        = string
    default     = "kube-system"
}

variable "efs_csi_driver_name" {
    description = "The name of the efs csi driver"
    type        = string
    default     = "aws-efs-csi-driver"
}

variable "efs_csi_driver_version" {
    description = "The version of the efs csi driver"
    type        = string
    default     = null
}

variable "storage_class_reclaim_policy" {
    description = "A list of subnet IDs for mount target"
    type        = string
    default     = "Delete"
}

variable "storage_class_parameters" {
    description = "A list of subnet IDs for mount target"
    type        = map(string)
    default     = {
        basePath       = "/dynamic_provisioning"
        directoryPerms = "700"
        uid            = "1000"
        gid            = "1000"
    }
}