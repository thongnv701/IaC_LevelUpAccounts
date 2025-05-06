variable "allowed_cidr" {
  description = "CIDR block allowed to access the cluster"
  type        = string
  default     = "0.0.0.0/0"  # Replace with your IP range
}

variable "rds_endpoint" {
  description = "RDS endpoint"
  type        = string
}

variable "rds_username" {
  description = "RDS username"
  type        = string
}

variable "rds_password" {
  description = "RDS password"
  type        = string
}

variable "private_key_content" {
  sensitive   = true
}

variable "route53_zone_id" {
  description = "The Route 53 hosted zone ID for thongit.space domain"
  type        = string
}

variable "route53_elb_zone_id" {
  description = "The Route 53 zone ID for the AWS region's ELB service (fixed value per AWS region)"
  type        = string
  # Default value for ap-southeast-1 (Singapore) region
  default     = "Z1LMS91P8CMLE5"
}