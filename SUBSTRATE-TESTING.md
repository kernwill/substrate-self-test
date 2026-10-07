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

You should see: `app_data`'s and `app_logs`'s public-access-block
evidence (all four flags `true`) under `AC-3` (`app_logs` is the
regression target - see main.tf's comment for how to break it on purpose);
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

**Status: still shelved, re-confirmed 2026-09-22.** Blocked on AWS
account access - the account reachable from the existing sign-in sits
inside an AWS Organization whose service control policy denies
`s3:CreateBucket` (not fixable from that member account), and a
fresh-account signup then hit a hard AWS Builder ID error requiring
AWS Support. Re-checked 2026-09-22 with a read-only
`aws iam simulate-principal-policy --action-names s3:CreateBucket`
against the current identity (`arn:aws:iam::034313911997:user/substrate-self-test`)
rather than assumed unchanged from memory: still `explicitDeny`,
`AllowedByOrganizations: false` - same SCP block, nothing resolved.
Tracked as open item 8 in `docs/REQUIREMENTS.md` section 31. Revisit
once a clean AWS account is available; the instructions below are
otherwise unchanged and ready to run as-is.

**Note:** `substrate collect` requires valid Okta flags on every
invocation now (section 6 below, resolved item 12) - the AWS-focused
command below uses `collect-okta.sh` for that reason, not because this
section is really about Okta.

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

Then run collect, and merge it into a compile. Okta flags are required
too now (see section 6 for where the values come from):

```
cd /Users/willkern/substrate-self-test
source okta.env  # or export OKTA_ORG_URL/OKTA_CLIENT_ID/OKTA_PRIVATE_KEY yourself
AWS_PROFILE=<your profile, if not default> ./collect-okta.sh --out /tmp/self-test-runtime
cd /Users/willkern/substrate
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

## 6. Exercise the Okta collectors (FR-3.9)

**Status: fully verified against a live org, 2026-09-21.** All four
Okta collectors (MFA enrollment, session policy, provisioning/
deprovisioning events, admin role assignments -
`internal/frontend/collectors/okta`) are built, wired into `substrate
collect`/`compile`, covered by fixture-based unit tests, and now
confirmed end to end against a real Okta Integrator Free Plan org: real
evidence (the org's actual default MFA enrollment policy, session
policy idle/lifetime settings, provisioning events, and admin role
assignments) flowed through a real `substrate compile --runtime` run,
tagged `"basis": "observed"`.

One extra setup step beyond scopes is required and easy to miss -
`docs/adr/0015` and `docs/okta-api-scopes.md` didn't originally mention
it, and it was found only by actually doing this. (A second one, DPoP,
used to be required too - **resolved 2026-09-22**: `TokenSource` now
implements RFC 9449 DPoP itself, so there's nothing to configure on the
app's General tab either way; leave DPoP on or off, it works.)

1. **Admin role assignment, separate from OAuth scopes.** Granting the
   four scopes below is necessary but not sufficient: the access token
   will correctly carry every granted scope, but
   `GET /api/v1/policies` and `GET /api/v1/logs` still 403 with
   `E0000006` until the app is ALSO assigned an actual Okta admin role.
   On the app's own **Admin roles** tab, click **Edit assignments** and
   assign **Read-Only Administrator** (not Org Admin - this is the
   least-privilege choice, matching FR-3.7's "read-only always"
   principle).

Full setup, start to finish:

1. Sign up at https://developer.okta.com/signup/ if you don't already
   have an org - free, and requires a business-looking email domain
   (personal providers like Gmail/Yahoo are rejected outright; a cheap
   domain + free forwarding, e.g. Cloudflare Email Routing, works fine
   if you don't have one).
2. In the Admin Console: **Applications → Applications → Create App
   Integration → API Services**. Name it (e.g. "substrate collector").
3. On the app's **General** tab, under **Client Credentials**, switch
   from "Client secret" to **"Public key / Private key"**, then
   **Add key → Generate new key**. Save the private key shown -
   Okta may show it as JWK JSON rather than PEM; either is fine to keep,
   but `--okta-private-key` needs PEM (`-----BEGIN ... PRIVATE
   KEY-----`) - convert JWK to PEM locally if that's what you got,
   never by pasting the key into a chat session. Note the **Client ID**
   on this same tab, and the **Key ID** if you generate more than one
   key. The DPoP toggle on this same tab can be left either way (see
   above).
4. Grant exactly the scopes `docs/okta-api-scopes.md` documents
   (`okta.policies.read`, `okta.logs.read`, `okta.users.read`,
   `okta.roles.read`) under the app's **Okta API Scopes** tab.
5. Assign **Read-Only Administrator** under the app's **Admin roles**
   tab (see above).
6. Run collect against it, then merge into compile:

`collect-okta.sh` (this repo) fills in the three Okta flags from
environment variables, so they don't need retyping on every run now
that they're required on every `substrate collect` call (item 12).
Copy `okta.env.example` to `okta.env`, fill in the real values from
steps 3-5 above, and it's gitignored so it never gets committed:

```
cd /Users/willkern/substrate-self-test
cp okta.env.example okta.env   # fill in OKTA_ORG_URL/OKTA_CLIENT_ID/OKTA_PRIVATE_KEY
source okta.env
./collect-okta.sh --out /tmp/self-test-okta-runtime

cd /Users/willkern/substrate
./bin/substrate compile --source /Users/willkern/substrate-self-test \
  --out /tmp/self-test-out-okta-runtime --runtime /tmp/self-test-okta-runtime
./bin/substrate ir query --dir /tmp/self-test-out-okta-runtime/ir --control IA-2
./bin/substrate ir query --dir /tmp/self-test-out-okta-runtime/ir --control AC-12
```

You should see the org's real MFA enrollment policy/policies under
`IA-2` and session policy rule(s) under `AC-12`, each tagged
`"source_type": "okta"` and `"basis": "observed"` in its provenance.

**Note - updated 2026-09-22, this got stricter.** AWS and Okta
collection are now both mandatory (item 12, resolved) - `collect` runs
them concurrently and fails the whole command if either leg errors, so
a blocked AWS account (section 5's still-open item 8, re-confirmed
still blocked 2026-09-22) means `collect`/`collect-okta.sh` cannot
succeed at all right now, full stop, even with perfectly correct Okta
credentials. There is no longer a way to get just the Okta artifacts
out of the `collect` command while AWS is blocked. Either fix AWS
access first (see section 5), or verify the Okta path alone by calling
`oktacollectors.CollectMFAEnrollmentPolicies`/`CollectSessionPolicies`/
`CollectProvisioningEvents`/`CollectAdminRoleAssignments` directly
against a `RESTClient` built from your org's credentials, write their
output to `okta_mfa.json`/`okta_session_policy.json`/
`okta_provisioning.json`/`okta_admin_role.json` in a runtime directory
(matching `collect.go`'s artifact names), and point `compile --runtime`
at that directory - this is exactly how the 2026-09-21 verification
above was actually done, since this environment's AWS account was
blocked at the time.

No cleanup needed - this is a read-only collector against your own org
(FR-3.7's "read-only always" principle, applied to Okta the same way it
already applies to AWS); nothing it does creates or modifies anything.

## What this fixture can't show yet

- No KSI indicator will ever read `satisfied` against this fixture,
  regardless of what you fix or break - real evidence coverage is
  still far short of what any indicator's full control list requires.
  This is the honest, current state of the product (see `docs/adr/0007`),
  not something wrong with the fixture.
- 7 of the 10 KSI families (all but SVC, IAM, and CNA) have no Rego
  module at all yet, so their indicators always read "not yet
  implemented" no matter what evidence exists.
- `gate`'s regression detection is real and tested (see
  `cmd/substrate/gate_test.go`), but won't visibly fire against this
  fixture until enough coverage exists for at least one indicator to
  reach `satisfied` in the first place.
