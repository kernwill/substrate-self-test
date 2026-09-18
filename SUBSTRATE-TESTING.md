# Testing substrate against this fixture

## 0. Build substrate once

```
cd /Users/willkern/substrate
make build
```

This produces `/Users/willkern/substrate/bin/substrate`. Every command
below assumes that path; substitute your own if you built it elsewhere.

## 1. Static pass: compile, no AWS credentials needed

```
cd /Users/willkern/substrate
./bin/substrate compile --source /Users/willkern/substrate-self-test --out /tmp/self-test-out
```

Expected output:

```
parsed 6 terraform resource(s), 4 kubernetes resource(s), and 1 github actions workflow(s) from /Users/willkern/substrate-self-test; compiled 9 evidence node(s) and 0 edge(s); evaluated 46 KSI indicator(s): 46 undetermined
```

`0 edges` is correct, not a bug: the bare `aws_s3_bucket` resources
that `app_data`'s versioning/encryption/public-access-block reference
have no IR node of their own (a bare bucket has no reviewed mapping),
so there's nothing for those references to link to.

**All 46 indicators reading `undetermined` is the expected, honest
result today**, not a fixture problem - see the "What this fixture
can't show yet" section below.

## 2. Inspect what it actually found

```
./bin/substrate ir query --dir /tmp/self-test-out/ir --control AC-3
./bin/substrate ir query --dir /tmp/self-test-out/ir --control SC-28.1
./bin/substrate ir query --dir /tmp/self-test-out/ir --control CM-7
./bin/substrate ir query --dir /tmp/self-test-out/ir --control SC-7.5
./bin/substrate ir query --dir /tmp/self-test-out/ir --control AC-6
```

You should see: `app_data`'s public-access-block evidence (all four
flags `true`) next to `app_logs`'s (all four `false`) under `AC-3`;
`app_data`'s KMS encryption under `SC-28.1`; the Deployment's pod and
container security contexts under `CM-7`; the NetworkPolicy's
default-deny under `SC-7.5`; and the workflow's `permissions` block
(including `id-token: write`, unredacted) under `AC-6`.

Also worth opening directly to see redaction work:

```
cat /tmp/self-test-out/kubernetes.json      # Secret's data/stringData: "[REDACTED]"; ConfigMap's api_key: "[REDACTED]", everything else untouched
cat /tmp/self-test-out/github_actions.json  # AWS_ACCESS_KEY_ID literal: "[REDACTED]"; permissions.id-token: "write" (NOT redacted)
```

## 3. Establish a baseline, confirm gate is clean

```
./bin/substrate baseline update --current /tmp/self-test-out/ksi_results.json --out /tmp/self-test-baseline.json
./bin/substrate gate --baseline /tmp/self-test-baseline.json --current /tmp/self-test-out/ksi_results.json
```

Expected: `substrate gate: no regressions (46 unchanged, 0 new, 0 improved, 0 other status change(s))`, exit code 0.

## 4. The regression -> remediate -> reverify loop

This is the self-test loop the revised Phase 2 exit criteria call for.
Two levels to check, and it matters which one you're looking at:

**What WILL change today: raw evidence, checked via `ir query`.**

```
# Remove app_data's encryption resource (open main.tf, delete the
# aws_s3_bucket_server_side_encryption_configuration.app_data block),
# then commit the change - substrate requires committed files.
git add -A && git commit -m "test: simulate removing encryption"

cd /Users/willkern/substrate
./bin/substrate compile --source /Users/willkern/substrate-self-test --out /tmp/self-test-out-2
./bin/substrate ir query --dir /tmp/self-test-out-2/ir --control SC-28.1
# -> "no facts bearing on SC-28.1 were found" - the evidence is gone.

# Now undo it (revert the commit, or just restore the block and commit
# again), recompile, confirm the evidence is back:
cd /Users/willkern/substrate-self-test && git revert --no-edit HEAD
cd /Users/willkern/substrate
./bin/substrate compile --source /Users/willkern/substrate-self-test --out /tmp/self-test-out-3
./bin/substrate ir query --dir /tmp/self-test-out-3/ir --control SC-28.1
# -> the sse_algorithm fact is back.
```

**What will NOT change yet: `gate`'s exit code.** Run `gate` against
the baseline from step 3 at any point in this loop and it will still
say "no regressions" - not a bug, an honest limitation of current
coverage. `gate` only fails when a whole KSI *indicator* flips away
from `satisfied`, and with only ~9 controls mapped across all
collectors today, no indicator has full enough evidence coverage to
ever read `satisfied` in the first place (every KSI-SVC indicator
references many more controls than that, and every other KSI family
has no Rego module yet at all). The regression is real and visible at
the control-evidence level (`ir query`); it just doesn't yet propagate
to a KSI-level verdict. That will start becoming demonstrable as more
collectors and controls are added.

## 5. Optional: exercise the live AWS collectors

**Status: shelved 2026-09-18, not yet done.** Blocked on AWS account
access - the account reachable from the existing sign-in sits inside
an AWS Organization whose service control policy denies
`s3:CreateBucket` (not fixable from that member account), and a
fresh-account signup then hit a hard AWS Builder ID error requiring
AWS Support. Tracked as open item 8 in `docs/REQUIREMENTS.md` section
31. Revisit once a clean AWS account is available; the instructions
below are otherwise unchanged and ready to run as-is.

Not required for the static-only pass above. If you want to test
`substrate collect` (FR-3) against real resources, this needs an AWS
account and the AWS CLI configured with credentials - IAM is free at
any scale, and a couple of near-empty S3 buckets cost fractions of a
cent a month (see the pricing discussion earlier in this session).

```
# Two buckets, contrasting public-access-block posture (both get
# default SSE-S3 encryption automatically - AWS has made that the
# account-wide default since January 2023, so there's no live
# equivalent of main.tf's "no encryption resource" case; that's a real
# difference between what Terraform declares and what AWS actually
# does, which is exactly why FR-4.2 tracks Declared vs Observed
# separately).
aws s3api create-bucket --bucket substrate-self-test-live-good --region us-east-1
aws s3api create-bucket --bucket substrate-self-test-live-bad --region us-east-1

# "good": leave Block Public Access at its own current default (every
# new bucket gets all four flags on by default since April 2023).
# "bad": explicitly turn it off, to get a real contrast.
aws s3api put-public-access-block --bucket substrate-self-test-live-bad \
  --public-access-block-configuration BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false

# Two IAM users, one with an access key, one without.
aws iam create-user --user-name substrate-self-test-good
aws iam create-user --user-name substrate-self-test-bad
aws iam create-access-key --user-name substrate-self-test-bad
```

(A freshly created access key's age will read as a few minutes, not
years - that's expected for a key you just made; there's no way to
backdate `CreateDate`, AWS assigns it at creation time.)

Enrolling real MFA needs an interactive step (an authenticator app
scanning a QR code, then two consecutive codes) - optional, and not
required to exercise the collector:

```
aws iam create-virtual-mfa-device --virtual-mfa-device-name substrate-self-test-good \
  --outfile /tmp/mfa-qr.png --bootstrap-method QRCodePNG
# scan /tmp/mfa-qr.png with an authenticator app, then:
aws iam enable-mfa-device --user-name substrate-self-test-good \
  --serial-number <the ARN create-virtual-mfa-device printed> \
  --authentication-code1 <first code> --authentication-code2 <next code>
```

Then run collect, and merge it into a compile:

```
cd /Users/willkern/substrate
AWS_PROFILE=<your profile, if not default> ./bin/substrate collect --out /tmp/self-test-runtime
./bin/substrate compile --source /Users/willkern/substrate-self-test --out /tmp/self-test-out-runtime --runtime /tmp/self-test-runtime
./bin/substrate ir query --dir /tmp/self-test-out-runtime/ir --control AC-3
```

You should see the two live buckets' public-access-block facts
alongside the Terraform ones, each tagged `"basis": "observed"` in its
provenance instead of `"declared"`.

**Cleanup**, whenever you're done - these resources have no ongoing
purpose:

```
aws s3api delete-bucket --bucket substrate-self-test-live-good
aws s3api delete-bucket --bucket substrate-self-test-live-bad
aws iam delete-access-key --user-name substrate-self-test-bad --access-key-id <the key ID create-access-key printed>
aws iam deactivate-mfa-device --user-name substrate-self-test-good --serial-number <the MFA ARN>  # if you enrolled one
aws iam delete-virtual-mfa-device --serial-number <the MFA ARN>                                    # if you enrolled one
aws iam delete-user --user-name substrate-self-test-good
aws iam delete-user --user-name substrate-self-test-bad
```

## What this fixture can't show yet

- No KSI indicator will ever read `satisfied` against this fixture,
  regardless of what you fix or break - real evidence coverage is
  still far short of what any indicator's full control list requires.
  This is the honest, current state of the product (see `docs/adr/0007`),
  not something wrong with the fixture.
- 9 of the 10 KSI families have no Rego module at all yet, so their
  indicators always read "not yet implemented" no matter what evidence
  exists.
- `gate`'s regression detection is real and tested (see
  `cmd/substrate/gate_test.go`), but won't visibly fire against this
  fixture until enough coverage exists for at least one indicator to
  reach `satisfied` in the first place.
