
# AWS Guide

**Table of Contents**
- [Verified Environment](#verified-environment)
- [Kubernetes](#kubernetes)
    - [EKS](#eks)
    - [Karpenter](#karpenter)
- [Reference](#reference)
    - [VPC and Subnets](#vpc-and-subnets)
    - [EFS](#efs)
- [TODO](#todo)
    - [Session Manager](#session-manager)
    - [Secret Manager](#secret-manager)


================================================================================

## Verified Environment

- aws-cli: 2.13.25
- eksctl: 0.161.0
- kubectl: v1.28.2
- helm: v3.13.1
- terraform: v1.6.2
- kubernetes: 1.28
- karpenter: v0.32.1
- aws load balancer controller: 1.6.2
- efs csi driver: 2.5.0

================================================================================
## Kubernetes

### Commands
```bash
# Configure kube config to access kubernetes api server
aws eks --region ap-northeast-2 update-kubeconfig --name edu-test
```


### EKS
- https://kubernetes.io/docs/concepts/scheduling-eviction/topology-spread-constraints/#topologyspreadconstraints-field
- https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/#inter-pod-affinity-and-anti-affinity


### Karpenter
alpha -> beta
- https://aws.amazon.com/ko/blogs/containers/karpenter-graduates-to-beta/

best practices
- https://aws.github.io/aws-eks-best-practices/karpenter/
- https://aws.github.io/aws-eks-best-practices/reliability/docs/application/#recommendations

Spot Instance
- https://karpenter.sh/preview/concepts/disruption/#interruption

================================================================================

## Reference

### VPC and Subnets
- https://docs.aws.amazon.com/ko_kr/vpc/latest/userguide/amazon-vpc-limits.html
- https://pseonghoon.github.io/post/eks-subnet/
- https://docs.aws.amazon.com/eks/latest/userguide/network_reqs.html#network-requirements-subnets
- https://github.com/terraform-aws-modules/terraform-aws-vpc#private-versus-intra-subnets
- https://aws.amazon.com/ko/about-aws/whats-new/2023/10/amazon-eks-modification-cluster-subnets-security/


### EFS
- https://kubernetes.io/docs/concepts/storage/storage-classes/
- https://github.com/kubernetes-sigs/aws-efs-csi-driver#storage-class-parameters-for-dynamic-provisioning
- https://docs.aws.amazon.com/efs/latest/ug/efs-access-points.html#enforce-root-directory-access-point

================================================================================

## TODO

### Session Manager
- Access to RDS using session manager

### Secret Manager
- secret mangaer, vault, etc... for credentials such as database info

### tfstate
- gitlab, s3, terraform cloud

### Service Mesh
- Istio to manage networking, etc...