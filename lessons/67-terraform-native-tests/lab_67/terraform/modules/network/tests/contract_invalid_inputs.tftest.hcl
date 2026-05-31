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
}

variables {
  aws_region           = "eu-west-1"
  project_name         = "lab67"
  environment          = "test"
  vpc_cidr             = "10.67.0.0/16"
  public_subnet_cidrs  = ["10.67.1.0/24", "10.67.2.0/24"]
  private_subnet_cidrs = ["10.67.11.0/24", "10.67.12.0/24"]
  web_ami_id           = "ami-0123456789abcdef0"
  ssm_proxy_ami_id     = "ami-0123456789abcdef0"
  github_owner         = "VlrRbn"
  github_repo          = "DevOps"
  tf_state_bucket_name = "vlrrbn-tfstate-123456789012-eu-west-1"
  tf_state_key         = "lab67/dev/full/terraform.tfstate"
}

run "bad_project_name_fails" {
  command = plan

  variables {
    project_name = "Bad_Name"
  }

  expect_failures = [
    var.project_name
  ]
}

run "bad_web_ami_id_fails" {
  command = plan

  variables {
    web_ami_id = "ubuntu-latest"
  }

  expect_failures = [
    var.web_ami_id
  ]
}

run "single_private_subnet_fails" {
  command = plan

  variables {
    private_subnet_cidrs = ["10.67.11.0/24"]
  }

  expect_failures = [
    var.private_subnet_cidrs
  ]
}

run "too_many_private_subnets_fails" {
  command = plan

  variables {
    private_subnet_cidrs = [
      "10.67.11.0/24",
      "10.67.12.0/24",
      "10.67.13.0/24",
      "10.67.14.0/24",
      "10.67.15.0/24",
      "10.67.16.0/24",
      "10.67.17.0/24",
    ]
  }

  expect_failures = [
    var.private_subnet_cidrs
  ]
}

run "duplicate_private_subnets_fail" {
  command = plan

  variables {
    private_subnet_cidrs = ["10.67.11.0/24", "10.67.11.0/24"]
  }

  expect_failures = [
    var.private_subnet_cidrs
  ]
}

run "bad_private_subnet_cidr_fails" {
  command = plan

  variables {
    private_subnet_cidrs = ["10.67.11.0/24", "not-a-cidr"]
  }

  expect_failures = [
    var.private_subnet_cidrs
  ]
}

run "bad_ssm_proxy_ami_id_fails" {
  command = plan

  variables {
    ssm_proxy_ami_id = "ubuntu-latest"
  }

  expect_failures = [
    var.ssm_proxy_ami_id
  ]
}

run "empty_tag_value_fails" {
  command = plan

  variables {
    common_tags = {
      Owner = ""
    }
  }

  expect_failures = [
    var.common_tags
  ]
}

run "reserved_tag_override_fails" {
  command = plan

  variables {
    common_tags = {
      Project = "manual"
    }
  }

  expect_failures = [
    var.common_tags
  ]
}

run "bad_health_check_threshold_fails" {
  command = plan

  variables {
    health_check_healthy_threshold = 1
  }

  expect_failures = [
    var.health_check_healthy_threshold
  ]
}

run "bad_state_key_fails" {
  command = plan

  variables {
    tf_state_key = "/absolute/path/terraform.tfstate"
  }

  expect_failures = [
    var.tf_state_key
  ]
}
