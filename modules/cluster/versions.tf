terraform {
  required_version = ">= 1.9"

  # Ranges rather than exact pins. These constraints are intersected with
  # every other module in the consumer's configuration, so an exact pin here
  # makes the module unusable alongside anything that has moved on a patch
  # release.
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.65"
    }
    talos = {
      source  = "siderolabs/talos"
      version = "~> 0.11"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.9"
    }
  }
}
