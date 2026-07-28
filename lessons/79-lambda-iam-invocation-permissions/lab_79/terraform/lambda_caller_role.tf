# This trust policy controls who may become the Lambda caller role. It grants
# sts:AssumeRole, not permission to invoke Lambda.
data "aws_iam_policy_document" "lambda_caller_trust" {
  statement {
    sid     = "AllowOperatorToAssumeLambdaCallerRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = [var.operator_iam_principal_arn]
    }
  }
}

resource "aws_iam_role" "lambda_caller" {
  name                 = local.lambda_caller_role_name
  assume_role_policy   = data.aws_iam_policy_document.lambda_caller_trust.json
  max_session_duration = 3600
}
