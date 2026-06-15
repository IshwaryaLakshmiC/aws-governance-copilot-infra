# RDS instance already exists — managed outside Terraform lifecycle.
# Use data source to reference it rather than recreating.
# instance: cloud-security-platform-postgres (db.t3.micro, pg 15.17)

resource "aws_db_subnet_group" "main" {
  name       = "${var.project}-db-subnet-group"
  subnet_ids = var.private_subnet_ids
  tags       = merge(var.tags, { Name = "${var.project}-db-subnet-group" })
}

resource "aws_db_parameter_group" "postgres15" {
  name   = "${var.project}-postgres15"
  family = "postgres15"
  parameter {
    name  = "shared_preload_libraries"
    value = "pg_stat_statements"
  }
  tags = var.tags
}

resource "aws_db_instance" "postgres" {
  identifier        = "${var.project}-postgres"
  engine            = "postgres"
  engine_version    = "15"
  instance_class    = "db.t3.micro"
  allocated_storage = 20
  storage_type      = "gp2"

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [var.rds_security_group_id]
  parameter_group_name   = aws_db_parameter_group.postgres15.name

  multi_az                     = false
  publicly_accessible          = false
  deletion_protection          = false
  skip_final_snapshot          = true
  backup_retention_period      = 1
  performance_insights_enabled = false
  monitoring_interval          = 0

  # Prevent Terraform from modifying instance class or engine version
  # since the account has free tier restrictions on modifications
  lifecycle {
    ignore_changes = [
      instance_class,
      engine_version,
      allocated_storage,
    ]
  }

  tags = merge(var.tags, { Name = "${var.project}-postgres" })
}
