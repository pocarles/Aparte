#!/bin/bash
set -euo pipefail
set +x
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
source "$project_dir/scripts/sparkle-common.sh"
output_dir=${1:?Expected release archive directory}
version=${2:?Expected marketing version}
build=${3:?Expected bundle build number}
key_file=${APARTE_SPARKLE_PRIVATE_KEY_FILE:?Expected private key file supplied by release automation}
[[ -f "$key_file" && -s "$output_dir/Aparte.dmg" ]]
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "$build" =~ ^[1-9][0-9]*$ ]]
validate_sparkle_public_key "${APARTE_SPARKLE_PUBLIC_ED_KEY:-}"
derived_public_key=$(swift "$project_dir/scripts/sparkle-public-key.swift" < "$key_file")
[[ "$derived_public_key" == "$APARTE_SPARKLE_PUBLIC_ED_KEY" ]] || {
    echo "The appcast signing key does not match APARTE_SPARKLE_PUBLIC_ED_KEY." >&2
    exit 78
}
[[ "$(plutil -extract CFBundleShortVersionString raw -o - "$sparkle_framework/Resources/Info.plist")" == "$sparkle_version" ]]
archive_url="https://github.com/pocarles/Aparte/releases/download/v$version/Aparte.dmg"
release_url="https://github.com/pocarles/Aparte/releases/tag/v$version"
"$sparkle_artifact/bin/generate_appcast" --ed-key-file "$key_file" \
    --download-url-prefix "https://github.com/pocarles/Aparte/releases/download/v$version/" \
    --link "$release_url" --full-release-notes-url "$release_url" \
    --maximum-deltas 0 --maximum-versions 1 -o "$output_dir/appcast.xml" "$output_dir"
feed="$output_dir/appcast.xml"
xmllint --noout "$feed"
[[ "$(xmllint --xpath 'count(/rss/channel/item)' "$feed")" == 1 ]]
[[ "$(xmllint --xpath 'string(/rss/channel/item/*[local-name()="version"])' "$feed")" == "$build" ]]
[[ "$(xmllint --xpath 'string(/rss/channel/item/*[local-name()="shortVersionString"])' "$feed")" == "$version" ]]
[[ "$(xmllint --xpath 'string(/rss/channel/item/enclosure/@url)' "$feed")" == "$archive_url" ]]
[[ "$(xmllint --xpath 'string(/rss/channel/item/*[local-name()="link"])' "$feed")" == "$release_url" ]]
[[ "$(xmllint --xpath 'string(/rss/channel/item/*[local-name()="fullReleaseNotesLink"])' "$feed")" == "$release_url" ]]
signature="$(xmllint --xpath 'string(/rss/channel/item/enclosure/@*[local-name()="edSignature"])' "$feed")"
[[ -n "$signature" ]]
"$sparkle_artifact/bin/sign_update" --verify --ed-key-file "$key_file" "$output_dir/Aparte.dmg" "$signature"
"$sparkle_artifact/bin/sign_update" --verify --ed-key-file "$key_file" "$feed"
echo "Signed archive and appcast verified for Aparte $version, build $build."
