terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = "us-west-2"
}

# Define variables
variable "vpc_cidr_block" {}
variable "env_prefix" {}
variable "public_subnet_cidr_block" {}
variable "avail_zone" {}
variable "my_ip" {}
variable "my-public-key" {}
variable "instance_type" {}

# Create a VPC
resource "aws_vpc" "web-vpc" {
  cidr_block       = var.vpc_cidr_block
  instance_tenancy = "default"

  tags = {
    Name = "${var.env_prefix}-vpc"
  }
}

# Create a public subnet
resource "aws_subnet" "public_subnet" {
  vpc_id            = aws_vpc.web-vpc.id
  cidr_block        = var.public_subnet_cidr_block
  availability_zone = var.avail_zone

  tags = {
    Name = "${var.env_prefix}-public-subnet"
  }
}

# Create Internet gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.web-vpc.id

  tags = {
    Name = "${var.env_prefix}-internet-gateway"
  }
}

# Create route table for public subnet
resource "aws_route_table" "public-rt" {
  vpc_id = aws_vpc.web-vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }


  tags = {
    Name = "${var.env_prefix}-route-table"
  }
}

# associate public subnet with route table
resource "aws_route_table_association" "a-rtb-subnet" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public-rt.id
}

# Create security group for web server
resource "aws_security_group" "web-sg" {
  name   = "web-sg"
  vpc_id = aws_vpc.web-vpc.id

  ingress {

    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]

  }


  ingress {

    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]

  }

  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks     = ["0.0.0.0/0"]
    prefix_list_ids = []
  }

  tags = {
    Name = "${var.env_prefix}-web-sg"
  }
}

# Create an EC2 instance for the web server
data "aws_ami" "amazon-linux-image" {

  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-kernel-5.10-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

output "ami_id" {
  value = data.aws_ami.amazon-linux-image.id

}
output "webserver-ip" {
  value = aws_instance.web.public_ip

}
# create a key-pair

resource "aws_key_pair" "ssh-key" {
  key_name   = "myapp-key"
  public_key = var.my-public-key
}
resource "aws_instance" "web" {
  ami                         = data.aws_ami.amazon-linux-image.id
  instance_type               = var.instance_type
  associate_public_ip_address = true
  subnet_id                   = aws_subnet.public_subnet.id
  vpc_security_group_ids      = [aws_security_group.web-sg.id]
  availability_zone           = var.avail_zone
  key_name                    = "myapp-key"

  tags = {
    Name = "${var.env_prefix}-webserver"
  }
  user_data = <<EOF
                 #!/bin/bash
                 sudo yum update -y && sudo yum install -y docker
                 sudo systemctl start docker
                 sudo usermod -aG docker ec2-user
                 docker run -p 8080:8080 nginx
              EOF
}



