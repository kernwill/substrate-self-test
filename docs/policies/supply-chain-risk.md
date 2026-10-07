---
controls: [ra-3.1, sr-6, sr-8, sa-15.3]
owner: CEO
---

# Supply chain risk assessment

Effective 2026-10-07. Updated at least every 3 months; whenever a
supplier, a GitHub Action, the Terraform provider or a container image
changes; and whenever a supplier announces a security-relevant change.

## Scope (RA-3(1) a)

Every system, component and service the environment depends on:

- AWS (the account and its us-east-2 services);
- Okta (the Integrator Free Plan org);
- GitHub (repository hosting, Actions runners, secret scanning);
- the GitHub Actions the CI workflow uses;
- the Terraform AWS provider;
- the container image named in `k8s/deployment.yaml`.

## Assessment and supplier review (RA-3(1), SR-6)

Each quarterly review re-reads this table, updates it, and records
what changed.

| Supplier or component | Risk | Assessment and response |
|---|---|---|
| AWS | Platform compromise; account takeover | Accepted: the platform's own controls are relied on. Account access is limited to the Administrator. CloudTrail and Config record changes. |
| AWS free plan | Only us-east-2 is usable, so there is no regional failover | Accepted for a test environment (`contingency-plan.md`) |
| Okta Integrator Free Plan | It is a developer org, not Okta's FedRAMP offering. A previous org's admin access was lost and could not be recovered. | Accepted for a self-test only. A production offering must use an identity provider authorized at Class C. Admin access is now tied to two registered devices. |
| GitHub | Repository compromise or loss of service | Branch protection that binds administrators; secret scanning and push protection; a local clone (`contingency-plan.md`) |
| GitHub Actions `actions/checkout`, `actions/dependency-review-action` | A version tag can be moved to different code | Each is pinned to a full commit SHA, with its version in a comment. Updating one is a reviewed change. |
| Terraform AWS provider 5.100.0 | A tampered provider binary | Provider hashes are pinned in `.terraform.lock.hcl` and checked on install |
| Container image `example/web:1.0` | Unknown provenance | Not deployed; it is a placeholder in the manifests. It must be replaced with a pinned, verified image before any deployment. |

## Criticality analysis (SA-15(3))

Rookwright develops the environment itself, so it performs the
criticality analysis.

- **When (a):**
  - before a component is added to the boundary;
  - before a supplier is replaced;
  - at each quarterly review.
- **Rigor (b):** component level. For each component, record whether
  its compromise would break:
  - integrity of the evidence substrate collects;
  - administrative access;
  - the change control on `main`.

Current result:

| Component | Integrity of evidence | Administrative access | Change control | Critical |
|---|---|---|---|---|
| GitHub repository and branch protection | Yes | No | Yes | Yes |
| Okta org | Yes (Okta evidence) | Yes | No | Yes |
| AWS account | Yes (AWS evidence) | Yes | No | Yes |
| GitHub Actions | No (CI only) | No | Yes (the required check) | Yes |
| Terraform provider | No | Yes (it applies changes) | No | Yes |
| Container image | No | No | No | No (not deployed) |

## Notification of supply chain compromises (SR-8)

**Agreements.** AWS, Okta and GitHub are used under their standard
customer agreements, which include their own security incident
notification terms. Rookwright has no separately negotiated
agreements.

**Procedures.**

- Each supplier's security notices go to an email address the
  Administrator monitors.
- GitHub sends secret scanning, push protection and Dependabot alerts
  for this repository.
- On a notice of a supplier compromise, the Administrator:
  1. assesses it against the criticality table above;
  2. rotates any affected credentials;
  3. runs substrate to confirm the boundary's state;
  4. records the event and response in the next update to this
     document.
