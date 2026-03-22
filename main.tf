# ============================================================
# TERRAFORM PROVIDER
# ============================================================
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# ============================================================
# VPC
# ============================================================
resource "aws_vpc" "main_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = { Name = "epicbook-vpc" }
}

# ============================================================
# PUBLIC SUBNET — EC2 lives here
# ============================================================
resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.main_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = { Name = "epicbook-public-subnet" }
}

# ============================================================
# PRIVATE SUBNET — RDS lives here
# ============================================================
resource "aws_subnet" "private_subnet_1" {
  vpc_id            = aws_vpc.main_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1a"

  tags = { Name = "epicbook-private-subnet-1" }
}

# RDS requires subnets in at least 2 availability zones
resource "aws_subnet" "private_subnet_2" {
  vpc_id            = aws_vpc.main_vpc.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "us-east-1b"

  tags = { Name = "epicbook-private-subnet-2" }
}

# ============================================================
# INTERNET GATEWAY
# ============================================================
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main_vpc.id

  tags = { Name = "epicbook-igw" }
}

# ============================================================
# ROUTE TABLE FOR PUBLIC SUBNET
# ============================================================
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = { Name = "epicbook-public-rt" }
}

resource "aws_route_table_association" "public_rta" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

# ============================================================
# SECURITY GROUP FOR EC2
# Allows SSH (22) and HTTP (80)
# ============================================================
resource "aws_security_group" "ec2_sg" {
  name        = "epicbook-ec2-sg"
  description = "Allow SSH and HTTP"
  vpc_id      = aws_vpc.main_vpc.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "epicbook-ec2-sg" }
}

# ============================================================
# SECURITY GROUP FOR RDS
# Allows MySQL (3306) from EC2 only
# ============================================================
resource "aws_security_group" "rds_sg" {
  name        = "epicbook-rds-sg"
  description = "Allow MySQL from EC2 only"
  vpc_id      = aws_vpc.main_vpc.id

  ingress {
    description     = "MySQL from EC2"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "epicbook-rds-sg" }
}

# ============================================================
# EC2 INSTANCE — Ubuntu 22.04
# ============================================================
resource "aws_instance" "epicbook_server" {
  ami                    = "ami-0866a3c8686eaeeba"
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]
  key_name               = "epicbook-key"

  tags = { Name = "epicbook-server" }
}

# ============================================================
# RDS SUBNET GROUP
# RDS needs to know which subnets it can use
# ============================================================
resource "aws_db_subnet_group" "rds_subnet_group" {
  name       = "epicbook-rds-subnet-group"
  subnet_ids = [aws_subnet.private_subnet_1.id, aws_subnet.private_subnet_2.id]

  tags = { Name = "epicbook-rds-subnet-group" }
}

# ============================================================
# RDS MYSQL INSTANCE — Private subnet
# ============================================================
resource "aws_db_instance" "epicbook_db" {
  identifier           = "epicbook-db"
  engine               = "mysql"
  engine_version       = "8.0"
  instance_class       = "db.t3.micro"
  allocated_storage    = 20
  storage_type         = "gp2"

  db_name              = "bookstore"
  username             = "admin"
  password             = "EpicBook1234Secure"
  skip_final_snapshot  = true
  publicly_accessible  = false

  db_subnet_group_name   = aws_db_subnet_group.rds_subnet_group.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]

  tags = { Name = "epicbook-db" }
}

# ============================================================
# OUTPUTS
# ============================================================
output "ec2_public_ip" {
  value       = aws_instance.epicbook_server.public_ip
  description = "Public IP of the EpicBook EC2 server"
}

output "rds_endpoint" {
  value       = aws_db_instance.epicbook_db.endpoint
  description = "RDS MySQL endpoint — use this in config.json"
}

output "ssh_command" {
  value       = "ssh -i epicbook-key.pem ubuntu@${aws_instance.epicbook_server.public_ip}"
  description = "Run this command to connect to your EC2 instance"
}