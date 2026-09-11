# Direct download releases

Aparte’s direct-download release is a Universal 2 DMG containing an ad-hoc-signed app for rehearsal or a Developer ID Application-signed app for release. Release signing uses the hardened runtime. The DMG is notarized with an App Store Connect API key, stapled, and checked with `stapler`, `codesign`, and Gatekeeper.

The workflow only publishes a GitHub Release for a `vX.Y.Z` tag whose commit is contained in `origin/main`. A manual run signs and notarizes a rehearsal artifact but does not publish it. This pipeline does not require an App Store Connect app record because it uses notarization, not App Store submission.

Required `release` environment secrets are `DEVELOPER_ID_CERT_P12`, `DEVELOPER_ID_CERT_PASSWORD`, `APPLE_TEAM_ID`, `APPLE_API_KEY_P8`, `APPLE_API_KEY_ID`, and `APPLE_API_ISSUER_ID`. The certificate and API key exist only in runner-temporary files and the temporary keychain; cleanup runs even after a failed build.

Local focused check:

```sh
make package-direct-dry-run
./scripts/validate-direct.sh --mode dry-run dist/direct-release/Aparte.dmg
```

Do not use the direct-download identity or entitlements for the Mac App Store package. `make package-app-store-local` and `make package-mas` remain separate targets.

## 1.2.1 release metadata

Version 1.2.1, build 8, is dated 2026-09-11. The app manifest, direct-package
defaults, validator defaults, and manual workflow inputs use these values.
Tagged releases read the build number from `Support/Info.plist` and require the
tag version to match the manifest. Run `make check` and `make check-direct` before
tagging `v1.2.1`; publication still requires the signed and notarized workflow.

## 1.1.0 packaging verification

The local 1.1.0 candidate passes `make check`, `make check-app-store`, and
`make check-direct`. Universal packaging builds the arm64 and x86_64 slices
separately with SwiftPM and combines them with `lipo`. This avoids the compiler
probe hang observed in Xcode 26.6's multi-architecture Swift Build path. Both
package validators still require the two architectures and verify the resulting
app's signature and bundle contents.
