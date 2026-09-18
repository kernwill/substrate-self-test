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
  KMS encryption, all four public-access-block flags on) and
  `app_logs` (deliberately under-configured: no versioning or
  encryption resource, public access block flags all off).
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
