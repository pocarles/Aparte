#!/bin/bash
set -euo pipefail

mode=dry-run
version=1.0.0
build_number=1
usage() { echo "Usage: scripts/validate-direct.sh [--mode dry-run|release] [--version X.Y.Z] [--build N] APP_OR_DMG"; }
while (($# > 0)); do
    case "$1" in
        --mode) mode=$2; shift 2 ;;
        --version) version=$2; shift 2 ;;
        --build) build_number=$2; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        --*) echo "Unknown argument: $1" >&2; exit 64 ;;
        *) break ;;
    esac
done
(( $# == 1 )) || { usage >&2; exit 64; }
target=$1
[[ "$mode" == dry-run || "$mode" == release ]] || { echo "Invalid mode." >&2; exit 64; }

validate_app() {
    local app=$1
    local info="$app/Contents/Info.plist"
    local binary="$app/Contents/MacOS/Aparte"
    [[ -d "$app" && -f "$info" && -x "$binary" && -f "$app/Contents/Resources/Aparte.icns" \
        && -f "$app/Contents/Resources/PrivacyInfo.xcprivacy" \
        && -f "$app/Contents/Resources/LICENSE.txt" ]] || { echo "App is incomplete: $app" >&2; exit 65; }
    plutil -lint "$info" "$app/Contents/Resources/PrivacyInfo.xcprivacy"
    [[ "$(plutil -extract CFBundleExecutable raw -o - "$info")" == Aparte ]]
    [[ "$(plutil -extract CFBundleIdentifier raw -o - "$info")" == com.pocarles.aparte ]]
    [[ "$(plutil -extract CFBundleShortVersionString raw -o - "$info")" == "$version" ]]
    [[ "$(plutil -extract CFBundleVersion raw -o - "$info")" == "$build_number" ]]
    architectures=" $(lipo -archs "$binary") "
    [[ "$architectures" == *" arm64 "* && "$architectures" == *" x86_64 "* ]] || { echo "App is not Universal 2." >&2; exit 65; }
    codesign --verify --deep --strict "$app"
    if [[ "$mode" == release ]]; then
        details="$(codesign -d --verbose=4 "$app" 2>&1)"
        grep -Eq '^Authority=Developer ID Application:' <<<"$details"
        grep -Eq '^TeamIdentifier=[A-Z0-9]{10}$' <<<"$details"
        grep -Eq 'flags=.*runtime' <<<"$details"
        [[ "$(sed -n 's/^TeamIdentifier=//p' <<<"$details")" == "${APARTE_TEAM_ID:?}" ]]
    else
        details="$(codesign -d --verbose=4 "$app" 2>&1)"
        grep -q 'Signature=adhoc' <<<"$details"
    fi
}

if [[ -d "$target" ]]; then
    validate_app "$target"
else
    [[ -f "$target" ]] || { echo "App or DMG not found: $target" >&2; exit 66; }
    [[ "$target" == *.dmg ]] || { echo "Expected an app bundle or DMG." >&2; exit 64; }
    mount_dir="$(mktemp -d "${TMPDIR:-/tmp}/aparte-dmg.XXXXXX")"
    cleanup() { hdiutil detach -quiet "$mount_dir" 2>/dev/null || true; rm -rf "$mount_dir"; }
    trap cleanup EXIT
    hdiutil attach -quiet -nobrowse -readonly -mountpoint "$mount_dir" "$target"
    [[ -d "$mount_dir/Aparte.app" && -L "$mount_dir/Applications" \
        && "$(readlink "$mount_dir/Applications")" == /Applications ]] || { echo "DMG layout is invalid." >&2; exit 65; }
    validate_app "$mount_dir/Aparte.app"
    if [[ "$mode" == release ]]; then
        codesign --verify --strict "$target"
        xcrun stapler validate "$target"
        spctl --assess --type open --context context:primary-signature "$target"
        spctl --assess --type execute "$mount_dir/Aparte.app"
    fi
fi
echo "validated $mode direct package: $target"
