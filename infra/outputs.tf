output "client_instance_id" {
  value       = aws_instance.client.id
  description = "EC2 client instance ID used by ./rig."
}

output "client_private_ip" {
  value = aws_instance.client.private_ip
}

output "farm_private_ip" {
  value = aws_instance.farm.private_ip
}

output "reapi_endpoint" {
  value = "grpc://${aws_instance.farm.private_ip}:50051"
}

output "ubuntu_ami_id" {
  value       = nonsensitive(aws_instance.client.ami)
  description = "Record this with benchmark metadata."
}

output "farm_instance_id" {
  value       = aws_instance.farm.id
  description = "EC2 farm instance ID used by ./rig."
}

output "amazon_linux_ami_id" {
  value       = nonsensitive(aws_instance.farm.ami)
  description = "Farm AMI ID; record this with benchmark metadata."
}

output "rig_operator_policy_arn" {
  value       = aws_iam_policy.rig_operator.arn
  description = "Attach this policy to identities that may operate the existing rig."
}

output "rig_operator_group_name" {
  value       = aws_iam_group.rig_operators.name
  description = "Add operator IAM users to this group."
}
