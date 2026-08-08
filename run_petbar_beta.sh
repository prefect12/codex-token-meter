#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/build/Task Bar Beta.app"

"$ROOT/build_petbar_beta.sh" >/dev/null
open -n "$APP"

echo "$APP"
