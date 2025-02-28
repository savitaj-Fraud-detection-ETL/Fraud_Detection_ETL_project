# TODO: Currently, sensitive variables (RDS password) are defined via terraform.tfvars.
# For improved security and industry-standard practice, the next step is to implement AWS Secrets Manager
# to manage sensitive information securely and avoid storing plaintext credentials in configuration files.


# S3 Bucket for Fraud Data
resource "aws_s3_bucket" "fraud_data" {
  bucket = "fraud-transactions-data-bucket"

  tags = {
    Project = "fraud-detection-ETL"
  }
}

# IAM Role for AWS Lambda
resource "aws_iam_role" "lambda_role" {
  name = "fraud_detection_lambda_execution_role"

  tags = {
    Project = "fraud-detection-ETL"
  }

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

# IAM Policy for Lambda to access S3 & RDS
resource "aws_iam_policy" "lambda_policy" {
  name        = "fraud_detection_lambda_s3_rds_policy"
  description = "Allows Lambda to access S3 and RDS"

  tags = {
    Project = "fraud-detection-ETL"
  }

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:GetObject"],
      "Resource": "arn:aws:s3:::fraud-transactions-data-bucket/*"
    },
    {
      "Effect": "Allow",
      "Action": ["s3:GetObject"],
      "Resource": "arn:aws:s3:::frauddetectionetl-lambda-function-layer/*"
    },
    {
      "Effect": "Allow",
      "Action": ["rds:*"],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:*:*:*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "lambda:GetLayerVersion",
        "lambda:GetLayerVersionPolicy"
      ],
      "Resource": "arn:aws:lambda:us-east-1:336392948345:layer:AWSLambda-Python39-SciPy1x:3"
    }
  ]
}
EOF
}

# Attach IAM Policy to Lambda Role
resource "aws_iam_role_policy_attachment" "lambda_policy_attach" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

# AWS RDS PostgreSQL Instance
resource "aws_db_instance" "fraud_rds" {
  allocated_storage    = 20
  engine              = "postgres"
  instance_class      = "db.t3.micro"
  identifier          = "fraud-detection-rds"
  username           = "fraud_etl_admin"
  password           = var.rds_password
  publicly_accessible = true
  skip_final_snapshot = true

  tags = {
    Project = "fraud-detection-ETL"
  }
}

#AWS Lambda function Layer - Pandas, psycopg2

resource "aws_s3_bucket" "fraudDetectionETL_lambda_function_dependencyLayer_bucket"{
  bucket = "frauddetectionetl-lambda-function-layer"
}

resource "aws_s3_object" "fraudDetectionETL_lambda_function_layer_zip"{
  bucket = aws_s3_bucket.fraudDetectionETL_lambda_function_dependencyLayer_bucket.id
  key = "frauddetectionetl-main/dependencies.zip"
  source = var.lambda_layer_dependencies_file
  etag = filemd5(var.lambda_layer_dependencies_file)
}

resource "aws_lambda_layer_version" "fraudDetectionETL_lambda_function_layer" {
  layer_name = "fraudDetectionETL_python_dependencies_pandas_psycopg2"
  s3_bucket = aws_s3_bucket.fraudDetectionETL_lambda_function_dependencyLayer_bucket.id
  s3_key = aws_s3_object.fraudDetectionETL_lambda_function_layer_zip.key
  compatible_runtimes = ["python3.9"]
  description = "Containes dependencies for pandas and psycopg2"
}

# AWS Lambda Function
resource "aws_lambda_function" "fraud_lambda" {
  function_name    = "fraud-detection-etl-lambda"
  runtime         = "python3.9"
  role            = aws_iam_role.lambda_role.arn
  handler         = "lambda_function_aws.lambda_handler"
  filename        = var.lambda_file
  source_code_hash = filebase64sha256(var.lambda_file)
  layers = [aws_lambda_layer_version.fraudDetectionETL_lambda_function_layer.arn]
  timeout = 50

  tags = {
    Project = "fraud-detection-ETL"
  }

  environment {
    variables = {
      S3_BUCKET = aws_s3_bucket.fraud_data.bucket
      RDS_HOST  = aws_db_instance.fraud_rds.address
      RDS_USER  = "fraud_etl_admin"
      RDS_PASS  = var.rds_password
      RDS_DB    = "fraud_detection_db"
    }
  }
}

# S3 Event Notification to Trigger Lambda
resource "aws_s3_bucket_notification" "fraud_data_notification" {
  bucket = aws_s3_bucket.fraud_data.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.fraud_lambda.arn
    events             = ["s3:ObjectCreated:*"]
  }
}

# Allow S3 to Invoke Lambda
resource "aws_lambda_permission" "allow_s3" {
  statement_id  = "AllowExecutionFromS3"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.fraud_lambda.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.fraud_data.arn
}

resource "aws_cloudwatch_log_group" "fraud_lambda_log_group" {
  name              = "/aws/lambda/${aws_lambda_function.fraud_lambda.function_name}"
  retention_in_days = 14 

  tags = {
    Project = "fraud-detection-ETL"
  }
}


# Output Useful Values
output "s3_bucket_name" {
  value = aws_s3_bucket.fraud_data.bucket
}

output "rds_endpoint" {
  value = aws_db_instance.fraud_rds.endpoint
}

output "rds_address" {
  value = aws_db_instance.fraud_rds.address
}

output "lambda_function_name" {
  value = aws_lambda_function.fraud_lambda.function_name
}