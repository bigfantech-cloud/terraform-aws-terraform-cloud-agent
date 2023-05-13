# output "webhook_url" {
#   description = "Webhook URL if using autoscaling through workspace notifications"
#   value       = aws_api_gateway_deployment.webhook.invoke_url
# }

output "tfc_ecs_task_role_arn" {
  description = "TFC Agent ECS Task IAM role ARN"
  value       = aws_iam_role.agent.arn
}

output "tfc_ecs_task_role_name" {
  description = "TFC Agent ECS Task IAM role name"
  value       = aws_iam_role.agent.name
}

output "tfc_ecs_task_execution_role_arn" {
  description = "TFC Agent ECS Task execution IAM role ARN"
  value       = aws_iam_role.agent_init.arn
}

output "tfc_ecs_task_execution_role_name" {
  description = "TFC Agent ECS Task execution IAM role name"
  value       = aws_iam_role.agent_init.name
}
