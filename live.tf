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

# --- Substrate's own collection identity: read-only. ---
# A role holding exactly substrate's published read-only policy
# (substrate-readonly-policy.json, a copy of substrate's
# docs/aws-readonly-policy.json - re-copy it when that file changes).
# Only the substrate-self-test user can assume it, so collection needs
# no new long-lived keys: the "substrate-collector" profile in
# ~/.aws/config assumes it from the default profile.
resource "aws_iam_policy" "substrate_readonly" {
  name   = "substrate-readonly"
  policy = jsonencode(jsondecode(file("${path.module}/substrate-readonly-policy.json")))
}

resource "aws_iam_role" "substrate_collector" {
  name = "substrate-collector"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:user/substrate-self-test" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "substrate_collector" {
  role       = aws_iam_role.substrate_collector.name
  policy_arn = aws_iam_policy.substrate_readonly.arn
}

# --- ca-7: one AWS Config managed rule, so the recorder produces
# continuous compliance results, not just configuration history. Every
# bucket here refuses non-TLS requests, so it should read COMPLIANT. ---
resource "aws_config_config_rule" "s3_tls_only" {
  name = "s3-bucket-ssl-requests-only"
  source {
    owner             = "AWS"
    source_identifier = "S3_BUCKET_SSL_REQUESTS_ONLY"
  }
  depends_on = [aws_config_configuration_recorder.main]
}

# --- sc-28: one small encrypted EBS volume, unattached. It gives the EBS
# collector a real volume to read; nothing is stored on it. ---
resource "aws_ebs_volume" "encrypted" {
  availability_zone = "us-east-2a"
  size              = 1
  type              = "gp3"
  encrypted         = true
  tags              = { Name = "substrate-self-test-encrypted" }
}

# --- cp-9.8 and cp-10.2: one small encrypted PostgreSQL instance with
# automated backups, so the RDS collector has a real database to read.
# It holds no data. Not reachable from anywhere: no public address and a
# security group with no rules. AWS generates the master password and
# keeps it in Secrets Manager, so it is never in Terraform state.
# No cross-Region copy yet (the free plan allows only us-east-2), so
# substrate correctly reports cp-6, cp-6.1, cp-7 and cp-7.1 as not
# satisfied until one exists. ---
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "aws_db_subnet_group" "app" {
  name       = "substrate-self-test"
  subnet_ids = data.aws_subnets.default.ids
}

resource "aws_security_group" "db" {
  name        = "substrate-self-test-db"
  description = "No inbound or outbound rules: nothing can reach the database"
  vpc_id      = data.aws_vpc.default.id
}

resource "aws_db_instance" "app" {
  identifier                  = "substrate-self-test"
  engine                      = "postgres"
  engine_version              = "16"
  instance_class              = "db.t4g.micro"
  allocated_storage           = 20
  storage_type                = "gp3"
  storage_encrypted           = true
  kms_key_id                  = aws_kms_key.app.arn
  username                    = "substrate"
  manage_master_user_password = true
  db_subnet_group_name        = aws_db_subnet_group.app.name
  vpc_security_group_ids      = [aws_security_group.db.id]
  publicly_accessible         = false
  backup_retention_period     = 7
  skip_final_snapshot         = true
  deletion_protection         = false
}
