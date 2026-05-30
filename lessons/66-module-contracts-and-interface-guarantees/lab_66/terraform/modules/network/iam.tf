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
}

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "runtime_secret_read" {
  statement {
    sid    = "ReadLesson65SecureString"
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
    sid    = "ReadLesson65Secret"
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

resource "aws_iam_role" "github_actions_role" {
  name = "${var.project_name}-github-actions-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Federated = aws_iam_openid_connect_provider.github_actions.arn
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
}

resource "aws_iam_role_policy_attachment" "github_actions_readonly" {
  # Broad read access keeps terraform refresh/plan from failing on Describe/Get APIs.
  role       = aws_iam_role.github_actions_role.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

resource "aws_iam_role_policy" "github_actions_backend_access" {
  # Terraform plan still needs write access to the backend object and lockfile.
  name = "${var.project_name}-github-actions-backend-access"
  role = aws_iam_role.github_actions_role.id

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
