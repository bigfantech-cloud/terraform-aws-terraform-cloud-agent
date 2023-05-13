variable "aws_region" {
  description = "AWS region where the resources are created"
}

variable "vpc_id" {
  description = "VPC to deploy agent into"
  type        = string
}

variable "subnet_ids" {
  description = "List of Subnet IDs to deploy agent into"
  type        = list(string)
}

variable "task_cpu" {
  description = "ECS Task CPU units. Default = 2048"
  type        = number
  default     = 2048
}

variable "task_memory" {
  description = "ECS Task memory (in MiB). Default = 4096"
  type        = number
  default     = 4096
}

variable "container_cpu" {
  description = "Container CPU units. Default = 1024"
  type        = number
  default     = 1024
}

variable "container_memory" {
  description = "Container memory (in MiB). Default = 2048"
  type        = number
  default     = 2048
}

variable "capacity_provider_strategies" {
  type = list(object({
    capacity_provider = string
    weight            = number
    base              = number
  }))

  description = <<EOF
    List of ECS Service Capacity Provider Strategies
    example: [
      {
        capacity_provider = "FARGATE"
        weight            = 50
        base              = 1
      },
      {
        capacity_provider = "FARGATE_SPOT"
        weight            = 50
        base              = 0
      },
    ]

    default = [{
      capacity_provider = "FARGATE"
      weight            = 100
      base              = 1
    }]
    EOF

  default = [{
    capacity_provider = "FARGATE"
    weight            = 100
    base              = 1
  }]
}

variable "tfc_agent_token" {
  description = "Terraform Cloud Agent Token"
  type        = string
}

variable "desired_count" {
  description = "Desired number of Terraform Cloud agents to run. Set this lower as desired if using lambda autoscaling. Default = 1"
  type        = number
  default     = 1
}

variable "lambda_app_version" {
  description = "Version of lambda to deploy. Default = 1.0.0"
  type        = string
  default     = "1.0.0"
}

variable "max_tfc_agent_count" {
  description = "(autoscalling with Lambda) Maximum number of Terraform Cloud agents to run. Default = 2"
  default     = 2
}

variable "cloudwatch_log_retention_in_days" {
  description = "ECS CloudWatch log retention in days. Default = 90"
  type        = number
  default     = 90
}
