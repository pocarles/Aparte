#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
source_dir="${1:-$project_dir}"
benchmark_dir="$(mktemp -d "${TMPDIR:-/tmp}/aparte-performance.XXXXXX")"
trap 'rm -rf "$benchmark_dir"' EXIT

# Compile the real sources with release optimization. All document/defaults/
# clipboard fixtures are private to this process; the installed app is untouched.
swiftc -swift-version 6 -O -enable-bare-slash-regex \
    -module-cache-path "$benchmark_dir/cache" -module-name AparteCore \
    -emit-module -emit-library "$source_dir"/Sources/AparteCore/*.swift \
    -emit-module-path "$benchmark_dir/AparteCore.swiftmodule" \
    -o "$benchmark_dir/libAparteCore.dylib"

app_sources=()
for source in "$source_dir"/Sources/Aparte/*.swift; do
    case "$(basename "$source")" in AparteMain.swift|RuntimeAcceptance.swift) continue ;; esac
    app_sources+=("$source")
done
swiftc -swift-version 6 -O -enable-bare-slash-regex \
    -module-cache-path "$benchmark_dir/cache" \
    -I "$benchmark_dir" -L "$benchmark_dir" -lAparteCore \
    -Xlinker -rpath -Xlinker "$benchmark_dir" \
    "${app_sources[@]}" "$project_dir/scripts/PerformanceBenchmark.swift" \
    -o "$benchmark_dir/benchmark"
"$benchmark_dir/benchmark" "${@:2}"
