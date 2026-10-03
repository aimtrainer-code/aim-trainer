#!/usr/bin/env bash
# Runs VANTA's self tests headlessly.
#
#   tools/test.sh [--filter substring]
#
# Requires GODOT to point at a Godot 4.7.x editor binary (see docs/BUILDING.md).
set -euo pipefail

GODOT="${GODOT:-godot}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v "$GODOT" >/dev/null 2>&1 && [ ! -x "$GODOT" ]; then
  echo "error: Godot binary not found (set GODOT=/path/to/godot)" >&2
  exit 127
fi

# Import first: it regenerates .godot/global_script_class_cache.cfg, which is what
# makes `class_name` types resolvable for scripts executed with --script.
# Do not hide import failures: a broken import should fail CI just like a broken test.
mkdir -p "$ROOT/build"
"$GODOT" --headless --path "$ROOT" --import 2>&1 | tee "$ROOT/build/import.log"

# Keep a complete, timestamped test log for local debugging and CI artifacts.
"$GODOT" --headless --path "$ROOT" --script res://tests/run_tests.gd -- "$@" 2>&1 | tee "$ROOT/build/test.log"
