module "network" {
  source  = "kn47ytv9mv/vpc/aws"
  version = "~> 1.0"

  vpc_cidr                = var.vpc_cidr
  availability_zone_count = var.availability_zone_count

  subnets = {
    public = {
      public = true
      tags   = { "kubernetes.io/role/elb" = "1" }
    }
    private = {
      nat_gateway_access = true
      tags               = { "kubernetes.io/role/internal-elb" = "1" }
    }
  }

  gateway_endpoints = {
    s3 = {}
  }

  tags = var.tags
}

module "endpoint_security_group" {
  source  = "kn47ytv9mv/vpc-security-groups/aws"
  version = "~> 1.0"

  name        = "${var.name}-endpoints"
  vpc_id      = module.network.vpc_id
  description = "Interface endpoints for cluster management traffic."

  ingress_rules = [
    {
      description = "HTTPS from inside the VPC."
      ip_protocol = "tcp"
      from_port   = 443
      to_port     = 443
      cidr_ipv4   = module.network.vpc_cidr_block
    },
  ]

  tags = var.tags
}

module "management_endpoint" {
  source  = "kn47ytv9mv/vpc-endpoint/aws"
  version = "~> 1.0"

  for_each = var.private_management ? toset(["ssm", "ssmmessages", "ec2messages"]) : toset([])

  vpc_id  = module.network.vpc_id
  service = each.value

  subnet_ids         = module.network.subnet_ids["private"]
  security_group_ids = [module.endpoint_security_group.id]

  tags = var.tags
}

module "secrets_key" {
  source  = "kn47ytv9mv/kms-key/aws"
  version = "~> 1.0"

  description = "Envelope encryption for ${var.name} Kubernetes secrets."

  tags = var.tags
}

module "cluster_role" {
  source  = "kn47ytv9mv/iam-role/aws"
  version = "~> 1.0"

  name                  = "${var.name}-cluster"
  principal_type        = "Service"
  principal_identifiers = ["eks.amazonaws.com"]
  managed_policy_arns   = ["arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"]

  tags = var.tags
}

module "node_role" {
  source  = "kn47ytv9mv/iam-role/aws"
  version = "~> 1.0"

  name                  = "${var.name}-node"
  principal_type        = "Service"
  principal_identifiers = ["ec2.amazonaws.com"]

  managed_policy_arns = [
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
  ]

  tags = var.tags
}

module "cluster" {
  source  = "kn47ytv9mv/eks-cluster/aws"
  version = "~> 1.0"

  name     = var.name
  role_arn = module.cluster_role.arn

  kubernetes_version = var.kubernetes_version
  subnet_ids         = module.network.subnet_ids["private"]
  kms_key_arn        = module.secrets_key.arn

  endpoint_public_access = var.endpoint_public_access
  public_access_cidrs    = var.public_access_cidrs

  tags = var.tags
}

module "nodes" {
  source  = "kn47ytv9mv/eks-node-group/aws"
  version = "~> 1.0"

  name          = var.name
  cluster_name  = module.cluster.name
  node_role_arn = module.node_role.arn

  subnet_ids         = module.network.subnet_ids["private"]
  kubernetes_version = var.kubernetes_version

  instance_types = var.instance_types
  capacity_type  = var.capacity_type

  desired_size = var.desired_size
  min_size     = var.min_size
  max_size     = var.max_size

  tags = var.tags
}

output "cluster_name" {
  description = "The name of the cluster. Pass to 'aws eks update-kubeconfig --name'."
  value       = module.cluster.name
}

output "cluster_endpoint" {
  description = "The HTTPS endpoint of the Kubernetes API server."
  value       = module.cluster.endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64-encoded certificate authority data, needed by any client authenticating to the API server."
  value       = module.cluster.certificate_authority_data
}

output "cluster_security_group_id" {
  description = "The security group EKS created for the cluster. Node groups already reach the control plane through it; reference it to let anything else through."
  value       = module.cluster.cluster_security_group_id
}

output "oidc_provider_arn" {
  description = "The IAM OIDC provider ARN. This is the Federated principal in the trust policy of any role a service account assumes."
  value       = module.cluster.oidc_provider_arn
}

output "oidc_issuer_url" {
  description = "The OIDC issuer URL, used to build the subject condition key of an IRSA role."
  value       = module.cluster.oidc_issuer_url
}

output "node_group_name" {
  description = "The name of the managed node group."
  value       = module.nodes.name
}

output "vpc_id" {
  description = "The ID of the VPC the cluster runs in."
  value       = module.network.vpc_id
}

output "subnet_ids" {
  description = "Map of subnet tier to subnet IDs. The private tier holds the nodes and the control plane interfaces."
  value       = module.network.subnet_ids
}

output "management_endpoint_ids" {
  description = "IDs of the interface endpoints carrying Session Manager traffic, empty when private_management is false."
  value       = [for endpoint in module.management_endpoint : endpoint.id]
}
