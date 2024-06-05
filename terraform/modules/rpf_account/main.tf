data "aws_caller_identity" "current" {}
data "aws_region" "now" {}
locals {
  account_id  = data.aws_caller_identity.current.account_id
  region      = data.aws_region.now.name
  system_name = "rpf-301"
}

variable "stage" {
  type    = string
  default = "dev"
}

data "template_file" "swagger" {
  template = file("../../../../account/document/webapi.yaml")

  vars = {
    account_id = local.account_id
    region     = local.region
    stage      = var.stage
  }
}

resource "aws_api_gateway_rest_api" "main" {
  name        = "RPF-301"
  description = "WebAPI for RPF-301"
  body        = data.template_file.swagger.rendered

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  lifecycle {
    ignore_changes = [
      # OpenAPI spec の変更でデプロイしたい場合は空にする、デプロイしたくない場合は body を指定する
      # REPLACE_IF_IGNORE_OPENAPI_CHANGES
    ]
  }
}

resource "aws_api_gateway_deployment" "main" {
  rest_api_id = aws_api_gateway_rest_api.main.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_rest_api.main.body,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "main" {
  stage_name            = var.stage
  rest_api_id           = aws_api_gateway_rest_api.main.id
  deployment_id         = aws_api_gateway_deployment.main.id
  cache_cluster_enabled = false
  cache_cluster_size    = "0.5"
}

resource "aws_iam_role" "main" {
  name = "${local.system_name}-lambda-role-${var.stage}"
  managed_policy_arns = [
    "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess",
    "arn:aws:iam::aws:policy/AmazonCognitoPowerUser"
  ]

  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Action" : "sts:AssumeRole",
        "Effect" : "Allow",
        "Principal" : {
          "Service" : "lambda.amazonaws.com"
        }
      }
    ]
  })

  inline_policy {
    name = "${local.system_name}-lambda-role-inline-${var.stage}"
    policy = jsonencode({
      "Version" : "2012-10-17",
      "Statement" : [
        {
          "Action" : [
            "logs:CreateLogStream",
            "logs:CreateLogGroup"
          ],
          "Resource" : [
            "arn:aws:logs:${local.region}:${local.account_id}:log-group:/aws/lambda/${local.system_name}-*:*"
          ],
          "Effect" : "Allow"
        },
        {
          "Action" : [
            "logs:PutLogEvents"
          ],
          "Resource" : [
            "arn:aws:logs:${local.region}:${local.account_id}:log-group:/aws/lambda/${local.system_name}-*:*"
          ],
          "Effect" : "Allow"
        },
        {
          "Action" : [
            "secretsmanager:GetSecretValue"
          ],
          "Resource" : "*",
          "Effect" : "Allow"
        }
      ]
    })
  }
}

resource "aws_cloudwatch_log_group" "main" {
  name              = "/aws/lambda/${local.system_name}-${var.stage}"
  retention_in_days = 30
}

data "archive_file" "test_terraform" {
  type        = "zip"
  source_dir  = "../../../../account/backend"
  output_path = "../../../../account/lambda.zip"
}

resource "aws_lambda_function" "main" {
  depends_on = [
    aws_iam_role.main,
  ]
  function_name    = "${local.system_name}-${var.stage}"
  filename         = data.archive_file.test_terraform.output_path
  source_code_hash = data.archive_file.test_terraform.output_base64sha256
  runtime          = "python3.11"
  handler          = "handler.lambda_handler"
  role             = aws_iam_role.main.arn

  lifecycle {
    ignore_changes = [
      environment,
      source_code_hash,
      memory_size,
      tags,
      tags_all,
      timeout,
    ]
  }
}

resource "aws_lambda_alias" "main" {
  depends_on = [
    aws_lambda_function.main
  ]
  name             = var.stage
  function_name    = "${local.system_name}-${var.stage}"
  function_version = "$LATEST"

  lifecycle {
    ignore_changes = [
      function_version,
    ]
  }
}
