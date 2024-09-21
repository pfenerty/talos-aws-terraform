variable "client_configuration" {
  type = object({
    ca_certificate     = string
    client_certificate = string
    client_key         = string
  })
}

variable "public_ip" {
  type = string
}

variable "private_ip" {
  type = string
}