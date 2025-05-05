resource "aws_vpc" "k3s_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "k3s-vpc"
  }
}

resource "aws_subnet" "k3s_subnet" {
  vpc_id            = aws_vpc.k3s_vpc.id
  cidr_block        = var.subnet_cidr
  availability_zone = var.availability_zone

  tags = {
    Name = "k3s-subnet"
  }
}

resource "aws_security_group" "k3s_security_group" {
  name        = "k3s-security-group"
  description = "Security group for K3s cluster"
  vpc_id      = aws_vpc.k3s_vpc.id

  # For test only, allow all traffic from anywhere
    ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # For production, restrict access to specific ports and CIDR blocks
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
  }
  ingress {
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
  }
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
  }
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "k3s-security-group"
  }
}

resource "aws_internet_gateway" "k3s_igw" {
  vpc_id = aws_vpc.k3s_vpc.id
  tags = { Name = "k3s-igw" }
}

resource "aws_route_table" "k3s_public" {
  vpc_id = aws_vpc.k3s_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.k3s_igw.id
  }
  tags = { Name = "k3s-public-rt" }
}

resource "aws_route_table_association" "k3s_subnet_assoc" {
  subnet_id      = aws_subnet.k3s_subnet.id
  route_table_id = aws_route_table.k3s_public.id
}