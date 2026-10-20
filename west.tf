# --- Security monitoring in the second site, us-west-2 (substrate ADR
# 0028). The database replica, its key and the replicated backups live
# there, so the per-Region services us-east-2 runs must run there too:
# GuardDuty (si-3, si-4, au-6), Security Hub (ca-7), Inspector (ra-5,
# si-2.2) and Resolver DNSSEC validation (sc-21). Macie isn't: it scans
# S3, and every bucket is in us-east-2.

resource "aws_guardduty_detector" "west" {
  provider = aws.west
  enable   = true
}

resource "aws_guardduty_detector_feature" "west_ebs_malware_protection" {
  provider    = aws.west
  detector_id = aws_guardduty_detector.west.id
  name        = "EBS_MALWARE_PROTECTION"
  status      = "ENABLED"
}

resource "aws_securityhub_account" "west" {
  provider                 = aws.west
  enable_default_standards = true
  depends_on               = [aws_config_configuration_recorder_status.west]
}

resource "aws_inspector2_enabler" "west" {
  provider       = aws.west
  account_ids    = [data.aws_caller_identity.current.account_id]
  resource_types = ["EC2", "ECR"]
}

resource "aws_route53_resolver_dnssec_config" "default_vpc_west" {
  provider    = aws.west
  resource_id = data.aws_vpc.default_west.id
}

# us-west-2's GuardDuty findings go to us-east-2's default event bus,
# where the incident rules (incidents.tf) open their issues: one
# pipeline, and one place substrate checks every finding reached an
# issue (ir-5, ir-4.1, si-4.5).
resource "aws_cloudwatch_event_rule" "west_guardduty_forward" {
  provider    = aws.west
  name        = "substrate-forward-guardduty-to-us-east-2"
  description = "GuardDuty findings in us-west-2, to the incident pipeline in us-east-2"
  event_pattern = jsonencode({
    source        = ["aws.guardduty"]
    "detail-type" = ["GuardDuty Finding"]
  })
}

resource "aws_iam_role" "west_guardduty_forward" {
  name = "substrate-forward-guardduty"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = { StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id } }
    }]
  })
}

resource "aws_iam_role_policy" "west_guardduty_forward" {
  name = "put-events-us-east-2"
  role = aws_iam_role.west_guardduty_forward.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "events:PutEvents"
      Resource = "arn:aws:events:us-east-2:${data.aws_caller_identity.current.account_id}:event-bus/default"
    }]
  })
}

resource "aws_cloudwatch_event_target" "west_guardduty_forward" {
  provider  = aws.west
  rule      = aws_cloudwatch_event_rule.west_guardduty_forward.name
  target_id = "us-east-2-default-bus"
  arn       = "arn:aws:events:us-east-2:${data.aws_caller_identity.current.account_id}:event-bus/default"
  role_arn  = aws_iam_role.west_guardduty_forward.arn
}
