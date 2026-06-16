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

  mock_resource "aws_launch_template" {
    defaults = {
      id             = "lt-0123456789abcdef0"
      latest_version = 1
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
}

run "stable_output_contract" {
  # Mocked apply makes computed outputs available without creating real AWS resources.
  command = apply

  assert {
    condition     = startswith(output.alb_dns_name, "internal-lab72-app-alb")
    error_message = "alb_dns_name must stay a non-empty DNS name consumed by SSM port-forward tests."
  }

  assert {
    condition     = startswith(output.web_tg_arn, "arn:aws:elasticloadbalancing:")
    error_message = "web_tg_arn must stay an ARN-shaped output consumed by health/drift checks."
  }

  assert {
    condition     = can(output.security_groups.web_sg) && can(output.security_groups.alb_sg)
    error_message = "security_groups output must keep stable web_sg and alb_sg keys."
  }

  assert {
    condition     = can(output.ssm_vpc_endpoint_ids["ssm"]) && can(output.ssm_vpc_endpoint_ids["secretsmanager"])
    error_message = "ssm_vpc_endpoint_ids must stay a map keyed by AWS service name."
  }

  assert {
    condition     = can(output.tf_apply_role_arn)
    error_message = "tf_apply_role_arn must stay available for the controlled apply workflow setup."
  }
}
