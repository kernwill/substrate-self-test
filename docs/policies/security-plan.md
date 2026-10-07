---
controls: [pl-8, pl-10, pm-7, ac-14]
owner: CEO
---

# Security plan: substrate self-test environment

Effective 2026-10-07. Reviewed at least every 3 months, and whenever a
component is added to or removed from the boundary. A change to this
document takes effect only when merged to `main` through an approved
pull request.

## Purpose and scope

The self-test environment exists so Rookwright can run substrate
against real infrastructure it owns. It serves no customers, holds no
customer or federal data, and is not offered to anyone. Its boundary is
declared in `substrate-boundary.yaml`:

| Component | What it is |
|---|---|
| AWS account, us-east-2 | S3 buckets (`app_data`, `app_logs`, the audit bucket), a KMS key, a CloudTrail trail with CloudWatch Logs, an AWS Config recorder, Resolver DNSSEC validation on the default VPC |
| Okta org | Workforce identity for the administrator and the substrate collector app |
| GitHub repository `kernwill/substrate-self-test` | Infrastructure code, Kubernetes manifests, CI, and these documents |
| Kubernetes manifests in `k8s/` | A Deployment, NetworkPolicy, Secret and ConfigMap. Defined but not deployed to any cluster |

## Control baseline (PL-10)

The selected baseline is FedRAMP 20x Class C under the Consolidated
Rules for 2026 (CR26), as expressed by its Key Security Indicators.
Class C is the class Rookwright's Phase 1 work targets. The environment
does not claim to meet the baseline; substrate's output reports how
much of it is verified.

## Security architecture (PL-8)

**Confidentiality.**

- S3 buckets block all public access and refuse non-TLS requests.
- `app_data` is encrypted with a customer-managed KMS key that rotates
  automatically.
- Administrator sign-in to the Okta Admin Console requires
  phishing-resistant authentication (Okta FastPass) from a registered
  device.

**Integrity.**

- Changes to `main` require a pull request, an approving review from
  someone other than the author, and a passing `test` check. The rule
  applies to administrators.
- CloudTrail records management events, with log file validation on.
- AWS Config records resource configuration changes.
- Resolver DNSSEC validation is on for the default VPC.
- Container manifests run as non-root, with a read-only root
  filesystem, no privilege escalation, all capabilities dropped, and a
  default-deny NetworkPolicy.

**Availability.** Availability is not a requirement of this
environment beyond what `contingency-plan.md` states. Infrastructure is
rebuilt from Terraform, not restored.

**Personally identifiable information.** The environment processes no
PII beyond workforce identity data: the names and email addresses of
its Okta and GitHub accounts. Substrate hashes GitHub author identities
before recording them. Adding any other PII requires updating this
plan first.

**External dependencies and assumptions.**

- AWS, Okta and GitHub operate the underlying platforms. Their own
  controls are assumed, not verified. `supply-chain-risk.md` assesses
  them.
- The AWS account is on AWS's free plan, which permits only us-east-2.
- The administrator's Mac holds the Terraform state and the collector
  credentials. `contingency-plan.md` covers its loss.

## Enterprise architecture (PM-7)

Rookwright's enterprise is small: this environment, the private
`rookwright/substrate` source repository, and the public rookwright.com
website with its security.txt. Information security is considered at
the enterprise level in two ways:

- the product's own source never runs in, or depends on, the
  self-test environment;
- identities are separate per system, with no shared credentials
  between the self-test environment and anything else.

Risk to individuals, other organizations and the Nation is limited
because no customer or federal data exists anywhere in the enterprise.
This section is maintained alongside the architecture above and
revised in the same pull request as any change to it.

## Actions permitted without identification or authentication (AC-14)

| Action | Rationale |
|---|---|
| Reading the public GitHub repository and its CI results | Deliberately public: GitHub Free provides branch protection and secret scanning only on public repositories. Nothing in it is secret. |
| Loading the Okta sign-in page | Required for anyone to begin authenticating. It grants no access. |
| Reading rookwright.com and its security.txt | Public by design, so researchers can report vulnerabilities. |

No other action on any component can be performed without
identification and authentication.

## Keeping this plan current

Planned architecture changes are written into this plan, and into
`contingency-plan.md` and `supply-chain-risk.md` where they apply, in
the same pull request that makes the change.
