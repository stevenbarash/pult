#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

if ! output="$(bash Scripts/ship-testflight.sh --dry-run --message "test release" 2>&1)"; then
  printf '%s\n' "$output"
  echo "ship-testflight dry run failed"
  exit 1
fi

assert_contains() {
  local needle="$1"
  if [[ "$output" != *"$needle"* ]]; then
    echo "Expected dry-run output to contain: $needle"
    echo "--- output ---"
    printf '%s\n' "$output"
    exit 1
  fi
}

assert_contains "DRY RUN: no commit, push, archive, or upload will be performed"
assert_contains "git commit -m test release"
assert_contains "git push"
assert_contains "xcodebuild archive"
assert_contains "PultPostHogHost"
assert_contains "PultCore.framework"
assert_contains "xcodebuild -exportArchive"

echo "ship-testflight dry run test passed"
