# Working on Aparte

## Product boundary

Aparte is a native macOS menu bar writing pad. It is one document invoked by a global hotkey. It is not a notes library, chat client, cloud service, or Electron app.

Never add accounts, analytics, remote storage, network calls, persistent background polling, or a permanent editor toolbar without an explicit product decision.

## Start, test, and stop

- Build and package: `make package`
- Run tests: `swift test`
- Full local gate: `make check`
- Run the app: `open dist/Aparte.app`
- Stop only the packaged app: `pkill -x Aparte`

## Local mistakes to avoid

- Do not run UI code in core tests. Keep persistence and Markdown conversion in `AparteCore`.
- Do not use repeating timers for hotkeys, autosave, or focus overlays. Idle CPU must settle near zero.
- Do not save attributed archives as the document source. Markdown is the source of truth.
- Do not copy rich paste styles directly into the editor. Normalize them to Aparte's type scale and supported attributes.

## Required proof

Run `make check`. For a release, complete `docs/manual-acceptance.md` on the packaged app and update measured CPU and memory in `docs/performance.md`.

