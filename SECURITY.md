# Security policy

## Supported version

Only the latest release receives security fixes.

## Reporting a vulnerability

Do not open a public issue for a vulnerability. Send a private report to the repository owner with the affected version, reproduction steps, impact, and any suggested fix. Expect an acknowledgement within seven days.

## Data boundary

Aparte stores its working Markdown document and optional recovery copy under the current macOS user's Application Support directory. It has no account, cloud sync, or analytics. HTML paste rejects subsidiary resource loads. Writing and clipboard contents are never sent to the updater.

## Direct-download updates

Only direct-download builds include Sparkle 2.9.6. They fetch a stable HTTPS feed from this repository's latest GitHub Release. Sparkle verifies the signed feed and Ed25519 archive signature before extraction. Release archives contain a Developer ID-signed, notarized app. Local and App Store builds neither link nor embed Sparkle and contain no updater configuration.

The release workflow derives the app's public key from one protected signing secret. Private keys must never enter source control or release assets. Each release must increase `CFBundleVersion`. Keep the signing key across releases; changing it requires Sparkle's documented key-rotation procedure. See [direct release instructions](docs/DIRECT_RELEASE.md).
