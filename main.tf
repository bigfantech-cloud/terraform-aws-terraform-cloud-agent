resource "aws_ecs_cluster" "tfc_agent" {
  name = "${module.this.id}-tfc-agent"
}

resource "aws_ecs_cluster_capacity_providers" "custom" {
  cluster_name       = aws_ecs_cluster.tfc_agent.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]
}

resource "aws_cloudwatch_log_group" "default" {
  name              = "ecs/tfc-agent"
  retention_in_days = var.cloudwatch_log_retention_in_days

  tags = module.this.tags
}

resource "aws_cloudwatch_log_stream" "default" {
  name           = module.this.id
  log_group_name = aws_cloudwatch_log_group.default.name
}

resource "aws_ecs_service" "tfc_agent" {
  name            = "tfc-agent"
  launch_type     = "FARGATE"
  cluster         = aws_ecs_cluster.tfc_agent.id
  task_definition = aws_ecs_task_definition.tfc_agent.arn
  desired_count   = var.desired_count
  network_configuration {
    security_groups  = [aws_security_group.tfc_agent.id]
    subnets          = var.subnet_ids
    assign_public_ip = true
  }

  dynamic "capacity_provider_strategy" {
    for_each = var.capacity_provider_strategies
    content {
      capacity_provider = capacity_provider_strategy.value.capacity_provider
      weight            = capacity_provider_strategy.value.weight
      base              = capacity_provider_strategy.value.base
    }
  }
}

resource "aws_ecs_task_definition" "tfc_agent" {
  family                   = module.this.id
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.agent.arn
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  container_definitions = jsonencode(
    [
      {
        name      = "tfc-agent"
        image     = "hashicorp/tfc-agent:latest"
        essential = true
        cpu       = var.container_cpu
        memory    = var.container_memory

        logConfiguration = {
          logDriver = "awslogs",
          options = {
            awslogs-create-group  = "false",
            awslogs-group         = aws_cloudwatch_log_group.default.name
            awslogs-region        = var.aws_region
            awslogs-stream-prefix = aws_cloudwatch_log_stream.default.name
          }
        }

        environment = [
          {
            name  = "TFC_AGENT_SINGLE",
            value = "true"
          },
          {
            name  = "TFC_AGENT_NAME",
            value = "${module.this.id}-ecs-fargate"
          }
        ]

        secrets = [
          {
            name      = "TFC_AGENT_TOKEN",
            valueFrom = aws_ssm_parameter.agent_token.arn
          }
        ]
      }
    ]
  )
}

resource "aws_ssm_parameter" "agent_token" {
  name        = "/${module.this.id}/tfc-agent-token"
  description = "Terraform Cloud agent token"
  type        = "SecureString"
  value       = var.tfc_agent_token
}

#---
# IAM
#---

# TAST EXECUTION ROLE

data "aws_iam_policy_document" "agent_assume_role_policy_definition" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      identifiers = ["ecs-tasks.amazonaws.com"]
      type        = "Service"
    }
  }
}

resource "aws_iam_role" "task_execution" {
  name               = "${module.this.id}-ecs-tfc-agent-task-execution-role"
  assume_role_policy = data.aws_iam_policy_document.agent_assume_role_policy_definition.json
}

resource "aws_iam_role_policy" "task_execution_policy" {
  role   = aws_iam_role.task_execution.name
  name   = "AccessSSMParameterforAgentToken"
  policy = data.aws_iam_policy_document.task_execution_policy.json
}

resource "aws_iam_role_policy_attachment" "task_execution_policy" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "task_execution_policy" {
  statement {
    effect    = "Allow"
    actions   = ["ssm:GetParameters"]
    resources = [aws_ssm_parameter.agent_token.arn]
  }
}

# TASK ROLE

resource "aws_iam_role" "task" {
  name               = "${module.this.id}-ecs-tfc-agent-tak-role"
  assume_role_policy = data.aws_iam_policy_document.agent_assume_role_policy_definition.json
}

resource "aws_iam_role_policy_attachment" "agent_task_admin_policy" {
  role       = aws_iam_role.task.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# networking for agents to reach internet
data "aws_vpc" "main" {
  id = var.vpc_id
}

resource "aws_security_group" "tfc_agent" {
  name_prefix = "${module.this.id}-tfc-agent-sg"
  description = "Security group for TFC agent VPC"
  vpc_id      = var.vpc_id
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "allow_egress" {
  security_group_id = aws_security_group.tfc_agent.id
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
}

# from here to EOF is optional, for lambda autoscaling
# resource "aws_lambda_function" "webhook" {
#   function_name           = "${module.this.id}-webhook"
#   description             = "Receives webhook notifications from TFC and automatically adjusts the number of tfc agents running."
#   code_signing_config_arn = aws_lambda_code_signing_config.this.arn
#   role                    = aws_iam_role.lambda_exec.arn
#   handler                 = "main.lambda_handler"
#   runtime                 = "python3.7"

#   s3_bucket = aws_s3_bucket.webhook.bucket
#   s3_key    = aws_s3_bucket_object.webhook.id

#   environment {
#     variables = {
#       CLUSTER        = aws_ecs_cluster.tfc_agent.name
#       MAX_AGENTS     = var.max_tfc_agent_count
#       REGION         = var.aws_region
#       SALT_PATH      = aws_ssm_parameter.notification_token.name
#       SERVICE        = aws_ecs_service.tfc_agent.name
#       SSM_PARAM_NAME = aws_ssm_parameter.current_count.name
#     }
#   }
# }

# resource "aws_ssm_parameter" "current_count" {
#   name        = "${module.this.id}-tfc-agent-current-count"
#   description = "Terraform Cloud agent current count"
#   type        = "String"
#   value       = var.desired_count
# }

# resource "aws_ssm_parameter" "notification_token" {
#   name        = "${module.this.id}-tfc-notification-token"
#   description = "Terraform Cloud webhook notification token"
#   type        = "SecureString"
#   value       = var.notification_token
# }

# resource "aws_s3_bucket" "webhook" {
#   bucket = module.this.id
#   acl    = "private"
# }

# resource "aws_s3_bucket_object" "webhook" {
#   bucket = aws_s3_bucket.webhook.id
#   key    = "v${var.lambda_app_version}/webhook.zip"
#   source = "${path.module}/files/webhook.zip"

#   etag = filemd5("${path.module}/files/webhook.zip")
# }

# resource "aws_iam_role" "lambda_exec" {
#   name = "${module.this.id}-webhook-lambda"

#   assume_role_policy = data.aws_iam_policy_document.webhook_assume_role_policy_definition.json
# }

# data "aws_iam_policy_document" "webhook_assume_role_policy_definition" {
#   statement {
#     effect  = "Allow"
#     actions = ["sts:AssumeRole"]
#     principals {
#       identifiers = ["lambda.amazonaws.com"]
#       type        = "Service"
#     }
#   }
# }

# resource "aws_iam_role_policy" "lambda_policy" {
#   role   = aws_iam_role.lambda_exec.name
#   name   = "${module.this.id}-lambda-webhook-policy"
#   policy = data.aws_iam_policy_document.lambda_policy_definition.json
# }

# data "aws_iam_policy_document" "lambda_policy_definition" {
#   statement {
#     effect    = "Allow"
#     actions   = ["ssm:GetParameter"]
#     resources = [aws_ssm_parameter.notification_token.arn, aws_ssm_parameter.current_count.arn]
#   }
#   statement {
#     effect    = "Allow"
#     actions   = ["ssm:PutParameter"]
#     resources = [aws_ssm_parameter.current_count.arn]
#   }
#   statement {
#     effect    = "Allow"
#     actions   = ["ecs:DescribeServices", "ecs:UpdateService"]
#     resources = ["*"]
#   }
# }

# resource "aws_iam_role_policy_attachment" "cloudwatch_lambda_attachment" {
#   role       = aws_iam_role.lambda_exec.name
#   policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
# }

# resource "aws_lambda_permission" "apigw" {
#   statement_id  = "AllowAPIGatewayInvoke"
#   action        = "lambda:InvokeFunction"
#   function_name = aws_lambda_function.webhook.function_name
#   principal     = "apigateway.amazonaws.com"

#   # The "/*/*" portion grants access from any method on any resource
#   # within the API Gateway REST API.
#   source_arn = "${aws_api_gateway_rest_api.webhook.execution_arn}/*/*"
# }

# # api gateway
# resource "aws_api_gateway_rest_api" "webhook" {
#   name        = "${module.this.id}-webhook"
#   description = "TFC webhook receiver for autoscaling tfc-agent"
# }

# resource "aws_api_gateway_resource" "proxy" {
#   rest_api_id = aws_api_gateway_rest_api.webhook.id
#   parent_id   = aws_api_gateway_rest_api.webhook.root_resource_id
#   path_part   = "{proxy+}"
# }

# resource "aws_api_gateway_method" "proxy" {
#   rest_api_id   = aws_api_gateway_rest_api.webhook.id
#   resource_id   = aws_api_gateway_resource.proxy.id
#   http_method   = "ANY"
#   authorization = "NONE"
# }

# resource "aws_api_gateway_integration" "lambda" {
#   rest_api_id = aws_api_gateway_rest_api.webhook.id
#   resource_id = aws_api_gateway_method.proxy.resource_id
#   http_method = aws_api_gateway_method.proxy.http_method

#   integration_http_method = "POST"
#   type                    = "AWS_PROXY"
#   uri                     = aws_lambda_function.webhook.invoke_arn
# }

# resource "aws_api_gateway_method" "proxy_root" {
#   rest_api_id   = aws_api_gateway_rest_api.webhook.id
#   resource_id   = aws_api_gateway_rest_api.webhook.root_resource_id
#   http_method   = "ANY"
#   authorization = "NONE"
# }

# resource "aws_api_gateway_integration" "lambda_root" {
#   rest_api_id = aws_api_gateway_rest_api.webhook.id
#   resource_id = aws_api_gateway_method.proxy_root.resource_id
#   http_method = aws_api_gateway_method.proxy_root.http_method

#   integration_http_method = "POST"
#   type                    = "AWS_PROXY"
#   uri                     = aws_lambda_function.webhook.invoke_arn
# }

# resource "aws_api_gateway_deployment" "webhook" {
#   depends_on = [
#     aws_api_gateway_integration.lambda,
#     aws_api_gateway_integration.lambda_root,
#   ]

#   rest_api_id = aws_api_gateway_rest_api.webhook.id
#   stage_name  = "test"
# }

# resource "aws_signer_signing_profile" "this" {
#   platform_id = "AWSLambda-SHA384-ECDSA"
# }

# resource "aws_lambda_code_signing_config" "this" {
#   allowed_publishers {
#     signing_profile_version_arns = [
#       aws_signer_signing_profile.this.arn,
#     ]
#   }

#   policies {
#     untrusted_artifact_on_deployment = "Warn"
#   }
# }
