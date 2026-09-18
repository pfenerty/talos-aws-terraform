output "role_arn" {
  value       = module.role.role_arn
  description = "ARN of the role the cloud controller manager assumes."
}
