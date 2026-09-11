#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
configuration="${CONFIGURATION:-release}"
distribution="${DISTRIBUTION:-local}"
universal="${UNIVERSAL:-0}"
source "$project_dir/scripts/sparkle-common.sh"
export APARTE_ENABLE_UPDATES=0

case "$distribution" in
    local)
        app_dir="$project_dir/dist/Aparte.app"
        entitlements=""
        ;;
    direct)
        app_dir="$project_dir/dist/direct/Aparte.app"
        entitlements=""
        validate_sparkle_public_key "${APARTE_SPARKLE_PUBLIC_ED_KEY:-}" || {
            echo "Direct packaging requires APARTE_SPARKLE_PUBLIC_ED_KEY containing a base64 32-byte public key." >&2
            exit 78
        }
        export APARTE_ENABLE_UPDATES=1
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
if [[ "$distribution" == direct ]]; then
    build_args+=(--scratch-path "$sparkle_build_dir")
    path_args+=(--scratch-path "$sparkle_build_dir")
fi
if [[ "$universal" == "1" ]]; then
    # Build each slice with SwiftPM, avoiding Swift Build's multi-architecture
    # compiler-probe deadlock on recent Xcode versions.
    architecture_binaries=()
    for architecture in arm64 x86_64; do
        swift "${build_args[@]}" --arch "$architecture"
        architecture_path="$(swift "${path_args[@]}" --arch "$architecture")"
        architecture_binaries+=("$architecture_path/Aparte")
    done
    binary_path="$project_dir/.build/Aparte-universal"
    lipo -create "${architecture_binaries[@]}" -output "$binary_path"
else
    swift "${build_args[@]}"
    binary_path="$(swift "${path_args[@]}")/Aparte"
fi

rm -rf "$app_dir"
mkdir -p "$macos_dir" "$resources_dir"
cp "$binary_path" "$macos_dir/Aparte"
cp "$project_dir/Support/Info.plist" "$contents_dir/Info.plist"
# The checked-in manifest never carries updater configuration.
[[ "$(plutil -convert xml1 -o - "$contents_dir/Info.plist" | /usr/bin/xmllint --xpath 'count(/plist/dict/key[starts-with(.,"SU")])' -)" == 0 ]]
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
if [[ "$distribution" == direct ]]; then
    [[ "$(plutil -extract CFBundleShortVersionString raw -o - "$sparkle_framework/Resources/Info.plist")" == "$sparkle_version" ]]
    mkdir -p "$contents_dir/Frameworks"
    ditto "$sparkle_framework" "$contents_dir/Frameworks/Sparkle.framework"
    cp "$sparkle_artifact/LICENSE" "$resources_dir/Sparkle-LICENSE.txt"
    cp "$project_dir/THIRD_PARTY_NOTICES.md" "$resources_dir/THIRD_PARTY_NOTICES.md"
    plutil -insert SUFeedURL -string "$sparkle_feed_url" "$contents_dir/Info.plist"
    plutil -insert SUPublicEDKey -string "$APARTE_SPARKLE_PUBLIC_ED_KEY" "$contents_dir/Info.plist"
    for key in SUEnableAutomaticChecks SUVerifyUpdateBeforeExtraction SURequireSignedFeed; do
        plutil -insert "$key" -bool true "$contents_dir/Info.plist"
    done
    plutil -insert SUEnableSystemProfiling -bool false "$contents_dir/Info.plist"
    plutil -insert SUAutomaticallyUpdate -bool false "$contents_dir/Info.plist"
    plutil -insert SUScheduledCheckInterval -integer 86400 "$contents_dir/Info.plist"
    sign_sparkle_framework "$contents_dir/Frameworks/Sparkle.framework" "$signing_identity"
    if [[ "$signing_identity" != - ]]; then sign_args+=(--timestamp --options runtime); fi
fi
if [[ -n "$entitlements" ]]; then
    test -f "$entitlements"
    sign_args+=(--entitlements "$entitlements")
fi
codesign "${sign_args[@]}" "$app_dir"
if [[ "$distribution" == direct ]]; then
    bash "$project_dir/scripts/validate-updater.sh" direct "$app_dir"
else
    bash "$project_dir/scripts/validate-updater.sh" none "$app_dir"
fi

echo "$app_dir"
