data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

locals {
  region = data.aws_region.current.name

  # Same format the talk builds with string concatenation in serverless.yml:
  # arn:aws:dynamodb:<region>:<account>:table/<name>
  # Because each replica is a regional table, every region's Lambdas are only
  # granted access to their LOCAL replica.
  table_arn = "arn:aws:dynamodb:${local.region}:${data.aws_caller_identity.current.account_id}:table/${var.table_name}"

  functions = {
    getNote    = { handler = "notes.getNote" }
    createNote = { handler = "notes.createNote" }
    updateNote = { handler = "notes.updateNote" }
    deleteNote = { handler = "notes.deleteNote" }
    health     = { handler = "notes.health" }
  }
}

# --- IAM ---------------------------------------------------------------------
data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda" {
  # IAM is global: include the region so both regional stacks can coexist.
  name               = "${var.name_prefix}-${local.region}-lambda"
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

resource "aws_iam_role_policy_attachment" "logs" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "dynamodb" {
  statement {
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:DeleteItem",
    ]
    resources = [local.table_arn]
  }
}

resource "aws_iam_role_policy" "dynamodb" {
  name   = "dynamodb-local-replica"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.dynamodb.json
}

# --- Functions -----------------------------------------------------------------
resource "aws_cloudwatch_log_group" "fn" {
  for_each          = local.functions
  name              = "/aws/lambda/${var.name_prefix}-${each.key}"
  retention_in_days = var.log_retention_days
}

resource "aws_lambda_function" "fn" {
  for_each = local.functions

  function_name    = "${var.name_prefix}-${each.key}"
  role             = aws_iam_role.lambda.arn
  runtime          = "nodejs20.x"
  handler          = each.value.handler
  filename         = var.lambda_zip_path
  source_code_hash = var.lambda_zip_hash
  timeout          = 10
  memory_size      = 256
  architectures    = ["arm64"]

  environment {
    variables = {
      TABLE_NAME = var.table_name
      # AWS_REGION is injected automatically by Lambda - the code stamps it
      # on each note so you can see which region served the write.
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.fn,
    aws_iam_role_policy_attachment.logs,
  ]
}

resource "aws_lambda_permission" "apigw" {
  for_each = local.functions

  statement_id  = "AllowApiGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.fn[each.key].function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.this.execution_arn}/*/*"
}
