#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
source "$project_dir/scripts/sparkle-common.sh"
fixture=11qYAYKxCrfVS/7TyWQHOg7hcvPapiMlrwIaaPcHURo=
validate_sparkle_public_key "$fixture"
for invalid in '' invalid AQ== "$fixture "; do
    if validate_sparkle_public_key "$invalid"; then
        echo "Invalid public key accepted." >&2; exit 1
    fi
done

scratch=$(mktemp -d "${TMPDIR:-/tmp}/aparte-updater-check.XXXXXX")
trap 'rm -rf "$scratch"' EXIT
expect_configuration_failure() {
    local status=0
    "$@" > "$scratch/output" 2>&1 || status=$?
    [[ "$status" == 78 ]] || { echo "Expected configuration rejection, got $status." >&2; exit 1; }
}
expect_configuration_failure env -u APARTE_SPARKLE_PUBLIC_ED_KEY DISTRIBUTION=direct bash "$project_dir/scripts/package-app.sh"
expect_configuration_failure env APARTE_SPARKLE_PUBLIC_ED_KEY=invalid DISTRIBUTION=direct bash "$project_dir/scripts/package-app.sh"
expect_configuration_failure env APARTE_SPARKLE_PUBLIC_ED_KEY="$fixture" bash "$project_dir/scripts/package-direct.sh" --mode release

# Only published RFC 8032 test vector 1 is used here, never a production signing key.
swiftc "$project_dir/scripts/sparkle-public-key.swift" -o "$scratch/public-key"
for invalid in '' invalid AQ==; do
    status=0
    printf '%s' "$invalid" | "$scratch/public-key" > "$scratch/public" 2> "$scratch/error" || status=$?
    [[ "$status" == 78 && ! -s "$scratch/public" ]]
done
umask 077
/usr/bin/ruby -rbase64 -e 'File.write(ARGV[0], Base64.strict_encode64(["9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60"].pack("H*")))' "$scratch/test-seed"
printf '%s\n' "$fixture" > "$scratch/expected-public"
"$scratch/public-key" < "$scratch/test-seed" > "$scratch/public"
cmp "$scratch/expected-public" "$scratch/public"

# A mismatch must stop before the archive is inspected or appcast generation starts.
printf 'Unused archive placeholder for key-mismatch rejection.\n' > "$scratch/Aparte.dmg"
expect_configuration_failure env APARTE_SPARKLE_PRIVATE_KEY_FILE="$scratch/test-seed" \
    APARTE_SPARKLE_PUBLIC_ED_KEY="21qYAYKxCrfVS/7TyWQHOg7hcvPapiMlrwIaaPcHURo=" \
    bash "$project_dir/scripts/generate-appcast.sh" "$scratch" 1.2.1 8
[[ ! -e "$scratch/appcast.xml" ]]
/usr/bin/ruby -rjson -e '
    pins = JSON.parse(File.read(ARGV[0])).fetch("pins")
    abort "Unexpected Sparkle resolution" unless pins.length == 1 && pins[0]["identity"] == "sparkle" &&
        pins[0]["state"] == {"revision" => "ac2def288cbff5cfc7df3ffef6abdf45b72bcb0a", "version" => "2.9.6"}
' "$project_dir/Package.resolved"
echo "Updater key derivation, mismatch rejection, release fixture rejection, and pinned resolution passed."
