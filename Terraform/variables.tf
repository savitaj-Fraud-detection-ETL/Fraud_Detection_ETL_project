variable "aws_access_key" {
  description = "AWS Access Key"
  type        = string
  sensitive   = true
}

variable "aws_secret_key" {
  description = "AWS Secret Key"
  type        = string
  sensitive   = true
}

variable "rds_password" {
  description = "Password for RDS PostgreSQL"
  type        = string
  sensitive   = true
}

provider "aws" {
  region = "ca-central-1"
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
}

variable "lambda_file" {
  description = "Lambda file location"
  type        = string
  sensitive   = false
}

variable "lambda_layer_dependencies_file" {
  description = "Lambda file location"
  type        = string
  sensitive   = false
}