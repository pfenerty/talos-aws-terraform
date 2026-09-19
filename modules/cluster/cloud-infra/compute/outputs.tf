output "control_plane_autoscaling_group_name" {
  value = aws_autoscaling_group.control_plane.name
}

output "worker_autoscaling_group_name" {
  value = aws_autoscaling_group.worker.name
}

# Karpenter launches nodes into the worker role's instance profile rather than
# creating one of its own, which keeps the instance-profile write permissions
# out of the controller's policy.
output "worker_instance_profile_name" {
  value = aws_iam_instance_profile.worker.name
}

output "worker_iam_role_arn" {
  value = aws_iam_role.worker_assume_role.arn
}

output "control_plane_ami_id" {
  value = data.aws_ami.control_plane.id
}

# Also what Karpenter launches from: its EC2NodeClass is handed this AMI, so
# the architecture it is allowed to provision has to match var.worker_architecture.
output "worker_ami_id" {
  value = data.aws_ami.worker.id
}

output "worker_architecture" {
  value = var.worker_architecture
}
