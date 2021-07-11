provider "aws" {
  region = "us-east-1"
  access_key = var.awsAccessKey
  secret_key = var.awsSecretKey
}

# EC2 instance
#  TODO install/enable apache
resource "aws_instance" "apache-server" {
  ami           = "ami-0dc2d3e4c0f9ebd18"
  instance_type = "t2.micro"
  key_name = "terraform-demo-keypair"
  availability_zone = "us-east-1a"
  network_interface {
    network_interface_id = aws_network_interface.prod-main-interface.id
    device_index = 0
  }

  user_data = <<-EOF
              #!/bin/bash
              sudo yum update -y
              sudo yum install httpd -y
              sudo systemctl start httpd
              sudo bash -c 'echo first web server with terraform > /var/www/html/index.html'
              EOF
  tags = {
    Name = "Ubuntu-Server"
  }
}

# VPC
resource "aws_vpc" "prod-vpc" {
  cidr_block = "10.0.0.0/16"
  enable_dns_hostnames = true
  tags = {
      Name = "production"
  }
}

# Internet gateway
resource "aws_internet_gateway" "production-gw" {
  vpc_id = aws_vpc.prod-vpc.id

  tags = {
      Name = "main"
  }
}

variable "subnet-prefix" {
  description = "CIDR block for subnet"
}

# Subnet
resource "aws_subnet" "prod-main" {
  vpc_id     = aws_vpc.prod-vpc.id
  cidr_block = var.subnet-prefix
  availability_zone = "us-east-1a"

  tags = {
    Name = "prod-main"
  }
}

# Route Table
resource "aws_route_table" "prod-main-route" {
  vpc_id = aws_vpc.prod-vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.production-gw.id
  }

  tags = {
    Name = "prod-main-route-table"
  }
}

# Route Table 
resource "aws_route_table_association" "prod-main-route-table-association" {
  subnet_id      = aws_subnet.prod-main.id
  route_table_id = aws_route_table.prod-main-route.id
}

# Security group
resource "aws_security_group" "allow_all_web_and_ssh" {
  name        = "allow_all_web_and_ssh"
  description = "Allow web traffic and ssh access"
  vpc_id      = aws_vpc.prod-vpc.id

  ingress {
    description      = "TLS"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    # ipv6_cidr_blocks = [aws_vpc.main.ipv6_cidr_block]
  }

  ingress {
    description      = "HTTP"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  ingress {
    description      = "SSH"
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "allow__all_web_and_ssh"
  }
}
# Network interface for subnet
resource "aws_network_interface" "prod-main-interface" {
  subnet_id       = aws_subnet.prod-main.id
  security_groups = [aws_security_group.allow_all_web_and_ssh.id]
  private_ips     = ["10.0.1.50"]
}


# EIP for Network interface
resource "aws_eip" "apache-server-eip" {
  vpc                       = true
  network_interface         = aws_network_interface.prod-main-interface.id
  associate_with_private_ip = "10.0.1.50"
  depends_on = [
    aws_internet_gateway.production-gw,
    aws_instance.apache-server
  ]
  tags = {
    "Name" = "apache-server-ip"
  }
}

output "server_public_ip" {
    value = aws_eip.apache-server-eip.public_ip
}