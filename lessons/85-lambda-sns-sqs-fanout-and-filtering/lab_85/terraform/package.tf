data "archive_file" "function_package" {
  type        = "zip"
  source_file = "${path.module}/../app/lambda_function.py"
  output_path = "${path.module}/.build/lambda-function.zip"
}
