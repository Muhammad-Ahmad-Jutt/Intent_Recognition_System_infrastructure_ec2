FROM hashicorp/terraform:latest

# Install AWS CLI and useful tools
RUN apk add --no-cache \
    aws-cli \
    curl \
    git \
    unzip \
    python3

# Verify installations
RUN terraform version && aws --version

WORKDIR /workspace

ENTRYPOINT ["/bin/sh"]