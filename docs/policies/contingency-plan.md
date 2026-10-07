---
controls: [cp-2.3, cp-2.8, cp-6.3, cp-7.2]
owner: CEO
---

# Contingency plan

Effective 2026-10-07. Reviewed at least every 3 months.

## Essential functions and resumption (CP-2(3))

The environment has one essential function: being available to run
substrate against, so that collection and compilation produce evidence.

That function is resumed within **5 business days** of this plan being
activated. Activation means a disruption that stops substrate running
against the boundary: losing a component, losing access to one, or
losing the administrator's Mac.

Resumption is by rebuilding, not restoring:

1. Clone the repository from GitHub.
2. Run `terraform apply` from `main` for the AWS resources.
3. Re-issue collector credentials.
4. Run substrate, and confirm the result matches the last recorded run.

## Critical assets (CP-2(8))

| Asset | Why it is critical | Protection |
|---|---|---|
| The GitHub repository | Source of truth for all infrastructure, manifests and these documents | Hosted by GitHub, with a full clone on the administrator's Mac. Protected `main`. |
| Okta Admin Console access | Without it the Okta component cannot be administered or re-credentialed. A previous org was lost this way. | Okta Verify FastPass on two registered devices, a Mac and an iPhone |
| AWS root and administrator credentials | Needed to rebuild AWS resources | Held by the administrator only |
| Terraform state | Maps code to live AWS resources | Local file on the administrator's Mac, deliberately not in git. If lost, resources are re-imported or destroyed and recreated. |
| Collector credentials | Needed to run substrate | Under `~/.substrate/` on the administrator's Mac. All can be re-issued from their consoles. |
| Audit records (CloudTrail bucket and CloudWatch Logs) | The environment's record of changes | Versioned, encrypted S3 with log file validation |

## Alternate storage site accessibility (CP-6(3))

The repository has two copies: GitHub, and the clone on the
administrator's Mac. AWS data, including the audit bucket, is in
us-east-2 only.

| Area-wide disruption | Accessibility problem | Mitigation |
|---|---|---|
| us-east-2 outage | AWS data and audit records are unreachable. No other Region can be used: the free plan permits only us-east-2. | Wait for the Region to recover. The environment holds no data that cannot be regenerated. If a longer outage is expected, upgrade the account plan and rebuild in another Region from Terraform. |
| GitHub outage | The hosted repository is unreachable | Keep working from the local clone. Changes wait for GitHub to recover, because none may bypass review. |
| Loss of the administrator's Mac | The local clone, Terraform state and collector credentials are gone | Re-clone from GitHub. Re-issue credentials, signing in to Okta from the registered iPhone. Rebuild state as described above. |

## Alternate processing site accessibility (CP-7(2))

Processing happens in two places: AWS us-east-2, and whichever machine
runs substrate (today, the administrator's Mac). The alternate
processing site for substrate is any other machine with Go and the
repository; it needs no special setup.

| Area-wide disruption | Accessibility problem | Mitigation |
|---|---|---|
| us-east-2 outage | Live collection from AWS cannot run | Static compilation from the repository still runs. Live collection resumes when the Region does, or after a rebuild in another Region as above. |
| Regional disruption where the administrator works (power, network) | No machine can reach the platforms | Run from any machine with network access once one is available. All credentials can be re-issued remotely. |
| Okta outage | No admin sign-in and no Okta collection | AWS and GitHub collection still run. The Okta evidence is marked undetermined until Okta recovers. |

## Not covered by this plan

Alternate processing site agreements with priority-of-service
provisions (CP-7(3)). No such agreement exists. AWS's standard terms
include none, and a 5-day recovery time doesn't need one.
