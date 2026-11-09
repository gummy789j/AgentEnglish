#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
testapp="$tmp/PanelTest.app/Contents"
mkdir -p "$testapp/MacOS" "$testapp/Resources"
cp "$root/Assets/mark.svg" "$testapp/Resources/"
xcrun swiftc -O "$root"/Sources/{Brand,Ollama,TranslationState,PreviewPanel}.swift "$root/Tests/Panel/main.swift" -o "$testapp/MacOS/PanelTest"
"$testapp/MacOS/PanelTest"
