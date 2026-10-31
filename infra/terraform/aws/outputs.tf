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
