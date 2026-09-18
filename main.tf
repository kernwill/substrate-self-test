terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# --- app_data: fully configured. Every control substrate currently
# understands for S3 is satisfied here, so this is the "should read
# as covered evidence" side of the fixture, and the target for the
# later "introduce a regression" self-test (flip one of these off,
# re-run compile+gate, confirm it's caught, flip it back, confirm the
# fix is picked up). ---

resource "aws_s3_bucket" "app_data" {
  bucket = "substrate-self-test-app-data"
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

# --- app_logs: deliberately under-configured. No versioning
# resource, no encryption resource, and a public access block that
# leaves every flag open. This is real "not_satisfied"-shaped raw
# evidence for AC-3 (once a backend predicate exists to judge it) and
# a second, independent target for later self-testing. ---

resource "aws_s3_bucket" "app_logs" {
  bucket = "substrate-self-test-app-logs"
}

resource "aws_s3_bucket_public_access_block" "app_logs" {
  bucket                  = aws_s3_bucket.app_logs.id
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}
