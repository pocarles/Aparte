#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
source "$project_dir/scripts/sparkle-common.sh"
kind=${1:?Expected direct or none}
app=${2:?Expected app bundle}
expected_team=${3:-}
info="$app/Contents/Info.plist"
binary="$app/Contents/MacOS/Aparte"
framework="$app/Contents/Frameworks/Sparkle.framework"
linked="$(otool -L "$binary")"
su_count="$(plutil -convert xml1 -o - "$info" | /usr/bin/xmllint --xpath 'count(/plist/dict/key[starts-with(.,"SU")])' -)"

if [[ "$kind" == none ]]; then
    [[ "$su_count" == 0 && ! -e "$framework" && "$linked" != *Sparkle.framework* ]]
    [[ -z "$(find "$app/Contents" -name '*Sparkle*' -print)" ]]
    echo "Updater absent from non-direct app."
    exit 0
fi
[[ "$kind" == direct ]] || exit 64
[[ "$linked" == *'@rpath/Sparkle.framework/Versions/B/Sparkle'* ]]
otool -l "$binary" | /usr/bin/awk '
    $1 == "cmd" && $2 == "LC_RPATH" { in_rpath = 1; next }
    in_rpath && $1 == "path" { if ($2 == "@executable_path/../Frameworks") found = 1; in_rpath = 0 }
    END { exit !found }
'
[[ -L "$framework/Versions/Current" && "$(readlink "$framework/Versions/Current")" == B ]]
for entry in Sparkle Resources Autoupdate Updater.app XPCServices; do
    [[ -L "$framework/$entry" && "$(readlink "$framework/$entry")" == "Versions/Current/$entry" ]]
done
[[ "$(plutil -extract CFBundleShortVersionString raw -o - "$framework/Resources/Info.plist")" == "$sparkle_version" ]]
[[ "$(plutil -extract SUFeedURL raw -o - "$info")" == "$sparkle_feed_url" ]]
validate_sparkle_public_key "$(plutil -extract SUPublicEDKey raw -o - "$info")"
for key in SUEnableAutomaticChecks SUVerifyUpdateBeforeExtraction SURequireSignedFeed; do
    [[ "$(plutil -extract "$key" raw -o - "$info")" == true ]]
done
[[ "$(plutil -extract SUEnableSystemProfiling raw -o - "$info")" == false ]]
[[ "$(plutil -extract SUAutomaticallyUpdate raw -o - "$info")" == false ]]
[[ "$(plutil -extract SUScheduledCheckInterval raw -o - "$info")" == 86400 ]]
[[ "$su_count" == 8 ]]
test -s "$app/Contents/Resources/Sparkle-LICENSE.txt"
test -s "$app/Contents/Resources/THIRD_PARTY_NOTICES.md"
for component in "$framework/Versions/B/Autoupdate" "$framework/Versions/B/Updater.app" \
    "$framework/Versions/B/XPCServices/Downloader.xpc" "$framework/Versions/B/XPCServices/Installer.xpc" "$framework"; do
    codesign --verify --strict "$component"
    if [[ -n "$expected_team" ]]; then
        details="$(codesign -dv --verbose=4 "$component" 2>&1)"
        [[ "$(sed -n 's/^TeamIdentifier=//p' <<< "$details")" == "$expected_team" ]]
        grep -Eq '^Authority=Developer ID Application:' <<< "$details"
        grep -Eq 'flags=.*runtime' <<< "$details"
    fi
done
echo "Direct updater framework, signatures, and configuration valid."
