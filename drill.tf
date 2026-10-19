# The monthly incident drill (ir-3; approved 2026-10-09). A scheduled
# GitHub Actions job creates one GuardDuty sample finding, which must
# open a [DRILL] issue within minutes (incidents.tf). The Administrator
# then acknowledges it by closing it with a comment: that response is
# what the drill tests. The role can do exactly three things.
resource "aws_iam_role" "incident_drill" {
  name = "substrate-incident-drill"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:sub" = "repo:kernwill@66508/substrate-self-test@1408966262:ref:refs/heads/main"
        }
      }
    }]
  })
  max_session_duration = 3600
}

resource "aws_iam_role_policy" "incident_drill" {
  name = "create-sample-findings"
  role = aws_iam_role.incident_drill.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "guardduty:ListDetectors"
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = "guardduty:CreateSampleFindings"
        # AWS checks this action against the detector's findings/create
        # sub-resource, not the detector itself (first run, 2026-10-09).
        Resource = "${aws_guardduty_detector.main.arn}/findings/create"
      },
      {
        # The audit failure drill (au-5, audit_alerts.tf): set the Okta
        # silence alarm to ALARM; it returns to OK on its next evaluation.
        Effect   = "Allow"
        Action   = "cloudwatch:SetAlarmState"
        Resource = aws_cloudwatch_metric_alarm.okta_log_silent.arn
      },
    ]
  })
}
