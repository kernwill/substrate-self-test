# substrate-self-test

A small, purpose-built fixture for manually testing `substrate` end to
end - not a real application, and not deployed anywhere. It exists to
give the compiler real Terraform, Kubernetes, and GitHub Actions
content to parse, with a deliberate mix of well-configured and
under-configured resources.

See `SUBSTRATE-TESTING.md` for exact instructions on how to run
`substrate` against this repo, including the live-AWS setup for
`substrate collect`.

## Layout

- `main.tf` - two S3 buckets: `app_data` (fully configured: versioning,
  KMS encryption, all four public-access-block flags on, TLS-only) and
  `app_logs` (the regression target: public access blocked and TLS-only
  by default; its comment explains how to break it on purpose and revert).
- `live.tf` - the rest of the live test environment (audit bucket,
  CloudTrail, KMS key, AWS Config, Resolver DNSSEC), applied in us-east-2.
- `substrate-boundary.yaml` - the declared assessment boundary.
- `substrate-readonly-policy.json` - a copy of substrate's published
  read-only AWS policy, held by the `substrate-collector` role in
  `live.tf`.
- `docs/policies/` - policy documents for substrate's artifact tier,
  approved through pull requests.
- `.github/workflows/policy-review-reminder.yml` - opens an issue when
  the policies are due for their quarterly review.
- `k8s/deployment.yaml` - a Deployment with a well-configured pod and
  container `securityContext`.
- `k8s/networkpolicy.yaml` - an explicit default-deny NetworkPolicy
  (both policy types, empty ingress/egress lists).
- `k8s/secret.yaml` - a `kind: Secret` with real-looking (but fake)
  credential material, to confirm redaction wipes it.
- `k8s/configmap.yaml` - an ordinary ConfigMap with one deliberately
  secret-shaped key (`api_key`), to confirm key-name redaction still
  fires outside a Secret object.
- `.github/workflows/ci.yml` - a workflow with an explicit
  `permissions` block (including `id-token: write`, the exact shape a
  past redaction bug broke), a `dependency-review-action` step, and one
  hardcoded, secret-shaped literal to confirm content-pattern
  redaction fires on a real fixture.
