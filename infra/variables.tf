variable "aws_region" {
  description = "AWS region in which to manage the development environment."
  type        = string
  default     = "us-east-1"
}

variable "aws_profile" {
  description = "Optional local AWS CLI profile. Prefer setting AWS_PROFILE."
  type        = string
  default     = null
  nullable    = true
}

variable "farm_name" {
  description = "Name of the NativeLink farm and its supporting resources."
  type        = string
  default     = "reapi-farm"

  validation {
    condition     = can(regex("^[A-Za-z0-9_-]+$", var.farm_name))
    error_message = "farm_name may contain only letters, numbers, underscores, and hyphens."
  }
}

variable "farm_instance_type" {
  description = "x86-64 farm type."
  type        = string
  default     = "c7i-flex.large"
}

variable "farm_volume_gb" {
  description = "Encrypted gp3 root volume size for the persistent CAS and worker data."
  type        = number
  default     = 30

  validation {
    condition     = var.farm_volume_gb >= 8 && floor(var.farm_volume_gb) == var.farm_volume_gb
    error_message = "farm_volume_gb must be an integer of at least 8."
  }
}

variable "nativelink_tag" {
  description = "NativeLink container and configuration release tag."
  type        = string
  default     = "v1.4.0"

  validation {
    condition     = can(regex("^[A-Za-z0-9._-]+$", var.nativelink_tag))
    error_message = "nativelink_tag may contain only letters, numbers, dots, underscores, and hyphens."
  }
}

variable "farm_server" {
  description = "REAPI server on the farm: buildbarn or nativelink. Changing it replaces the server's containers and keeps both servers' data."
  type        = string
  default     = "buildbarn"
  nullable    = false

  validation {
    condition     = contains(["buildbarn", "nativelink"], var.farm_server)
    error_message = "farm_server must be buildbarn or nativelink."
  }
}

variable "client_name" {
  description = "Name for this developer's Linux client. Use a unique value per developer."
  type        = string
  default     = "reapi-client"
}

variable "client_instance_type" {
  description = "x86-64 client type. m7i-flex.large is 2 vCPU/8 GiB and Free Tier eligible for some newer accounts."
  type        = string
  default     = "m7i-flex.large"
}

variable "client_volume_gb" {
  description = "Encrypted gp3 root volume size."
  type        = number
  default     = 30

  validation {
    condition     = var.client_volume_gb >= 8 && floor(var.client_volume_gb) == var.client_volume_gb
    error_message = "client_volume_gb must be an integer of at least 8."
  }
}

