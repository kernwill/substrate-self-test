# Live test resources for substrate's AWS collectors (approved
# 2026-10-06). Each one gives a collector real data to read: good
# configurations that should pass, and app_logs (main.tf) staying
# deliberately weak. All read by substrate with read-only access; this
# file is the only thing that creates them.

# --- sc-8: app_data accepts only TLS connections. ---
resource "aws_s3_bucket_policy" "app_data_tls_only" {
  bucket = aws_s3_bucket.app_data.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource  = [aws_s3_bucket.app_data.arn, "${aws_s3_bucket.app_data.arn}/*"]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })
  depends_on = [aws_s3_bucket_public_access_block.app_data]
}

# --- sc-12: a customer-managed KMS key with rotation on. ---
resource "aws_kms_key" "app" {
  description             = "substrate self-test key"
  enable_key_rotation     = true
  deletion_window_in_days = 7
}

resource "aws_kms_alias" "app" {
  name          = "alias/substrate-self-test"
  target_key_id = aws_kms_key.app.key_id
}

# --- Audit logging: a bucket for CloudTrail and AWS Config. ---
resource "aws_s3_bucket" "audit" {
  bucket        = "substrate-self-test-audit-${local.suffix}"
  force_destroy = true
}

resource "aws_s3_bucket_versioning" "audit" {
  bucket = aws_s3_bucket.audit.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "audit" {
  bucket = aws_s3_bucket.audit.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_s3_bucket_public_access_block" "audit" {
  bucket                  = aws_s3_bucket.audit.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "audit" {
  bucket = aws_s3_bucket.audit.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "CloudTrailAclCheck"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.audit.arn
      },
      {
        Sid       = "CloudTrailWrite"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.audit.arn}/cloudtrail/AWSLogs/${local.suffix}/*"
        Condition = { StringEquals = { "s3:x-amz-acl" = "bucket-owner-full-control" } }
      },
      {
        Sid       = "ConfigAclCheck"
        Effect    = "Allow"
        Principal = { Service = "config.amazonaws.com" }
        Action    = ["s3:GetBucketAcl", "s3:ListBucket"]
        Resource  = aws_s3_bucket.audit.arn
      },
      {
        Sid       = "ConfigWrite"
        Effect    = "Allow"
        Principal = { Service = "config.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.audit.arn}/config/AWSLogs/${local.suffix}/*"
        Condition = { StringEquals = { "s3:x-amz-acl" = "bucket-owner-full-control" } }
      },
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = [aws_s3_bucket.audit.arn, "${aws_s3_bucket.audit.arn}/*"]
        Condition = { Bool = { "aws:SecureTransport" = "false" } }
      },
    ]
  })
  depends_on = [aws_s3_bucket_public_access_block.audit]
}

# --- au-2, au-7, au-9, au-12: a CloudTrail trail with log file
# validation, delivering to CloudWatch Logs. Single-Region: the free
# plan doesn't support multi-Region trails. ---
resource "aws_cloudwatch_log_group" "trail" {
  name              = "/substrate-self-test/cloudtrail"
  retention_in_days = 30
}

resource "aws_iam_role" "trail_to_logs" {
  name = "substrate-self-test-cloudtrail-logs"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "cloudtrail.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}

resource "aws_iam_role_policy" "trail_to_logs" {
  name = "write-log-events"
  role = aws_iam_role.trail_to_logs.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "${aws_cloudwatch_log_group.trail.arn}:*"
    }]
  })
}

resource "aws_cloudtrail" "main" {
  name                          = "substrate-self-test"
  s3_bucket_name                = aws_s3_bucket.audit.id
  s3_key_prefix                 = "cloudtrail"
  include_global_service_events = true
  is_multi_region_trail         = false
  enable_log_file_validation    = true
  cloud_watch_logs_group_arn    = "${aws_cloudwatch_log_group.trail.arn}:*"
  cloud_watch_logs_role_arn     = aws_iam_role.trail_to_logs.arn
  depends_on                    = [aws_s3_bucket_policy.audit, aws_iam_role_policy.trail_to_logs]
}

# --- cm-2.2, cm-6: AWS Config recording all supported resource types. ---
resource "aws_iam_service_linked_role" "config" {
  aws_service_name = "config.amazonaws.com"
}

resource "aws_config_configuration_recorder" "main" {
  name     = "default"
  role_arn = aws_iam_service_linked_role.config.arn
  recording_group {
    all_supported                 = true
    include_global_resource_types = true
  }
}

resource "aws_config_delivery_channel" "main" {
  name           = "default"
  s3_bucket_name = aws_s3_bucket.audit.id
  s3_key_prefix  = "config"
  depends_on     = [aws_config_configuration_recorder.main, aws_s3_bucket_policy.audit]
}

resource "aws_config_configuration_recorder_status" "main" {
  name       = aws_config_configuration_recorder.main.name
  is_enabled = true
  depends_on = [aws_config_delivery_channel.main]
}

# --- sc-21: Route 53 Resolver DNSSEC validation on the default VPC. ---
data "aws_vpc" "default" {
  default = true
}

resource "aws_route53_resolver_dnssec_config" "default_vpc" {
  resource_id = data.aws_vpc.default.id
}
