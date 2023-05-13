# BigFantech-Cloud

We automate your infrastructure.
You will have full control of your infrastructure, including Infrastructure as Code (IaC).

To hire, email: `bigfantech@yahoo.com`

# Purpose of this code

> Terraform module

Setup Terraform Cloud Agent in ECS FARGATE cluster

## Required Providers

| Name                | Description |
| ------------------- | ----------- |
| aws (hashicorp/aws) | >= 4.47     |

## Variables

### Required Variables

| Name              | Description                                | Type         | Default |
| ----------------- | ------------------------------------------ | ------------ | ------- |
| `project_name`    | | string       |         |
| `tfc_agent_token` | Terraform Cloud Agent Token                | string       |         |
| `aws_region`      | AWS region where the resources are created | string       |         |
| `vpc_id`          | VPC to deploy agent into                   | string       |         |
| `subnet_ids`      | List of Subnet IDs to deploy agent into    | list(string) |         |

### Optional Variables

| Name                               | Description                                                                                            | Type                                                                                   | Default                                                               |
| ---------------------------------- | ------------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------- | --------------------------------------------------------------------- |
| `task_cpu`                         | ECS Task CPU units                                                                                     | number                                                                                 | 2048                                                                  |
| `task_memory`                      | ECS Task memory (in MiB)                                                                               | number                                                                                 | 4096                                                                  |
| `container_cpu`                    | Container CPU units                                                                                    | number                                                                                 | 1024                                                                  |
| `container_memory`                 | Container memory (in MiB)                                                                              | number                                                                                 | 2048                                                                  |
| `capacity_provider_strategies`     | List of ECS Service Capacity Provider Strategies                                                       | list(object({<br>capacity_provider = string<br>weight = number<br>base = number<br>})) | [{<br>capacity_provider = "FARGATE"<br>weight = 100<br>base = 1<br>}] |
| `desired_count`                    | Desired number of Terraform Cloud agents to run. Set this lower as desired if using lambda autoscaling | number                                                                                 | 1                                                                     |
| `lambda_app_version`               | Version of lambda to deploy                                                                            | string                                                                                 | 1.0.0                                                                 |
| `max_tfc_agent_count`              | (autoscalling with Lambda) Maximum number of Terraform Cloud agents to run                             | number                                                                                 | 2                                                                     |
| `cloudwatch_log_retention_in_days` | ECS CloudWatch log retention in days                                                                   | number                                                                                 | 90                                                                    |

### Example config

> Check the `example` folder in this repo

## References

- [Terraform Cloud Agents](https://www.terraform.io/docs/cloud/workspaces/agent.html)
- [Agent Pools and Agents API](https://www.terraform.io/docs/cloud/api/agents.html)
- [Agent Tokens API](https://www.terraform.io/docs/cloud/api/agent-tokens.html)
