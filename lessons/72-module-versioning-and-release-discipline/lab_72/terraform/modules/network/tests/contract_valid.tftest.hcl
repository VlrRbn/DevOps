mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = {
      names = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]
    }
  }

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  mock_resource "aws_lb" {
    defaults = {
      arn      = "arn:aws:elasticloadbalancing:eu-west-1:123456789012:loadbalancer/app/lab72-app-alb/test"
      dns_name = "internal-lab72-app-alb.example.local"
    }
  }

  mock_resource "aws_lb_target_group" {
    defaults = {
      arn = "arn:aws:elasticloadbalancing:eu-west-1:123456789012:targetgroup/lab72-web-tg/test"
    }
  }
}

variables {
  aws_region           = "eu-west-1"
  project_name         = "lab72"
  environment          = "test"
  vpc_cidr             = "10.72.0.0/16"
  public_subnet_cidrs  = ["10.72.1.0/24", "10.72.2.0/24"]
  private_subnet_cidrs = ["10.72.11.0/24", "10.72.12.0/24"]
  web_ami_id           = "ami-0123456789abcdef0"
  ssm_proxy_ami_id     = "ami-0123456789abcdef0"
  github_owner         = "VlrRbn"
  github_repo          = "DevOps"
  tf_state_bucket_name = "vlrrbn-tfstate-123456789012-eu-west-1"
  tf_state_key         = "lab72/dev/full/terraform.tfstate"

  common_tags = {
    Owner = "devops-track"
  }
}

run "valid_contract_inputs_plan" {
  command = plan

  assert {
    condition     = output.web_asg_name == "lab72-web-asg"
    error_message = "web_asg_name must keep the stable '<project>-web-asg' output contract."
  }

  assert {
    condition     = output.demo_api_token_parameter_name == "/devops/lab72/demo/api-token"
    error_message = "The runtime SSM parameter output must expose only the stable metadata name."
  }

  assert {
    condition     = output.demo_app_secret_name == "/devops/lab72/demo/app-secret"
    error_message = "The runtime Secrets Manager output must expose only the stable metadata name."
  }
}
