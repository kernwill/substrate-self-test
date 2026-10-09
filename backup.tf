# Backups and weekly restore tests of the database (cp-4, cp-9.1,
# cp-10; approved 2026-10-09). AWS Backup takes a daily snapshot, and
# AWS Backup restore testing restores the newest one every week into a
# throwaway database, waits an hour, and deletes it. Each test's result
# opens a GitHub issue labelled contingency-test, which the
# Administrator reviews and closes with a comment (cp-4 b and c).

resource "aws_backup_vault" "main" {
  name        = "substrate-self-test"
  kms_key_arn = aws_kms_key.app.arn
}

resource "aws_iam_role" "backup" {
  name = "substrate-backup"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "backup.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "backup" {
  for_each = toset([
    "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup",
    "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores",
  ])
  role       = aws_iam_role.backup.name
  policy_arn = each.value
}

# Daily at 05:00 UTC, kept 14 days: the recovery point objective is 24
# hours (substrate-parameters.yaml).
resource "aws_backup_plan" "main" {
  name = "substrate-self-test-daily"
  rule {
    rule_name         = "daily"
    target_vault_name = aws_backup_vault.main.name
    schedule          = "cron(0 5 * * ? *)"
    start_window      = 60
    completion_window = 180
    lifecycle {
      delete_after = 14
    }
  }
}

resource "aws_backup_selection" "database" {
  name         = "database"
  plan_id      = aws_backup_plan.main.id
  iam_role_arn = aws_iam_role.backup.arn
  resources    = [aws_db_instance.app.arn]
}

# Every Saturday at 15:00 UTC, restore the newest snapshot of the week.
resource "aws_backup_restore_testing_plan" "weekly" {
  name                = "substrate_self_test_weekly"
  schedule_expression = "cron(0 15 ? * SAT *)"
  start_window_hours  = 1
  recovery_point_selection {
    algorithm             = "LATEST_WITHIN_WINDOW"
    include_vaults        = [aws_backup_vault.main.arn]
    recovery_point_types  = ["SNAPSHOT"]
    selection_window_days = 7
  }
}

# The restored copy gets the smallest class, no network access (the
# database's own subnet group and rule-less security group) and is
# deleted after an hour.
resource "aws_backup_restore_testing_selection" "database" {
  name                      = "database"
  restore_testing_plan_name = aws_backup_restore_testing_plan.weekly.name
  protected_resource_type   = "RDS"
  protected_resource_arns   = [aws_db_instance.app.arn]
  iam_role_arn              = aws_iam_role.backup.arn
  validation_window_hours   = 1
  restore_metadata_overrides = {
    dbInstanceClass     = "db.t4g.micro"
    dbSubnetGroupName   = aws_db_subnet_group.app.name
    vpcSecurityGroupIds = jsonencode([aws_security_group.db.id])
  }
}

# Each restore test's outcome opens an issue for review. statusMessage
# is left out: AWS warns it can hold unescaped characters that would
# break the JSON. Substrate reads the job's details from AWS Backup.
resource "aws_cloudwatch_event_rule" "restore_tests" {
  name        = "substrate-contingency-restore-test"
  description = "AWS Backup restore tests that finished, failed or were aborted"
  event_pattern = jsonencode({
    source        = ["aws.backup"]
    "detail-type" = ["Restore Job State Change"]
    detail = {
      status                = ["COMPLETED", "FAILED", "ABORTED"]
      restoreTestingPlanArn = [{ exists = true }]
    }
  })
}

resource "aws_cloudwatch_event_target" "restore_tests" {
  rule      = aws_cloudwatch_event_rule.restore_tests.name
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
    input_paths = {
      job      = "$.detail.restoreJobId"
      status   = "$.detail.status"
      resource = "$.detail.resourceType"
      created  = "$.detail.creationDate"
    }
    # Literal JSON: jsonencode would escape the <placeholders>.
    input_template = <<-EOT
      {"title": "Restore test <status>: <resource>", "body": "AWS Backup restore test finished with status <status>.\n\nRestore job ID: <job>\nStarted: <created>\n\nReview the result and close this issue with a comment: what was checked, and any corrective action.\n\nOpened automatically by EventBridge rule substrate-contingency-restore-test.", "labels": ["contingency-test"], "assignees": ["kernwill"]}
    EOT
  }
}
