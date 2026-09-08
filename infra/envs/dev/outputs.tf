output "vpc_id" {
  value = module.network.vpc_id
}

output "alb_dns_name" {
  value = module.ecs.load_balancer_dns_name
}

output "ecs_cluster_name" {
  value = module.ecs.cluster_name
}

output "ecs_service_name" {
  value = module.ecs.service_name
}

output "rds_endpoint" {
  value = module.rds.rds_endpoint
}

output "rds_port" {
  value = module.rds.rds_port
}
