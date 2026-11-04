output "vpc_id" {
  description = "ID of the TaskForge VPC."
  value       = aws_vpc.main.id
}

output "public_subnet_id" {
  description = "ID of the TaskForge public subnet."
  value       = aws_subnet.public.id
}

output "aws_region" {
  description = "AWS region used by the deployment."
  value       = var.aws_region
}

output "ec2_instance_id" {
  description = "TaskForge EC2 instance ID."
  value       = aws_instance.taskforge.id
}

output "ec2_instance_type" {
  description = "TaskForge EC2 instance type."
  value       = aws_instance.taskforge.instance_type
}

output "ec2_public_ip" {
  description = "Temporary public IPv4 address of the instance."
  value       = aws_instance.taskforge.public_ip
}

output "ec2_private_ip" {
  description = "Private IP address of the instance."
  value       = aws_instance.taskforge.private_ip
}

output "ec2_ami_id" {
  description = "Amazon Linux 2023 AMI used by the instance."
  value       = data.aws_ami.amazon_linux_2023.id
}
