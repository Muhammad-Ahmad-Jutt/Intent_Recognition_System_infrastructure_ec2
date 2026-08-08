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
  key_name = var.key_pair_name

  public_key = tls_private_key.ssh_key.public_key_openssh
}


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



resource "aws_instance" "trainer" {

  ami = "ami-024f768332f0"

  instance_type = var.dev_instance_type

  key_name = aws_key_pair.generated_key.key_name


  security_groups = [
    aws_security_group.ssh_access.name
  ]


  user_data = file("setup.sh")


  tags = {

    Name = var.dev_instance_name

    Role = "trainer"

  }
}




resource "aws_instance" "web_server" {

  ami = "ami-024f768332f0"

  instance_type = var.prod_instance_type

  key_name = aws_key_pair.generated_key.key_name


  security_groups = [
    aws_security_group.ssh_access.name
  ]


  user_data = file("setup.sh")


  tags = {

    Name = var.prod_instance_name

    Role = "production"

  }
}



output "trainer_instance_id" {

  value = aws_instance.trainer.id

}

resource "aws_s3_bucket" "public_bucket" {
  bucket = var.s3_bucket_name

  tags = {
    Name    = var.s3_bucket_name
    Purpose = "public storage"
  }
}

resource "aws_s3_bucket_acl" "public_bucket_acl" {
  bucket = aws_s3_bucket.public_bucket.id
  acl    = "public-read"
}

resource "aws_s3_bucket_public_access_block" "public_bucket" {
  bucket = aws_s3_bucket.public_bucket.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "public_bucket_policy" {
  bucket = aws_s3_bucket.public_bucket.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid = "AllowPublicRead"
        Effect = "Allow"
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
          countNumber = 1
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

output "production_instance_id" {

  value = aws_instance.web_server.id

}


output "private_key_path" {

  value = local_file.private_key.filename

}


output "trainer_private_ip" {

  value = aws_instance.trainer.private_ip

}


output "production_private_ip" {

  value = aws_instance.web_server.private_ip

}