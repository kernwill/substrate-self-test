# The monthly incident drill (ir-3; approved 2026-10-09). A scheduled
# GitHub Actions job creates one GuardDuty sample finding, which must
# open a [DRILL] issue within minutes (incidents.tf). The Administrator
# then acknowledges it by closing it with a comment: that response is
# what the drill tests. The role can do exactly two things.
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
        Effect   = "Allow"
        Action   = "guardduty:CreateSampleFindings"
        Resource = aws_guardduty_detector.main.arn
      },
    ]
  })
}
