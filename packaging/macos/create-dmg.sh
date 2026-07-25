#!/usr/bin/env bash
set -euo pipefail
app_path="$1"
output_path="$2"
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
cp -R "$app_path" "$stage/Vityo Nightly.app"
ln -s /Applications "$stage/Applications"
hdiutil create -volname "Vityo Nightly" -srcfolder "$stage" -ov -format UDZO "$output_path"
