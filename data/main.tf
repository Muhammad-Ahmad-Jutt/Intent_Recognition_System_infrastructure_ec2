

# =========================================================
# SSH PRIVATE KEY
# =========================================================

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


# =========================================================
# SECURITY GROUP
# =========================================================

resource "aws_security_group" "app_security_group" {
  name        = "terraform-ml-security-group"
  description = "Security group for ML trainer and production EC2 instances"

  # SSH
  #
  # Keep this only if you still want emergency/manual SSH.
  # Ideally restrict this to your own IP instead of 0.0.0.0/0.
  ingress {
    description = "SSH access"

    from_port = 22
    to_port   = 22
    protocol  = "tcp"

    cidr_blocks = [
      "0.0.0.0/0"
    ]
  }

  # Application/API port
  #
  # Change this if your application uses another port.
  ingress {
    description = "Application/API"

    from_port = 5000
    to_port   = 5000
    protocol  = "tcp"

    cidr_blocks = [
      "0.0.0.0/0"
    ]
  }

  # Outbound internet access
  egress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"

    cidr_blocks = [
      "0.0.0.0/0"
    ]
  }

  tags = {
    Name = "terraform-ml-security-group"
  }
}


# =========================================================
# COMMON SECRET VALUES
# =========================================================

locals {

  secret_common = {
    command = var.command

    HF_TOKEN   = var.hf_token
    MODEL_NAME = var.model_name

    dataset_path        = var.dataset_path
    new_dataset_folder  = var.new_dataset_folder

    test_size    = var.test_size
    random_state = var.random_state

    num_train_epochs            = var.num_train_epochs
    per_device_train_batch_size = var.per_device_train_batch_size
    per_device_eval_batch_size  = var.per_device_eval_batch_size

    weight_decay = var.weight_decay

    eval_strategy = var.eval_strategy
    save_strategy = var.save_strategy

    load_best_model_at_end = var.load_best_model_at_end

    logging_steps    = var.logging_steps
    learning_rate    = var.learning_rate
    logging_strategy = var.logging_strategy

    metric_for_best_model = var.metric_for_best_model
    greater_is_better     = var.greater_is_better

    model_out_directory = var.model_out_directory
    model_path          = var.model_path

    metrics_output_file      = var.metrics_output_file
    label_mapping_file_path  = var.label_mapping_file_path
    accuracy_comparison_file = var.accuracy_comparison_file
    unseen_data_path         = var.unseen_data_path

    s3_bucket_name = var.s3_bucket_name

    aws_region = var.aws_region
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


# =========================================================
# DEVELOPMENT SECRET
# =========================================================

resource "aws_secretsmanager_secret" "dev_secret" {
  name                    = var.secret_manager_dev_name
  description             = "Development/trainer environment secret values"
  recovery_window_in_days = 0

  tags = {
    Environment = "development"
    ManagedBy   = "terraform"
  }
}


resource "aws_secretsmanager_secret_version" "dev_secret_version" {
  secret_id     = aws_secretsmanager_secret.dev_secret.id
  secret_string = jsonencode(local.dev_secret)
}


# =========================================================
# PRODUCTION SECRET
# =========================================================

resource "aws_secretsmanager_secret" "prod_secret" {
  name                    = var.secret_manager_prod_name
  description             = "Production environment secret values"
  recovery_window_in_days = 0

  tags = {
    Environment = "production"
    ManagedBy   = "terraform"
  }
}


resource "aws_secretsmanager_secret_version" "prod_secret_version" {
  secret_id     = aws_secretsmanager_secret.prod_secret.id
  secret_string = jsonencode(local.prod_secret)
}


# =========================================================
# S3 BUCKET
# =========================================================

resource "aws_s3_bucket" "model_bucket" {
  bucket = var.s3_bucket_name

  tags = {
    Name      = var.s3_bucket_name
    Purpose   = "ML model and dataset storage"
    ManagedBy = "terraform"
  }
}


# =========================================================
# S3 PUBLIC ACCESS BLOCK
#
# The bucket is PRIVATE.
# We are NOT making model files public.
# =========================================================

resource "aws_s3_bucket_public_access_block" "model_bucket" {
  bucket = aws_s3_bucket.model_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}


# =========================================================
# ECR REPOSITORY
# =========================================================

resource "aws_ecr_repository" "repo" {
  name                 = var.ecr_repo_name
  image_tag_mutability = "MUTABLE"
  force_delete = true
  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name      = var.ecr_repo_name
    ManagedBy = "terraform"
  }
}


# =========================================================
# ECR LIFECYCLE POLICY
# =========================================================

resource "aws_ecr_lifecycle_policy" "repo_policy" {
  repository = aws_ecr_repository.repo.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1

        description = "Expire images older than 1 day"

        selection = {
          tagStatus   = "any"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }

        action = {
          type = "expire"
        }
      }
    ]
  })
}


# =========================================================
# =========================================================
# TRAINER EC2 IAM ROLE
# =========================================================
# =========================================================

resource "aws_iam_role" "trainer_role" {
  name = "${var.dev_instance_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Sid    = "EC2AssumeRole"
        Effect = "Allow"

        Principal = {
          Service = "ec2.amazonaws.com"
        }

        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Environment = "development"
    Role        = "trainer"
    ManagedBy   = "terraform"
  }
}


# =========================================================
# TRAINER - SSM
# =========================================================

resource "aws_iam_role_policy_attachment" "trainer_ssm" {
  role = aws_iam_role.trainer_role.name

  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}


# =========================================================
# TRAINER - S3
#
# Trainer can:
#   - read objects
#   - upload objects
#   - list bucket
#
# DeleteObject intentionally omitted.
# =========================================================
resource "aws_iam_role_policy" "trainer_s3_policy" {
  name = "${var.dev_instance_name}-s3-policy"
  role = aws_iam_role.trainer_role.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [

      # =====================================================
      # BUCKET-LEVEL PERMISSIONS
      # =====================================================

      {
        Sid    = "TrainerBucketAccess"
        Effect = "Allow"

        Action = [
          "s3:ListAllMyBuckets",

          "s3:CreateBucket",
          "s3:DeleteBucket",

          "s3:GetBucketLocation",
          "s3:GetBucketPolicy",
          "s3:PutBucketPolicy",
          "s3:DeleteBucketPolicy",

          "s3:GetBucketTagging",
          "s3:PutBucketTagging",
          "s3:DeleteBucketTagging",

          "s3:GetBucketVersioning",
          "s3:PutBucketVersioning",

          "s3:GetLifecycleConfiguration",
          "s3:PutLifecycleConfiguration",
          "s3:DeleteLifecycleConfiguration"
        ]

        Resource = "*"
      },


      # =====================================================
      # OBJECT LISTING
      # =====================================================

      {
        Sid    = "TrainerObjectListing"
        Effect = "Allow"

        Action = [
          "s3:ListBucket"
        ]

        Resource = aws_s3_bucket.model_bucket.arn
      },


      # =====================================================
      # OBJECT PERMISSIONS
      # =====================================================

      {
        Sid    = "TrainerObjectAccess"
        Effect = "Allow"

        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",

          "s3:PutObject",

          "s3:DeleteObject",
          "s3:DeleteObjectVersion",

          "s3:GetObjectAcl",
          "s3:PutObjectAcl"
        ]

        Resource = "${aws_s3_bucket.model_bucket.arn}/*"
      }
    ]
  })
}
# =========================================================
# TRAINER - SECRETS MANAGER
# =========================================================

resource "aws_iam_role_policy" "trainer_secrets_policy" {
  name = "${var.dev_instance_name}-secrets-policy"
  role = aws_iam_role.trainer_role.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Sid    = "TrainerSecretAccess"
        Effect = "Allow"

        Action = [
          "secretsmanager:GetSecretValue"
        ]

        Resource = aws_secretsmanager_secret.dev_secret.arn
      }
    ]
  })
}


# =========================================================
# TRAINER - ECR PULL
# =========================================================

resource "aws_iam_role_policy" "trainer_ecr_policy" {
  name = "${var.dev_instance_name}-ecr-policy"
  role = aws_iam_role.trainer_role.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Sid    = "ECRAuthentication"
        Effect = "Allow"

        Action = [
          "ecr:GetAuthorizationToken"
        ]

        Resource = "*"
      },

      {
        Sid    = "ECRPull"
        Effect = "Allow"

        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer"
        ]

        Resource = aws_ecr_repository.repo.arn
      }
    ]
  })
}


# =========================================================
# TRAINER INSTANCE PROFILE
# =========================================================

resource "aws_iam_instance_profile" "trainer_profile" {
  name = "${var.dev_instance_name}-instance-profile"

  role = aws_iam_role.trainer_role.name
}


# =========================================================
# =========================================================
# PRODUCTION EC2 IAM ROLE
# =========================================================
# =========================================================

resource "aws_iam_role" "production_role" {
  name = "${var.prod_instance_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Sid    = "EC2AssumeRole"
        Effect = "Allow"

        Principal = {
          Service = "ec2.amazonaws.com"
        }

        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Environment = "production"
    Role        = "production"
    ManagedBy   = "terraform"
  }
}


# =========================================================
# PRODUCTION - SSM
# =========================================================

resource "aws_iam_role_policy_attachment" "production_ssm" {
  role = aws_iam_role.production_role.name

  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}


# =========================================================
# PRODUCTION - S3 READ ONLY
# =========================================================
resource "aws_iam_role_policy" "production_s3_policy" {
  name = "${var.prod_instance_name}-s3-policy"
  role = aws_iam_role.production_role.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [

      # =====================================================
      # BUCKET ACCESS + OBJECT LISTING
      # =====================================================

      {
        Sid    = "ProductionBucketRead"
        Effect = "Allow"

        Action = [
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]

        Resource = aws_s3_bucket.model_bucket.arn
      },

      # =====================================================
      # OBJECT READ ACCESS
      # =====================================================

      {
        Sid    = "ProductionObjectRead"
        Effect = "Allow"

        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion"
        ]

        Resource = "${aws_s3_bucket.model_bucket.arn}/*"
      }
    ]
  })
}

# =========================================================
# PRODUCTION - SECRETS MANAGER
# =========================================================

resource "aws_iam_role_policy" "production_secrets_policy" {
  name = "${var.prod_instance_name}-secrets-policy"
  role = aws_iam_role.production_role.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Sid    = "ProductionSecretAccess"
        Effect = "Allow"

        Action = [
          "secretsmanager:GetSecretValue"
        ]

        Resource = aws_secretsmanager_secret.prod_secret.arn
      }
    ]
  })
}


# =========================================================
# PRODUCTION - ECR PULL
# =========================================================

resource "aws_iam_role_policy" "production_ecr_policy" {
  name = "${var.prod_instance_name}-ecr-policy"
  role = aws_iam_role.production_role.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Sid    = "ECRAuthentication"
        Effect = "Allow"

        Action = [
          "ecr:GetAuthorizationToken"
        ]

        Resource = "*"
      },

      {
        Sid    = "ECRPull"
        Effect = "Allow"

        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer"
        ]

        Resource = aws_ecr_repository.repo.arn
      }
    ]
  })
}


# =========================================================
# PRODUCTION INSTANCE PROFILE
# =========================================================

resource "aws_iam_instance_profile" "production_profile" {
  name = "${var.prod_instance_name}-instance-profile"

  role = aws_iam_role.production_role.name
}


# =========================================================
# =========================================================
# GITHUB OIDC PROVIDER
# =========================================================
# =========================================================

resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = [
    "sts.amazonaws.com"
  ]
}


# =========================================================
# GITHUB ACTIONS IAM ROLE
# =========================================================

resource "aws_iam_role" "github_actions_role" {
  name = "github-actions-deployment-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Sid    = "GitHubActionsOIDC"
        Effect = "Allow"

        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }

        Action = "sts:AssumeRoleWithWebIdentity"

        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"

            "token.actions.githubusercontent.com:sub" = "repo:${var.github_repository}:ref:refs/heads/main"
          }
        }
      }
    ]
  })

  tags = {
    ManagedBy = "terraform"
    Purpose   = "GitHub Actions deployment"
  }
}


# =========================================================
# GITHUB - ECR PUSH
# =========================================================

resource "aws_iam_role_policy" "github_ecr_policy" {
  name = "github-ecr-push"
  role = aws_iam_role.github_actions_role.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Sid    = "ECRAuthentication"
        Effect = "Allow"

        Action = [
          "ecr:GetAuthorizationToken"
        ]

        Resource = "*"
      },

      {
        Sid    = "ECRPush"
        Effect = "Allow"

        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:CompleteLayerUpload",
          "ecr:InitiateLayerUpload",
          "ecr:PutImage",
          "ecr:UploadLayerPart",
          ]

          Resource = "*"
      }
    ]
  })
}


# =========================================================
# GITHUB - EC2 DISCOVERY
# =========================================================

resource "aws_iam_role_policy" "github_ec2_describe_policy" {
  name = "github-ec2-discovery"
  role = aws_iam_role.github_actions_role.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Sid    = "DescribeInstances"
        Effect = "Allow"

        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceStatus"
        ]

        Resource = "*"
      }
    ]
  })
}


# =========================================================
# GITHUB - EC2 START / STOP
#
# Used if your workflow starts/stops instances to save cost.
# =========================================================

resource "aws_iam_role_policy" "github_ec2_power_policy" {
  name = "github-ec2-power"
  role = aws_iam_role.github_actions_role.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Sid    = "StartStopTrainerProduction"
        Effect = "Allow"

        Action = [
          "ec2:StartInstances",
          "ec2:StopInstances"
        ]

        Resource = "*"

        Condition = {
          StringEquals = {
            "ec2:ResourceTag/Role" = [
              "trainer",
              "production"
            ]
          }
        }
      }
    ]
  })
}


# =========================================================
# GITHUB - SSM SEND COMMAND
# =========================================================

resource "aws_iam_role_policy" "github_ssm_policy" {
  name = "github-ssm-deployment"
  role = aws_iam_role.github_actions_role.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
    # -----------------------------------------------------
      # Check whether SSM agent is online
      # -----------------------------------------------------

      {
        Sid    = "DescribeSSMInstances"
        Effect = "Allow"

        Action = [
          "ssm:DescribeInstanceInformation"
        ]

        Resource = "*"
      },

      # -----------------------------------------------------
      # Allow using AWS-RunShellScript
      # -----------------------------------------------------

      {
        Sid    = "RunShellScriptDocument"
        Effect = "Allow"

        Action = [
          "ssm:SendCommand"
        ]

        Resource = "arn:aws:ssm:${var.aws_region}:*:document/AWS-RunShellScript"
      },

      # -----------------------------------------------------
      # Allow sending commands to tagged EC2 instances
      # -----------------------------------------------------

      {
        Sid    = "RunCommandOnTaggedInstances"
        Effect = "Allow"

        Action = [
          "ssm:SendCommand"
        ]

        Resource = "arn:aws:ec2:${var.aws_region}:*:instance/*"

        Condition = {
          StringEquals = {
            "ssm:resourceTag/Role" = [
              "trainer",
              "production"
            ]
          }
        }
      },

      # -----------------------------------------------------
      # Check command result
      # -----------------------------------------------------

      {
        Sid    = "ReadSSMCommandStatus"
        Effect = "Allow"

        Action = [
          "ssm:GetCommandInvocation",
          "ssm:ListCommandInvocations",
          "ssm:ListCommands"
        ]

        Resource = "*"
      }
    ]
  })
}


# =========================================================
# =========================================================
# TRAINER EC2 INSTANCE
# =========================================================
# =========================================================

resource "aws_instance" "trainer" {

  ami           = "ami-04bc53b7a499f5d37"
  instance_type = var.dev_instance_type

  key_name = aws_key_pair.generated_key.key_name

  vpc_security_group_ids = [
    aws_security_group.app_security_group.id
  ]

  iam_instance_profile = aws_iam_instance_profile.trainer_profile.name
  root_block_device {
    volume_size = 40
    volume_type = "gp3"
    encrypted   = true
  }
  user_data = templatefile("${path.module}/setup.sh", {

    aws_region = var.aws_region

    secret_manager_name = var.secret_manager_dev_name

    environment = "development"
  })

  depends_on = [
    aws_secretsmanager_secret_version.dev_secret_version
  ]

  tags = {
    Name        = var.dev_instance_name
    Role        = "trainer"
    Environment = "development"
    ManagedBy   = "terraform"
  }
}


# =========================================================
# =========================================================
# PRODUCTION EC2 INSTANCE
# =========================================================
# =========================================================

resource "aws_instance" "web_server" {

  ami           = "ami-04bc53b7a499f5d37"
  instance_type = var.prod_instance_type

  key_name = aws_key_pair.generated_key.key_name

  vpc_security_group_ids = [
    aws_security_group.app_security_group.id
  ]

  iam_instance_profile = aws_iam_instance_profile.production_profile.name
  root_block_device {
    volume_size = 40
    volume_type = "gp3"
    encrypted   = true
  }
  user_data = templatefile("${path.module}/setup.sh", {

    aws_region = var.aws_region

    secret_manager_name = var.secret_manager_prod_name

    environment = "production"
  })

  depends_on = [
    aws_secretsmanager_secret_version.prod_secret_version
  ]

  tags = {
    Name        = var.prod_instance_name
    Role        = "production"
    Environment = "production"
    ManagedBy   = "terraform"
  }
}


# =========================================================
# =========================================================
# EXPORT
# =========================================================
# =========================================================

locals {

  terraform_export = {

    ecr_repo = {
      name           = aws_ecr_repository.repo.name
      url            = aws_ecr_repository.repo.repository_url
      arn            = aws_ecr_repository.repo.arn
      registry       = split("/", aws_ecr_repository.repo.repository_url)[0]
    }

    s3_bucket = {
      name = aws_s3_bucket.model_bucket.bucket
      arn  = aws_s3_bucket.model_bucket.arn
    }

    roles = {

      github = {
        name = aws_iam_role.github_actions_role.name
        arn  = aws_iam_role.github_actions_role.arn
      }

      trainer = {
        name = aws_iam_role.trainer_role.name
        arn  = aws_iam_role.trainer_role.arn
      }

      production = {
        name = aws_iam_role.production_role.name
        arn  = aws_iam_role.production_role.arn
      }
    }

    instances = {

      trainer = {
        id         = aws_instance.trainer.id
        public_ip  = aws_instance.trainer.public_ip
        private_ip = aws_instance.trainer.private_ip
        role       = "trainer"
      }

      production = {
        id         = aws_instance.web_server.id
        public_ip  = aws_instance.web_server.public_ip
        private_ip = aws_instance.web_server.private_ip
        role       = "production"
      }
    }
  }
}


resource "local_file" "terraform_export" {
  content  = jsonencode(local.terraform_export)
  filename = "${path.module}/terraform-outputs.json"
}


# =========================================================
# OUTPUTS
# =========================================================

output "private_key_path" {
  value = local_file.private_key.filename
}


output "trainer_instance_id" {
  value = aws_instance.trainer.id
}


output "trainer_public_ip" {
  value = aws_instance.trainer.public_ip
}


output "production_instance_id" {
  value = aws_instance.web_server.id
}


output "production_public_ip" {
  value = aws_instance.web_server.public_ip
}


output "ecr_url" {
  value = aws_ecr_repository.repo.repository_url
}


output "s3_bucket_name" {
  value = aws_s3_bucket.model_bucket.bucket
}


output "github_actions_role_arn" {
  value = aws_iam_role.github_actions_role.arn
}


output "trainer_role_arn" {
  value = aws_iam_role.trainer_role.arn
}


output "production_role_arn" {
  value = aws_iam_role.production_role.arn
}