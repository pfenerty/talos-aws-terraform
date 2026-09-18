output "role_arn" {
  value       = aws_iam_role.this.arn
  description = "ARN of the role. The workload names it in AWS_ROLE_ARN, or in its shared AWS config file."
}

output "role_name" {
  value       = aws_iam_role.this.name
  description = "Name of the role."
}
