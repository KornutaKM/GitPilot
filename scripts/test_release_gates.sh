#!/usr/bin/env bash
# Offline, dependency-free regression checks for the publisher-signed AAB gate.
# The mocked signer tests the script's error handling; it does not validate a real signature.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox"' EXIT
mkdir -p "$sandbox/repo/scripts" "$sandbox/bin"
cp "$root/scripts/build_play_bundle.sh" "$sandbox/repo/scripts/build_play_bundle.sh"

cat > "$sandbox/repo/gradlew" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
: "${MOCK_GRADLE_MARKER:?}"
printf 'invoked\n' > "$MOCK_GRADLE_MARKER"
if [[ "${MOCK_BUNDLE_MODE:-present}" == missing ]]; then
  exit 0
fi
mkdir -p app/build/outputs/bundle/release
printf 'test-only fake AAB\n' > app/build/outputs/bundle/release/app-release.aab
STUB
cat > "$sandbox/bin/jarsigner" <<'STUB'
#!/usr/bin/env bash
case "${MOCK_SIGNER_MODE:-verified}" in
  verified) printf 'jar verified.\n' ;;
  unsigned) printf 'jar is unsigned.\n' ;;
  failure) exit 1 ;;
  *) exit 99 ;;
esac
STUB
chmod +x "$sandbox/repo/gradlew" "$sandbox/bin/jarsigner"

export PATH="$sandbox/bin:$PATH"
export MOCK_GRADLE_MARKER="$sandbox/gradle-invoked"
export GITPILOT_SIGNING_STORE_PASSWORD=unimportant-test-value
export GITPILOT_SIGNING_KEY_ALIAS=test-only
export GITPILOT_SIGNING_KEY_PASSWORD=unimportant-test-value

# Capture a failing command without masking its exit code.
assert_exit() {
  local expected="$1" actual output
  shift
  rm -f "$MOCK_GRADLE_MARKER"
  actual=0
  output="$(cd "$sandbox/repo" && "$@" 2>&1)" || actual=$?
  if [[ "$actual" -ne "$expected" ]]; then
    printf 'FAIL: expected exit %s, got %s\n%s\n' "$expected" "$actual" "$output" >&2
    exit 1
  fi
}

# Mandatory secrets are checked before touching Gradle.
export GITPILOT_SIGNING_STORE_FILE="$sandbox/does-not-exist"
assert_exit 2 env -u GITPILOT_SIGNING_STORE_PASSWORD bash scripts/build_play_bundle.sh
[[ ! -e "$MOCK_GRADLE_MARKER" ]] || { echo 'FAIL: Gradle ran without password' >&2; exit 1; }

# Directories and zero-byte placeholders must not be accepted as keystores.
export GITPILOT_SIGNING_STORE_FILE="$sandbox"
assert_exit 2 bash scripts/build_play_bundle.sh
[[ ! -e "$MOCK_GRADLE_MARKER" ]] || { echo 'FAIL: Gradle ran with directory keystore' >&2; exit 1; }
export GITPILOT_SIGNING_STORE_FILE="$sandbox/empty.jks"
: > "$GITPILOT_SIGNING_STORE_FILE"
assert_exit 2 bash scripts/build_play_bundle.sh
[[ ! -e "$MOCK_GRADLE_MARKER" ]] || { echo 'FAIL: Gradle ran with empty keystore' >&2; exit 1; }

# A valid-looking keystore allows a build, but an absent AAB must fail closed.
export GITPILOT_SIGNING_STORE_FILE="$sandbox/test.jks"
printf 'dummy keystore bytes\n' > "$GITPILOT_SIGNING_STORE_FILE"
assert_exit 3 env MOCK_BUNDLE_MODE=missing bash scripts/build_play_bundle.sh
[[ -e "$MOCK_GRADLE_MARKER" ]] || { echo 'FAIL: expected mock Gradle call' >&2; exit 1; }

# Even a present AAB must not pass when jarsigner rejects or does not verify it.
assert_exit 3 env MOCK_SIGNER_MODE=failure bash scripts/build_play_bundle.sh
assert_exit 3 env MOCK_SIGNER_MODE=unsigned bash scripts/build_play_bundle.sh
assert_exit 0 env MOCK_SIGNER_MODE=verified bash scripts/build_play_bundle.sh

# Prevent re-introduction of expression interpolation into shell source.
workflow="$root/.github/workflows/android.yml"
grep -Fq 'GITPILOT_GITHUB_CLIENT_ID: ${{ vars.GITPILOT_GITHUB_CLIENT_ID }}' "$workflow"
grep -Fq '"-Pgitpilot.githubClientId=${GITPILOT_GITHUB_CLIENT_ID}"' "$workflow"
if grep -Fq 'gitpilot.githubClientId="${{ vars.' "$workflow"; then
  echo 'FAIL: GitHub Actions expression interpolated into shell command' >&2
  exit 1
fi

echo 'PASS: signing gate rejects invalid configuration, invalid bundles, and unverified signatures.'
