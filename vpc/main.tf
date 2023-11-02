data "aws_availability_zones" "available" {
    state = "available"
}

locals {
    azs_count = min(length(data.aws_availability_zones.available.names), var.azs_count)
    azs       = slice(data.aws_availability_zones.available.names, 0, local.azs_count)

    subnet_cidrs          = chunklist([for i in range(local.azs_count * 4) : cidrsubnet(var.vpc_cidr, 8, i)], local.azs_count)
    public_subnet_cidrs   = local.subnet_cidrs[0]
    private_subnet_cidrs  = local.subnet_cidrs[1]
    intra_subnet_cidrs    = local.subnet_cidrs[2]
    database_subnet_cidrs = local.subnet_cidrs[3]

    nat_gateway_count = var.single_nat_gateway ? 1 : local.azs_count
}

################################################################################
# VPC
################################################################################
resource "aws_vpc" "this" {
    cidr_block = var.vpc_cidr
    assign_generated_ipv6_cidr_block = false

    enable_dns_support   = var.enalbe_dns
    enable_dns_hostnames = var.enalbe_dns

    instance_tenancy = "default"

    tags = merge(
        { "Name" = var.name },
        var.additional_tags
    )
}

################################################################################
# Internet Gateway
################################################################################
resource "aws_internet_gateway" "this" {
    vpc_id = aws_vpc.this.id

    tags = merge(
        { "Name" = format("${var.name}/InternetGateway") },
        var.additional_tags
    )
}

################################################################################
# Public Subnets
################################################################################
resource "aws_subnet" "public" {
    count = local.azs_count

    vpc_id = aws_vpc.this.id  
    availability_zone = local.azs[count.index]
    cidr_block = local.public_subnet_cidrs[count.index]

    tags = merge(
        { "Name" = format("${var.name}-public-%s", local.azs[count.index]) },
        var.additional_tags
    )
}

resource "aws_route_table" "public" {
    vpc_id = aws_vpc.this.id

    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = aws_internet_gateway.this.id
    }

    tags = merge(
        { "Name" = "${var.name}-public" },
        var.additional_tags
    )
}

resource "aws_route_table_association" "public" {
    count = length(aws_subnet.public[*].id)

    subnet_id      = element(aws_subnet.public[*].id, count.index)
    route_table_id = aws_route_table.public.id
}

################################################################################
# Private Subnets
################################################################################
resource "aws_subnet" "private" {
    count = local.azs_count

    vpc_id            = aws_vpc.this.id
    availability_zone = local.azs[count.index]
    cidr_block        = local.private_subnet_cidrs[count.index]

    tags = merge(
        { "Name" = format("${var.name}-private-%s", local.azs[count.index]) },
        var.additional_tags
    )
}

resource "aws_route_table" "private" {
    count = length(aws_subnet.private[*].id)

    vpc_id = aws_vpc.this.id
    route {
        cidr_block     = "0.0.0.0/0"
        nat_gateway_id = element(aws_nat_gateway.this[*].id, count.index)
    }

    tags = merge(
        { "Name" = format("${var.name}-private-%s", local.azs[count.index]) },
        var.additional_tags
    )
}

resource "aws_route_table_association" "private" {
    count = length(aws_subnet.private[*].id)

    subnet_id      = element(aws_subnet.private[*].id, count.index)
    route_table_id = element(aws_route_table.private[*].id, count.index)
}

################################################################################
# Intra Subnets
# https://www.youtube.com/watch?v=V8DidcYmNmU
################################################################################
resource "aws_subnet" "intra" {
    count = local.azs_count

    vpc_id            = aws_vpc.this.id
    availability_zone = local.azs[count.index]
    cidr_block        = local.intra_subnet_cidrs[count.index]

    tags = merge(
        { "Name" = format("${var.name}-intra-%s", local.azs[count.index]) },
        var.additional_tags
    )
}

################################################################################
# Database Subnets
################################################################################
resource "aws_subnet" "database" {
    count = local.azs_count

    vpc_id            = aws_vpc.this.id
    availability_zone = local.azs[count.index]
    cidr_block        = local.database_subnet_cidrs[count.index]

    tags = merge(
        { "Name" = format("${var.name}-database-%s", local.azs[count.index]) },
        var.additional_tags
    )
}

resource "aws_db_subnet_group" "database" {
    name       = "${var.name}-db-subnetgroup"
    subnet_ids = aws_subnet.database[*].id
}

resource "aws_route_table" "database" {
    count = length(aws_subnet.database[*].id)

    vpc_id = aws_vpc.this.id

    tags = merge(
        { "Name" = format("${var.name}-database-%s", local.azs[count.index]) },
        var.additional_tags
    )
}

resource "aws_route_table_association" "database" {
    count = length(aws_subnet.database[*].id)

    subnet_id      = element(aws_subnet.database[*].id, count.index)
    route_table_id = element(aws_route_table.database[*].id, count.index)
}

################################################################################
# NAT Gateway
################################################################################
resource "aws_eip" "this" {
    count = local.nat_gateway_count

    domain = "vpc"

    tags = merge(
        { "Name" = var.name },
        var.additional_tags
    )
}

resource "aws_nat_gateway" "this" {
    count = local.nat_gateway_count

    allocation_id = element(aws_eip.this[*].id, count.index)
    subnet_id     = element(aws_subnet.public[*].id, count.index)

    tags = merge(
        { "Name" = format("${var.name}-%s/NATGateway", local.azs[count.index]) },
        var.additional_tags
    )
    depends_on = [aws_eip.this]
}