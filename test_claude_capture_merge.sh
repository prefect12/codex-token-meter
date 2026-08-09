#!/bin/zsh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/claude-capture-merge-tests.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT

xcrun swiftc -O \
  "$ROOT/Sources/CodexTokenMeter/ClaudeCaptureMerge.swift" \
  "$ROOT/Tests/ClaudeCaptureMergeTests.swift" \
  -o "$TEST_DIR/ClaudeCaptureMergeTests"

"$TEST_DIR/ClaudeCaptureMergeTests"
