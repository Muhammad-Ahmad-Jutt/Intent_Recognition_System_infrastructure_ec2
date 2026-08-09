#!/bin/bash

set -euo pipefail

# =========================================================
# Logging
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
echo "AWS endpoint: ${aws_endpoint_url}"


# =========================================================
# Update packages
# =========================================================

echo "Updating packages..."

dnf update -y


# =========================================================
# Install required packages
# =========================================================

echo "Installing Docker, Git, unzip, Python, curl..."

dnf install -y \
    docker \
    git \
    unzip \
    python3 \
    curl


# =========================================================
# Start Docker
# =========================================================

echo "Starting Docker..."

systemctl enable --now docker

echo "Docker status:"
systemctl is-active docker || true

echo "Docker version:"
docker --version


# =========================================================
# Add ec2-user to Docker group
# =========================================================

echo "Adding ec2-user to Docker group..."

usermod -aG docker ec2-user || true


# =========================================================
# Install Docker Compose
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

docker-compose version || true


# =========================================================
# Install AWS CLI
# =========================================================

if ! command -v aws >/dev/null 2>&1; then

    echo "Installing AWS CLI..."

    dnf install -y awscli

else

    echo "AWS CLI already installed."

fi

echo "AWS CLI version:"
aws --version


# =========================================================
# Create application environment directory
# =========================================================

echo "Creating /etc/app..."

mkdir -p /etc/app

chmod 700 /etc/app


# =========================================================
# Create initial application environment file
# =========================================================

echo "Creating application environment file..."

cat > /etc/app/app_env.env <<EOF
aws_access_key_id=${aws_access_key_id}
aws_secret_access_key=${aws_secret_access_key}
aws_region=${aws_region}
aws_endpoint_url=${aws_endpoint_url}
environment=${environment}
secret_manager_name=${secret_manager_name}
EOF

chmod 600 /etc/app/app_env.env


# =========================================================
# Configure AWS CLI environment
# =========================================================

export AWS_ACCESS_KEY_ID="${aws_access_key_id}"
export AWS_SECRET_ACCESS_KEY="${aws_secret_access_key}"
export AWS_DEFAULT_REGION="${aws_region}"


# =========================================================
# Test AWS / LocalStack connectivity
# =========================================================

echo "Testing Secrets Manager connectivity..."

if ! aws secretsmanager list-secrets \
    --endpoint-url "${aws_endpoint_url}" \
    --region "${aws_region}" \
    >/tmp/secrets-list.json 2>/tmp/secrets-error.log
then

    echo "ERROR: Unable to connect to Secrets Manager."

    echo "AWS CLI error:"
    cat /tmp/secrets-error.log

    exit 1
fi

echo "Secrets Manager connectivity successful."


# =========================================================
# Retrieve secret
# =========================================================

echo "Retrieving secret:"
echo "${secret_manager_name}"

if secret_string=$(
    aws secretsmanager get-secret-value \
        --secret-id "${secret_manager_name}" \
        --endpoint-url "${aws_endpoint_url}" \
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
# Validate secret JSON
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
# Secure permissions
# =========================================================

chmod 600 /etc/app/app_env.env

chown root:root /etc/app/app_env.env


# =========================================================
# Show environment variable names only
# Do NOT print secret values
# =========================================================

echo "Environment file contains:"

cut -d '=' -f 1 /etc/app/app_env.env


# =========================================================
# Finished
# =========================================================

echo "================================================="
echo "USER DATA COMPLETED SUCCESSFULLY"
echo "================================================="
date