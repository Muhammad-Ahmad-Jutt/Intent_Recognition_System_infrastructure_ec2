#!/bin/bash
set -e

# Update packages
dnf update -y

# Install Docker, Git, unzip, and Python
dnf install -y docker git unzip python3

# Start Docker service
systemctl enable --now docker

# Add ec2-user to Docker group
usermod -aG docker ec2-user || true

# Install Docker Compose if missing
if ! command -v docker-compose >/dev/null 2>&1; then
  curl -SL https://github.com/docker/compose/releases/download/v2.39.2/docker-compose-linux-x86_64 \
    -o /usr/local/bin/docker-compose
  chmod +x /usr/local/bin/docker-compose
fi

# Install AWS CLI if missing
if ! command -v aws >/dev/null 2>&1; then
  curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
  unzip -o /tmp/awscliv2.zip -d /tmp
  /tmp/aws/install --update
fi

# Create app env directory
mkdir -p /etc/app
# Write app environment file for Docker and apps
cat > /etc/app/app_env.env <<EOF
aws_access_key_id=${aws_access_key_id}
aws_secret_access_key=${aws_secret_access_key}
aws_region=${aws_region}
aws_region=${aws_region}
aws_endpoint_url=${aws_endpoint_url}
environment=${environment}
secret_manager_name=${secret_manager_name}
EOF

# Write global environment file for shell sessions
cat > /etc/environment <<EOF
aws_access_key_id=${aws_access_key_id}
aws_secret_access_key=${aws_secret_access_key}
aws_region=${aws_region}
aws_region=${aws_region}
aws_endpoint_url=${aws_endpoint_url}
environment=${environment}
secret_manager_name=${secret_manager_name}
EOF

cat > /etc/profile.d/app_env.sh <<'EOP'
#!/bin/bash
export aws_access_key_id="${aws_access_key_id}"
export aws_secret_access_key="${aws_secret_access_key}"
export aws_region="${aws_region}"
export aws_region="${aws_region}"
export aws_endpoint_url="${aws_endpoint_url}"
export environment="${environment}"
export secret_manager_name="${secret_manager_name}"
EOP
chmod +x /etc/profile.d/app_env.sh

# Fetch secret from AWS Secrets Manager and append values to env files
if secret_string=$(AWS_ACCESS_KEY_ID="${aws_access_key_id}" AWS_SECRET_ACCESS_KEY="${aws_secret_access_key}" aws_region="${aws_region}" aws --endpoint-url "${aws_endpoint_url}" secretsmanager get-secret-value --secret-id "${secret_manager_name}" --query SecretString --output text 2>/dev/null); then
  export SECRET_STRING="$secret_string"
  python3 - <<'PY'
import json, os
secret = json.loads(os.environ['SECRET_STRING'])
with open('/etc/app/app_env.env', 'a') as f:
    for k, v in secret.items():
        f.write(f"{k}={v}\n")
with open('/etc/environment', 'a') as f:
    for k, v in secret.items():
        f.write(f"{k}={v}\n")
PY
else
  echo "Warning: could not load secret ${secret_manager_name}"
fi

