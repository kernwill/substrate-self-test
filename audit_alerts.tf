# au-5: an audit logging failure alerts the Administrator through the
# incident issue pipeline (incidents.tf), for both audit sources.
#
# - AWS: CloudTrail stopped or deleted (incidents.tf, cloudtrail_stopped).
# - Okta: a stream that stops sends no error, so the alarm below fires
#   when Okta's archived System Log (okta_archive.tf) gets no event for
#   24 hours. Every collection and every control-tasks run (each six
#   hours) signs in to Okta, so a working stream is never silent that
#   long.
#
# A monthly drill (.github/workflows/audit-failure-drill.yml) sets the
# alarm to ALARM with a reason starting "Drill", which opens a [DRILL]
# issue through the same destination. Substrate judges all of it
# (au-5, audit_failure_alerts in substrate-parameters.yaml).

resource "aws_cloudwatch_metric_alarm" "okta_log_silent" {
  alarm_name          = "substrate-audit-okta-log-silent"
  alarm_description   = "Okta's archived System Log received no event for 24 hours (au-5)"
  namespace           = "AWS/Logs"
  metric_name         = "IncomingLogEvents"
  dimensions          = { LogGroupName = aws_cloudwatch_log_group.okta_system_log.name }
  statistic           = "Sum"
  period              = 21600
  evaluation_periods  = 4
  datapoints_to_alarm = 4
  threshold           = 1
  comparison_operator = "LessThanThreshold"
  # No events means no data points: that is the failure.
  treat_missing_data = "breaching"
}

resource "aws_cloudwatch_event_rule" "audit_failure" {
  name        = "substrate-incident-audit-failure"
  description = "Okta's System Log archive went silent (au-5)"
  event_pattern = jsonencode({
    source        = ["aws.cloudwatch"]
    "detail-type" = ["CloudWatch Alarm State Change"]
    detail = {
      alarmName = [aws_cloudwatch_metric_alarm.okta_log_silent.alarm_name]
      state = {
        value  = ["ALARM"]
        reason = [{ "anything-but" = { prefix = "Drill" } }]
      }
    }
  })
}

resource "aws_cloudwatch_event_rule" "audit_failure_drill" {
  name        = "substrate-incident-audit-failure-drill"
  description = "Audit failure alert drills (au-5)"
  event_pattern = jsonencode({
    source        = ["aws.cloudwatch"]
    "detail-type" = ["CloudWatch Alarm State Change"]
    detail = {
      alarmName = [aws_cloudwatch_metric_alarm.okta_log_silent.alarm_name]
      state = {
        value  = ["ALARM"]
        reason = [{ prefix = "Drill" }]
      }
    }
  })
}

locals {
  audit_failure_paths = {
    alarm = "$.detail.alarmName"
    time  = "$.detail.state.timestamp"
  }
}

resource "aws_cloudwatch_event_target" "audit_failure" {
  rule      = aws_cloudwatch_event_rule.audit_failure.name
  target_id = "github-issue"
  arn       = aws_cloudwatch_event_api_destination.github_issues.arn
  role_arn  = aws_iam_role.incident_issues.arn
  dead_letter_config {
    arn = aws_sqs_queue.incident_dlq.arn
  }
  retry_policy {
    maximum_event_age_in_seconds = 3600
    maximum_retry_attempts       = 24
  }
  input_transformer {
    input_paths    = local.audit_failure_paths
    input_template = <<-EOT
      {"title": "Audit logging failure: Okta System Log silent", "body": "CloudWatch alarm <alarm> entered ALARM at <time>: Okta's archived System Log received no event for 24 hours. Check the Okta log stream and the EventBridge partner event source.\n\nOpened automatically by EventBridge rule substrate-incident-audit-failure.", "labels": ["incident", "audit-failure"], "assignees": ["kernwill"]}
    EOT
  }
}

resource "aws_cloudwatch_event_target" "audit_failure_drill" {
  rule      = aws_cloudwatch_event_rule.audit_failure_drill.name
  target_id = "github-issue"
  arn       = aws_cloudwatch_event_api_destination.github_issues.arn
  role_arn  = aws_iam_role.incident_issues.arn
  dead_letter_config {
    arn = aws_sqs_queue.incident_dlq.arn
  }
  retry_policy {
    maximum_event_age_in_seconds = 3600
    maximum_retry_attempts       = 24
  }
  input_transformer {
    input_paths    = local.audit_failure_paths
    input_template = <<-EOT
      {"title": "[DRILL] Audit logging failure alert", "body": "CloudWatch alarm <alarm> was set to ALARM at <time> by the monthly audit failure drill.\n\nOpened automatically by EventBridge rule substrate-incident-audit-failure-drill.", "labels": ["incident", "audit-failure", "drill"], "assignees": ["kernwill"]}
    EOT
  }
}
