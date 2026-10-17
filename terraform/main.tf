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

# Use the default VPC
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Security Group for the Kubernetes node
resource "aws_security_group" "k3s" {
  name        = "k3s-sg"
  description = "Security group for k3s cluster"
  vpc_id      = data.aws_vpc.default.id

  # Allow SSH
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow Kubernetes API
  ingress {
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all traffic inside the security group
  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true
  }

  # Allow all outbound
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "k3s-sg"
  }
}

# Create a key pair for SSH (you will download the private key)
resource "aws_key_pair" "k3s" {
  key_name   = "k3s-key"
  public_key = tls_private_key.k3s.public_key_openssh
}

resource "tls_private_key" "k3s" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Save the private key locally
resource "local_file" "private_key" {
  content         = tls_private_key.k3s.private_key_pem
  filename        = "${path.module}/k3s-key.pem"
  file_permission = "0400"
}

# EC2 instance that will run k3s
resource "aws_instance" "k3s" {
  ami           = "ami-0c7217cdde317cfec" # Ubuntu 22.04 in us-east-1
  instance_type = "t3.small"
  key_name      = aws_key_pair.k3s.key_name
  subnet_id     = data.aws_subnets.default.ids[0]

  vpc_security_group_ids = [aws_security_group.k3s.id]

  user_data = <<-EOF
              #!/bin/bash
              curl -sfL https://get.k3s.io | sh -s - --write-kubeconfig-mode 644
              EOF

  tags = {
    Name = "k3s-server"
  }
}

output "instance_public_ip" {
  value = aws_instance.k3s.public_ip
}

output "ssh_command" {
  value = "ssh -i k3s-key.pem ubuntu@${aws_instance.k3s.public_ip}"
}