output "role_arn" {
  value       = module.role.role_arn
  description = "ARN of the role the EBS CSI controller assumes."
}
