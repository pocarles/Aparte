#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
app_dir="${1:-$project_dir/dist/app-store/Aparte.app}"
validation_level="${2:-local}"
info="$app_dir/Contents/Info.plist"
entitlements_file="$(mktemp "${TMPDIR:-/tmp}/aparte-entitlements.XXXXXX")"
profile_plist="$(mktemp "${TMPDIR:-/tmp}/aparte-profile.XXXXXX")"
trap 'rm -f "$entitlements_file" "$profile_plist"' EXIT

if [[ "$validation_level" != "local" && "$validation_level" != "distribution" ]]; then
    echo "Validation level must be local or distribution." >&2
    exit 64
fi

test -d "$app_dir"
test -f "$app_dir/Contents/Resources/Aparte.icns"
test -f "$app_dir/Contents/Resources/PrivacyInfo.xcprivacy"

[[ "$(plutil -extract CFBundleIdentifier raw -o - "$info")" == "com.pocarles.aparte" ]]
[[ "$(plutil -extract LSApplicationCategoryType raw -o - "$info")" == "public.app-category.productivity" ]]
[[ "$(plutil -extract ITSAppUsesNonExemptEncryption raw -o - "$info")" == "false" ]]

codesign --verify --deep --strict "$app_dir"
codesign -d --entitlements :- "$app_dir" >"$entitlements_file" 2>/dev/null
entitlements="$(plutil -p "$entitlements_file")"
grep -q '"com\.apple\.security\.app-sandbox" => true' <<<"$entitlements"
grep -q '"com\.apple\.security\.files\.user-selected\.read-write" => true' <<<"$entitlements"
entitlement_count="$(plutil -convert xml1 -o - "$entitlements_file" | /usr/bin/xmllint --xpath 'count(/plist/dict/key)' -)"
expected_entitlement_count=2
if [[ "$validation_level" == "distribution" ]]; then
    expected_entitlement_count=4
fi
if [[ "$entitlement_count" != "$expected_entitlement_count" ]]; then
    echo "The signed app contains unexpected or missing entitlements." >&2
    exit 1
fi

if [[ "$validation_level" == "distribution" ]]; then
    embedded_profile="$app_dir/Contents/embedded.provisionprofile"
    test -f "$embedded_profile"
    security cms -D -i "$embedded_profile" >"$profile_plist"

    profile_identifier="$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.application-identifier' "$profile_plist")"
    profile_team="$(plutil -extract TeamIdentifier.0 raw -o - "$profile_plist")"
    entitlement_team="$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.developer.team-identifier' "$profile_plist")"
    signed_identifier="$(/usr/libexec/PlistBuddy -c 'Print :com.apple.application-identifier' "$entitlements_file")"
    signed_team="$(/usr/libexec/PlistBuddy -c 'Print :com.apple.developer.team-identifier' "$entitlements_file")"
    expiration="$(plutil -extract ExpirationDate raw -o - "$profile_plist")"
    expiration_epoch="$(date -j -f '%Y-%m-%dT%H:%M:%SZ' "$expiration" '+%s')"
    signature_team="$(codesign -dv --verbose=4 "$app_dir" 2>&1 | sed -n 's/^TeamIdentifier=//p')"

    [[ "$profile_identifier" == "$profile_team.com.pocarles.aparte" ]]
    [[ "$entitlement_team" == "$profile_team" ]]
    [[ "$signed_identifier" == "$profile_identifier" ]]
    [[ "$signed_team" == "$profile_team" ]]
    [[ "$signature_team" == "$profile_team" ]]
    (( expiration_epoch > $(date '+%s') ))
    [[ "$(plutil -extract Platform xml1 -o - "$profile_plist" | /usr/bin/xmllint --xpath 'boolean(/plist/array/string[text()="OSX"])' -)" == "true" ]]
fi

architectures="$(lipo -archs "$app_dir/Contents/MacOS/Aparte")"
[[ " $architectures " == *" arm64 "* ]]
[[ " $architectures " == *" x86_64 "* ]]

if [[ "$validation_level" == "distribution" ]]; then
    echo "App Store distribution signature and structure valid: $app_dir"
else
    echo "Local App Store structure valid (not upload-ready): $app_dir"
fi
