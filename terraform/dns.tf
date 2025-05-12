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

locals {
  # Flatten domain validation options
  domain_validation_options = flatten([
    for cert in aws_acm_certificate.service_certs : [
      for dvo in cert.domain_validation_options : {
        domain_name           = dvo.domain_name
        resource_record_name  = dvo.resource_record_name
        resource_record_value = dvo.resource_record_value
        resource_record_type  = dvo.resource_record_type
      }
    ]
  ])
}

# Create validation records for the certificates
resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in local.domain_validation_options : dvo.domain_name => dvo
  }

  allow_overwrite = true
  name            = each.value.resource_record_name
  records         = [each.value.resource_record_value]
  ttl             = 60
  type            = each.value.resource_record_type
  zone_id         = data.aws_route53_zone.main.zone_id
}

# Validate the certificates
resource "aws_acm_certificate_validation" "cert_validation" {
  for_each = aws_acm_certificate.service_certs

  certificate_arn = each.value.arn
  validation_record_fqdns = [
    for dvo in each.value.domain_validation_options : aws_route53_record.cert_validation[dvo.domain_name].fqdn
  ]
  
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