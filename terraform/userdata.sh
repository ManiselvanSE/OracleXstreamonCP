#!/bin/bash

set -e

echo "========================================"
echo "Oracle XStream CDC Setup - Starting"
echo "========================================"

# Update system
yum update -y
yum install -y wget unzip jq git nc

# Install Docker
yum install -y docker
usermod -a -G docker ec2-user
service docker start
chkconfig docker on

# Configure Docker for production
echo "vm.max_map_count=262144" >> /etc/sysctl.conf
sysctl -w vm.max_map_count=262144
echo "    *       soft  nofile  65535" >> /etc/security/limits.conf
echo "    *       hard  nofile  65535" >> /etc/security/limits.conf

# Install Docker Compose
DOCKER_COMPOSE_VERSION="2.24.0"
curl -SL https://github.com/docker/compose/releases/download/v$${DOCKER_COMPOSE_VERSION}/docker-compose-linux-x86_64 -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose

# Wait for Docker to be ready
sleep 5

# Create working directory
mkdir -p /home/ec2-user/oracle-cdc
cd /home/ec2-user/oracle-cdc

# Download Oracle JDBC driver
wget -q https://download.oracle.com/otn-pub/otn_software/jdbc/233/ojdbc11.jar -O /home/ec2-user/oracle-cdc/ojdbc11.jar

# Create setup scripts directory
mkdir -p /home/ec2-user/oracle-cdc/oracle-setup/scripts

# Create Oracle setup script marker
touch /home/ec2-user/oracle-cdc/.setup_in_progress

# Change ownership
chown -R ec2-user:ec2-user /home/ec2-user/oracle-cdc

echo "========================================"
echo "Base setup completed"
echo "Oracle and Confluent Platform will be configured via scripts"
echo "========================================"
