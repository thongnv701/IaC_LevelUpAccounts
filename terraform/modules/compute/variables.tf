variable "ami" {}
variable "instance_type" {}
variable "key_name" {}
variable "subnet_id" {}
variable "security_group_id" {}
variable "master_user_data" {}
variable "worker_user_data" {}
variable "worker_count" { default = 1}
variable "kubeconfig_fetch_script" {}
variable "private_key_content" {}