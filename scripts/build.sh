#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
build_dir="$project_dir/build"
app_dir="$build_dir/AgentMemoryBar.app"
version="$(cat "$project_dir/VERSION")"
arch="${ARCH:-universal}"
mkdir -p "$build_dir/module-cache" "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
compile() {
  xcrun swiftc -swift-version 5 -O -target "$1-apple-macosx13.0" \
    -module-cache-path "$build_dir/module-cache" \
    "$project_dir/Sources/Controller.swift" "$project_dir/Sources/main.swift" \
    -o "$build_dir/AgentMemoryBar-$1" -framework AppKit
}
if [[ "$arch" == universal ]]; then
  compile arm64
  compile x86_64
  lipo -create "$build_dir/AgentMemoryBar-arm64" "$build_dir/AgentMemoryBar-x86_64" \
    -output "$app_dir/Contents/MacOS/AgentMemoryBar"
elif [[ "$arch" == arm64 || "$arch" == x86_64 ]]; then
  compile "$arch"
  cp "$build_dir/AgentMemoryBar-$arch" "$app_dir/Contents/MacOS/AgentMemoryBar"
else
  echo 'ARCH must be universal, arm64, or x86_64' >&2
  exit 1
fi
xcrun swiftc -swift-version 5 -O -module-cache-path "$build_dir/module-cache" \
  "$project_dir/scripts/make-icon.swift" -o "$build_dir/make-icon" -framework AppKit
"$build_dir/make-icon" "$build_dir/AppIcon.iconset"
iconutil -c icns "$build_dir/AppIcon.iconset" -o "$app_dir/Contents/Resources/AppIcon.icns"
cp "$project_dir/Resources/Info.plist" "$app_dir/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$app_dir/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $version" "$app_dir/Contents/Info.plist"
if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$app_dir"
else
  codesign --force --sign - --timestamp=none "$app_dir"
fi
codesign --verify --deep --strict "$app_dir"
echo "$app_dir"
