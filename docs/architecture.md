# Architecture

## Reference decision

Aparte is built from scratch, with Wisp and Inkdown used as design references only. No source, assets, fonts, dependencies, or release scripts were copied from either project.

This is the smallest clean choice.

- For V1, forking Wisp would have brought font selection, storage switching, updating, tours, release UI, and other product behavior outside Aparte's scope. Wisp did confirm that a Carbon hotkey, an accessory AppKit process, an `NSPanel`, and Markdown-on-disk fit the intended shape.
- Forking Inkdown would bring a document browser, `DocumentGroup`, split preview, WebKit, JavaScript, bundled Markdown packages, KaTeX, Mermaid, and a large third-party license set. Inkdown did confirm the value of `NSTextView`, normalized UTF-16 ranges, and SF Pro typography.
- Copying isolated code would still create attribution and maintenance work without saving much implementation time. Aparte's V1 shell and document rules are small enough to own directly.

The inspected snapshots were:

- Wisp, `sulemaanhamza/wisp`, commit `e4a5c95119aeb8cf822acb103495cd68f2e2d303`, MIT.
- Inkdown, `renardresearch/inkdown`, commit `c5b676791c1a51ec568b789a7925bfe43aea1403`, MIT.

## Runtime shape

Aparte is an accessory-only AppKit process. It has no Dock icon and owns:

- one `NSStatusItem` menu bar button;
- one Carbon global hotkey registration, defaulting to Option-Space, driven by the system event loop rather than polling;
- one reusable 1,032 by 816 point `NSPanel`, fitted down for smaller displays, containing a native, vertically scrolling `NSTextView`;
- one borderless dimming window per connected display while the pad is visible;
- one working Markdown document and one optional last-cleared recovery file.

The panel sits above the dimming windows. Focus mode animates only window alpha for 140 to 180 milliseconds. It uses no blur, screenshots, screen capture, or repeating animation timer.

## Document model

`AparteCore` owns the document boundary:

- `MarkdownCodec` converts the supported Markdown subset to a normalized attributed string and back.
- `PasteNormalizer` accepts RTF, HTML, or plain text but keeps only supported meaning. It drops foreign fonts, sizes, colors, and spacing.
- `PersistenceStore` atomically writes UTF-8 Markdown to the application support directory returned by Foundation. A normal local build uses `~/Library/Application Support/Aparte/aparte.md`. A sandboxed App Store build uses Aparte's private container.

The editor displays a normalized attributed string. Markdown remains the saved and export format. This avoids an opaque attributed-text archive and keeps the document usable outside Aparte.

Supported V1 meaning is bold, italic, underline through `<u>`, headings, ordered and unordered lists, and links. Underline uses explicit HTML because CommonMark has no underline syntax.

The Link popover reads the clipboard only when the user opens it. It prefills only when the clipboard contains one valid HTTP or HTTPS address. Aparte does not monitor clipboard changes in the background.

The lower Save action opens the standard macOS Save panel. It derives the proposed filename from the first non-empty line and limits it to 80 characters. The user chooses the destination and confirms any overwrite. This interaction gives the sandboxed app access only to the selected file.

## UI structure

`EditorTextView` is a native rich `NSTextView` with macOS undo, spelling, selection, keyboard navigation, and text input behavior. A small contextual formatting bar appears only when the selection is non-empty. It changes the selected attributed ranges and then the document controller schedules a save.

The autosave debounce uses a one-shot `DispatchWorkItem`. It is canceled and replaced on edits and does no work at idle. Markdown is cached until the next content or formatting change. After a successful save, a file metadata check lets an unchanged pad skip serialization and disk reads. A changed, replaced, or missing file forces the normal save path, and failed saves remain eligible for retry. Dismissal and application termination still flush pending changes.

## Privacy and dependencies

Local and App Store builds link only Apple system frameworks and contain no updater. Direct-download builds additionally link Sparkle 2.9.6, pinned in `Package.resolved`, behind `APARTE_DIRECT_UPDATES`. SwiftPM resolves the package for every build but adds it to the executable only when `APARTE_ENABLE_UPDATES=1`; the packaging script selects the build mode.

The direct updater uses Sparkle's scheduler for daily HTTPS checks and its standard update window. Aparte adds no polling timer. The main menu, status menu, and options card share the same Check for Updates… command and validate it against `canCheckForUpdates`. The signed GitHub feed and archive are verified before extraction. System profiling and unattended installation default to off. No writing or clipboard contents enter update requests.

The privacy manifest declares no tracking, collected data, or tracking domains. It declares UserDefaults with reason CA92.1 for preferences stored by Aparte and FileTimestamp with reason C617.1 for the local document metadata used by the save cache. The HTML paste importer denies every subsidiary resource request, including remote images and stylesheets.

## Packaging

Swift Package Manager builds the executable and `scripts/package-app.sh` assembles the app. The normal local package stays separate from the App Store candidate so sandbox testing does not silently replace the user's existing local document.

Direct builds use a separate SwiftPM scratch directory. Packaging preserves Sparkle's framework symlinks, signs each nested executable before the framework and app, and injects the feed and public key only into the direct bundle. Validators check the configuration, signatures, linkage, and runtime search path. Non-direct validators require Sparkle and all `SU*` keys to be absent.

The App Store candidate is universal for Apple silicon and Intel Macs. Its entitlements enable App Sandbox, read-write access to files chosen through a system panel, and outgoing network connections for Send to endpoint…. `scripts/package-mas.sh` can sign the app and installer after the correct Apple Distribution certificate, Mac Installer Distribution certificate, and provisioning profile exist. It does not upload.

## Writing preferences and recovery

The word and character count is hidden by default. Document totals are cached
until the text changes, and selection totals are cached by text revision and
selected range. Moving an empty caret reuses the document total. Formatting
changes leave counts valid while invalidating cached Markdown. Display zoom uses the native scroll
view's magnification; it does not rewrite document fonts or Markdown. These
preferences and the selected global shortcut use local UserDefaults.

Clear writes the current nonempty Markdown atomically to `aparte.recovery.md`
before erasing the editor. A failed recovery write prevents Clear. Restore is
one undoable editor replacement; discard removes only the recovery file.

Return uses the small `AparteCore` list-marker parser and one native undoable
replacement to insert the next item or remove an empty marker. Clipboard export
uses normalized editor content, with an explicit plain-text option.

Shortcut changes register the replacement before retiring the previous hotkey.
Launch at login uses Apple's Service Management API and reads its current status
when Settings opens or regains focus. A single reusable, normal AppKit Settings window contains the shortcut recorder and login controls; errors stay beside their controls. Command-comma and Settings… in the application, status, and writing-options menus open the same window after hiding the pad and saving the document. Shortcut recording begins only when requested and stops when cancelled, saved, the window closes, or focus leaves it. Direct builds include an update button that uses the same updater availability and dispatch as the menus. Neither feature introduces polling or a helper process.

## Endpoint response memory

Send to endpoint uses a task delegate to discard response-body chunks as they
arrive. Success is reported only after the complete transfer finishes, so a
connection failure after successful headers still reports a failed send. The
delegate refuses redirects and cancels its URLSession task when the Swift task
is cancelled. No response body is retained.
