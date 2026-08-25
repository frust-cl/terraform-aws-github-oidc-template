# Terraform and provider version constraints.
#
# Why this file exists: without a `required_providers` block, every `terraform
# init` resolves the newest provider release available at that moment. Two runs
# of the same commit can then produce different plans. The pin makes the build
# reproducible.
#
# Commit `.terraform.lock.hcl` alongside this file. The constraint below selects
# a range. The lock file selects the exact version inside that range.

terraform {
  required_version = ">= 1.15.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.61"
    }
  }
}
