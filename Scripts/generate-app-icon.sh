#!/bin/sh
# Usage: Scripts/generate-app-icon.sh path/to/icon-artwork.png
set -e
root="$(cd "$(dirname "$0")/.." && pwd)"
tool="$(mktemp -d)/generate"
swiftc "$root/Scripts/GenerateAppIcon/main.swift" -o "$tool"
"$tool" "$1" "$root/MacReader/Assets.xcassets/AppIcon.appiconset"
