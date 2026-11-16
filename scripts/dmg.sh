#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
version="$(cat "$project_dir/VERSION")"
build_dir="$project_dir/build"
app_dir="$build_dir/AgentMemoryBar.app"
image="$build_dir/AgentMemoryBar-$version.dmg"
test -d "$app_dir" || { echo 'Run scripts/build.sh first' >&2; exit 1; }
stage="$(mktemp -d "$build_dir/dmg.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
ditto "$app_dir" "$stage/AgentMemoryBar.app"
ln -s /Applications "$stage/Applications"
cp "$project_dir/docs/INSTALL.txt" "$stage/Read Me First.txt"
hdiutil create -volname AgentMemoryBar -srcfolder "$stage" -ov -format UDZO "$image"
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  : "${SIGN_IDENTITY:?Signing is required for notarization}"
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$image"
  xcrun notarytool submit "$image" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$image"
fi
hdiutil verify "$image"
(cd "$build_dir" && shasum -a 256 "$(basename "$image")" > SHA256SUMS)
echo "$image"
