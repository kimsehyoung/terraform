output "vpc_id" {
    description = "The ID of the VPC"
    value       = aws_vpc.this.id
}

output "igw_id" {
    description = "The ID of the Internet Gateway"
    value       = aws_internet_gateway.this.id
}

output "public_subnets" {
    description = "The ID and CIDR block of public subnets"
    value = {
      ids = aws_subnet.public[*].id
      cidr_blocks = aws_subnet.public[*].cidr_block
    }
}

output "private_subnets" {
  description = "The ID and CIDR block of private subnets"
  value = {
    ids = aws_subnet.private[*].id
    cidr_blocks = aws_subnet.private[*].cidr_block
  }
}

output "intra_subnets" {
  description = "The ID and CIDR block of intra subnets"
  value = {
    ids = aws_subnet.intra[*].id
    cidr_blocks = aws_subnet.intra[*].cidr_block
  }
}

output "database_subnets" {
  description = "The ID and CIDR block of database subnets"
  value = {
    ids = aws_subnet.database[*].id
    cidr_blocks = aws_subnet.database[*].cidr_block
  }
}

output "database_subnet_group_name" {
    description = "The subnet group for RDS"
    value       = aws_db_subnet_group.database.name
}

output "nat_ids" {
    description = "The ID of EIP created for NAT Gateway"
    value       = aws_eip.this[*].id
}

output "natgw_ids" {
    description = "List of NAT Gateway IDs"
    value       = aws_nat_gateway.this[*].id
}