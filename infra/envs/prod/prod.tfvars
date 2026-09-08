aws_region = "eu-west-1"
environment = "prod"
name        = "booking-prod"

vpc_cidr             = "10.20.0.0/16"
public_subnet_cidrs  = ["10.20.1.0/24", "10.20.2.0/24"]
private_subnet_cidrs = ["10.20.11.0/24", "10.20.12.0/24"]

single_nat_gateway = false

container_image = "nginx:alpine"
container_port  = 80
task_cpu        = 512
task_memory     = 1024
desired_count   = 2
log_retention_days = 30

rds_engine_version        = "16"
rds_instance_class        = "db.t4g.small"
rds_allocated_storage     = 50
rds_max_allocated_storage = 200
rds_db_name               = "appdb"
rds_username              = "appadmin"
rds_password              = "ChangeMe-Prod-Example-123456!"
rds_backup_retention_days = 14
rds_deletion_protection   = true
rds_multi_az              = true
rds_skip_final_snapshot   = false
