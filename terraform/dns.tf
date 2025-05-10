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