terraform {
  required_providers {
    aws = {
      version = "~> 6.61"
    }
  }
}

provider "aws" {
  region = var.region
}
