#!/bin/bash

# Update packages
dnf update -y

# Install Docker
dnf install docker -y

# Start Docker service
systemctl start docker

# Add ec2-user to Docker group
usermod -aG docker ec2-user

# Install Git
dnf install git -y

# Install Docker Compose
curl -SL https://github.com/docker/compose/releases/download/v2.39.2/docker-compose-linux-x86_64 \
-o /usr/local/bin/docker-compose

# Give execute permissions
chmod +x /usr/local/bin/docker-compose

# Verify installation
docker --version
docker-compose --version