#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
xcrun swiftc -swift-version 5 "$root"/Sources/{Ollama,TranslationState}.swift \
  "$root/Tests/Prompts/main.swift" -o "$tmp/PromptReview"
"$tmp/PromptReview" "${1:-$root/Tests/Prompts/cases.json}"
