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
    "kubernetes.io/role/elb"         = "1"
    "kubernetes.io/cluster/default"  = "owned"
  }
}

resource "aws_subnet" "k3s_subnet_2" {
  vpc_id            = aws_vpc.k3s_vpc.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, 2)  # 10.0.2.0/24
  availability_zone = var.availability_zones[1]
  map_public_ip_on_launch = true

  tags = {
    Name = "k3s-subnet-2"
    "kubernetes.io/role/elb"         = "1"
    "kubernetes.io/cluster/default"  = "owned"
  }
}

resource "aws_security_group" "k3s_security_group" {
  name        = "k3s-security-group"
  description = "Security group for K3s cluster"
  vpc_id      = aws_vpc.k3s_vpc.id

  # Allow all inbound traffic for testing
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all inbound traffic (FOR TESTING ONLY)"
  }

  # Allow all outbound traffic
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

# Allow SSH access from allowed CIDR
resource "aws_security_group_rule" "allow_ssh" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = [var.allowed_cidr]
  security_group_id = aws_security_group.k3s_security_group.id
}

# Allow Kubernetes API access from allowed CIDR
resource "aws_security_group_rule" "allow_k8s_api" {
  type              = "ingress"
  from_port         = 6443
  to_port           = 6443
  protocol          = "tcp"
  cidr_blocks       = [var.allowed_cidr]
  security_group_id = aws_security_group.k3s_security_group.id
}

# Allow HTTP traffic from ALB
resource "aws_security_group_rule" "allow_alb_http" {
  type                     = "ingress"
  from_port                = 30080
  to_port                  = 30080
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.k3s_security_group.id
  security_group_id        = aws_security_group.k3s_security_group.id
}

# Allow HTTPS traffic from ALB
resource "aws_security_group_rule" "allow_alb_https" {
  type                     = "ingress"
  from_port                = 30443
  to_port                  = 30443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.k3s_security_group.id
  security_group_id        = aws_security_group.k3s_security_group.id
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

resource "aws_lb" "k3s_alb" {
  name               = "k3s-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.k3s_security_group.id]
  subnets            = [aws_subnet.k3s_subnet_1.id, aws_subnet.k3s_subnet_2.id]

  tags = {
    Name = "k3s-alb"
  }
}

resource "aws_lb_target_group" "k3s_http" {
  name        = "k3s-http-tg"
  port        = 30080
  protocol    = "HTTP"
  vpc_id      = aws_vpc.k3s_vpc.id
  target_type = "instance"

  health_check {
    path                = "/healthz"
    port                = "traffic-port"
    healthy_threshold   = 2
    unhealthy_threshold = 10
  }

  tags = {
    Name = "k3s-http-tg"
  }
}

resource "aws_lb_target_group" "k3s_https" {
  name        = "k3s-https-tg"
  port        = 30443
  protocol    = "HTTPS"
  vpc_id      = aws_vpc.k3s_vpc.id
  target_type = "instance"

  health_check {
    path                = "/healthz"
    port                = "traffic-port"
    healthy_threshold   = 2
    unhealthy_threshold = 10
  }

  tags = {
    Name = "k3s-https-tg"
  }
}

resource "aws_lb_listener" "k3s_http" {
  load_balancer_arn = aws_lb.k3s_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_listener" "k3s_https" {
  load_balancer_arn = aws_lb.k3s_alb.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = values(var.certificate_arns)[0]  # Use the first certificate as default

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.k3s_https.arn
  }
}

# Add additional listeners for each domain
resource "aws_lb_listener_certificate" "additional_certs" {
  for_each = {
    for domain, arn in var.certificate_arns : domain => arn
    if domain != keys(var.certificate_arns)[0]  # Skip the first certificate as it's already used
  }

  listener_arn    = aws_lb_listener.k3s_https.arn
  certificate_arn = each.value
}