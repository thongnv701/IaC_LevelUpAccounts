output "vpc_id" {
  value = aws_vpc.k3s_vpc.id
}

output "subnet_id" {
  value = aws_subnet.k3s_subnet_1.id  # Using the first subnet for the compute module
}

output "subnet_ids" {
  value = [aws_subnet.k3s_subnet_1.id, aws_subnet.k3s_subnet_2.id]
}

output "security_group_id" {
  value = aws_security_group.k3s_security_group.id
}

output "alb_dns_name" {
  description = "The DNS name of the ALB"
  value       = aws_lb.k3s_alb.dns_name
}

output "alb_zone_id" {
  description = "The canonical hosted zone ID of the ALB"
  value       = aws_lb.k3s_alb.zone_id
}

output "http_target_group_arn" {
  description = "ARN of the HTTP target group"
  value       = aws_lb_target_group.k3s_http.arn
}

output "https_target_group_arn" {
  description = "ARN of the HTTPS target group"
  value       = aws_lb_target_group.k3s_https.arn
}