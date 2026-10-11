# si-12.3: information is disposed of after its retention period, by S3
# lifecycle expiration (the founder chose 1 year on 2026-10-11). Each
# bucket below expires objects 365 days after they're written and, where
# versioning keeps replaced or deleted objects, their old versions 30
# days after they stop being current. Incomplete multipart uploads are
# cleaned up after 7 days. The Terraform state bucket is deliberately
# kept: it's the system's own record (substrate-parameters.yaml,
# disposal.keep).
#
# The audit bucket's 365 days is also au-11's audit record retention.

locals {
  retention_days  = 365
  noncurrent_days = 30
}

resource "aws_s3_bucket_lifecycle_configuration" "app_data" {
  bucket = aws_s3_bucket.app_data.id
  rule {
    id     = "dispose-after-retention"
    status = "Enabled"
    filter {}
    expiration {
      days = local.retention_days
    }
    noncurrent_version_expiration {
      noncurrent_days = local.noncurrent_days
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "app_logs" {
  bucket = aws_s3_bucket.app_logs.id
  rule {
    id     = "dispose-after-retention"
    status = "Enabled"
    filter {}
    expiration {
      days = local.retention_days
    }
    noncurrent_version_expiration {
      noncurrent_days = local.noncurrent_days
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "audit" {
  bucket = aws_s3_bucket.audit.id
  rule {
    id     = "dispose-after-retention"
    status = "Enabled"
    filter {}
    expiration {
      days = local.retention_days
    }
    noncurrent_version_expiration {
      noncurrent_days = local.noncurrent_days
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}
