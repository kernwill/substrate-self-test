#!/usr/bin/env bash
set -euo pipefail

# Wrapper for `substrate collect` that fills in the Okta flags from
# environment variables, so they don't have to be retyped on every run
# now that Okta collection is mandatory (substrate's
# docs/REQUIREMENTS.md item 12, resolved 2026-09-22) - the same
# AWS_PROFILE-as-env-var convenience SUBSTRATE-TESTING.md already
# leans on for AWS, extended to Okta's three required flags.
#
# Required:
#   OKTA_ORG_URL      e.g. https://your-org.okta.com
#   OKTA_CLIENT_ID    the API Services app's client ID
#   OKTA_PRIVATE_KEY  path to the app's private key, PEM-encoded
#
# Optional:
#   OKTA_KEY_ID       only needed if the app has more than one key
#   SUBSTRATE_BIN     path to the substrate binary
#                      (default: ../substrate/bin/substrate)
#
# Usage - anything after the script name is passed straight through to
# `substrate collect` (--out is still required, this script doesn't
# default it):
#
#   export OKTA_ORG_URL=https://your-org.okta.com
#   export OKTA_CLIENT_ID=<client id>
#   export OKTA_PRIVATE_KEY=/path/to/key.pem
#   ./collect-okta.sh --out /tmp/self-test-runtime
#
# Never commit real values for these into this repo - export them in
# your shell, or source them from a local file this repo's .gitignore
# excludes (see okta.env.example).

missing=()
[[ -z "${OKTA_ORG_URL:-}" ]] && missing+=("OKTA_ORG_URL")
[[ -z "${OKTA_CLIENT_ID:-}" ]] && missing+=("OKTA_CLIENT_ID")
[[ -z "${OKTA_PRIVATE_KEY:-}" ]] && missing+=("OKTA_PRIVATE_KEY")

if [[ ${#missing[@]} -gt 0 ]]; then
  echo "collect-okta.sh: missing required environment variable(s): ${missing[*]}" >&2
  echo "" >&2
  echo "set them first, e.g.:" >&2
  echo "  export OKTA_ORG_URL=https://your-org.okta.com" >&2
  echo "  export OKTA_CLIENT_ID=<client id from the API Services app's General tab>" >&2
  echo "  export OKTA_PRIVATE_KEY=/path/to/your-key.pem" >&2
  echo "" >&2
  echo "or copy okta.env.example to okta.env, fill it in, and run:" >&2
  echo "  source okta.env && ./collect-okta.sh --out <dir>" >&2
  exit 1
fi

if [[ ! -f "$OKTA_PRIVATE_KEY" ]]; then
  echo "collect-okta.sh: OKTA_PRIVATE_KEY ($OKTA_PRIVATE_KEY) does not exist" >&2
  exit 1
fi

substrate_bin="${SUBSTRATE_BIN:-../substrate/bin/substrate}"
if [[ ! -x "$substrate_bin" ]]; then
  echo "collect-okta.sh: substrate binary not found or not executable at $substrate_bin" >&2
  echo "build it first (cd ../substrate && make build), or set SUBSTRATE_BIN" >&2
  exit 1
fi

args=(collect --okta-org-url "$OKTA_ORG_URL" --okta-client-id "$OKTA_CLIENT_ID" --okta-private-key "$OKTA_PRIVATE_KEY")
if [[ -n "${OKTA_KEY_ID:-}" ]]; then
  args+=(--okta-key-id "$OKTA_KEY_ID")
fi
args+=("$@")

exec "$substrate_bin" "${args[@]}"
