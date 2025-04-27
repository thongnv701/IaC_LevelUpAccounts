output "vpc_id" { value = aws_vpc.k3s_vpc.id }
output "subnet_id" { value = aws_subnet.k3s_subnet.id }
output "security_group_id" { value = aws_security_group.k3s_security_group.id }