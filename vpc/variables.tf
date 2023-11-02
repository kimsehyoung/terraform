variable "name" {
    description = "Name to be used on all the resources as identifier"
    type        = string
    default     = ""
}

variable "vpc_cidr" {
    description = "The IPv4 CIDR block for the VPC."
    type        = string
    default     = "10.0.0.0/16"
}

variable "azs_count" {
    description = "The number of availability zones in the region"
    type        = number
    default     = 3
}

variable "enalbe_dns" {
    description = "Enabling DNS support and hostnames in the VPC"
    type        = bool
    default     = true
}

variable "single_nat_gateway" {
    description = "The number of nat gateway will be either single or azs_count"
    type        = bool
    default     = true
}

variable "additional_tags" {
    description = "Additional resource tags"
    type        = map(string)
    default     = {}
}