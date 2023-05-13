data "archive_file" "autoscale_tfc_agent_ecs_task" {
  type        = "zip"
  source_file = "${path.module}/script/autoscale_tfc_agent_ecs_task.py"
  output_path = "${path.module}/script/autoscale_tfc_agent_ecs_task.zip"
}

resource "aws_s3_bucket" "autoscale_tfc_agent_ecs_task" {
  bucket = "${module.this.id}-tfc-agent-ecs-task-autoscaler-code"
}

resource "aws_s3_bucket_object" "autoscale_tfc_agent_ecs_task" {
  bucket = aws_s3_bucket.autoscale_tfc_agent_ecs_task.id
  key    = "v${var.lambda_code_version}/autoscale_tfc_agent_ecs_task.zip"
  source = data.archive_file.autoscale_tfc_agent_ecs_task.output_path

  etag = filemd5(data.archive_file.autoscale_tfc_agent_ecs_task.output_path)
}

resource "aws_lambda_function" "autoscale_tfc_agent_ecs_task" {
  function_name           = "${module.this.id}-tfc-agent-ecs-task-autoscaler"
  description             = "Receives webhook notifications from TFC and automatically adjusts the number of TFC agents running in ECS"
  code_signing_config_arn = aws_lambda_code_signing_config.this.arn
  role                    = aws_iam_role.lambda_exec.arn
  handler                 = "autoscale_tfc_agent_ecs_task.lambda_handler"
  runtime                 = "python3.7"

  s3_bucket = aws_s3_bucket.autoscale_tfc_agent_ecs_task.id
  s3_key    = aws_s3_bucket_object.autoscale_tfc_agent_ecs_task.id

  environment {
    variables = {
      ECS_CLUSTER_NAME                      = aws_ecs_cluster.tfc_agent.name
      ECS_SERVICE_NAME                      = aws_ecs_service.tfc_agent.name
      REGION                                = var.aws_regiom
      MAX_AGENTS                            = var.max_tfc_agent_count
      NOTIFICATION_TOKEN_SSM_PARAMETER_NAME = aws_ssm_parameter.notification_token.name
      TFC_CURRENT_COUNT_SSM_PARAMETER_NAME  = aws_ssm_parameter.tfc_agent_current_count.name
    }
  }
}

resource "aws_ssm_parameter" "tfc_agent_current_count" {
  name        = "/${module.this.id}/tfc/agent-current-count"
  description = "Terraform Cloud agent current count"
  type        = "String"
  value       = var.desired_count
}

resource "aws_ssm_parameter" "notification_token" {
  name        = "/${module.this.id}/tfc/notification-token"
  description = "Terraform Cloud webhook notification token"
  type        = "SecureString"
  value       = var.notification_token
}

#--
# IAM 
#--

data "aws_iam_policy_document" "assume_role_policy_definition" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      identifiers = ["lambda.amazonaws.com"]
      type        = "Service"
    }
  }
}

data "aws_iam_policy_document" "lambda_policy_definition" {
  statement {
    effect    = "Allow"
    actions   = ["ssm:GetParameter"]
    resources = [aws_ssm_parameter.notification_token.arn, aws_ssm_parameter.tfc_agent_current_count.arn]
  }
  statement {
    effect    = "Allow"
    actions   = ["ssm:PutParameter"]
    resources = [aws_ssm_parameter.current_count.arn]
  }
  statement {
    effect    = "Allow"
    actions   = ["ecs:DescribeServices", "ecs:UpdateService"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "lambda_policy" {
  role   = aws_iam_role.lambda_exec.name
  name   = "${module.this.id}-tfc-agent-ecs-task-autoscaler-policy"
  policy = data.aws_iam_policy_document.lambda_policy_definition.json
}

resource "aws_iam_role" "lambda_exec" {
  name = "${module.this.id}-tfc-agent-ecs-task-autoscaler"

  assume_role_policy = data.aws_iam_policy_document.assume_role_policy_definition.json
}

resource "aws_iam_role_policy_attachment" "cloudwatch_lambda_attachment" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
}

resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.webhook.function_name
  principal     = "apigateway.amazonaws.com"

  # The "/*/*" portion grants access from any method on any resource
  # within the API Gateway REST API.
  source_arn = "${aws_api_gateway_rest_api.webhook.execution_arn}/*/*"
}

# api gateway
resource "aws_api_gateway_rest_api" "webhook" {
  name        = "${module.this.id}-webhook"
  description = "TFC webhook receiver for autoscaling tfc-agent"
}

resource "aws_api_gateway_resource" "proxy" {
  rest_api_id = aws_api_gateway_rest_api.webhook.id
  parent_id   = aws_api_gateway_rest_api.webhook.root_resource_id
  path_part   = "{proxy+}"
}

resource "aws_api_gateway_method" "proxy" {
  rest_api_id   = aws_api_gateway_rest_api.webhook.id
  resource_id   = aws_api_gateway_resource.proxy.id
  http_method   = "ANY"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "lambda" {
  rest_api_id = aws_api_gateway_rest_api.webhook.id
  resource_id = aws_api_gateway_method.proxy.resource_id
  http_method = aws_api_gateway_method.proxy.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.webhook.invoke_arn
}

resource "aws_api_gateway_method" "proxy_root" {
  rest_api_id   = aws_api_gateway_rest_api.webhook.id
  resource_id   = aws_api_gateway_rest_api.webhook.root_resource_id
  http_method   = "ANY"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "lambda_root" {
  rest_api_id = aws_api_gateway_rest_api.webhook.id
  resource_id = aws_api_gateway_method.proxy_root.resource_id
  http_method = aws_api_gateway_method.proxy_root.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.webhook.invoke_arn
}

resource "aws_api_gateway_deployment" "webhook" {
  depends_on = [
    aws_api_gateway_integration.lambda,
    aws_api_gateway_integration.lambda_root,
  ]

  rest_api_id = aws_api_gateway_rest_api.webhook.id
  stage_name  = "test"
}

resource "aws_signer_signing_profile" "this" {
  platform_id = "AWSLambda-SHA384-ECDSA"
}

resource "aws_lambda_code_signing_config" "this" {
  allowed_publishers {
    signing_profile_version_arns = [
      aws_signer_signing_profile.this.arn,
    ]
  }

  policies {
    untrusted_artifact_on_deployment = "Warn"
  }
}


variable "lambda_code_version" {
  description = "An version identifier for the Python script (Lambda function code), you will increase this version as you make changes to the script. Default = 1.0.0"
  type        = string
  default     = "1.0.0"
}

variable "max_tfc_agent_count" {
  description = "(autoscalling with Lambda) Maximum number of Terraform Cloud agents to run. Default = 2"
  default     = 2
}

variable "notification_token" {
  description = "Used to generate the HMAC on the notification request. Read more in the documentation."
  default     = "ArandomStriNg"
}
