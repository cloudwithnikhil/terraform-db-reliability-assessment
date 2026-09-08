resource "aws_security_group" "rds" {
  name        = "${var.name}-rds-sg"
  description = "Private RDS security group"
  vpc_id      = var.vpc_id

  ingress {
    description     = "PostgreSQL only from ECS tasks"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [var.ecs_security_group_id]
  }

  egress {
    description = "Default RDS egress"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name}-rds-sg"
  }
}

resource "aws_db_subnet_group" "this" {
  name       = "${var.name}-db-subnets"
  subnet_ids = var.private_subnet_ids

  tags = {
    Name = "${var.name}-db-subnets"
  }
}

resource "aws_db_instance" "this" {
  identifier = "${var.name}-postgres"

  engine         = "postgres"
  engine_version = var.engine_version

  instance_class        = var.instance_class
  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password
  port     = 5432

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false

  multi_az                  = var.multi_az
  backup_retention_period   = var.backup_retention_days
  deletion_protection      = var.deletion_protection
  skip_final_snapshot       = var.skip_final_snapshot
  copy_tags_to_snapshot     = true
  auto_minor_version_upgrade = true

  backup_window      = "03:00-04:00"
  maintenance_window = "sun:04:00-sun:05:00"

  tags = {
    Name        = "${var.name}-postgres"
    Environment = var.environment
  }
}
