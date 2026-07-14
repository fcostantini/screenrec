#!/bin/bash
# Locates the code-signing identity for screenrec builds and prints it on stdout
# (consumed by bundle.sh). Never creates or modifies certificates.
#
# Preference order:
#   1. "screenrec-dev"     — the project's self-signed identity (stable across rebuilds,
#                            so TCC grants survive; created once, manually — see below)
#   2. "Apple Development" — any Apple-issued development identity
#
# Exit 0 with the identity on stdout, or exit 1 with setup instructions on stderr.
# --pretend-missing: behave as if no identity exists (for verification).
set -euo pipefail

PREFERRED="screenrec-dev"

if [[ "${1:-}" == "--pretend-missing" ]]; then
  identities=""
else
  identities=$(security find-identity -p codesigning -v 2>/dev/null || true)
fi

if grep -q "\"${PREFERRED}\"" <<<"$identities"; then
  cert_hash=$(grep "\"${PREFERRED}\"" <<<"$identities" | head -1 | awk '{print $2}')
  echo "Using identity: ${PREFERRED} (${cert_hash})" >&2
  echo "${PREFERRED}"
  exit 0
fi

apple_dev=$(grep -o '"Apple Development: [^"]*"' <<<"$identities" | head -1 | tr -d '"' || true)
if [[ -n "$apple_dev" ]]; then
  echo "Using identity: ${apple_dev}" >&2
  echo "${apple_dev}"
  exit 0
fi

cat >&2 <<EOF
✗ No valid code-signing identity found.

Builds signed ad-hoc get a new identity every time, so macOS re-asks for the
Screen Recording permission on every rebuild. Create the stable identity once
(manual, ~2 minutes — this script never creates certificates):

  1. Open Keychain Access:
     open "/System/Library/CoreServices/Applications/Keychain Access.app"
  2. Menu bar: Keychain Access → Certificate Assistant → Create a Certificate…
       Name: ${PREFERRED}   Identity Type: Self-Signed Root   Type: Code Signing
  3. Trust it for code signing (a password dialog will appear):
     security find-certificate -c ${PREFERRED} -p > /tmp/${PREFERRED}.pem
     security add-trusted-cert -r trustRoot -p codeSign /tmp/${PREFERRED}.pem
  4. Confirm: security find-identity -p codesigning -v   # → 1 valid identity

Then re-run this script.
EOF
exit 1
