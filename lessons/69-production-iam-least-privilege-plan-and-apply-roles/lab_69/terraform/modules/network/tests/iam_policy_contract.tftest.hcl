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
      arn      = "arn:aws:elasticloadbalancing:eu-west-1:123456789012:loadbalancer/app/lab69-app-alb/test"
      dns_name = "internal-lab69-app-alb.example.local"
    }
  }

  mock_resource "aws_lb_target_group" {
    defaults = {
      arn = "arn:aws:elasticloadbalancing:eu-west-1:123456789012:targetgroup/lab69-web-tg/test"
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
  project_name         = "lab69"
  environment          = "test"
  vpc_cidr             = "10.69.0.0/16"
  public_subnet_cidrs  = ["10.69.1.0/24", "10.69.2.0/24"]
  private_subnet_cidrs = ["10.69.11.0/24", "10.69.12.0/24"]
  web_ami_id           = "ami-0123456789abcdef0"
  ssm_proxy_ami_id     = "ami-0123456789abcdef0"
  github_owner         = "VlrRbn"
  github_repo          = "DevOps"
  tf_state_bucket_name = "vlrrbn-tfstate-123456789012-eu-west-1"
  tf_state_key         = "lab69/dev/full/terraform.tfstate"
}

run "iam_policy_contract" {
  # Mocked apply makes computed policy documents available without creating real AWS resources.
  command = apply

  assert {
    condition = (
      !strcontains(aws_iam_role_policy.github_actions_apply_scoped.policy, "AdministratorAccess") &&
      !strcontains(aws_iam_role_policy.github_actions_plan_read.policy, "ReadOnlyAccess")
    )
    error_message = "Lesson 69 must not reintroduce broad AWS managed policies into the normal plan/apply roles."
  }

  assert {
    condition = (
      strcontains(aws_iam_role_policy.github_actions_backend_access.policy, "lab69/dev/full/terraform.tfstate") &&
      strcontains(aws_iam_role_policy.github_actions_backend_access.policy, "lab69/dev/full/terraform.tfstate.tflock") &&
      !strcontains(aws_iam_role_policy.github_actions_backend_access.policy, "lab68/dev/full/terraform.tfstate")
    )
    error_message = "Plan role backend policy must be scoped to the lesson 69 state key and lockfile only."
  }

  assert {
    condition = (
      strcontains(aws_iam_role_policy.github_actions_apply_scoped.policy, "lab69/dev/full/terraform.tfstate") &&
      strcontains(aws_iam_role_policy.github_actions_apply_scoped.policy, "lab69/dev/full/terraform.tfstate.tflock") &&
      !strcontains(aws_iam_role_policy.github_actions_apply_scoped.policy, "lab68/dev/full/terraform.tfstate")
    )
    error_message = "Apply role backend policy must be scoped to the lesson 69 state key and lockfile only."
  }

  assert {
    condition = (
      !contains(flatten([for statement in jsondecode(aws_iam_role_policy.github_actions_plan_read.policy).Statement : try(tolist(statement.Action), [statement.Action])]), "ec2:CreateVpc") &&
      !contains(flatten([for statement in jsondecode(aws_iam_role_policy.github_actions_plan_read.policy).Statement : try(tolist(statement.Action), [statement.Action])]), "ec2:RunInstances") &&
      !contains(flatten([for statement in jsondecode(aws_iam_role_policy.github_actions_plan_read.policy).Statement : try(tolist(statement.Action), [statement.Action])]), "iam:PassRole")
    )
    error_message = "Plan role policy must not include obvious mutation or PassRole permissions."
  }

  assert {
    condition = anytrue([
      for statement in jsondecode(aws_iam_role_policy.github_actions_apply_scoped.policy).Statement :
      try(
        statement.Sid == "PassOnlyLabRuntimeRolesToEc2" &&
        statement.Action == "iam:PassRole" &&
        statement.Resource == "arn:aws:iam::123456789012:role/lab69-ec2-ssm-role" &&
        statement.Condition.StringEquals["iam:PassedToService"] == "ec2.amazonaws.com",
        false
      )
    ])
    error_message = "Apply role PassRole must be restricted to the lab69 EC2 runtime role and ec2.amazonaws.com."
  }

  assert {
    condition = (
      strcontains(aws_iam_role.github_actions_apply_role.assume_role_policy, "repo:VlrRbn/DevOps:environment:terraform-dev") &&
      !strcontains(aws_iam_role.github_actions_apply_role.assume_role_policy, "pull_request")
    )
    error_message = "Apply role trust must stay bound to the protected GitHub Environment subject, not PR jobs."
  }
}
