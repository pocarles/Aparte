#!/bin/bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "usage: $0 SOURCE_PNG OUTPUT_ICNS" >&2
    exit 64
fi

source_png="$1"
output_icns="$2"
icon_work="$(mktemp -d "${TMPDIR:-/tmp}/aparte-icon.XXXXXX")"
iconset="$icon_work/Aparte.iconset"
trap 'rm -rf "$icon_work"' EXIT

mkdir -p "$iconset" "$(dirname "$output_icns")"

make_icon() {
    local pixels="$1"
    local filename="$2"
    sips -z "$pixels" "$pixels" "$source_png" --out "$iconset/$filename" >/dev/null
}

make_icon 16 icon_16x16.png
make_icon 32 icon_16x16@2x.png
make_icon 32 icon_32x32.png
make_icon 64 icon_32x32@2x.png
make_icon 128 icon_128x128.png
make_icon 256 icon_128x128@2x.png
make_icon 256 icon_256x256.png
make_icon 512 icon_256x256@2x.png
make_icon 512 icon_512x512.png
make_icon 1024 icon_512x512@2x.png

iconutil --convert icns --output "$output_icns" "$iconset"
