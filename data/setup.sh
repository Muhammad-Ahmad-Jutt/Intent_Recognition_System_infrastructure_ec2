#!/bin/bash

set -euo pipefail


# =========================================================
# LOGGING
# =========================================================

exec > >(tee -a /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

echo "================================================="
echo "USER DATA STARTED"
echo "================================================="

date

echo "Running as: $(whoami)"
echo "Environment: ${environment}"
echo "Secret name: ${secret_manager_name}"
echo "AWS region: ${aws_region}"


# =========================================================
# UPDATE PACKAGES
# =========================================================

echo "Updating packages..."

dnf update -y


# =========================================================
# INSTALL REQUIRED PACKAGES
# =========================================================

echo "Installing required packages..."

dnf install -y \
    docker \
    git \
    unzip \
    python3 \
    awscli


# =========================================================
# DOCKER
# =========================================================

echo "Starting Docker..."

systemctl enable --now docker

echo "Docker status:"
systemctl is-active docker || true

echo "Docker version:"
docker --version


# =========================================================
# DOCKER GROUP
# =========================================================

echo "Adding ec2-user to Docker group..."

usermod -aG docker ec2-user || true


# =========================================================
# DOCKER COMPOSE
# =========================================================

if ! command -v docker-compose >/dev/null 2>&1; then

    echo "Installing Docker Compose..."

    curl -fL \
        "https://github.com/docker/compose/releases/download/v2.39.2/docker-compose-linux-x86_64" \
        -o /usr/local/bin/docker-compose

    chmod +x /usr/local/bin/docker-compose

else

    echo "Docker Compose already installed."

fi


echo "Docker Compose version:"
docker-compose version || true


# =========================================================
# AWS CLI
# =========================================================

echo "AWS CLI version:"
aws --version


# =========================================================
# AWS IAM ROLE TEST
#
# IMPORTANT:
#
# We DO NOT configure:
#
# AWS_ACCESS_KEY_ID
# AWS_SECRET_ACCESS_KEY
#
# EC2 gets temporary credentials automatically from
# its IAM instance profile.
# =========================================================

echo "Testing EC2 IAM role..."

if aws sts get-caller-identity \
    --region "${aws_region}" \
    >/tmp/aws-identity.json \
    2>/tmp/aws-identity-error.log
then

    echo "EC2 IAM role is working."

    cat /tmp/aws-identity.json

else

    echo "ERROR: EC2 IAM role is not working."

    cat /tmp/aws-identity-error.log

    exit 1

fi


# =========================================================
# CREATE APPLICATION DIRECTORY
# =========================================================

echo "Creating /etc/app..."

mkdir -p /etc/app

chmod 700 /etc/app


# =========================================================
# INITIAL ENVIRONMENT FILE
# =========================================================

echo "Creating application environment file..."

cat > /etc/app/app_env.env <<EOF
aws_region=${aws_region}
environment=${environment}
secret_manager_name=${secret_manager_name}
EOF

chmod 600 /etc/app/app_env.env

chown root:root /etc/app/app_env.env


# =========================================================
# GET SECRET FROM SECRETS MANAGER
#
# AWS CLI automatically uses the EC2 IAM role.
# =========================================================

echo "Retrieving secret..."

if secret_string=$(
    aws secretsmanager get-secret-value \
        --secret-id "${secret_manager_name}" \
        --region "${aws_region}" \
        --query SecretString \
        --output text
); then

    echo "Secret retrieved successfully."

else

    echo "ERROR: Could not retrieve secret:"
    echo "${secret_manager_name}"

    exit 1

fi


# =========================================================
# VALIDATE SECRET
# =========================================================

export SECRET_STRING="$secret_string"

python3 - <<'PY'
import json
import os

secret_string = os.environ["SECRET_STRING"]

try:
    secret = json.loads(secret_string)

except json.JSONDecodeError as e:
    print("ERROR: SecretString is not valid JSON.")
    print(e)
    raise SystemExit(1)


if not isinstance(secret, dict):
    print("ERROR: SecretString must contain a JSON object.")
    raise SystemExit(1)


print("Secret JSON validated successfully.")


with open("/etc/app/app_env.env", "a") as f:

    for key, value in secret.items():
        f.write(f"{key}={value}\n")


print("Secret values written to /etc/app/app_env.env")

PY


# =========================================================
# SECURE ENVIRONMENT FILE
# =========================================================

chmod 600 /etc/app/app_env.env

chown root:root /etc/app/app_env.env


# =========================================================
# SHOW ONLY VARIABLE NAMES
#
# NEVER PRINT SECRET VALUES.
# =========================================================

echo "Environment variables configured:"

cut -d '=' -f 1 /etc/app/app_env.env


# =========================================================
# SSM AGENT
# =========================================================

echo "Checking AWS SSM Agent..."

if systemctl list-unit-files | grep -q "amazon-ssm-agent"; then

    echo "SSM Agent found."

    systemctl enable --now amazon-ssm-agent

    echo "SSM Agent status:"
    systemctl is-active amazon-ssm-agent || true

else

    echo "SSM Agent service was not found."

    echo "Trying to install amazon-ssm-agent..."

    if dnf install -y amazon-ssm-agent; then

        systemctl enable --now amazon-ssm-agent

        echo "SSM Agent installed successfully."

    else

        echo "WARNING: Could not install SSM Agent."

        echo "Make sure the selected AMI contains the SSM Agent."
    fi

fi


# =========================================================
# FINAL STATUS
# =========================================================

echo "================================================="
echo "USER DATA COMPLETED SUCCESSFULLY"
echo "================================================="

date