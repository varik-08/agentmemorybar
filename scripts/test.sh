#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT
mkdir -p "$project_dir/build/module-cache"
xcrun swiftc -swift-version 5 -D TESTING -module-cache-path "$project_dir/build/module-cache" \
  "$project_dir/Sources/Controller.swift" "$project_dir/Tests/main.swift" -o "$test_dir/tests"
env -u AGENTMEMORY_SECRET "$test_dir/tests" "$test_dir/home"
