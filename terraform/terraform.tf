terraform {
  backend "s3" {
    bucket         = "my-terraform-backup-0701"
    key            = "levelupaccounts/terraform.tfstate"
    region         = "ap-southeast-1"
    encrypt        = true
  }
}