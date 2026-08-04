#!/bin/zsh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/claude-quota-parsing-tests.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT

xcrun swiftc -O \
  "$ROOT/Sources/CodexTokenMeter/ClaudeQuotaParsing.swift" \
  "$ROOT/Tests/ClaudeQuotaParsingTests.swift" \
  -o "$TEST_DIR/ClaudeQuotaParsingTests"

"$TEST_DIR/ClaudeQuotaParsingTests"
