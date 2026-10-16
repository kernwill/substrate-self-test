# au-11 for Okta (2026-10-16): Okta streams its System Log to this
# account as an EventBridge partner event source (Reports > Log
# Streaming in the Okta Admin Console, created by the administrator).
# The bus below accepts it, and the rule archives every event in a
# CloudWatch Logs group kept 365 days, the same year as the other audit
# records (retention.tf). Substrate reads the group's retention and its
# newest event: an archive that stops receiving stops counting.

data "aws_cloudwatch_event_source" "okta" {
  name_prefix = "aws.partner/okta.com/integrator-2677113/substrateselftestokta"
}

resource "aws_cloudwatch_event_bus" "okta" {
  name              = data.aws_cloudwatch_event_source.okta.name
  event_source_name = data.aws_cloudwatch_event_source.okta.name
}

resource "aws_cloudwatch_log_group" "okta_system_log" {
  name              = "/aws/events/okta-system-log"
  retention_in_days = 365
}

# EventBridge writes to the group under this resource policy, limited to
# this account's rules.
resource "aws_cloudwatch_log_resource_policy" "okta_system_log" {
  policy_name = "eventbridge-okta-system-log"
  policy_document = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "EventBridgeDelivery"
      Effect    = "Allow"
      Principal = { Service = ["events.amazonaws.com", "delivery.logs.amazonaws.com"] }
      Action    = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource  = "${aws_cloudwatch_log_group.okta_system_log.arn}:*"
      Condition = { ArnLike = { "aws:SourceArn" = "arn:aws:events:us-east-2:${local.suffix}:rule/*" } }
    }]
  })
}

resource "aws_cloudwatch_event_rule" "okta_archive" {
  name           = "substrate-okta-system-log-archive"
  description    = "Archive Okta's System Log (au-11)"
  event_bus_name = aws_cloudwatch_event_bus.okta.name
  event_pattern  = jsonencode({ source = [{ prefix = "aws.partner/okta.com" }] })
}

resource "aws_cloudwatch_event_target" "okta_archive" {
  rule           = aws_cloudwatch_event_rule.okta_archive.name
  event_bus_name = aws_cloudwatch_event_bus.okta.name
  target_id      = "okta-system-log"
  arn            = aws_cloudwatch_log_group.okta_system_log.arn
}
