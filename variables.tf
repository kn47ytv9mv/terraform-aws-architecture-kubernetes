variable "region" {
  default     = null
  description = "Region the architecture is created in."
}

variable "name" {
  default     = null
  description = "Name applied to the cluster, and the prefix for the roles, key and security group created alongside it."
}

variable "kubernetes_version" {
  default     = null
  description = "Kubernetes minor version for the control plane and nodes (e.g. '1.31'). Left null, AWS picks its current default, which moves over time. Pin it for anything intended to last."
}

variable "vpc_cidr" {
  default     = "10.0.0.0/16"
  description = "CIDR block for the VPC the cluster runs in."
}

variable "availability_zone_count" {
  default     = 2
  description = "Number of availability zones to spread across. Each zone adds a NAT gateway and an interface endpoint ENI per service, so this is the largest single cost lever in the architecture."
}

variable "endpoint_public_access" {
  default     = false
  description = "Whether the Kubernetes API endpoint is reachable from the internet. Defaults to false, so kubectl works from inside the VPC or across a VPN. See the README."
}

variable "public_access_cidrs" {
  default     = null
  description = "CIDR blocks allowed to reach the public API endpoint. Only meaningful when endpoint_public_access is true. Left null with public access on, AWS allows the whole internet."
}

variable "private_management" {
  default     = true
  description = "Whether to create interface endpoints for ssm, ssmmessages and ec2messages. With these, Session Manager reaches the nodes over PrivateLink rather than the internet, so management needs no SSH, no bastion and no public path. Each endpoint bills hourly per availability zone."
}

variable "instance_types" {
  default     = ["t3.medium"]
  description = "Instance types for the nodes. With capacity_type 'SPOT', list several so the group can fall back when one pool is unavailable."
}

variable "capacity_type" {
  default     = "ON_DEMAND"
  description = "Purchasing option for the nodes (e.g. 'ON_DEMAND' or 'SPOT')."
}

variable "desired_size" {
  default     = 2
  description = "Number of nodes to run."
}

variable "min_size" {
  default     = 1
  description = "Minimum number of nodes."
}

variable "max_size" {
  default     = 3
  description = "Maximum number of nodes."
}

variable "tags" {
  default     = null
  description = "A map of tags to assign to everything the architecture creates."
}
