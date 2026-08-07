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