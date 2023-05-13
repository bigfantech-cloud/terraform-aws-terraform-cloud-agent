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
