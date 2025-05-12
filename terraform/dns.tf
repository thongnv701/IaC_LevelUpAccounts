# Route 53 DNS Management

# Get the hosted zone for thongit.space
data "aws_route53_zone" "main" {
  name = "thongit.space"
}

# Get the public IPs of the EC2 instances
data "aws_instances" "k3s_instances" {
  filter {
    name   = "tag:Name"
    values = ["*k3s*"]
  }

  filter {
    name   = "instance-state-name"
    values = ["running"]
  }
}

locals {
  # Extract all available public IPs (excluding empty ones)
  public_ips = [
    for instance in data.aws_instances.k3s_instances.public_ips : 
    instance if instance != null && instance != ""
  ]
  
  # Use fallback IPs if no instances are found (same fallback as in GitHub workflow)
  fallback_ips = ["13.250.45.250", "18.142.178.71"]
  
  # Use public_ips if available, otherwise use fallback_ips
  effective_ips = length(local.public_ips) > 0 ? local.public_ips : local.fallback_ips
  
  # Define all the domains we want to manage
  managed_domains = [
    "argocd.thongit.space",
    "grafana.thongit.space",
    "api.thongit.space"
  ]
}

# Create certificates for all managed domains
resource "aws_acm_certificate" "service_certs" {
  for_each = toset(local.managed_domains)

  domain_name       = each.value
  validation_method = "DNS"
  
  # Add www subdomain as SAN
  subject_alternative_names = ["www.${each.value}"]

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "${replace(each.value, ".", "-")}-cert"
  }
}

# Create validation records for all certificates
resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in flatten([
      for cert in aws_acm_certificate.service_certs : [
        for dvo in cert.domain_validation_options : {
          domain_name = dvo.domain_name
          resource_record_name = dvo.resource_record_name
          resource_record_value = dvo.resource_record_value
          resource_record_type = dvo.resource_record_type
        }
      ]
    ]) : dvo.domain_name => dvo
  }

  allow_overwrite = true
  name            = each.value.resource_record_name
  records         = [each.value.resource_record_value]
  ttl             = 60
  type            = each.value.resource_record_type
  zone_id         = data.aws_route53_zone.main.zone_id
}

# Validate all certificates
resource "aws_acm_certificate_validation" "service_certs" {
  for_each = aws_acm_certificate.service_certs

  certificate_arn         = each.value.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn if record.name == each.value.domain_validation_options[0].resource_record_name]
  
  timeouts {
    create = "45m"
  }
}

# Create A records for all managed domains
resource "aws_route53_record" "service_records" {
  for_each = toset(local.managed_domains)

  zone_id = data.aws_route53_zone.main.zone_id
  name    = each.value
  type    = "A"
  ttl     = "300"
  records = local.effective_ips
}

# Output the created DNS records
output "dns_records" {
  value = {
    for domain in local.managed_domains :
    domain => "${domain} -> ${join(", ", local.effective_ips)}"
  }
  description = "DNS records created in Route 53"
}

# Output the certificate ARNs
output "certificate_arns" {
  value = {
    for domain, cert in aws_acm_certificate.service_certs :
    domain => cert.arn
  }
  description = "ARNs of the created SSL certificates"
}

provider "aws" {
  alias  = "singapore"
  region = "ap-southeast-1"  # Required for ACM certificates used with CloudFront/ALB
} 