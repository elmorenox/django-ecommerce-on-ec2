# 1 VPC
# 2 AZ's
# 3 Subnets
# 3 EC2's
# 2 Route Table
# Security Group Ports: 8080, 8000, 3000, 22 for frontend 
# BE Security Group: 22, 8000

provider "aws" {
  region = "us-east-1"
}
#VPC
resource "aws_vpc" "ecommerce_vpc" {
  cidr_block = var.vpc_cidr_block

  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "ecommerce_vpc"
  }
}

resource "aws_eip" "elastic-ip" {
  domain = "vpc"
}

# internet gateway
resource "aws_internet_gateway" "internet_gateway" {
  vpc_id = aws_vpc.ecommerce_vpc.id
  tags = {
    Name = "ecommerce_internet_gateway"
  }
}


# subnets
resource "aws_subnet" "public_subnet" {
  vpc_id            = aws_vpc.ecommerce_vpc.id
  cidr_block        = var.subnet_cidr_blocks.0
  availability_zone = var.availability_zone
  tags = {
    Name = "ecommerce_public_subnet"
  }
}

resource "aws_subnet" "private_subnet" {
  vpc_id            = aws_vpc.ecommerce_vpc.id
  cidr_block        = var.subnet_cidr_blocks.1
  availability_zone = var.availability_zone
  tags = {
    Name = "ecommerce_private_subnet"
  }
}

# 2nd az, failover for rds and 2nd instaces of FE and BE (not included here but is part of student WL)
resource "aws_subnet" "private_subnet_2" {
  vpc_id            = aws_vpc.ecommerce_vpc.id
  cidr_block        = var.subnet_cidr_blocks[2]
  availability_zone = var.availability_zone_2
  tags = {
    Name = "ecommerce_private_subnet_2"
  }
}

resource "aws_db_subnet_group" "rds_subnet_group" {
  name       = "rds_subnet_group"
  subnet_ids = [aws_subnet.private_subnet.id, aws_subnet.private_subnet_2.id]

  tags = {
    Name = "RDS subnet group"
  }
}


# nat gateway (get internet into private subnet)
resource "aws_nat_gateway" "ngw" {
  subnet_id     = aws_subnet.public_subnet.id
  allocation_id = aws_eip.elastic-ip.id
}


# route tables
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.ecommerce_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.internet_gateway.id
  }
  tags = { name = "public" }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.ecommerce_vpc.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.ngw.id
  }
  tags = { name = "private" }
}


# route table <> subnets
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private_subnet.id
  route_table_id = aws_route_table.private.id
}

resource "aws_security_group" "front_end_security_group" {
  name_prefix = "web_"
  vpc_id      = aws_vpc.ecommerce_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ecommerce_frontend_security_group"
  }
}

resource "aws_security_group" "backend_security_group" {
  vpc_id = aws_vpc.ecommerce_vpc.id
  name   = "BE security"

  ingress {
    from_port       = 8000 # Django default port
    to_port         = 8000
    protocol        = "tcp"
    security_groups = [aws_security_group.front_end_security_group.id]
  }

  ingress {
    from_port       = 22 # SSH port so the you can hop from frontend to backend
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.front_end_security_group.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ecommerce_backend_security_group"
  }
}

resource "aws_security_group" "rds_sg" {
  name        = "rds_sg"
  description = "Security group for RDS"
  vpc_id      = aws_vpc.ecommerce_vpc.id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.backend_security_group.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "RDS Security Group"
  }
}

# EC2s
resource "aws_instance" "frontend_server" {
  ami                         = var.ec2_ami
  instance_type               = var.ec2_instance_type
  subnet_id                   = aws_subnet.public_subnet.id
  vpc_security_group_ids      = [aws_security_group.front_end_security_group.id]
  key_name                    = var.key_name
  associate_public_ip_address = true
  user_data                   = file("frontend_install.sh")
  tags = {
    Name = "frontend_server"
  }
}

resource "aws_instance" "backend_server" {
  ami                    = var.ec2_ami
  instance_type          = var.ec2_instance_type
  subnet_id              = aws_subnet.private_subnet.id
  vpc_security_group_ids = [aws_security_group.backend_security_group.id]
  key_name               = var.key_name
  tags = {
    Name = "backend_server"
  }
}

# Create the RDS instance
resource "aws_db_instance" "postgres_db" {
  identifier           = "ecommerce-db"
  engine               = "postgres"
  engine_version       = "14.13"
  instance_class       = var.db_instance_class
  allocated_storage    = 20
  storage_type         = "standard"
  db_name              = var.db_name
  username             = var.db_username
  password             = var.db_password
  parameter_group_name = "default.postgres14"
  skip_final_snapshot  = true

  db_subnet_group_name   = aws_db_subnet_group.rds_subnet_group.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]

  tags = {
    Name = "Ecommerce Postgres DB"
  }
}


output "instance_ips" {
  value = [aws_instance.frontend_server.public_ip]
}

output "rds_endpoint" {
  value = aws_db_instance.postgres_db.endpoint
}