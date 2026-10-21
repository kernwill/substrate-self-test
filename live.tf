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
# validation, delivering to CloudWatch Logs. Multi-Region since
# 2026-10-08, so it also records us-west-2, where the database copies
# live (the old account's free plan didn't allow it). ---
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
  is_multi_region_trail         = true
  enable_log_file_validation    = true
  cloud_watch_logs_group_arn    = "${aws_cloudwatch_log_group.trail.arn}:*"
  cloud_watch_logs_role_arn     = aws_iam_role.trail_to_logs.arn
  depends_on                    = [aws_s3_bucket_policy.audit, aws_iam_role_policy.trail_to_logs]

  # Advanced selectors (2026-10-21) replace the default basic one, which
  # recorded management events only. The first keeps every management
  # event, reads and writes (au-2, au-12; a secret read is one).
  advanced_event_selector {
    name = "Management events"
    field_selector {
      field  = "eventCategory"
      equals = ["Management"]
    }
  }

  # ac-6.2: S3 object reads and writes (data events), so substrate can
  # check that no one with security access uses the system's data with
  # a privileged identity. Every bucket but the audit bucket: its writes
  # are CloudTrail's and Config's own deliveries, and recording them
  # would record each delivery of the records of the last. Reading audit
  # logs is a security function anyway (declared in
  # substrate-parameters.yaml). $0.10 per 100,000 events (checked
  # 2026-10-21); the self-test makes a few thousand a month.
  advanced_event_selector {
    name = "S3 object events except the audit bucket"
    field_selector {
      field  = "eventCategory"
      equals = ["Data"]
    }
    field_selector {
      field  = "resources.type"
      equals = ["AWS::S3::Object"]
    }
    field_selector {
      field           = "resources.ARN"
      not_starts_with = ["${aws_s3_bucket.audit.arn}/"]
    }
  }
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

# The second site's recorder (cm-8.3, pl-9): without it the RDS replica's
# Region has no inventory, so substrate can't check it. Global resources
# (IAM) are recorded once, in us-east-2. Deliveries go to the same audit
# bucket; Config writes across Regions.
resource "aws_config_configuration_recorder" "west" {
  provider = aws.west
  name     = "default"
  role_arn = aws_iam_service_linked_role.config.arn
  recording_group {
    all_supported                 = true
    include_global_resource_types = false
  }
}

resource "aws_config_delivery_channel" "west" {
  provider       = aws.west
  name           = "default"
  s3_bucket_name = aws_s3_bucket.audit.id
  s3_key_prefix  = "config"
  depends_on     = [aws_config_configuration_recorder.west, aws_s3_bucket_policy.audit]
}

resource "aws_config_configuration_recorder_status" "west" {
  provider   = aws.west
  name       = aws_config_configuration_recorder.west.name
  is_enabled = true
  depends_on = [aws_config_delivery_channel.west]
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
# Only the substrate-admin user can assume it, so collection needs
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
    Statement = [
      {
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:user/substrate-admin" }
        Action    = "sts:AssumeRole"
      },
      # The post-merge substrate run (cm-4.2): this repository's
      # workflows on main only, by GitHub OIDC (subject as in drift.tf).
      {
        Effect    = "Allow"
        Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
        Action    = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
            "token.actions.githubusercontent.com:sub" = "repo:kernwill@66508/substrate-self-test@1408966262:ref:refs/heads/main"
          }
        }
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "substrate_collector" {
  role       = aws_iam_role.substrate_collector.name
  policy_arn = aws_iam_policy.substrate_readonly.arn
}

# ac-6.2: reading the trail's records, which the read-only policy never
# allows (it reads no log or object contents). Substrate's opt-in
# docs/aws-trail-activity-policy.json, filled in for this trail's log
# group only.
resource "aws_iam_role_policy" "substrate_collector_trail_activity" {
  name = "substrate-trail-activity"
  role = aws_iam_role.substrate_collector.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "SubstrateTrailActivityReadTrailLogGroup"
      Effect   = "Allow"
      Action   = ["logs:FilterLogEvents"]
      Resource = ["${aws_cloudwatch_log_group.trail.arn}:*"]
    }]
  })
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
# security group with no rules. The master password is generated by
# Secrets Manager as an ephemeral value, stored in a Secrets Manager
# secret, and given to RDS write-only, so it is never in Terraform state.
# (RDS-managed passwords, used until 2026-10-08, rule out read replicas
# on every engine but SQL Server and Db2, per AWS's RDS documentation.)
# No cross-Region copy yet (a follow-up adds one in us-west-2), so
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

ephemeral "aws_secretsmanager_random_password" "db_master" {
  password_length     = 32
  exclude_punctuation = true
}

resource "aws_secretsmanager_secret" "db_master" {
  name       = "substrate-self-test/db-master"
  kms_key_id = aws_kms_key.app.arn
}

# The secret's value was written once (2026-10-08), write-only, and is
# no longer managed here: refreshing a secret version calls
# GetSecretValue even when it is write-only, and the nightly drift
# check's role must never read the database password (found
# 2026-10-09). The secret and its value stay in AWS; Terraform keeps
# managing the secret itself. To rotate, set a new password on the
# database (bump password_wo_version) and store the same value in the
# secret by hand with put-secret-value, outside this configuration.
removed {
  from = aws_secretsmanager_secret_version.db_master
  lifecycle {
    destroy = false
  }
}

resource "aws_db_instance" "app" {
  identifier              = "substrate-self-test"
  engine                  = "postgres"
  engine_version          = "16"
  instance_class          = "db.t4g.micro"
  allocated_storage       = 20
  storage_type            = "gp3"
  storage_encrypted       = true
  kms_key_id              = aws_kms_key.app.arn
  username                = "substrate"
  password_wo             = ephemeral.aws_secretsmanager_random_password.db_master.random_password
  password_wo_version     = 1
  db_subnet_group_name    = aws_db_subnet_group.app.name
  vpc_security_group_ids  = [aws_security_group.db.id]
  publicly_accessible     = false
  backup_retention_period = 7
  skip_final_snapshot     = true
  deletion_protection     = false
}

# --- Security services (2026-10-08), possible since the move to an
# account in Rookwright's own organization. GuardDuty with EBS malware
# protection (si-3, si-4, si-4.2, si-4.4, au-6, au-6.1), Security Hub
# (ca-7), Inspector EC2 and ECR scanning (ra-5, si-2.2), and Macie
# (cm-12.1). With no EC2 instances or ECR images, Inspector and
# GuardDuty's malware scans have nothing to scan and cost nothing. ---
resource "aws_guardduty_detector" "main" {
  enable = true
}

resource "aws_guardduty_detector_feature" "ebs_malware_protection" {
  detector_id = aws_guardduty_detector.main.id
  name        = "EBS_MALWARE_PROTECTION"
  status      = "ENABLED"
}

resource "aws_securityhub_account" "main" {
  enable_default_standards = true
  depends_on               = [aws_config_configuration_recorder_status.main]
}

resource "aws_inspector2_enabler" "main" {
  account_ids    = [data.aws_caller_identity.current.account_id]
  resource_types = ["EC2", "ECR"]
}

resource "aws_macie2_account" "main" {
  status = "ENABLED"
}

# --- Second site in us-west-2 (cp-6, cp-6.1, cp-7, cp-7.1): the
# database's automated backups are replicated there, and a read replica
# runs there. Both are encrypted with a key in us-west-2, since a KMS key
# can't be used outside its Region. Nothing in us-west-2 is reachable:
# no public address, and a security group with no rules. ---
provider "aws" {
  alias  = "west"
  region = "us-west-2"
}

resource "aws_kms_key" "app_west" {
  provider                = aws.west
  description             = "substrate self-test key, us-west-2"
  enable_key_rotation     = true
  deletion_window_in_days = 7
}

resource "aws_db_instance_automated_backups_replication" "app" {
  provider               = aws.west
  source_db_instance_arn = aws_db_instance.app.arn
  kms_key_id             = aws_kms_key.app_west.arn
  retention_period       = 7
}

data "aws_vpc" "default_west" {
  provider = aws.west
  default  = true
}

data "aws_subnets" "default_west" {
  provider = aws.west
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default_west.id]
  }
}

resource "aws_db_subnet_group" "app_west" {
  provider   = aws.west
  name       = "substrate-self-test-west"
  subnet_ids = data.aws_subnets.default_west.ids
}

resource "aws_security_group" "db_west" {
  provider    = aws.west
  name        = "substrate-self-test-db-west"
  description = "No inbound or outbound rules: nothing can reach the replica"
  vpc_id      = data.aws_vpc.default_west.id
}

resource "aws_db_instance" "app_replica" {
  provider               = aws.west
  identifier             = "substrate-self-test-replica"
  replicate_source_db    = aws_db_instance.app.arn
  instance_class         = "db.t4g.micro"
  storage_encrypted      = true
  kms_key_id             = aws_kms_key.app_west.arn
  db_subnet_group_name   = aws_db_subnet_group.app_west.name
  vpc_security_group_ids = [aws_security_group.db_west.id]
  publicly_accessible    = false
  skip_final_snapshot    = true
  deletion_protection    = false
}

# --- cm-7.1: least functionality. Each default VPC's default security
# group came with one rule allowing all traffic between its members.
# Nothing uses either group (no network interfaces, checked 2026-10-19),
# so both are adopted here with no rules at all: the system has no
# inbound access, which substrate-parameters.yaml declares. ---
resource "aws_default_security_group" "default" {
  vpc_id = data.aws_vpc.default.id
}

resource "aws_default_security_group" "default_west" {
  provider = aws.west
  vpc_id   = data.aws_vpc.default_west.id
}
