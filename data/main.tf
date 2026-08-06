#################################
# Generate SSH key pair
#################################

resource "tls_private_key" "ssh_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}


#################################
# Save private key locally
#################################

resource "local_file" "private_key" {
  content         = tls_private_key.ssh_key.private_key_pem
  filename        = "./terraform-key.pem"
  file_permission = "0600"
}


#################################
# Upload public key to EC2
#################################

resource "aws_key_pair" "generated_key" {
  key_name   = "terraform-key"
  public_key = tls_private_key.ssh_key.public_key_openssh
}


#################################
# Security group
#################################

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


#################################
# EC2 Instance
#################################

resource "aws_instance" "web_server" {

  # Replace this with an AMI available in LocalStack
  ami = "ami-024f768332f0"

  instance_type = "t2.micro"

  key_name = aws_key_pair.generated_key.key_name


  security_groups = [
    aws_security_group.ssh_access.name
  ]


  user_data = <<-EOF
              #!/bin/bash
              echo "Hello from Terraform LocalStack EC2" > /tmp/message.txt
              EOF


  tags = {
    Name = "terraform-test-instance"
  }
}


#################################
# Outputs
#################################

output "instance_id" {
  value = aws_instance.web_server.id
}


output "private_key_path" {
  value = local_file.private_key.filename
}


output "private_ip" {
  value = aws_instance.web_server.private_ip
}