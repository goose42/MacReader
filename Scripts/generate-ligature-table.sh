#!/bin/sh
# Usage: Scripts/generate-ligature-table.sh path/to/JetBrainsMono-Regular.ttf
set -e
root="$(cd "$(dirname "$0")/.." && pwd)"
kit="$root/MacReaderKit/Sources/MacReaderKit/Structure"
tool="$(mktemp -d)/generate"
swiftc "$kit/GlyphFingerprint.swift" "$root/Scripts/GenerateLigatureTable/main.swift" -o "$tool"
"$tool" "$1" "$kit/CodeLigatureTable.swift"
