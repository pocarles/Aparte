#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
mode=dry-run
version="${APARTE_VERSION:-1.0.0}"
build_number="${APARTE_BUILD_NUMBER:-1}"
output_dir="${APARTE_OUTPUT_DIR:-$project_dir/dist/direct-release}"
configuration="${CONFIGURATION:-release}"
identity="${APARTE_SIGN_IDENTITY:-}"
team_id="${APARTE_TEAM_ID:-}"
api_key_path="${APPLE_API_KEY_PATH:-}"
api_key_id="${APPLE_API_KEY_ID:-}"
api_issuer_id="${APPLE_API_ISSUER_ID:-}"
overwrite="${APARTE_OVERWRITE:-0}"

usage() {
    echo "Usage: scripts/package-direct.sh [--mode dry-run|release]"
}

while (($# > 0)); do
    case "$1" in
        --mode) (($# >= 2)) || { usage >&2; exit 64; }; mode=$2; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown argument: $1" >&2; usage >&2; exit 64 ;;
    esac
done

[[ "$mode" == dry-run || "$mode" == release ]] || { echo "Mode must be dry-run or release." >&2; exit 64; }
[[ "$version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || {
    echo "APARTE_VERSION must use X.Y.Z." >&2; exit 64;
}
[[ "$build_number" =~ ^[1-9][0-9]*$ ]] || { echo "APARTE_BUILD_NUMBER must be positive." >&2; exit 64; }

for command_name in swift plutil codesign ditto hdiutil lipo shasum xcrun; do
    command -v "$command_name" >/dev/null || { echo "Required command is unavailable: $command_name" >&2; exit 69; }
done

if [[ "$mode" == release ]]; then
    [[ "$identity" == Developer\ ID\ Application:* ]] || {
        echo "Release mode requires APARTE_SIGN_IDENTITY to be a Developer ID Application identity." >&2; exit 78;
    }
    [[ "$team_id" =~ ^[A-Z0-9]{10}$ ]] || { echo "Release mode requires APARTE_TEAM_ID." >&2; exit 78; }
    [[ -f "$api_key_path" && -n "$api_key_id" && -n "$api_issuer_id" ]] || {
        echo "Release mode requires APPLE_API_KEY_PATH, APPLE_API_KEY_ID, and APPLE_API_ISSUER_ID." >&2; exit 78;
    }
    security find-identity -v -p codesigning | grep -Fq -- "\"$identity\"" || {
        echo "The requested Developer ID identity is not available." >&2; exit 78;
    }
else
    identity=-
fi

if [[ "$overwrite" != "1" &&
      ( -e "$output_dir/Aparte.dmg" || -e "$output_dir/Aparte.dmg.sha256" ) ]]; then
    echo "Release output already exists in $output_dir" >&2
    exit 73
fi

temp_root="$(mktemp -d "${TMPDIR:-/tmp}/aparte-direct.XXXXXX")"
staged_dmg="$temp_root/Aparte.dmg"
stage_root="$temp_root/dmg-root"
app_stage="$temp_root/Aparte.app"
cleanup() { rm -rf "$temp_root"; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

cd "$project_dir"
DISTRIBUTION=direct UNIVERSAL=1 CONFIGURATION="$configuration" \
    APP_VERSION="$version" APP_BUILD_NUMBER="$build_number" SIGNING_IDENTITY=- \
    "$project_dir/scripts/package-app.sh" >/dev/null
ditto "$project_dir/dist/direct/Aparte.app" "$app_stage"

if [[ "$mode" == release ]]; then
    codesign --force --timestamp --options runtime --sign "$identity" "$app_stage"
else
    codesign --force --sign - "$app_stage"
fi

"$project_dir/scripts/validate-direct.sh" --mode "$mode" --version "$version" \
    --build "$build_number" "$app_stage"

mkdir -p "$stage_root"
ditto "$app_stage" "$stage_root/Aparte.app"
ln -s /Applications "$stage_root/Applications"
hdiutil create -quiet -volname Aparte -srcfolder "$stage_root" -format UDZO "$staged_dmg"

if [[ "$mode" == release ]]; then
    codesign --force --timestamp --sign "$identity" "$staged_dmg"
    codesign --verify --strict "$staged_dmg"
    xcrun notarytool submit "$staged_dmg" --key "$api_key_path" \
        --key-id "$api_key_id" --issuer "$api_issuer_id" --wait
    xcrun stapler staple "$staged_dmg"
    xcrun stapler validate "$staged_dmg"
    spctl --assess --type open --context context:primary-signature --verbose=2 "$staged_dmg"
fi

mkdir -p "$output_dir"
if [[ "$overwrite" == "1" ]]; then
    rm -f "$output_dir/Aparte.dmg" "$output_dir/Aparte.dmg.sha256"
fi
mv "$staged_dmg" "$output_dir/Aparte.dmg"
(cd "$output_dir" && shasum -a 256 Aparte.dmg > Aparte.dmg.sha256 && shasum -a 256 -c Aparte.dmg.sha256)
"$project_dir/scripts/validate-direct.sh" --mode "$mode" --version "$version" \
    --build "$build_number" "$output_dir/Aparte.dmg"
echo "$output_dir/Aparte.dmg"
