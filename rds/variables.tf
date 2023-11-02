variable "identifier" {
    description = "The name of the RDS instance"
    type        = string
}

variable "engine" {
    description = "The database engine to use"
    type        = string
}

variable "engine_version" {
    description = "The engine version to use"
    type        = string
    default     = null
}

variable "parameter_group_name" {
    description = "Name of the DB parameter group to associate"
    type        = string
    default     = null
}

variable "instance_class" {
    description = "The instance type of the RDS instance"
    type        = string
}

variable "multi_az" {
    description = "Specifies if the RDS instance is multi-AZ"
    type        = bool
    default     = false
}

variable "username" {
    description = "Username for the master DB user"
    type        = string
}

variable "password" {
    description = "Password for the master DB user. Note that this may show up in logs, and it will be stored in the state file"
    type        = string
}

variable "db_name" {
    description = "The DB name to create. If omitted, no database is created initially"
    type        = string
    default     = null
}

variable "port" {
    description = "The port on which the DB accepts connections"
    type        = string
    default     = null
}

################################################################################
# Storage
################################################################################
variable "storage_type" {
    description = "One of 'standard', 'gp2', 'gp3', or 'io1'. The default is 'io1' if iops is specified, 'gp2' if not."
    type        = string
    default     = null
}

variable "allocated_storage" {
    description = "The allocated storage in gigabytes"
    type        = number
    default     = 20
}

variable "max_allocated_storage" {
    description = "Specifies the value for Storage Autoscaling"
    type        = number
    default     = 0
}

################################################################################
# Connectivity
################################################################################
variable "vpc_id" {
    description = "VPC ID"
    type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR"
  type        = string
}

variable "db_subnet_group_name" {
    description = "Name of DB subnet group. If unspecified, will be created in the default VPC."
    type        = string
}

variable "publicly_accessible" {
    description = "Bool to control if instance is publicly accessible"
    type        = bool
    default     = false
}

################################################################################
# Additional configuration
################################################################################
variable "performance_insights_enabled" {
    description = "Specifies whether Performance Insights are enabled"
    type        = bool
    default     = false
}

variable "performance_insights_retention_period" {
    description = "The amount of time in days to retain Performance Insights data. (Default to '7')"
    type        = number
    default     = 7
}

variable "backup_retention_period" {
    description = "The days to retain backups for"
    type        = number
    default     = 0
}

variable "allow_major_version_upgrade" {
    description = "Indicates that major version upgrades are allowed. Changing this parameter does not result in an outage and the change is asynchronously applied as soon as possible"
    type        = bool
    default     = false
}

variable "auto_minor_version_upgrade" {
    description = "Indicates that minor engine upgrades will be applied automatically to the DB instance during the maintenance window"
    type        = bool
    default     = true
}

variable "deletion_protection" {
    description = "The database can't be deleted when this value is set to true."
    type        = bool
    default     = false
}

variable "skip_final_snapshot" {
    description = "Determines whether a final DB snapshot is created before the DB instance is deleted."
    type        = bool
    default     = false
}

variable "final_snapshot_identifier" {
    description = "DB snapshot name. Must be provided if skip_final_snapshot is set to false"
    type        = string
    default     = false
}

variable "tags" {
    description = "tags"
    type        = string
    default     = null
}