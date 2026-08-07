variable "aws_access_key" {
  description = "AWS access key"
  type        = string
}

variable "aws_secret_key" {
  description = "AWS secret key"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}


variable "key_pair_name" {
  description = "ssh-key pair name"
  type        = string
}

variable "dev_instance_name" {
  description = "development instance name"
  type        = string
}

variable "prod_instance_name" {
  description = "production instance name"
  type        = string
}

variable "dev_instance_type" {
  description = "development instance type"
  type        = string
}

variable "prod_instance_type" {
  description = "production instance type"
  type        = string
}