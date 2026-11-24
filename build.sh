#!/bin/bash
set -euo pipefail

cd -- "$(dirname -- "$0")"
output="$PWD/build"
app="$output/Chroma.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$output/cache"
cp Info.plist "$app/Contents/Info.plist"

target="$(uname -m)-apple-macosx14.0"
xcrun swiftc -O -target "$target" -module-cache-path "$output/cache" \
    Sources/*.swift -o "$app/Contents/MacOS/Chroma"
xcrun swift -module-cache-path "$output/cache" Artwork/Icon.swift "$app/Contents/Resources/Chroma.icns"
codesign --force --sign - "$app"
printf '%s\n' "$app"
