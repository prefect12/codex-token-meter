#!/bin/zsh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/taskbar-process-runner-tests.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT

xcrun swiftc -O \
  "$ROOT/Sources/CodexPetBar/TaskBarProcessRunner.swift" \
  "$ROOT/Tests/TaskBarProcessRunnerTests.swift" \
  -o "$TEST_DIR/TaskBarProcessRunnerTests"

"$TEST_DIR/TaskBarProcessRunnerTests"
