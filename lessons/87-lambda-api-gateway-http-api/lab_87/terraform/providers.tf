provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Lesson      = "87"
    }
  }
}

data "aws_caller_identity" "current" {}
