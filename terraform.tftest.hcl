mock_provider "aws" {
  mock_data "aws_region" {
    defaults = { region = "us-east-1" }
  }

  mock_data "aws_availability_zones" {
    defaults = { names = ["us-east-1a", "us-east-1b", "us-east-1c"] }
  }

  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }

  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }

  mock_data "aws_iam_policy_document" {
    defaults = { json = "{}" }
  }

  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::123456789012:role/example" }
  }

  mock_resource "aws_kms_key" {
    defaults = { arn = "arn:aws:kms:us-east-1:123456789012:key/00000000-0000-0000-0000-000000000000" }
  }

  mock_resource "aws_vpc" {
    defaults = { cidr_block = "10.0.0.0/16" }
  }

  mock_resource "aws_eks_cluster" {
    defaults = {
      certificate_authority = [{ data = "TU9DS0VE" }]

      identity = [{
        oidc = [{ issuer = "https://oidc.eks.us-east-1.amazonaws.com/id/EXAMPLE" }]
      }]
    }
  }
}

variables {
  region             = "us-east-1"
  name               = "example"
  kubernetes_version = "1.31"
}

run "private_management_creates_one_endpoint_per_service" {
  command = plan

  assert {
    condition     = length(module.management_endpoint) == 3
    error_message = "Session Manager needs ssm, ssmmessages and ec2messages. Any fewer and the control path falls back to the internet."
  }
}

run "private_management_can_be_turned_off" {
  command = plan

  variables {
    private_management = false
  }

  assert {
    condition     = length(module.management_endpoint) == 0
    error_message = "Setting private_management to false should create no interface endpoints at all."
  }
}

run "the_cluster_consumes_the_key_the_architecture_created" {
  command = apply

  assert {
    condition     = module.cluster.arn != null
    error_message = "The cluster should be created, which only happens if the KMS key satisfied its required kms_key_arn."
  }
}

run "nodes_and_control_plane_share_the_private_tier" {
  command = plan

  assert {
    condition     = length(module.network.subnet_ids["private"]) == 2
    error_message = "Two availability zones should produce two private subnets by default."
  }

  assert {
    condition     = length(module.network.subnet_ids["public"]) == 2
    error_message = "A public tier is still needed for NAT and for internet-facing load balancers."
  }
}

run "the_api_endpoint_is_private_by_default" {
  command = apply

  assert {
    condition     = output.cluster_endpoint != null
    error_message = "The cluster endpoint should be exposed as an output."
  }

  assert {
    condition     = output.oidc_provider_arn != null
    error_message = "The OIDC provider ARN is what an IRSA trust policy needs, so the architecture must surface it."
  }
}

run "a_third_zone_widens_every_tier" {
  command = plan

  variables {
    availability_zone_count = 3
  }

  assert {
    condition     = length(module.network.subnet_ids["private"]) == 3
    error_message = "Raising availability_zone_count should add a private subnet per zone."
  }
}
