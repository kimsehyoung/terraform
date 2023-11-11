### The latest news

- EKS https://aws.amazon.com/ko/about-aws/whats-new/2023/10/amazon-eks-modification-cluster-subnets-security/
- Karpetner https://aws.amazon.com/ko/blogs/containers/karpenter-graduates-to-beta/


### VPC and Subnets
- https://github.com/terraform-aws-modules/terraform-aws-vpc#private-versus-intra-subnets
- https://docs.aws.amazon.com/eks/latest/userguide/network_reqs.html#network-requirements-subnets


### Security groups
- https://aws.github.io/aws-eks-best-practices/security/docs/network/#security-groups
- https://docs.aws.amazon.com/eks/latest/userguide/sec-group-reqs.html


### Karpenter
- https://aws.github.io/aws-eks-best-practices/karpenter/
- https://aws.github.io/aws-eks-best-practices/reliability/docs/application/#recommendations
- https://karpenter.sh/preview/concepts/disruption/#interruption


### Additional commands
```bash
# Add-on configuration
aws eks describe-addon-configuration --addon-name aws-efs-csi-driver --addon-version v1.7.0-eksbuild.1 --query 'configurationSchema' --output text | jq .

# Change the Log level of terraform 
export TF_LOG=DEBUG # INFO DEBUG
# Enable debug logging
https://karpenter.sh/docs/troubleshooting/#enable-debug-logging

# If you are getting a "oci://public.ecr.aws/karpenter/karpenter: 403 forbidden error",
helm registry logout public.ecr.aws

# Configure kube config to access kubernetes api server using cli
aws eks --region ap-northeast-2 update-kubeconfig --name hello
```
