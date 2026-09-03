#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"

: "${APP_STORE_APP_IDENTITY:?Set APP_STORE_APP_IDENTITY to the Apple Distribution certificate name.}"
: "${APP_STORE_INSTALLER_IDENTITY:?Set APP_STORE_INSTALLER_IDENTITY to the Mac Installer Distribution certificate name.}"
: "${APP_STORE_PROVISIONING_PROFILE:?Set APP_STORE_PROVISIONING_PROFILE to the Mac App Store provisioning profile path.}"

test -f "$APP_STORE_PROVISIONING_PROFILE"

if [[ "$APP_STORE_APP_IDENTITY" != "Apple Distribution:"* ]]; then
    echo "APP_STORE_APP_IDENTITY must name an Apple Distribution certificate." >&2
    exit 64
fi
if [[ "$APP_STORE_INSTALLER_IDENTITY" != "Mac Installer Distribution:"* ]]; then
    echo "APP_STORE_INSTALLER_IDENTITY must name a Mac Installer Distribution certificate." >&2
    exit 64
fi
if [[ ! "$APP_STORE_APP_IDENTITY" =~ \(([A-Z0-9]{10})\)$ ]]; then
    echo "Could not read the Apple team identifier from APP_STORE_APP_IDENTITY." >&2
    exit 64
fi
app_identity_team="${BASH_REMATCH[1]}"
if [[ ! "$APP_STORE_INSTALLER_IDENTITY" =~ \(([A-Z0-9]{10})\)$ ]] ||
   [[ "${BASH_REMATCH[1]}" != "$app_identity_team" ]]; then
    echo "The application and installer certificates must belong to the same Apple team." >&2
    exit 64
fi

if ! security find-identity -v -p codesigning | grep -Fq -- "\"$APP_STORE_APP_IDENTITY\""; then
    echo "The requested Apple Distribution identity is not available in the keychain." >&2
    exit 64
fi

profile_plist="$(mktemp "${TMPDIR:-/tmp}/aparte-profile.XXXXXX")"
sign_entitlements="$(mktemp "${TMPDIR:-/tmp}/aparte-sign-entitlements.XXXXXX")"
trap 'rm -f "$profile_plist" "$sign_entitlements"' EXIT
security cms -D -i "$APP_STORE_PROVISIONING_PROFILE" >"$profile_plist"
profile_identifier="$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.application-identifier' "$profile_plist")"
profile_team="$(/usr/libexec/PlistBuddy -c 'Print :TeamIdentifier:0' "$profile_plist")"
entitlement_team="$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.developer.team-identifier' "$profile_plist")"
expiration="$(plutil -extract ExpirationDate raw -o - "$profile_plist")"
expiration_epoch="$(date -j -f '%Y-%m-%dT%H:%M:%SZ' "$expiration" '+%s')"

if [[ "$profile_identifier" != "$app_identity_team.com.pocarles.aparte" ]]; then
    echo "The provisioning profile does not match com.pocarles.aparte." >&2
    exit 64
fi
if [[ "$profile_team" != "$app_identity_team" || "$entitlement_team" != "$app_identity_team" ]]; then
    echo "The provisioning profile and Apple Distribution certificate belong to different teams." >&2
    exit 64
fi
if (( expiration_epoch <= $(date '+%s') )); then
    echo "The provisioning profile has expired." >&2
    exit 64
fi
if [[ "$(plutil -extract Platform xml1 -o - "$profile_plist" | /usr/bin/xmllint --xpath 'boolean(/plist/array/string[text()="OSX"])' -)" != "true" ]]; then
    echo "The provisioning profile is not valid for macOS." >&2
    exit 64
fi
if [[ "$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.security.app-sandbox' "$profile_plist")" != "true" ]] ||
   [[ "$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.security.files.user-selected.read-write' "$profile_plist")" != "true" ]]; then
    echo "The provisioning profile does not authorize Aparte's sandbox file access." >&2
    exit 64
fi

identity_fingerprint="$(security find-certificate -c "$APP_STORE_APP_IDENTITY" -p | openssl x509 -outform der | shasum -a 256 | awk '{print $1}')"
certificate_count="$(plutil -extract DeveloperCertificates raw -o - "$profile_plist")"
profile_contains_identity=0
for ((certificate_index = 0; certificate_index < certificate_count; certificate_index++)); do
    profile_fingerprint="$(plutil -extract "DeveloperCertificates.$certificate_index" raw -o - "$profile_plist" | base64 -D | shasum -a 256 | awk '{print $1}')"
    if [[ "$profile_fingerprint" == "$identity_fingerprint" ]]; then
        profile_contains_identity=1
        break
    fi
done
if [[ "$profile_contains_identity" != "1" ]]; then
    echo "The provisioning profile does not include the selected Apple Distribution certificate." >&2
    exit 64
fi

cp "$project_dir/Support/Aparte.entitlements" "$sign_entitlements"
/usr/libexec/PlistBuddy -c "Add :com.apple.application-identifier string $profile_identifier" "$sign_entitlements"
/usr/libexec/PlistBuddy -c "Add :com.apple.developer.team-identifier string $profile_team" "$sign_entitlements"

DISTRIBUTION=app-store \
UNIVERSAL=1 \
SIGNING_IDENTITY="$APP_STORE_APP_IDENTITY" \
PROVISIONING_PROFILE="$APP_STORE_PROVISIONING_PROFILE" \
ENTITLEMENTS_FILE="$sign_entitlements" \
"$project_dir/scripts/package-app.sh"

app_dir="$project_dir/dist/app-store/Aparte.app"
"$project_dir/scripts/validate-app-store.sh" "$app_dir" distribution

version="$(plutil -extract CFBundleShortVersionString raw -o - "$app_dir/Contents/Info.plist")"
package="$project_dir/dist/Aparte-$version.pkg"

productbuild \
    --component "$app_dir" /Applications \
    --sign "$APP_STORE_INSTALLER_IDENTITY" \
    "$package"

pkgutil --check-signature "$package"
echo "$package"
