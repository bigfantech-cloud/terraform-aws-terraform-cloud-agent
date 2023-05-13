module "tfc_agent" {
  source       = "bigfantech-cloud/ecs-terraform-cloud-agent/aws"
  # version      = "a.b.c" find the latest version from https://registry.terraform.io/modules/bigfantech-cloud/ecs-terraform-cloud-agent/aws/latest
  
  product_name    = "abc"
  desired_count   = 2
  vpc_id          = "vpc-123vpcid"
  subnet_ids      = ["sub-123subnerid"]
  tfc_agent_token = "1234-abcd" # token is specified here for sake of this example, in actual setup it must be treated as secure value in the actual setup
  
  capacity_provider_strategies  = [
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
}
