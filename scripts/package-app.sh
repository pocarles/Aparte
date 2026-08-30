#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
configuration="${CONFIGURATION:-release}"
app_dir="$project_dir/dist/Aparte.app"
contents_dir="$app_dir/Contents"
macos_dir="$contents_dir/MacOS"
resources_dir="$contents_dir/Resources"

swift build --package-path "$project_dir" -c "$configuration" --product Aparte
binary_path="$(swift build --package-path "$project_dir" -c "$configuration" --show-bin-path)/Aparte"

rm -rf "$app_dir"
mkdir -p "$macos_dir" "$resources_dir"
cp "$binary_path" "$macos_dir/Aparte"
cp "$project_dir/Support/Info.plist" "$contents_dir/Info.plist"
printf 'APPL????' > "$contents_dir/PkgInfo"
codesign --force --sign - "$app_dir"

echo "$app_dir"

