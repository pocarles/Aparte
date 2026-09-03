# Working on Aparte

## Product boundary

Aparte is a native macOS menu bar writing pad. It is one document invoked by a global hotkey. It is not a notes library, chat client, cloud service, or Electron app.

Never add accounts, analytics, remote storage, network calls, persistent background polling, or a permanent editor toolbar without an explicit product decision.

## Start, test, and stop

- Build and package: `make package`
- Build the sandboxed universal App Store candidate: `make package-app-store-local`
- Run tests: `swift test`
- Full local gate: `make check` runs unit tests, release packaging, the packaged AppKit runtime acceptance harness, diff checks, and strict signature verification.
- App Store gate: `make check-app-store` runs the tests, packages the sandboxed universal candidate, exercises its runtime harness, and verifies its icon, privacy manifest, architectures, signature, and entitlements.
- Direct-download package gate: `make check-direct` builds and verifies the Universal 2 DMG shape without Apple credentials.
- Run the app: `open dist/Aparte.app`
- Stop only the packaged app: `pkill -x Aparte`

## Local mistakes to avoid

- Do not run UI code in core tests. Keep persistence and Markdown conversion in `AparteCore`.
- Do not use repeating timers for hotkeys, autosave, or focus overlays. Idle CPU must settle near zero.
- Do not save attributed archives as the document source. Markdown is the source of truth.
- Do not copy rich paste styles directly into the editor. Normalize them to Aparte's type scale and supported attributes.
- Do not add direct access to Desktop or another user folder. Store builds use App Sandbox, so export through `NSSavePanel` and keep the user-selected file entitlement narrow.

## Required proof

Run `make check`. For a direct release, also run `make check-direct` and follow `docs/DIRECT_RELEASE.md`. For an App Store release, run `make check-app-store`, complete `docs/manual-acceptance.md` on the sandboxed candidate, and update measured CPU and memory in `docs/performance.md`.
