#!/bin/bash
# Shared pinned artifact paths and public configuration. Never source private keys.
sparkle_version=2.9.6
sparkle_build_dir="$project_dir/.build/direct-updates"
sparkle_artifact="$sparkle_build_dir/artifacts/sparkle/Sparkle"
sparkle_framework="$sparkle_artifact/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
sparkle_feed_url="https://github.com/pocarles/Aparte/releases/latest/download/appcast.xml"

validate_sparkle_public_key() {
    printf '%s' "$1" | /usr/bin/ruby -rbase64 -e '
        text = STDIN.read
        begin
            key = Base64.strict_decode64(text)
            exit(key.bytesize == 32 && Base64.strict_encode64(key) == text ? 0 : 1)
        rescue ArgumentError
            exit 1
        end
    '
}

sign_sparkle_framework() {
    local framework=$1 identity=$2
    local version="$framework/Versions/B"
    local flags=(--force --sign "$identity")
    if [[ "$identity" != - ]]; then flags+=(--timestamp --options runtime); fi
    # Sign inside out. These are the executable components in the pinned artifact.
    codesign "${flags[@]}" "$version/Autoupdate"
    codesign "${flags[@]}" "$version/Updater.app"
    codesign "${flags[@]}" --preserve-metadata=entitlements "$version/XPCServices/Downloader.xpc"
    codesign "${flags[@]}" "$version/XPCServices/Installer.xpc"
    codesign "${flags[@]}" "$framework"
}
