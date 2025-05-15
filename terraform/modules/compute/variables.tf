variable "ami" {}
variable "master_instance_type" {}
variable "worker_instance_type" {}
variable "key_name" {}
variable "subnet_id" {}
variable "security_group_id" {}
variable "master_user_data" {}
variable "worker_user_data" {}
variable "worker_count" {}
variable "kubeconfig_fetch_script" {}
variable "private_key_content" {}
variable "http_target_group_arn" {
  description = "ARN of the HTTP target group"
  type        = string
}

variable "https_target_group_arn" {
  description = "ARN of the HTTPS target group"
  type        = string
}