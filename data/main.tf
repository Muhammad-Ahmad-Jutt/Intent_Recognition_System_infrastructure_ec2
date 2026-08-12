resource "tls_private_key" "ssh_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_file" "private_key" {
  content         = tls_private_key.ssh_key.private_key_pem
  filename        = var.key_pair_name
  file_permission = "0600"
}

resource "aws_key_pair" "generated_key" {
  key_name   = var.key_pair_name
  public_key = tls_private_key.ssh_key.public_key_openssh
}

# ---------------------------------------------------------
# Security Group
# ---------------------------------------------------------

resource "aws_security_group" "ssh_access" {
  name = "terraform-ssh-security-group"

  ingress {
    description = "SSH access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"

    cidr_blocks = [
      "0.0.0.0/0"
    ]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"

    cidr_blocks = [
      "0.0.0.0/0"
    ]
  }
}

# ---------------------------------------------------------
# Common secret values
# ---------------------------------------------------------

locals {
  secret_common = {
    command                     = var.command
    HF_TOKEN                    = var.hf_token
    MODEL_NAME                  = var.model_name

    dataset_path                = var.dataset_path
    new_dataset_folder         = var.new_dataset_folder

    test_size                   = var.test_size
    random_state                = var.random_state

    num_train_epochs            = var.num_train_epochs
    per_device_train_batch_size = var.per_device_train_batch_size
    per_device_eval_batch_size  = var.per_device_eval_batch_size

    weight_decay                = var.weight_decay

    eval_strategy               = var.eval_strategy
    save_strategy               = var.save_strategy

    load_best_model_at_end      = var.load_best_model_at_end

    logging_steps               = var.logging_steps
    learning_rate               = var.learning_rate
    logging_strategy            = var.logging_strategy

    metric_for_best_model       = var.metric_for_best_model
    greater_is_better            = var.greater_is_better

    model_out_directory         = var.model_out_directory
    model_path                  = var.model_path

    metrics_output_file         = var.metrics_output_file
    label_mapping_file_path     = var.label_mapping_file_path
    accuracy_comparison_file    = var.accuracy_comparison_file
    unseen_data_path            = var.unseen_data_path

    s3_bucket_name              = var.s3_bucket_name

    # These are currently being used by your LocalStack setup.
    aws_access_key_id           = var.aws_access_key_id
    aws_secret_access_key       = var.aws_secret_access_key
    aws_region                  = var.aws_region
  }

  dev_secret = merge(
    local.secret_common,
    {
      environment = "development"
    }
  )

  prod_secret = merge(
    local.secret_common,
    {
      environment = "production"
    }
  )
}

# ---------------------------------------------------------
# Development Secret
# ---------------------------------------------------------

resource "aws_secretsmanager_secret" "dev_secret" {
  name                    = var.secret_manager_dev_name
  description             = "Development environment secret values"
  recovery_window_in_days = 0

  tags = {
    environment = "development"
  }
}

resource "aws_secretsmanager_secret_version" "dev_secret_version" {
  secret_id     = aws_secretsmanager_secret.dev_secret.id
  secret_string = jsonencode(local.dev_secret)
}

# ---------------------------------------------------------
# Production Secret
# ---------------------------------------------------------

resource "aws_secretsmanager_secret" "prod_secret" {
  name                    = var.secret_manager_prod_name
  description             = "Production environment secret values"
  recovery_window_in_days = 0

  tags = {
    environment = "production"
  }
}

resource "aws_secretsmanager_secret_version" "prod_secret_version" {
  secret_id     = aws_secretsmanager_secret.prod_secret.id
  secret_string = jsonencode(local.prod_secret)
}

# ---------------------------------------------------------
# Development EC2
# ---------------------------------------------------------

resource "aws_instance" "trainer" {
  ami           = "ami-0bdc7d025135d7b49"
  instance_type = var.dev_instance_type

  key_name = aws_key_pair.generated_key.key_name

  security_groups = [
    aws_security_group.ssh_access.name
  ]

  user_data = templatefile("${path.module}/setup.sh", {
    aws_access_key_id     = var.aws_access_key_id
    aws_secret_access_key = var.aws_secret_access_key
    aws_region            = var.aws_region

    secret_manager_name = var.secret_manager_dev_name

    environment = "development"
  })

  iam_instance_profile = aws_iam_instance_profile.trainer_profile.name

  # Make sure the secret exists BEFORE user_data runs.
  depends_on = [
    aws_secretsmanager_secret_version.dev_secret_version
  ]

  tags = {
    Name = var.dev_instance_name
    Role = "trainer"
  }
}

# ---------------------------------------------------------
# Production EC2
# ---------------------------------------------------------

resource "aws_instance" "web_server" {
  ami           = "ami-0bdc7d025135d7b49"
  instance_type = var.prod_instance_type

  key_name = aws_key_pair.generated_key.key_name

  security_groups = [
    aws_security_group.ssh_access.name
  ]

  user_data = templatefile("${path.module}/setup.sh", {
    aws_access_key_id     = var.aws_access_key_id
    aws_secret_access_key = var.aws_secret_access_key
    aws_region            = var.aws_region

    secret_manager_name = var.secret_manager_prod_name

    environment = "production"
  })

  iam_instance_profile = aws_iam_instance_profile.production_profile.name

  # Make sure the secret exists BEFORE user_data runs.
  depends_on = [
    aws_secretsmanager_secret_version.prod_secret_version
  ]

  tags = {
    Name = var.prod_instance_name
    Role = "production"
  }
}

# ---------------------------------------------------------
# S3 Bucket
# ---------------------------------------------------------
# ---------------------------------------------------------
# S3 Bucket
# ---------------------------------------------------------

resource "aws_s3_bucket" "public_bucket" {
  bucket = var.s3_bucket_name

  tags = {
    Name    = var.s3_bucket_name
    Purpose = "public storage"
  }
}

# 1. Turn off public access blocks FIRST
resource "aws_s3_bucket_public_access_block" "public_bucket" {
  bucket = aws_s3_bucket.public_bucket.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# 2. Apply the public read bucket policy SECOND (depends explicitly on the block removal)
resource "aws_s3_bucket_policy" "public_bucket_policy" {
  bucket = aws_s3_bucket.public_bucket.id

  # This forces Terraform to wait until the public block is safely removed before applying the policy
  depends_on = [aws_s3_bucket_public_access_block.public_bucket]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowPublicRead"
        Effect    = "Allow"
        Principal = "*"
        Action = [
          "s3:GetObject"
        ]
        Resource = [
          "${aws_s3_bucket.public_bucket.arn}/*"
        ]
      }
    ]
  })
}


# ---------------------------------------------------------
# ECR Repository
# ---------------------------------------------------------

resource "aws_ecr_repository" "repo" {
  name                 = var.ecr_repo_name
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "repo_policy" {
  repository = aws_ecr_repository.repo.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire images older than 1 day"
        selection = {
          tagStatus   = "any"
          countType   = "sinceImagePushed"
          countUnit   = "days" # <-- Added this missing required parameter
          countNumber = 1
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# ---------------------------------------------------------
# IAM roles, users and credentials
# ---------------------------------------------------------

resource "aws_iam_role" "trainer_role" {
  name = "${var.dev_instance_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role" "production_role" {
  name = "${var.prod_instance_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "trainer_profile" {
  name = "${var.dev_instance_name}-instance-profile"
  role = aws_iam_role.trainer_role.name
}

resource "aws_iam_instance_profile" "production_profile" {
  name = "${var.prod_instance_name}-instance-profile"
  role = aws_iam_role.production_role.name
}

resource "aws_iam_role_policy" "trainer_bucket_policy" {
  role = aws_iam_role.trainer_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.public_bucket.arn,
          "${aws_s3_bucket.public_bucket.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy" "production_bucket_policy" {
  role = aws_iam_role.production_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.public_bucket.arn,
          "${aws_s3_bucket.public_bucket.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_user" "trainer_user" {
  name = "${var.dev_instance_name}-user"
}

resource "aws_iam_user" "production_user" {
  name = "${var.prod_instance_name}-user"
}

resource "aws_iam_user_policy" "trainer_user_policy" {
  user = aws_iam_user.trainer_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.public_bucket.arn,
          "${aws_s3_bucket.public_bucket.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_user_policy" "production_user_policy" {
  user = aws_iam_user.production_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.public_bucket.arn,
          "${aws_s3_bucket.public_bucket.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_access_key" "trainer_user_key" {
  user = aws_iam_user.trainer_user.name
}

resource "aws_iam_access_key" "production_user_key" {
  user = aws_iam_user.production_user.name
}

locals {
  terraform_export = {
    ecr_repo = {
      info = aws_ecr_repository.repo
    }
    s3_bucket = {
      name = aws_s3_bucket.public_bucket.bucket
      arn  = aws_s3_bucket.public_bucket.arn
    }
    roles = {
      trainer = {
        name = aws_iam_role.trainer_role.name
        arn  = aws_iam_role.trainer_role.arn
      }
      production = {
        name = aws_iam_role.production_role.name
        arn  = aws_iam_role.production_role.arn
      }
    }
    credentials = {
      trainer = {
        access_key = aws_iam_access_key.trainer_user_key.id
        secret_key = aws_iam_access_key.trainer_user_key.secret
      }
      production = {
        access_key = aws_iam_access_key.production_user_key.id
        secret_key = aws_iam_access_key.production_user_key.secret
      }
    }
  }
}

resource "local_file" "terraform_export" {
  content  = jsonencode(local.terraform_export)
  filename = "${path.module}/terraform-outputs.json"
}

# ---------------------------------------------------------
# Outputs
# ---------------------------------------------------------


output "private_key_path" {
  value = local_file.private_key.filename
}

output "trainer_public_ip" {
  value = aws_instance.trainer.public_ip
}

output "production_public_ip" {
  value = aws_instance.web_server.public_ip
}
output "ecr_url" {
  value = aws_ecr_repository.repo.arn
}
