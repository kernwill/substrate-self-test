# Terraform state and drift detection (approved 2026-10-08, Phase A
# step 2). The state moves from this machine to a versioned S3 bucket,
# so every previous version of the baseline configuration is kept
# (cm-2.3), and a scheduled GitHub Actions job compares the live
# account with main every night (si-7, si-7.1) through a read-only role
# it reaches by OIDC, with no stored AWS keys.

# --- cm-2.3: the state bucket. Named literally (no interpolation): the
# backend block must name it literally, and substrate links the two by
# that literal name. ---
resource "aws_s3_bucket" "tfstate" {
  bucket = "substrate-self-test-tfstate-632839731153"
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket                  = aws_s3_bucket.tfstate.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource  = [aws_s3_bucket.tfstate.arn, "${aws_s3_bucket.tfstate.arn}/*"]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })
  depends_on = [aws_s3_bucket_public_access_block.tfstate]
}

# --- si-7: GitHub Actions reaches AWS by OIDC. Only workflows running
# on main, which changes only through a reviewed pull request, can
# assume the role. ---
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

resource "aws_iam_role" "drift_check" {
  name = "substrate-drift-check"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:sub" = "repo:kernwill/substrate-self-test:ref:refs/heads/main"
        }
      }
    }]
  })
  max_session_duration = 3600
}

# terraform plan refreshes every resource, so the role reads
# configuration across the account (AWS's ReadOnlyAccess)...
resource "aws_iam_role_policy_attachment" "drift_check_readonly" {
  role       = aws_iam_role.drift_check.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# ...but never data: it can read no S3 object except the state file and
# no secret value. Generating the database password during plan (an
# ephemeral value, never stored) needs GetRandomPassword.
resource "aws_iam_role_policy" "drift_check_limits" {
  name = "drift-check-limits"
  role = aws_iam_role.drift_check.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid         = "NoObjectReadsButState"
        Effect      = "Deny"
        Action      = ["s3:GetObject", "s3:GetObjectVersion"]
        NotResource = "${aws_s3_bucket.tfstate.arn}/self-test/terraform.tfstate"
      },
      {
        Sid      = "NoSecretValues"
        Effect   = "Deny"
        Action   = ["secretsmanager:GetSecretValue", "ssm:GetParameter*", "kms:Decrypt"]
        Resource = "*"
      },
      {
        Sid      = "ReadState"
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "${aws_s3_bucket.tfstate.arn}/self-test/terraform.tfstate"
      },
      {
        Sid      = "EphemeralPassword"
        Effect   = "Allow"
        Action   = ["secretsmanager:GetRandomPassword"]
        Resource = "*"
      },
    ]
  })
}
