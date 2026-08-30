# Aparte

Aparte is a native macOS menu bar writing pad. Press Option-Space, write, copy, and press Escape. It keeps one local Markdown document and stays out of the way.

## V1 principles

- Native AppKit and TextKit. No Electron or embedded browser.
- One focused writing pad, not a notes library or chat client.
- Local Markdown only. No accounts, cloud sync, analytics, or network calls.
- No idle polling. CPU should settle near zero while the pad is hidden.

## Requirements

- macOS 14 or later
- Xcode 16 or a newer Swift 6 toolchain

## Build and run

```sh
make check
make run
```

The packaged app is written to `dist/Aparte.app` and ad-hoc signed for local use.

## Keyboard shortcuts

| Action | Shortcut |
| --- | --- |
| Show or hide Aparte | Option-Space |
| Dismiss | Escape |
| Bold | Command-B |
| Italic | Command-I |
| Underline | Command-U |
| Copy as Markdown | Command-Shift-C |
| Save Markdown As | Command-Shift-S |

See [docs/architecture.md](docs/architecture.md), [docs/manual-acceptance.md](docs/manual-acceptance.md), and [docs/performance.md](docs/performance.md) for V1 design and proof.

## License

Aparte is available under the MIT License. Third-party research and notices are recorded in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

