#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
app="${1:-$root/dist/AgentEnglish.app}"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
flags=()
if [[ "${AGENTENGLISH_TEST_PROBES:-0}" == 1 ]]; then flags+=(-DTEST_PROBES); fi
xcrun swiftc ${flags[@]+"${flags[@]}"} -O -swift-version 5 -target "$(uname -m)-apple-macosx15.0" "$root"/Sources/*.swift -o "$app/Contents/MacOS/AgentEnglish"
cp "$root/Info.plist" "$app/Contents/"
cp "$root/Docs/guide.html" "$root/Assets/"{AgentEnglish.icns,mark.svg} "$app/Contents/Resources/"
bridge="$app/Contents/Resources/Bridge"
mkdir -p "$bridge"
if [[ ! -d "$root/Bridge/node_modules/@xterm/headless" ]]; then (cd "$root/Bridge" && npm ci --no-audit --no-fund); fi
cp "$root/Bridge/XTERM-LICENSE" "$bridge/"
cp "$root"/Bridge/*.cjs "$root"/Bridge/agent-en "$root"/Bridge/integration.zsh "$bridge/"
for pkg in @xterm/headless node-pty; do
  origin="$root/Bridge/node_modules/$pkg"
  dest="$bridge/node_modules/$pkg"
  mkdir -p "$dest"
  lib=lib; [[ "$pkg" != @xterm/headless ]] || lib=lib-headless
  cp -R "$origin/$lib" "$origin/package.json" "$dest/"
  for license in "$origin"/LICENSE*; do [[ ! -f "$license" ]] || cp "$license" "$dest/"; done
done
arch="$(node -p process.arch)"
native="$bridge/node_modules/node-pty/prebuilds/darwin-$arch"
mkdir -p "$native"
cp "$root/Bridge/node_modules/node-pty/prebuilds/darwin-$arch/"{pty.node,spawn-helper} "$native/"
chmod +x "$native/spawn-helper" "$bridge/agent-en"
codesign --force --sign - "$native/pty.node"
codesign --force --sign - "$native/spawn-helper"
codesign --force --sign - "$app"
codesign --verify --deep --strict "$app"
