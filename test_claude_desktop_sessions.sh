#!/bin/zsh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/claude-desktop-sessions-tests.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT

xcrun swiftc -O \
  "$ROOT/Sources/CodexPetBar/ClaudeDesktopSessions.swift" \
  "$ROOT/Tests/ClaudeDesktopSessionsTests.swift" \
  -o "$TEST_DIR/ClaudeDesktopSessionsTests"

"$TEST_DIR/ClaudeDesktopSessionsTests"
