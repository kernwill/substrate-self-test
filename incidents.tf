# Incidents become GitHub issues (approved 2026-10-08, Phase A step 3).
# EventBridge opens an issue labelled incident, assigned to the
# Administrator, for every new GuardDuty finding of Medium severity or
# above and for CloudTrail being stopped or deleted (ir-4.1, ir-5,
# si-4.5). GuardDuty sample findings (drills) open issues labelled drill
# too, so they can never be mistaken for real incidents.
#
# The GitHub token is never in this configuration or its state: the
# connection is created with a placeholder and the real token is set
# once outside Terraform (SUBSTRATE-TESTING.md), which ignore_changes
# keeps. EventBridge stores it in its own Secrets Manager secret, which
# the drift-check role can't read.

resource "aws_cloudwatch_event_connection" "github" {
  name               = "substrate-self-test-github"
  description        = "GitHub API, token limited to opening issues in kernwill/substrate-self-test"
  authorization_type = "API_KEY"
  auth_parameters {
    api_key {
      key   = "Authorization"
      value = "Bearer placeholder-set-outside-terraform"
    }
    invocation_http_parameters {
      header {
        key   = "Accept"
        value = "application/vnd.github+json"
      }
      header {
        key   = "X-GitHub-Api-Version"
        value = "2022-11-28"
      }
    }
  }
  lifecycle {
    ignore_changes = [auth_parameters]
  }
}

resource "aws_cloudwatch_event_api_destination" "github_issues" {
  name                             = "substrate-self-test-github-issues"
  description                      = "Open an issue in kernwill/substrate-self-test"
  invocation_endpoint              = "https://api.github.com/repos/kernwill/substrate-self-test/issues"
  http_method                      = "POST"
  invocation_rate_limit_per_second = 1
  connection_arn                   = aws_cloudwatch_event_connection.github.arn
}

resource "aws_iam_role" "incident_issues" {
  name = "substrate-incident-issues"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = { StringEquals = { "aws:SourceAccount" = local.suffix } }
    }]
  })
}

resource "aws_iam_role_policy" "incident_issues" {
  name = "invoke-github-issues"
  role = aws_iam_role.incident_issues.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "events:InvokeApiDestination"
      Resource = aws_cloudwatch_event_api_destination.github_issues.arn
    }]
  })
}

locals {
  # Each finding opens one issue: GuardDuty re-sends an active finding
  # every 6 hours with service.count raised, so only count 1 is new.
  guardduty_finding_paths = {
    id       = "$.detail.id"
    type     = "$.detail.type"
    severity = "$.detail.severity"
    region   = "$.region"
    created  = "$.detail.createdAt"
  }
}

resource "aws_cloudwatch_event_rule" "guardduty_findings" {
  name        = "substrate-incident-guardduty"
  description = "New GuardDuty findings, Medium severity and above"
  event_pattern = jsonencode({
    source        = ["aws.guardduty"]
    "detail-type" = ["GuardDuty Finding"]
    detail = {
      severity = [{ numeric = [">=", 4] }]
      service = {
        count = [1]
        # Not a sample finding. GuardDuty documents the event's detail as
        # the GetFindings object, where a sample is marked inside the
        # additionalInfo.value JSON string ("sample":true, seen live
        # 2026-10-09); either form is excluded. Both patterns were
        # checked with test-event-pattern against both forms.
        additionalInfo = {
          "$or" = [
            { sample = [{ exists = false }], value = [{ exists = false }] },
            { sample = [{ exists = false }], value = [{ "anything-but" = { wildcard = "*\"sample\":true*" } }] },
          ]
        }
      }
    }
  })
}

resource "aws_cloudwatch_event_target" "guardduty_findings" {
  rule      = aws_cloudwatch_event_rule.guardduty_findings.name
  target_id = "github-issue"
  arn       = aws_cloudwatch_event_api_destination.github_issues.arn
  role_arn  = aws_iam_role.incident_issues.arn
  input_transformer {
    input_paths = local.guardduty_finding_paths
    # Literal JSON, not jsonencode: jsonencode escapes < and >, which
    # would hide EventBridge's <placeholders>. A heredoc keeps \n as
    # JSON's newline escape.
    input_template = <<-EOT
      {"title": "GuardDuty: <type>", "body": "GuardDuty finding of severity <severity> in <region>.\n\nFinding ID: <id>\nCreated: <created>\n\nOpened automatically by EventBridge rule substrate-incident-guardduty.", "labels": ["incident", "guardduty"], "assignees": ["kernwill"]}
    EOT
  }
}

# Drills: GuardDuty sample findings (CreateSampleFindings). Every sample
# event opens an issue, so each drill shows the whole path.
resource "aws_cloudwatch_event_rule" "guardduty_drills" {
  name        = "substrate-incident-guardduty-drill"
  description = "GuardDuty sample findings, for incident drills"
  event_pattern = jsonencode({
    source        = ["aws.guardduty"]
    "detail-type" = ["GuardDuty Finding"]
    detail = {
      service = {
        additionalInfo = {
          "$or" = [
            { sample = [true] },
            { value = [{ wildcard = "*\"sample\":true*" }] },
          ]
        }
      }
    }
  })
}

resource "aws_cloudwatch_event_target" "guardduty_drills" {
  rule      = aws_cloudwatch_event_rule.guardduty_drills.name
  target_id = "github-issue"
  arn       = aws_cloudwatch_event_api_destination.github_issues.arn
  role_arn  = aws_iam_role.incident_issues.arn
  input_transformer {
    input_paths    = local.guardduty_finding_paths
    input_template = <<-EOT
      {"title": "[DRILL] GuardDuty: <type>", "body": "GuardDuty sample finding of severity <severity> in <region>, from an incident drill.\n\nFinding ID: <id>\nCreated: <created>\n\nOpened automatically by EventBridge rule substrate-incident-guardduty-drill.", "labels": ["incident", "guardduty", "drill"], "assignees": ["kernwill"]}
    EOT
  }
}

# Audit logging switched off or removed (au-5's kind of event): always
# an incident.
resource "aws_cloudwatch_event_rule" "cloudtrail_stopped" {
  name        = "substrate-incident-cloudtrail-stopped"
  description = "CloudTrail logging stopped or a trail deleted"
  event_pattern = jsonencode({
    source        = ["aws.cloudtrail"]
    "detail-type" = ["AWS API Call via CloudTrail"]
    detail = {
      eventSource = ["cloudtrail.amazonaws.com"]
      eventName   = ["StopLogging", "DeleteTrail"]
    }
  })
}

resource "aws_cloudwatch_event_target" "cloudtrail_stopped" {
  rule      = aws_cloudwatch_event_rule.cloudtrail_stopped.name
  target_id = "github-issue"
  arn       = aws_cloudwatch_event_api_destination.github_issues.arn
  role_arn  = aws_iam_role.incident_issues.arn
  input_transformer {
    input_paths = {
      name  = "$.detail.eventName"
      who   = "$.detail.userIdentity.arn"
      event = "$.detail.eventID"
      time  = "$.detail.eventTime"
    }
    input_template = <<-EOT
      {"title": "CloudTrail: <name>", "body": "<name> was called by <who> at <time>.\n\nCloudTrail event ID: <event>\n\nOpened automatically by EventBridge rule substrate-incident-cloudtrail-stopped.", "labels": ["incident", "cloudtrail"], "assignees": ["kernwill"]}
    EOT
  }
}
