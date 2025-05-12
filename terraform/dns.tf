# Route 53 DNS Management

# Get the hosted zone for thongit.space
data "aws_route53_zone" "main" {
  name = "thongit.space"
}

# Create ACM certificates for all domains
resource "aws_acm_certificate" "service_certs" {
  for_each = toset(var.managed_domains)

  domain_name       = each.value
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

# Create validation records for the certificates
resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in local.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.main.zone_id
}

locals {
  domain_validation_options = flatten([
    for cert in aws_acm_certificate.service_certs : cert.domain_validation_options
  ])
}

# Validate the certificates
resource "aws_acm_certificate_validation" "cert_validation" {
  for_each = aws_acm_certificate.service_certs

  certificate_arn         = each.value.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn if record.name == each.value.domain_validation_options[0].resource_record_name]
  
  timeouts {
    create = "45m"  # Increased timeout for DNS propagation
  }
}

# Create alias records for all domains pointing to the ALB
resource "aws_route53_record" "domain_aliases" {
  for_each = toset(var.managed_domains)

  zone_id = data.aws_route53_zone.main.zone_id
  name    = each.value
  type    = "A"

  alias {
    name                   = module.network.alb_dns_name
    zone_id                = module.network.alb_zone_id
    evaluate_target_health = true
  }
}

# Output the created DNS records
output "dns_records" {
  description = "The DNS records created"
  value = {
    for domain in var.managed_domains : domain => aws_route53_record.domain_aliases[domain].fqdn
  }
}

# Output the certificate ARNs
output "certificate_arns" {
  description = "The ARNs of the created certificates"
  value = {
    for domain in var.managed_domains : domain => aws_acm_certificate.service_certs[domain].arn
  }
}

provider "aws" {
  alias  = "singapore"
  region = "ap-southeast-1"  # Required for ACM certificates used with CloudFront/ALB
} 