# Direct download releases

Aparte’s direct-download release is a Universal 2 DMG containing an ad-hoc-signed app for rehearsal or a Developer ID Application-signed app for release. Release signing uses the hardened runtime. The DMG is notarized with an App Store Connect API key, stapled, and checked with `stapler`, `codesign`, and Gatekeeper.

The workflow only publishes a GitHub Release for a `vX.Y.Z` tag whose commit is contained in `origin/main`. A manual run signs and notarizes a rehearsal artifact but does not publish it. This pipeline does not require an App Store Connect app record because it uses notarization, not App Store submission.

Required `release` environment secrets are `DEVELOPER_ID_CERT_P12`, `DEVELOPER_ID_CERT_PASSWORD`, `APPLE_TEAM_ID`, `APPLE_API_KEY_P8`, `APPLE_API_KEY_ID`, `APPLE_API_ISSUER_ID`, and `SPARKLE_ED25519_PRIVATE_KEY`. The certificate and keys exist only in runner-temporary files and the temporary keychain; cleanup runs even after a failed build.

Local focused check:

```sh
make package-direct-dry-run
./scripts/validate-direct.sh --mode dry-run "${TMPDIR:-/tmp}/aparte-package-dry/Aparte.dmg"
```

Do not use the direct-download identity or entitlements for the Mac App Store package. `make package-app-store-local` and `make package-mas` remain separate targets.

## Signed updates

Direct builds include Sparkle 2.9.6 and check `https://github.com/pocarles/Aparte/releases/latest/download/appcast.xml` daily. Check for Updates… is also available in the main, status, and options menus. Sparkle verifies both the feed and archive before extraction and asks before installing by default. System profiling is disabled. Local and App Store builds contain no updater or `SU*` keys.

At the authorized first updater release, create and securely back up a Sparkle Ed25519 key using the pinned distribution's `generate_keys` tool. Store its exported base64 32-byte seed in the protected `release` environment secret `SPARKLE_ED25519_PRIVATE_KEY`. Do not put the seed in commands, logs, source files, or release assets. The workflow derives the public key with CryptoKit and passes it to packaging as `APARTE_SPARKLE_PUBLIC_ED_KEY`. No separate public-key secret is needed. Keep this key for later releases.

Ordinary direct packaging requires `APARTE_SPARKLE_PUBLIC_ED_KEY` to contain a canonical base64 32-byte public key. The Makefile dry-run target supplies an RFC 8032 public test vector solely to exercise packaging without credentials. Release mode rejects that fixture. It cannot produce a production update.

Before tagging, increase both the marketing version and the positive integer `CFBundleVersion`. The workflow rejects a build number that does not exceed the latest published release. It signs and notarizes the DMG, then uses the pinned `generate_appcast` tool with the signing key in a mode-0600 temporary file. `scripts/generate-appcast.sh` checks the version, build, archive URL, release-note links, archive signature, and embedded feed signature. Never edit the XML after signing.

The workflow uploads the DMG, checksum, and signed `appcast.xml` into one draft release before publishing it as latest. This keeps the stable feed and its archive available together. A manual workflow run prepares a signed rehearsal package without publication.

Version 1.2.1 and earlier releases have no updater. Existing users must install the first updater-enabled release manually. Before publishing it, complete the direct-update checks in [manual acceptance](manual-acceptance.md), including an actual signed upgrade from an older test build. Local packaging checks do not prove installation or notarization.

## 1.3.0 release metadata

Version 1.3.0, build 9, is dated 2026-09-11. The app manifest, direct-package
defaults, validator defaults, and manual workflow inputs use these values.
Tagged releases read the build number from `Support/Info.plist` and require the
tag version to match the manifest. Run `make check` and `make check-direct` before
tagging `v1.3.0`; publication still requires the signed and notarized workflow.

## 1.1.0 packaging verification

The local 1.1.0 candidate passes `make check`, `make check-app-store`, and
`make check-direct`. Universal packaging builds the arm64 and x86_64 slices
separately with SwiftPM and combines them with `lipo`. This avoids the compiler
probe hang observed in Xcode 26.6's multi-architecture Swift Build path. Both
package validators still require the two architectures and verify the resulting
app's signature and bundle contents.
