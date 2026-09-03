#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
configuration="${CONFIGURATION:-release}"
distribution="${DISTRIBUTION:-local}"
universal="${UNIVERSAL:-0}"

case "$distribution" in
    local)
        app_dir="$project_dir/dist/Aparte.app"
        entitlements=""
        ;;
    direct)
        app_dir="$project_dir/dist/direct/Aparte.app"
        entitlements=""
        ;;
    app-store-local|app-store)
        app_dir="$project_dir/dist/app-store/Aparte.app"
        entitlements="${ENTITLEMENTS_FILE:-$project_dir/Support/Aparte.entitlements}"
        ;;
    *)
        echo "Unknown DISTRIBUTION value: $distribution" >&2
        exit 64
        ;;
esac

contents_dir="$app_dir/Contents"
macos_dir="$contents_dir/MacOS"
resources_dir="$contents_dir/Resources"

build_args=(build --package-path "$project_dir" -c "$configuration" --product Aparte)
path_args=(build --package-path "$project_dir" -c "$configuration" --show-bin-path)
if [[ "$universal" == "1" ]]; then
    build_args+=(--arch arm64 --arch x86_64)
    path_args+=(--arch arm64 --arch x86_64)
fi

swift "${build_args[@]}"
binary_path="$(swift "${path_args[@]}")/Aparte"

rm -rf "$app_dir"
mkdir -p "$macos_dir" "$resources_dir"
cp "$binary_path" "$macos_dir/Aparte"
cp "$project_dir/Support/Info.plist" "$contents_dir/Info.plist"
if [[ -n "${APP_VERSION:-}" ]]; then
    plutil -replace CFBundleShortVersionString -string "$APP_VERSION" "$contents_dir/Info.plist"
fi
if [[ -n "${APP_BUILD_NUMBER:-}" ]]; then
    if [[ ! "$APP_BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]]; then
        echo "APP_BUILD_NUMBER must be a positive integer." >&2
        exit 64
    fi
    plutil -replace CFBundleVersion -string "$APP_BUILD_NUMBER" "$contents_dir/Info.plist"
fi
cp "$project_dir/Support/PrivacyInfo.xcprivacy" "$resources_dir/PrivacyInfo.xcprivacy"
cp "$project_dir/LICENSE" "$resources_dir/LICENSE.txt"
"$project_dir/scripts/build-icon.sh" "$project_dir/Support/AppIconSource.png" "$resources_dir/Aparte.icns"
printf 'APPL????' > "$contents_dir/PkgInfo"

if [[ -n "${PROVISIONING_PROFILE:-}" ]]; then
    cp "$PROVISIONING_PROFILE" "$contents_dir/embedded.provisionprofile"
fi

signing_identity="${SIGNING_IDENTITY:--}"
sign_args=(--force --sign "$signing_identity")
if [[ -n "$entitlements" ]]; then
    test -f "$entitlements"
    sign_args+=(--entitlements "$entitlements")
fi
codesign "${sign_args[@]}" "$app_dir"

echo "$app_dir"
