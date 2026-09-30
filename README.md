# terraform-aws-architecture-kubernetes

A complete EKS platform assembled from this family's modules: a VPC, a
control plane with encrypted secrets, a managed node group, and private
management access over PrivateLink. Nothing in it is reachable from the
internet by default.

## Cost

This is one of the more expensive architectures in the family, and almost
all of it is standing charge rather than usage.

The **EKS control plane** bills per hour from the moment it exists,
whether or not a pod is ever scheduled. **NAT gateways** bill per hour and
per gigabyte, one per availability zone. **Nodes** bill as EC2 instance
hours plus an EBS root volume each. The **interface endpoints** bill per
hour for every availability zone they are placed in, and there are three
of them when `private_management` is on. The **KMS key** carries a small
monthly charge.

**`availability_zone_count` is the largest single lever**, because it
multiplies both the NAT gateways and the interface endpoint network
interfaces. It defaults to two rather than three for that reason. Going
to three raises the standing cost of the network by half before a single
pod runs.

The one thing working in the other direction is the **S3 gateway
endpoint**, which is created by default, carries no charge, and keeps S3
traffic off the NAT gateways. Container image layers come from S3 behind
ECR, so this removes a meaningful slice of NAT data processing on a
cluster that pulls images regularly.

Rates are on AWS's [EKS pricing](https://aws.amazon.com/eks/pricing/),
[VPC pricing](https://aws.amazon.com/vpc/pricing/) and
[PrivateLink pricing](https://aws.amazon.com/privatelink/pricing/) pages.

## Design

The defaults describe a private cluster. The Kubernetes API endpoint is
not exposed to the internet, the nodes sit in private subnets, secrets are
envelope-encrypted under a customer managed key, and access is granted
through EKS access entries rather than the legacy `aws-auth` ConfigMap.

### Management without a public path

With `private_management` left on, the architecture creates interface
endpoints for `ssm`, `ssmmessages` and `ec2messages`, and the node role
carries `AmazonSSMManagedInstanceCore`. Session Manager then reaches the
nodes entirely over PrivateLink.

The consequence is that the cluster needs no SSH, no bastion and no public
route for management traffic. The usual objection to Session Manager is
that its control path runs over the internet; these three endpoints are
the answer to it.

### Why the endpoints are separate module calls

`terraform-aws-vpc` can create interface endpoints itself, and doing so
would be fewer moving parts. It does not work here. The endpoints need a
security group, that security group needs the VPC's ID, and the VPC would
then need the security group — a dependency cycle. Creating the endpoints
with `terraform-aws-vpc-endpoint` after the security group breaks it.

### Subnet discovery

The public tier carries `kubernetes.io/role/elb` and the private tier
`kubernetes.io/role/internal-elb`, which is how the AWS load balancer
controller finds somewhere to place a load balancer. Without those tags an
ingress resource provisions nothing and the failure is silent.

### Reaching the API server

`kubectl` works from inside the VPC: a bastion, a CI runner in a private
subnet, or across a VPN or Direct Connect. Where outside access is needed,
set `endpoint_public_access` **and** `public_access_cidrs` together.
Setting the first alone yields AWS's own default of the entire internet.

### What this does not build

Add-ons beyond the EKS defaults of VPC CNI, CoreDNS and kube-proxy. An
ingress controller. A GitOps agent. Anything inside the cluster, in fact —
this stands up the platform, and what runs on it is a separate concern
with a separate lifecycle.

## Usage

```hcl
module "platform" {
  source  = "kn47ytv9mv/architecture-kubernetes/aws"
  version = "~> 1.0"

  region = "us-east-1"
  name   = "example"

  kubernetes_version = "1.31"
}
```

With the API server reachable from one office range, and spot capacity:

```hcl
module "platform" {
  source  = "kn47ytv9mv/architecture-kubernetes/aws"
  version = "~> 1.0"

  region = "us-east-1"
  name   = "example"

  kubernetes_version = "1.31"

  endpoint_public_access = true
  public_access_cidrs    = ["203.0.113.0/24"]

  capacity_type  = "SPOT"
  instance_types = ["t3.medium", "t3a.medium", "t2.medium"]
  max_size       = 10
}
```

## Requirements

| Name | Version |
|---|---|
| terraform | >= 1.9 |
| aws | ~> 6.61 |

## Providers

| Name | Version |
|---|---|
| aws | ~> 6.61 |

## Inputs

| Name | Description | Default | Required |
|---|---|---|---|
| region | Region the architecture is created in. | `null` | no |
| name | Name for the cluster, and the prefix for the roles, key and security group. | `null` | no |
| kubernetes_version | Kubernetes minor version for the control plane and nodes. | `null` | no |
| vpc_cidr | CIDR block for the VPC. | `"10.0.0.0/16"` | no |
| availability_zone_count | Availability zones to spread across. The largest cost lever. | `2` | no |
| endpoint_public_access | Whether the Kubernetes API endpoint is reachable from the internet. | `false` | no |
| public_access_cidrs | CIDR blocks allowed to reach the public API endpoint. | `null` | no |
| private_management | Whether to create the ssm, ssmmessages and ec2messages endpoints. | `true` | no |
| instance_types | Instance types for the nodes. | `["t3.medium"]` | no |
| capacity_type | Purchasing option (e.g. `'ON_DEMAND'` or `'SPOT'`). | `"ON_DEMAND"` | no |
| desired_size | Number of nodes to run. | `2` | no |
| min_size | Minimum number of nodes. | `1` | no |
| max_size | Maximum number of nodes. | `3` | no |
| tags | A map of tags to assign to everything created. | `null` | no |

## Outputs

| Name | Description |
|---|---|
| cluster_name | The name of the cluster. Pass to `aws eks update-kubeconfig --name`. |
| cluster_endpoint | The HTTPS endpoint of the Kubernetes API server. |
| cluster_certificate_authority_data | Base64-encoded certificate authority data for the cluster. |
| cluster_security_group_id | The security group EKS created for the cluster. |
| oidc_provider_arn | The IAM OIDC provider ARN, the federated principal in an IRSA trust policy. |
| oidc_issuer_url | The OIDC issuer URL, used to build the subject condition key of an IRSA role. |
| node_group_name | The name of the managed node group. |
| vpc_id | The ID of the VPC the cluster runs in. |
| subnet_ids | Map of subnet tier to subnet IDs. |
| management_endpoint_ids | IDs of the Session Manager interface endpoints, empty when `private_management` is false. |

## License

MIT — see [LICENSE.md](LICENSE.md).
