variable "client_configuration" {
  type = object({
    ca_certificate     = string
    client_certificate = string
    client_key         = string
  })
  sensitive   = true
  description = "Talos client certificates produced by the config module."
}

variable "public_ip" {
  type        = string
  description = "Public IP of a control plane node, used as the Talos API endpoint."
}

variable "private_ip" {
  type        = string
  description = "Private IP of the same control plane node, used as the Talos node address."
}
