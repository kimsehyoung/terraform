resource "aws_security_group" "database" {
    name = "${var.identifier}-database-sg"
    vpc_id = var.vpc_id
    
    ingress {
        from_port   = var.port
        to_port     = var.port
        protocol    = "tcp"
        cidr_blocks = [var.vpc_cidr]
    }
    egress {
        from_port   = 0
        to_port     = 0
        protocol    = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }
}

resource "aws_db_instance" "this" {
    identifier           = "${var.identifier}-database"
    engine               = var.engine
    engine_version       = var.engine_version
    parameter_group_name = var.parameter_group_name
    instance_class       = var.instance_class
    multi_az             = var.multi_az

    username = var.username
    password = var.password
    db_name  = var.db_name
    port     = var.port

    storage_type          = var.storage_type
    allocated_storage     = var.allocated_storage
    max_allocated_storage = var.max_allocated_storage

    db_subnet_group_name   = var.db_subnet_group_name
    publicly_accessible    = var.publicly_accessible
    vpc_security_group_ids = [aws_security_group.database.id]

    performance_insights_enabled          = var.performance_insights_enabled
    performance_insights_retention_period = var.performance_insights_enabled ? var.performance_insights_retention_period : null

    backup_retention_period = var.backup_retention_period

    allow_major_version_upgrade = var.allow_major_version_upgrade
    auto_minor_version_upgrade  = var.auto_minor_version_upgrade
    deletion_protection         = var.deletion_protection
    skip_final_snapshot         = var.skip_final_snapshot
    final_snapshot_identifier   = var.skip_final_snapshot ? null : var.final_snapshot_identifier
}
