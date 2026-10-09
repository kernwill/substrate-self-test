---
controls: [ca-7.4]
owner: CEO
---

# Continuous monitoring strategy

Effective 2026-10-07. Reviewed at least every 3 months.

## When monitoring runs

Substrate is run against the whole boundary (`collect`, then `compile`):

- before any infrastructure change is merged and after it is applied;
- at each quarterly review of these documents;
- whenever a supplier announces a security-relevant change.

Each run's numbers are recorded in substrate's `docs/REQUIREMENTS.md`.

## Risk monitoring (CA-7(4))

Risk monitoring is part of this strategy in three forms.

**Effectiveness monitoring (a).** `substrate collect` observes the live
configuration of AWS, Okta and GitHub. Observed evidence is compared
with the declared configuration in Terraform, so a control that is
declared but not in effect is visible.

**Compliance monitoring (b).** `substrate compile` evaluates the
evidence against FedRAMP 20x Class C. It reports each indicator as
satisfied, not satisfied, undetermined or not applicable, and the share
of cited controls that are verified. Any indicator that moves to "not
satisfied" is treated as a finding and fixed or explained in the next
pull request.

**Change monitoring (c).**

- Every change to the environment's code is a reviewed pull request on
  `main`.
- CloudTrail records management events in the AWS account.
- AWS Config records resource configuration changes.
- Okta's System Log records administrative changes, which substrate
  collects.
- Comparing successive substrate runs shows what changed between them.
- Every night, a GitHub Actions job compares the live AWS account with
  `main` (`terraform plan`, read-only). Any difference opens an issue
  labelled `drift` and `incident`.

## Incidents

Every new GuardDuty finding of Medium severity or above, and any
attempt to stop or delete CloudTrail logging, opens a GitHub issue in
this repository automatically. The issue is labelled `incident` and
assigned to the Administrator, and GitHub notifies them. The issue is
the incident's record: it is worked and closed with a comment saying
what was done. GuardDuty sample findings from drills open issues
labelled `drill` too, and are never counted as real incidents.

**Incident drill.** On the first of every month a GitHub Actions job
creates a GuardDuty sample finding. Its `[DRILL]` issue must appear
within 15 minutes, and the Administrator acknowledges it within 3 days
by closing it with a comment saying the alert was received and what
would have been done. A missing issue fails the job; an unacknowledged
drill is a failed drill.
