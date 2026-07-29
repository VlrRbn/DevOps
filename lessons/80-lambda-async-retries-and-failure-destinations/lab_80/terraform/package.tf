data "archive_file" "function_package" {
  type             = "zip"
  source_file      = "${path.module}/../app/lambda_function.py"
  output_file_mode = "0644"
  output_path      = "${path.module}/.terraform/lambda_function.zip"
}
