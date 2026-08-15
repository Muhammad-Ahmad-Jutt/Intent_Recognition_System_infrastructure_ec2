# =========================================================
# AWS
# =========================================================

variable "aws_region" {
  description = "AWS region"
  type        = string
}


# =========================================================
# GITHUB
# =========================================================

variable "github_repository" {
  description = "GitHub repository in owner/repository format"
  type        = string
}


# =========================================================
# EC2 / SSH
# =========================================================

variable "key_pair_name" {
  description = "SSH key pair name"
  type        = string
}


variable "dev_instance_name" {
  description = "Development/trainer EC2 instance name"
  type        = string
}


variable "prod_instance_name" {
  description = "Production EC2 instance name"
  type        = string
}


variable "dev_instance_type" {
  description = "Development/trainer EC2 instance type"
  type        = string
}


variable "prod_instance_type" {
  description = "Production EC2 instance type"
  type        = string
}


# =========================================================
# S3 / ECR
# =========================================================

variable "s3_bucket_name" {
  description = "Private S3 bucket used for datasets and ML models"
  type        = string
}


variable "ecr_repo_name" {
  description = "ECR repository name"
  type        = string
}


# =========================================================
# SECRETS MANAGER
# =========================================================

variable "secret_manager_dev_name" {
  description = "Development/trainer Secrets Manager secret name"
  type        = string
}


variable "secret_manager_prod_name" {
  description = "Production Secrets Manager secret name"
  type        = string
}


# =========================================================
# APPLICATION / TRAINING CONFIGURATION
# =========================================================

variable "command" {
  description = "Application/training command"
  type        = string
}


variable "hf_token" {
  description = "HuggingFace token"
  type        = string
  sensitive   = true
}


variable "model_name" {
  description = "Machine learning model name"
  type        = string
}


variable "dataset_path" {
  description = "Dataset path"
  type        = string
}


variable "new_dataset_folder" {
  description = "New dataset folder"
  type        = string
}


variable "test_size" {
  description = "Test dataset ratio"
  type        = string
}


variable "random_state" {
  description = "Random state"
  type        = string
}


variable "num_train_epochs" {
  description = "Number of training epochs"
  type        = string
}


variable "per_device_train_batch_size" {
  description = "Training batch size per device"
  type        = string
}


variable "per_device_eval_batch_size" {
  description = "Evaluation batch size per device"
  type        = string
}


variable "weight_decay" {
  description = "Weight decay"
  type        = string
}


variable "eval_strategy" {
  description = "Evaluation strategy"
  type        = string
}


variable "save_strategy" {
  description = "Save strategy"
  type        = string
}


variable "load_best_model_at_end" {
  description = "Load best model at end"
  type        = string
}


variable "logging_steps" {
  description = "Logging steps"
  type        = string
}


variable "learning_rate" {
  description = "Learning rate"
  type        = string
}


variable "logging_strategy" {
  description = "Logging strategy"
  type        = string
}


variable "metric_for_best_model" {
  description = "Metric used for best model selection"
  type        = string
}


variable "greater_is_better" {
  description = "Whether greater metric values are better"
  type        = string
}


variable "model_out_directory" {
  description = "Model output directory"
  type        = string
}


variable "model_path" {
  description = "Model path"
  type        = string
}


variable "metrics_output_file" {
  description = "Metrics output file"
  type        = string
}


variable "label_mapping_file_path" {
  description = "Label mapping file path"
  type        = string
}


variable "accuracy_comparison_file" {
  description = "Accuracy comparison file"
  type        = string
}


variable "unseen_data_path" {
  description = "Unseen data path"
  type        = string
}