terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  # The account's free plan allows only its selected Region (us-east-2).
  region = "us-east-2"
}

data "aws_caller_identity" "current" {}

locals {
  # S3 bucket names are global across all accounts; the account ID keeps
  # these unique.
  suffix = data.aws_caller_identity.current.account_id
}

# --- app_data: fully configured. Every control substrate currently
# understands for S3 is satisfied here, so this is the "should read
# as covered evidence" side of the fixture, and the target for the
# later "introduce a regression" self-test (flip one of these off,
# re-run compile+gate, confirm it's caught, flip it back, confirm the
# fix is picked up). ---

resource "aws_s3_bucket" "app_data" {
  bucket = "substrate-self-test-app-data-${local.suffix}"
}

resource "aws_s3_bucket_versioning" "app_data" {
  bucket = aws_s3_bucket.app_data.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "app_data" {
  bucket = aws_s3_bucket.app_data.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "app_data" {
  bucket                  = aws_s3_bucket.app_data.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# --- app_logs: the regression target. Configured well by default. To
# test that compile + gate catch a regression, set the four
# public-access-block flags below to false and remove the
# DenyInsecureTransport statement, apply, compile, gate; then revert.
# Plain literals on purpose: substrate's static parser doesn't evaluate
# conditionals over variables (it records them unresolved), so a
# variable "switch" would lose the static evidence. ---

resource "aws_s3_bucket" "app_logs" {
  bucket = "substrate-self-test-app-logs-${local.suffix}"
}

resource "aws_s3_bucket_public_access_block" "app_logs" {
  bucket                  = aws_s3_bucket.app_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "app_logs" {
  bucket = aws_s3_bucket.app_logs.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource  = [aws_s3_bucket.app_logs.arn, "${aws_s3_bucket.app_logs.arn}/*"]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })
  depends_on = [aws_s3_bucket_public_access_block.app_logs]
}
