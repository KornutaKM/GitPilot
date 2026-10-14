#!/usr/bin/env bash
# Build a publisher-signed Android App Bundle for Google Play internal testing.
# Run from repository root on a secure publisher-controlled build machine.
set -euo pipefail

required=(
  GITPILOT_SIGNING_STORE_FILE
  GITPILOT_SIGNING_STORE_PASSWORD
  GITPILOT_SIGNING_KEY_ALIAS
  GITPILOT_SIGNING_KEY_PASSWORD
)
for name in "${required[@]}"; do
  if [[ -z "${!name:-}" ]]; then
    echo "Missing required signing setting: ${name}" >&2
    exit 2
  fi
done
if [[ ! -r "${GITPILOT_SIGNING_STORE_FILE}" ]]; then
  echo "Cannot read release signing keystore" >&2
  exit 2
fi
command -v jarsigner >/dev/null || { echo 'JDK jarsigner is required' >&2; exit 2; }

./gradlew --no-daemon :app:testDebugUnitTest :app:lintDebug :app:bundleRelease

bundle="app/build/outputs/bundle/release/app-release.aab"
[[ -s "$bundle" ]] || { echo 'Release AAB missing or empty' >&2; exit 3; }

verification="$(jarsigner -verify -verbose "$bundle" 2>&1)" || {
  echo 'AAB signature verification failed' >&2
  exit 3
}
grep -qi 'jar verified\.' <<<"$verification" || {
  echo 'AAB has no verified upload signature' >&2
  exit 3
}
echo 'PASS: publisher-signed release AAB; upload to Google Play internal testing.'
sha256sum "$bundle"
