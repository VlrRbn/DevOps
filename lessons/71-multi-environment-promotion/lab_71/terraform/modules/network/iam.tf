# ***** IAM for SSM *****

# IAM role for SSM managed instances.
resource "aws_iam_role" "ec2_ssm_role" {
  name = "${var.project_name}-ec2-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = merge(local.tags, {
    Name = "${var.project_name}-ec2-ssm-role"
    Role = "runtime-ssm"
  })
}

# Attach AmazonSSMManagedInstanceCore to the role.
resource "aws_iam_role_policy_attachment" "ec2_ssm_role_attach" {
  role       = aws_iam_role.ec2_ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Instance profile for EC2 SSM role.
resource "aws_iam_instance_profile" "ec2_ssm_instance_profile" {
  name = "${var.project_name}-ec2-ssm-instance-profile"
  role = aws_iam_role.ec2_ssm_role.name

  tags = merge(local.tags, {
    Name = "${var.project_name}-ec2-ssm-instance-profile"
    Role = "runtime-ssm"
  })
}

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "runtime_secret_read" {
  statement {
    sid    = "ReadLesson71SecureString"
    effect = "Allow"

    actions = [
      "ssm:GetParameter"
    ]

    # The role gets access to a named parameter, but Terraform never reads the plaintext SecureString.
    resources = [
      "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter${var.demo_api_token_parameter_name}"
    ]
  }

  statement {
    sid    = "ReadLesson71Secret"
    effect = "Allow"

    actions = [
      "secretsmanager:GetSecretValue"
    ]

    # Secrets Manager ARNs include a random suffix, so the IAM resource uses the secret name prefix.
    resources = [
      "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:${var.demo_app_secret_name}*"
    ]
  }
}

resource "aws_iam_role_policy" "runtime_secret_read" {
  name   = "${var.project_name}-runtime-secret-read"
  role   = aws_iam_role.ec2_ssm_role.id
  policy = data.aws_iam_policy_document.runtime_secret_read.json
}

# ***** IAM for GitHub Actions OIDC *****

resource "aws_iam_openid_connect_provider" "github_actions" {
  count = var.github_oidc_provider_arn == "" ? 1 : 0

  # GitHub Actions exchanges its job identity token against this OIDC provider.
  url = "https://token.actions.githubusercontent.com"

  client_id_list = [
    "sts.amazonaws.com"
  ]

  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd"
  ]
}

locals {
  github_oidc_provider_arn = var.github_oidc_provider_arn != "" ? var.github_oidc_provider_arn : aws_iam_openid_connect_provider.github_actions[0].arn
}

resource "aws_iam_role" "github_actions_plan_role" {
  name = "${var.project_name}-github-actions-plan-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Federated = local.github_oidc_provider_arn
        }

        Action = "sts:AssumeRoleWithWebIdentity"

        Condition = {
          StringEquals = {
            # GitHub OIDC tokens for AWS STS must always use this audience.
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }

          StringLike = {
            # Allow this exact repo either on the protected branch or as a PR workflow.
            "token.actions.githubusercontent.com:sub" = [
              "repo:${var.github_owner}/${var.github_repo}:ref:refs/heads/${var.github_branch}",
              "repo:${var.github_owner}/${var.github_repo}:pull_request"
            ]
          }
        }
      }
    ]
  })

  tags = merge(local.tags, {
    Name = "${var.project_name}-github-actions-plan-role"
    Role = "ci-plan"
  })
}

resource "aws_iam_role_policy" "github_actions_plan_read" {
  # Purpose-built plan permissions: enough for refresh/plan, not enough to mutate infrastructure.
  name = "${var.project_name}-github-actions-plan-read"
  role = aws_iam_role.github_actions_plan_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadForTerraformRefresh"
        Effect = "Allow"
        Action = [
          "autoscaling:Describe*",
          "cloudwatch:Describe*",
          "cloudwatch:Get*",
          "cloudwatch:List*",
          "ec2:Describe*",
          "elasticloadbalancing:Describe*",
          "iam:Get*",
          "iam:List*",
          "secretsmanager:DescribeSecret",
          "ssm:Describe*",
          "ssm:GetParameter"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy" "github_actions_backend_access" {
  # Terraform plan still needs write access to the backend object and lockfile.
  name = "${var.project_name}-github-actions-backend-access"
  role = aws_iam_role.github_actions_plan_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ListStateBucket"
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = "arn:aws:s3:::${var.tf_state_bucket_name}"
        Condition = {
          StringLike = {
            "s3:prefix" = [
              var.tf_state_key,
              "${var.tf_state_key}.tflock"
            ]
          }
        }
      },
      {
        Sid    = "ReadWriteStateObjects"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = [
          "arn:aws:s3:::${var.tf_state_bucket_name}/${var.tf_state_key}",
          "arn:aws:s3:::${var.tf_state_bucket_name}/${var.tf_state_key}.tflock"
        ]
      }
    ]
  })
}

# Apply role is intentionally separate from the read/plan role.
# The trust policy is bound to a GitHub Environment subject, so the workflow must
# pass GitHub Environment protection before AWS STS will issue credentials.
resource "aws_iam_role" "github_actions_apply_role" {
  name = "${var.project_name}-github-actions-apply-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Federated = local.github_oidc_provider_arn
        }

        Action = "sts:AssumeRoleWithWebIdentity"

        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }

          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_owner}/${var.github_repo}:environment:${var.github_apply_environment}"
          }
        }
      }
    ]
  })

  tags = merge(local.tags, {
    Name = "${var.project_name}-github-actions-apply-role"
    Role = "ci-apply"
  })
}

resource "aws_iam_role_policy" "github_actions_apply_scoped" {
  # Lesson 71 replaces AdministratorAccess with a scoped policy for this lab stack.
  # Some AWS APIs, especially Describe/List operations and several EC2 mutations,
  # do not support tight resource-level scoping; keep the action list narrow instead.
  name = "${var.project_name}-github-actions-apply-scoped"
  role = aws_iam_role.github_actions_apply_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ListStateBucket"
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = "arn:aws:s3:::${var.tf_state_bucket_name}"
        Condition = {
          StringLike = {
            "s3:prefix" = [
              var.tf_state_key,
              "${var.tf_state_key}.tflock"
            ]
          }
        }
      },
      {
        Sid    = "ReadWriteStateObjects"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = [
          "arn:aws:s3:::${var.tf_state_bucket_name}/${var.tf_state_key}",
          "arn:aws:s3:::${var.tf_state_bucket_name}/${var.tf_state_key}.tflock"
        ]
      },
      {
        Sid    = "ReadForTerraformRefresh"
        Effect = "Allow"
        Action = [
          "autoscaling:Describe*",
          "cloudwatch:Describe*",
          "cloudwatch:Get*",
          "cloudwatch:List*",
          "ec2:Describe*",
          "elasticloadbalancing:Describe*",
          "iam:Get*",
          "iam:List*",
          "secretsmanager:DescribeSecret",
          "ssm:Describe*",
          "ssm:GetParameter"
        ]
        Resource = "*"
      },
      {
        Sid    = "ManageLabEc2NetworkAndInstances"
        Effect = "Allow"
        Action = [
          "ec2:CreateVpc",
          "ec2:DeleteVpc",
          "ec2:ModifyVpcAttribute",
          "ec2:CreateSubnet",
          "ec2:DeleteSubnet",
          "ec2:ModifySubnetAttribute",
          "ec2:CreateInternetGateway",
          "ec2:AttachInternetGateway",
          "ec2:DetachInternetGateway",
          "ec2:DeleteInternetGateway",
          "ec2:CreateRouteTable",
          "ec2:DeleteRouteTable",
          "ec2:CreateRoute",
          "ec2:DeleteRoute",
          "ec2:AssociateRouteTable",
          "ec2:DisassociateRouteTable",
          "ec2:CreateSecurityGroup",
          "ec2:DeleteSecurityGroup",
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:AuthorizeSecurityGroupEgress",
          "ec2:RevokeSecurityGroupIngress",
          "ec2:RevokeSecurityGroupEgress",
          "ec2:ModifySecurityGroupRules",
          "ec2:CreateLaunchTemplate",
          "ec2:CreateLaunchTemplateVersion",
          "ec2:ModifyLaunchTemplate",
          "ec2:DeleteLaunchTemplate",
          "ec2:RunInstances",
          "ec2:TerminateInstances",
          "ec2:CreateTags",
          "ec2:DeleteTags"
        ]
        Resource = "*"
      },
      {
        Sid    = "ManageLabLoadBalancing"
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:CreateLoadBalancer",
          "elasticloadbalancing:DeleteLoadBalancer",
          "elasticloadbalancing:CreateTargetGroup",
          "elasticloadbalancing:DeleteTargetGroup",
          "elasticloadbalancing:CreateListener",
          "elasticloadbalancing:DeleteListener",
          "elasticloadbalancing:ModifyListener",
          "elasticloadbalancing:ModifyLoadBalancerAttributes",
          "elasticloadbalancing:ModifyTargetGroup",
          "elasticloadbalancing:ModifyTargetGroupAttributes",
          "elasticloadbalancing:AddTags",
          "elasticloadbalancing:RemoveTags"
        ]
        Resource = "*"
      },
      {
        Sid    = "ManageLabAutoScaling"
        Effect = "Allow"
        Action = [
          "autoscaling:CreateAutoScalingGroup",
          "autoscaling:UpdateAutoScalingGroup",
          "autoscaling:DeleteAutoScalingGroup",
          "autoscaling:CreateOrUpdateTags",
          "autoscaling:DeleteTags",
          "autoscaling:PutScalingPolicy",
          "autoscaling:DeletePolicy",
          "autoscaling:StartInstanceRefresh",
          "autoscaling:CancelInstanceRefresh"
        ]
        Resource = "*"
      },
      {
        Sid    = "ManageLabCloudWatchAlarms"
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricAlarm",
          "cloudwatch:DeleteAlarms",
          "cloudwatch:TagResource",
          "cloudwatch:UntagResource"
        ]
        Resource = "*"
      },
      {
        Sid    = "ManageLabIamRolesAndPolicies"
        Effect = "Allow"
        Action = [
          "iam:CreateRole",
          "iam:DeleteRole",
          "iam:UpdateAssumeRolePolicy",
          "iam:TagRole",
          "iam:UntagRole",
          "iam:AttachRolePolicy",
          "iam:DetachRolePolicy",
          "iam:PutRolePolicy",
          "iam:DeleteRolePolicy",
          "iam:CreateInstanceProfile",
          "iam:DeleteInstanceProfile",
          "iam:AddRoleToInstanceProfile",
          "iam:RemoveRoleFromInstanceProfile",
          "iam:TagInstanceProfile"
        ]
        Resource = [
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.project_name}-*",
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:instance-profile/${var.project_name}-*"
        ]
      },
      {
        Sid      = "CreateRequiredServiceLinkedRoles"
        Effect   = "Allow"
        Action   = "iam:CreateServiceLinkedRole"
        Resource = "*"
        Condition = {
          StringEquals = {
            "iam:AWSServiceName" = [
              "autoscaling.amazonaws.com",
              "elasticloadbalancing.amazonaws.com"
            ]
          }
        }
      },
      {
        Sid      = "PassOnlyLabRuntimeRolesToEc2"
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.project_name}-ec2-ssm-role"
        Condition = {
          StringEquals = {
            "iam:PassedToService" = "ec2.amazonaws.com"
          }
        }
      }
    ]
  })
}
