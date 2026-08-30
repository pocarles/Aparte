# Architecture

## Reference decision

Aparte is built from scratch, with Wisp and Inkdown used as design references only. No source, assets, fonts, dependencies, or release scripts were copied from either project.

This is the smallest clean choice.

- Forking Wisp would bring preferences, font selection, storage switching, launch-at-login, updating, tours, release UI, and other product behavior that Aparte does not need. Wisp did confirm that a Carbon hotkey, an accessory AppKit process, an `NSPanel`, and Markdown-on-disk fit the intended shape.
- Forking Inkdown would bring a document browser, `DocumentGroup`, split preview, WebKit, JavaScript, bundled Markdown packages, KaTeX, Mermaid, and a large third-party license set. Inkdown did confirm the value of `NSTextView`, normalized UTF-16 ranges, and SF Pro typography.
- Copying isolated code would still create attribution and maintenance work without saving much implementation time. Aparte's V1 shell and document rules are small enough to own directly.

The inspected snapshots were:

- Wisp, `sulemaanhamza/wisp`, commit `e4a5c95119aeb8cf822acb103495cd68f2e2d303`, MIT.
- Inkdown, `renardresearch/inkdown`, commit `c5b676791c1a51ec568b789a7925bfe43aea1403`, MIT.

## Runtime shape

Aparte is an accessory-only AppKit process. It has no Dock icon and owns:

- one `NSStatusItem` menu bar button;
- one Carbon Option-Space hotkey registration, driven by the system event loop rather than polling;
- one reusable 660 by 520 point `NSPanel` containing a native `NSTextView`;
- one borderless dimming window per connected display while the pad is visible;
- one local Markdown document.

The panel sits above the dimming windows. Focus mode animates only window alpha for 140 to 180 milliseconds. It uses no blur, screenshots, screen capture, or repeating animation timer.

## Document model

`AparteCore` owns the document boundary:

- `MarkdownCodec` converts the supported Markdown subset to a normalized attributed string and back.
- `PasteNormalizer` accepts RTF, HTML, or plain text but keeps only supported meaning. It drops foreign fonts, sizes, colors, and spacing.
- `PersistenceStore` atomically writes UTF-8 Markdown to `~/Library/Application Support/Aparte/aparte.md`.

The editor displays a normalized attributed string. Markdown remains the saved and export format. This avoids an opaque attributed-text archive and keeps the document usable outside Aparte.

Supported V1 meaning is bold, italic, underline through `<u>`, headings, ordered and unordered lists, and links. Underline uses explicit HTML because CommonMark has no underline syntax.

## UI structure

`EditorTextView` is a native rich `NSTextView` with macOS undo, spelling, selection, keyboard navigation, and text input behavior. A small contextual formatting bar appears only when the selection is non-empty. It changes the selected attributed ranges and then the document controller schedules a save.

The autosave debounce uses a one-shot `DispatchWorkItem`. It is canceled and replaced on edits and does no work at idle. Dismissal and application termination force a final save.

## Privacy and dependencies

Aparte has no external package dependency, web view, network request, updater, account, cloud sync, analytics, or telemetry. It links only Apple system frameworks through AppKit, Foundation, Uniform Type Identifiers, and Carbon.

## Packaging

Swift Package Manager builds the executable and `scripts/package-app.sh` assembles `dist/Aparte.app`. The local package is ad-hoc signed. Distribution outside local development still needs a Developer ID signature and notarization.

