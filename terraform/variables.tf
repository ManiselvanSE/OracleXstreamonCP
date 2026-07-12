variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-south-1"
}

variable "ami_id" {
  description = "AMI ID for EC2 instance (Amazon Linux 2023)"
  type        = string
  default     = "ami-0c1b03e30bca3b373"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.xlarge"
}

variable "ssh_key_name" {
  description = "Name of SSH key pair in AWS"
  type        = string
}

variable "ssh_key_path" {
  description = "Local path to SSH private key"
  type        = string
}

variable "myip" {
  description = "Your IP address for SSH and UI access (CIDR format)"
  type        = string
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to access services"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "oracle_password" {
  description = "Oracle SYS password"
  type        = string
  default     = "confluent123"
  sensitive   = true
}
