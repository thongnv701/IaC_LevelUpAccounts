resource "aws_vpc" "k3s_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "k3s-vpc"
  }
}

resource "aws_subnet" "k3s_subnet_1" {
  vpc_id            = aws_vpc.k3s_vpc.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, 1)  # 10.0.1.0/24
  availability_zone = var.availability_zones[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "k3s-subnet-1"
  }
}

resource "aws_subnet" "k3s_subnet_2" {
  vpc_id            = aws_vpc.k3s_vpc.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, 2)  # 10.0.2.0/24
  availability_zone = var.availability_zones[1]
  map_public_ip_on_launch = true

  tags = {
    Name = "k3s-subnet-2"
  }
}

resource "aws_security_group" "k3s_security_group" {
  name        = "k3s-security-group"
  description = "Security group for K3s cluster"
  vpc_id      = aws_vpc.k3s_vpc.id

  # For production, restrict these rules
    ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }


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
  tags = { 
    Name = "k3s-igw" 
  }
}

resource "aws_route_table" "k3s_public" {
  vpc_id = aws_vpc.k3s_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.k3s_igw.id
  }
  tags = { 
    Name = "k3s-public-rt" 
  }
}

resource "aws_route_table_association" "k3s_subnet_1_assoc" {
  subnet_id      = aws_subnet.k3s_subnet_1.id
  route_table_id = aws_route_table.k3s_public.id
}

resource "aws_route_table_association" "k3s_subnet_2_assoc" {
  subnet_id      = aws_subnet.k3s_subnet_2.id
  route_table_id = aws_route_table.k3s_public.id
}