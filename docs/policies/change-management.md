---
controls: [cm-3.4]
owner: CEO
---

# Configuration change control

Effective 2026-10-07. Reviewed at least every 3 months.

## The change control element

Configuration change control for the self-test environment is the pull
request review on `main` in `kernwill/substrate-self-test`. Every
change to Terraform, Kubernetes manifests, CI, the boundary declaration
and these documents goes through it.

Its members are:

- the **Administrator**, who proposes changes; and
- the **Independent Reviewer**, who approves or rejects them.

## Security and privacy representatives (CM-3(4))

The Independent Reviewer is the security representative **and** the
privacy representative on the change control element. They are
required members: branch protection rejects a change to `main` without
their approval, and the rule applies to administrators.

When reviewing, the representative considers:

- whether the change weakens any security property in
  `security-plan.md`;
- whether it introduces personally identifiable information beyond
  workforce identity data;
- whether it changes the boundary, a supplier, or a critical asset.

If it does any of those, the matching document must be updated in the
same pull request.
