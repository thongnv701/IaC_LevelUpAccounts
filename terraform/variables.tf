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