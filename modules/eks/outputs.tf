output "cluster_certificate_authority_data" {
    description = "Base64 encoded certificate data required to communicate with the cluster"
    value       = aws_eks_cluster.this.certificate_authority[0].data
}

output "cluster_name" {
    description = "Name of the EKS cluster"
    value       = aws_eks_cluster.this.id
}

output "cluster_endpoint" {
    description = "Endpoint for your Kubernetes API server"
    value       = aws_eks_cluster.this.endpoint
}

output "cluster_primary_security_group_id" {
    description = "Cluster security group that was created by Amazon EKS for the cluster. Managed node groups use this security group for control-plane-to-data-plane communication. Referred to as 'Cluster security group' in the EKS console"
    value       = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

output "oidc_provider" {
    description = "The OpenID Connect identity provider (issuer URL without leading `https://`)"
    value       = replace(aws_iam_openid_connect_provider.eks_cluster.url, "https://", "")
}

output "oidc_provider_arn" {
    description = "The ARN of the OIDC Provider if `enable_irsa = true`"
    value       = aws_iam_openid_connect_provider.eks_cluster.arn
}

output "node_role_name" {
    description = "Name of the worker node role"
    value       = aws_iam_role.node_by_karpenter.name
}