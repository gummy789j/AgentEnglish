#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
app="$(cd "$1" && pwd)"
agent="$2"
cwd="$(cd "$3" && pwd)"
tmp="$(mktemp -d)"
trap 'touch "$tmp/done"' EXIT
"$app/Contents/MacOS/AgentEnglish" --verify-cli "${4:-}" >"$tmp/report" &
probe=$!
open -na /Applications/Ghostty.app --args -e "$(command -v node)" "$root/Tests/panel-driver.cjs" "$app" "$agent" "$cwd" "$tmp/done" "${4:-}"
rc=0; wait "$probe" || rc=$?
cat "$tmp/report"; exit "$rc"
