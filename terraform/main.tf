terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

resource "random_id" "id" {
  byte_length = 4
}

# Security Group for Oracle 21c XE
resource "aws_security_group" "oracle_cdc_sg" {
  name        = "oracle-cdc-sg-${random_id.id.hex}"
  description = "Security Group for Oracle 21c XE with CDC"

  # SSH access
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.myip]
    description = "SSH access"
  }

  # Oracle Database
  ingress {
    from_port   = 1521
    to_port     = 1521
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
    description = "Oracle DB"
  }

  # Oracle EM Express
  ingress {
    from_port   = 5500
    to_port     = 5500
    protocol    = "tcp"
    cidr_blocks = [var.myip]
    description = "Oracle EM Express"
  }

  # Kafka Broker
  ingress {
    from_port   = 9092
    to_port     = 9092
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
    description = "Kafka Broker"
  }

  # Kafka Connect REST API
  ingress {
    from_port   = 8083
    to_port     = 8083
    protocol    = "tcp"
    cidr_blocks = [var.myip]
    description = "Kafka Connect REST API"
  }

  # Schema Registry
  ingress {
    from_port   = 8081
    to_port     = 8081
    protocol    = "tcp"
    cidr_blocks = [var.myip]
    description = "Schema Registry"
  }

  # Control Center
  ingress {
    from_port   = 9021
    to_port     = 9021
    protocol    = "tcp"
    cidr_blocks = [var.myip]
    description = "Confluent Control Center"
  }

  # JMX Ports for monitoring
  ingress {
    from_port   = 9101
    to_port     = 9105
    protocol    = "tcp"
    cidr_blocks = [var.myip]
    description = "JMX Ports for Kafka monitoring"
  }

  # Outbound internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "oracle-cdc-sg-${random_id.id.hex}"
    Environment = "Demo"
    Purpose     = "Oracle XStream CDC"
  }
}

# EC2 Instance for Oracle + Confluent Platform
resource "aws_instance" "oracle_cdc" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  key_name               = var.ssh_key_name
  vpc_security_group_ids = [aws_security_group.oracle_cdc_sg.id]
  user_data              = templatefile("${path.module}/userdata.sh", {
    oracle_password = var.oracle_password
  })

  root_block_device {
    volume_type = "gp3"
    volume_size = 100
  }

  tags = {
    Name        = "oracle-cdc-${random_id.id.hex}"
    Environment = "Demo"
    Purpose     = "Oracle XStream CDC with Confluent Platform"
  }
}

# Outputs
output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.oracle_cdc.id
}

output "public_ip" {
  description = "Public IP address"
  value       = aws_instance.oracle_cdc.public_ip
}

output "ssh_command" {
  description = "SSH command to connect"
  value       = "ssh -i ${var.ssh_key_path} ec2-user@${aws_instance.oracle_cdc.public_ip}"
}

output "control_center_url" {
  description = "Confluent Control Center URL"
  value       = "http://${aws_instance.oracle_cdc.public_ip}:9021"
}

output "kafka_connect_url" {
  description = "Kafka Connect REST API URL"
  value       = "http://${aws_instance.oracle_cdc.public_ip}:8083"
}
