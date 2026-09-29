# REST API with a REGIONAL endpoint.
# Important (from the talk): the default EDGE type puts a hidden CloudFront
# distribution in front of the API, which breaks per-region latency routing.
resource "aws_api_gateway_rest_api" "this" {
  name = "${var.name_prefix}-notes-api"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

# /notes
resource "aws_api_gateway_resource" "notes" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_rest_api.this.root_resource_id
  path_part   = "notes"
}

# /notes/{id}
resource "aws_api_gateway_resource" "note" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_resource.notes.id
  path_part   = "{id}"
}

# /health  (used by the Route 53 health check)
resource "aws_api_gateway_resource" "health" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_rest_api.this.root_resource_id
  path_part   = "health"
}

locals {
  routes = {
    create = { resource_id = aws_api_gateway_resource.notes.id, method = "POST", fn = "createNote" }
    get    = { resource_id = aws_api_gateway_resource.note.id, method = "GET", fn = "getNote" }
    update = { resource_id = aws_api_gateway_resource.note.id, method = "PUT", fn = "updateNote" }
    delete = { resource_id = aws_api_gateway_resource.note.id, method = "DELETE", fn = "deleteNote" }
    health = { resource_id = aws_api_gateway_resource.health.id, method = "GET", fn = "health" }
  }
}

resource "aws_api_gateway_method" "route" {
  for_each = local.routes

  rest_api_id   = aws_api_gateway_rest_api.this.id
  resource_id   = each.value.resource_id
  http_method   = each.value.method
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "route" {
  for_each = local.routes

  rest_api_id             = aws_api_gateway_rest_api.this.id
  resource_id             = each.value.resource_id
  http_method             = aws_api_gateway_method.route[each.key].http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.fn[each.value.fn].invoke_arn
}

resource "aws_api_gateway_deployment" "this" {
  rest_api_id = aws_api_gateway_rest_api.this.id

  triggers = {
    redeploy = sha1(jsonencode([
      aws_api_gateway_resource.notes,
      aws_api_gateway_resource.note,
      aws_api_gateway_resource.health,
      aws_api_gateway_method.route,
      aws_api_gateway_integration.route,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "this" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  deployment_id = aws_api_gateway_deployment.this.id
  stage_name    = var.stage_name
}
