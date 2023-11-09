variable "additional_tags" {
    description = "Additional resource tags"
    type        = map(string)
    default     = {}
}
################################################################################
# EKS Cluster
################################################################################
variable "cluster_name" {
  description = "The name of the EKS cluster"
  type        = string
  default     = ""
}

variable "cluster_version" {
    description = "The version of the EKS cluster (Default to The latest available version)"
    type        = string
    default     = null
}

variable "intra_subnet_ids" {
    description = "A list of subnet IDs where the EKS cluster control plane (ENIs) will be provisione to allow communication between your nodes and the Kubernetes control plane"
    type        = list(string)
    default     = []
}

variable "endpoint_private_access" {
    description = "Indicates whether or not the Amazon EKS private API server endpoint is enabled"
    type        = bool
    default     = true
}

variable "endpoint_public_access" {
    description = "Indicates whether or not the Amazon EKS public API server endpoint is enabled"
    type        = bool
    default     = true
}

variable "endpoint_public_access_cidrs" {
    description = "List of CIDR blocks which can access the Amazon EKS public API server endpoint"
    type        = list(string)
    default     = ["0.0.0.0/0"]
}

variable "cluster_additional_security_group_rules" {
    description = "List of additional security group rules to add to the cluster security group created. Set `source_node_security_group = true` inside rules to set the `node_security_group` as source"
    type        = any
    default     = {}
}

################################################################################
# EKS add-ons
################################################################################
variable "coredns_replicas" {
    description = "The replicas of CoreDNS"
    type        = number
    default     = 2
}

variable "coredns_resources" {
    description = "The resources of CoreDNS"
    type        = map(map(string))
    default     =  {
        requests = {
            cpu    = "200m",
            memory = "128Mi"
        },
        limits = {
            cpu    = "400m",
            memory = "256Mi"
        }
    }
}

################################################################################
# EKS Node Group
################################################################################
variable "private_subnet_ids" {
    description = "List of subnet IDs where the nodes/node groups will be provisioned"
    type        = list(string)
    default     = []
}

variable "node_group_instance_types" {
    description = "List of instance types associated with the EKS Node Group. (Default 't3.medium')"
    type        = list(string)
    default     = null
}

variable "node_group_ami_type" {
    description = "Type of AMI associated with the EKS Node Group"
    type        = string
    default     = null
}

variable "scaling_config" {
    description = "Scaling settings of node group that critical components(karpenter) exist"
    type        = object({
        desired_size = number
        min_size     = number
        max_size     = number
    })
    default     = {
        desired_size = 1
        min_size     = 1
        max_size     = 2
    }
}

variable "node_group_disk_size" {
    description = "Disk size in GiB for nodes (Default to '20')"
    type        = number
    default     = null
}

variable "node_group_labels" {
    description = "Node Group's labels that that critical components(karpenter) exist"
    type        = map(string)
    default     = null
}

variable "node_group_taints" {
    description = "Node Group's taints that critical components(karpenter) exist"
    type        = list(any)
    default     = [{
        key    = "karpenter"
        effect = "NO_SCHEDULE"
    }]
}

################################################################################
# Karpenter
################################################################################
variable "vpc_id" {
    description = "VPC ID"
    type        = string
}

variable "karpenter_namespace" {
    description = "The namespace of Karpenter"
    type        = string
    default     = "karpenter"
}

variable "karpenter_name" {
    description = "The name of Karpenter"
    type        = string
    default     = "karpenter"
}

variable "karpenter_version" {
    description = "The version of Karpenter (Default to 'the latest release')"
    type        = string
    default     = null
}

variable "karpenter_replicas" {
    description = "The replicas of Karpenter"
    type        = number
    default     = 2
}

variable "karpenter_resources" {
    description = "The resources of Karpenter"
    type        = map(map(string))
    default     =  {
        requests = {
            cpu    = "0.5"
            memory = "1Gi"
        },
        limits = {
            cpu    = "0.5"
            memory = "1Gi"
        }
    }
}

variable "karpenter_batch" {
    description = "The settings of Karpenter batch"
    type        = map(string)
    default     =  {
        idle_duration = "2s"
        max_duration  = "10s"
    }
}

################################################################################
# AWS Load Balancer Controller
################################################################################
variable "aws_load_balancer_controller_namespace" {
    description = "The namespace of AWS Load Balancer Controller"
    type        = string
    default     = "kube-system"
}

variable "aws_load_balancer_controller_name" {
    description = "The name of AWS Load Balancer Controller"
    type        = string
    default     = "aws-load-balancer-controller"
}

variable "aws_load_balancer_controller_version" {
    description = "The version of AWS Load Balancer Controller (Default to 'the latest release')"
    type        = string
    default     = null
}

variable "aws_load_balancer_controller_replicas" {
    description = "The replicas of AWS Load Balancer Controller"
    type        = number
    default     = 2
}
