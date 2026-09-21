# V1 manual acceptance

Run this checklist against `dist/Aparte.app`. Record the date, macOS version, commit, and result before tagging V1.

## Automated release-harness evidence

On August 30, 2026, commit `da9657a` passed `make check` on macOS 26.5.2. The command built and ad-hoc signed the release app, then ran `dist/Aparte.app/Contents/MacOS/Aparte --runtime-acceptance` against temporary test data.

The packaged AppKit runtime passed all 13 checks:

- panel visible at up to 1,032 by 816 points, fitted down for smaller displays;
- editor owns first-responder focus;
- panel level stays above the focus overlays;
- one passive, translucent, non-blur overlay exists per connected display;
- contextual formatting bar appears for a selection;
- autosave completes without error;
- the saved file is clean Markdown;
- Markdown restores through a fresh document controller;
- Escape dismisses the panel and removes the overlays;
- twenty consecutive show/hide cycles leave no visible panel or retained overlay.

This harness does not replace the manual checks below. A person still needs to judge the animation and typography, invoke Option-Space from another app, test rich paste through the live clipboard, and review both system appearances.

On September 3, 2026, the locally prepared sandboxed candidate opened with a separate empty document. It accepted text ending in an emoji without crashing and opened the standard Save panel with `One clear place to think` proposed from the first line. The save was cancelled, the throwaway document was cleared, the candidate was stopped, and the normal local app was relaunched. The existing unsandboxed document was not opened or changed. Computer-driven Option-Space did not produce a conclusive result, so the physical shortcut check remains open.

## Invocation and focus

- [ ] Aparte appears in the menu bar and not the Dock.
- [ ] Option-Space opens a centered pad near 1,032 by 816 points from another app, or fits it to the available display.
- [ ] The editor receives keyboard focus without an extra click.
- [ ] Each connected display dims subtly without blur or an opaque flash.
- [ ] Option-Space, Escape, and clicking outside dismiss the pad and remove every dimming window.

## Editing and formatting

- [ ] Plain typing, selection, undo, redo, spelling, and keyboard navigation behave like a macOS text editor.
- [ ] One Return starts a paragraph with visible space above it. Return after a heading resumes body text.
- [ ] The gap after a list matches the gap between paragraphs, both while typing and after a relaunch.
- [ ] A heading is followed by twice the body paragraph gap.
- [ ] Shift-Return inserts a line break inside the paragraph that survives save and reopen.
- [ ] A long document scrolls smoothly with a wheel, trackpad, scrollbar, and keyboard navigation.
- [ ] The selection bar appears only for a non-empty selection.
- [ ] Bold, italic, underline, headings, unordered lists, ordered lists, and links work.
- [ ] Link entry preserves the selected text, accepts a complete address or a bare domain, and returns focus to the editor.
- [ ] The Link field prefills only when the clipboard contains one valid web address; ordinary clipboard text leaves it empty.
- [ ] No permanent formatting toolbar remains when there is no selection.
- [ ] Clear empties the pad, and one Command-Z restores the complete document with its formatting.

## Paste and Markdown

- [ ] Pasting rich text preserves basic bold, italic, underline, links, headings, and lists.
- [ ] Pasted fonts, sizes, colors, and spacing normalize to Aparte's typography.
- [ ] Pasting plain text stays plain.
- [ ] Copy as Markdown produces clean Markdown for the selected text or full document.
- [ ] Copy places the full document on the clipboard with rich and plain representations without moving the cursor or changing the selection.
- [ ] Snapshot copies the whole pad as an image, including text scrolled out of view, and pastes into another app. Check light and dark mode.
- [ ] Copy two prose paragraphs into an unsent Mail draft. Paragraph separation, bold, italic, underline, and links remain usable, and body text follows the draft's font and size.
- [ ] Copy the same text into a plain-text field or an unsent WhatsApp message. Each prose paragraph has one blank line between it and the next; consecutive list items stay compact.
- [ ] Command-C on a selection, the footer Copy button, and plain-text copy produce the same paragraph boundaries. Copying, pasting back, saving, and reopening does not accumulate extra blank lines.
- [ ] Save and Save Markdown As open a system Save panel with a useful filename derived from the first non-empty line.
- [ ] Saving writes readable Markdown to a user-selected folder and handles overwrite confirmation through the system panel.
- [ ] Command-Option-U, or Send to endpoint… from the File menu, the status menu, or the Save button's menu, opens an address field on the Save button. The field shows the last address that sent successfully.
- [ ] A successful send shows "Sent" on the Save button, naming the host, and the address is remembered. A selection sends only that selection; otherwise the whole pad is sent. An empty pad shows "Empty" and sends nothing.
- [ ] An address that is not a URL stays in the field with a short error and sends nothing.
- [ ] A plain http address for a host other than localhost is rejected and sends nothing. `http://localhost` is accepted.
- [ ] An endpoint that answers 404 shows "Failed" on the Save button with the status, and the address is not remembered.
- [ ] An unreachable host shows "Failed" with the connection error. Nothing is sent again unless you ask.
- [ ] Copy, Save, Clear, and every abbreviated formatting control explain their action on hover.

## Persistence and appearance

- [ ] Content autosaves locally after editing.
- [ ] Content restores after quitting and relaunching.
- [ ] Light and dark mode both remain readable.
- [ ] The pad fits on the smallest connected screen and recenters on the active screen.
- [ ] On a wide pad, the text column stays capped and centred instead of stretching with the window.

## Performance and reliability

- [ ] Hidden idle CPU settles near 0 percent.
- [ ] Idle resident memory is recorded in `docs/performance.md`.
- [ ] Twenty consecutive invoke, type, dismiss cycles do not lose content, focus, or overlays.
- [ ] The app remains responsive after display arrangement and appearance changes.

## App Store candidate

- [ ] Test `dist/app-store/Aparte.app`, not the normal local package.
- [ ] Use `open -na dist/app-store/Aparte.app --args --show-for-acceptance` when the normal app is not running to open the candidate without first testing the shortcut.
- [ ] Confirm the first sandboxed launch starts with its own local document and never changes the normal local build's document.
- [ ] Save a Markdown file to the Desktop through the system panel, confirm the file exists, then open it and compare its full contents. Cancelling the panel does not pass this check.
- [ ] Verify Option-Space from another app while the sandboxed candidate is active.
- [ ] Confirm the app icon is clear in Finder, the menu bar, About Aparte, and at the smallest displayed size.
- [ ] Capture at least one clean 16:10 screenshot at an Apple-accepted Mac size.

## Writing tools

- [ ] Plain-text copy contains the selected passage, or the whole pad when there is no selection, with no rich clipboard formats.
- [ ] Click the three-dot footer button; the options card stays inside the pad and matches its appearance. Check light and dark mode.
- [ ] Choose an option, click outside the card, or press Escape; the card closes and the pad stays open. Outside clicks do not move the cursor or activate the control underneath.
- [ ] Tab and arrow keys reach the options without moving focus behind the card; Return chooses the focused option. Unavailable recovery actions stay disabled.
- [ ] Every action with a keyboard binding has a small shortcut hint. Expand Formatting, Editing, Recovery, and Aparte to check the grouped actions. All labels fit, and expanded content scrolls from top to bottom.
- [ ] Enabled options use a small filled dot with space before the label. Submenus use a smaller, separate chevron. Opening a submenu closes the previous one; clicking it again closes it.
- [ ] While scrolling, the scrollbar stays to the right of the shortcut hints without covering them.
- [ ] Command-/ opens and closes options. Command-Shift-W toggles counts with the card open or closed; formatting shortcuts work even when their group is collapsed.
- [ ] Command-Option-Delete clears with recovery. Command-Shift-R restores; Command-Option-Shift-R asks before discarding recovery. Cancel leaves the copy intact.
- [ ] Command-K opens the link field for selected text. Return applies a valid link; Escape cancels the field while keeping the pad open.
- [ ] Show word and character count, select text including an emoji, then deselect; the counter follows the selection and can be hidden again.
- [ ] Command-plus, Command-minus, and Command-0 change and reset display size without changing copied or saved formatting; long lines remain readable and scrollable.
- [ ] Clear, quit, relaunch, and restore the last cleared text; a second nonempty Clear replaces the recovery copy, and an empty Clear preserves it.
- [ ] Restoring over current writing asks first; Cancel preserves it and Command-Z undoes an accepted restore.
- [ ] Discard recovery copy removes recovery without changing current writing.
- [ ] Return continues both bullet and numbered lists; Return on an empty item exits the list, and Undo restores the prior text.
- [ ] Settings… appears once in the Aparte application menu, status menu, and writing-options card. Command-comma opens a normal Settings window, hides the pad, and saves the draft. There is no separate top-level Settings menu.
- [ ] Close and reopen Settings; the same window returns. Tab reaches its controls. Check light and dark appearance and verify all status/error text fits.
- [ ] In Settings, click the shortcut control and set a different global shortcut, invoke from another app, relaunch, and verify it persists; reset returns to Option-Space.
- [ ] An unavailable shortcut reports failure and leaves the previous shortcut working. Escape cancels recording without changing the shortcut or closing Settings; Escape outside recording closes Settings. Closing Settings or switching windows also stops recording.
- [ ] On an installed signed candidate, turn launch at login on and off and confirm System Settings matches; if macOS requires approval, Settings shows approval is required and offers Open Login Items. Return from System Settings and verify the status refreshes. Errors remain visible beside the control.

## Direct-download updates

- [ ] On an installed direct candidate, Check for Updates… appears in the main Aparte menu, status menu, and three-dot options card. Its label fits without a keyboard hint. Settings also has a Check for Updates button that disables when a check is unavailable.
- [ ] Choosing it dismisses the writing pad and dimming overlays, shows Sparkle's window, and preserves the draft. It is disabled while Sparkle cannot start another check.
- [ ] A current version reports no update. An offline check reports a recoverable error, and writing still works.
- [ ] A signed older test build discovers the published signed candidate, displays its version and release notes, installs after approval, relaunches, and restores the same writing.
- [ ] A tampered feed and archive are rejected in an isolated test feed. No production feed or user's installed app is changed for this test.
- [ ] The App Store candidate and normal local package have no Check for Updates… command, Sparkle framework, or `SU*` keys.

## September 7 local writing-tools verification

The local changes based on `601fd15` passed `make check`: 25 core tests, 59
packaged AppKit runtime checks, diff validation, and strict signature validation.
The runtime checks cover plain and rich clipboard output without changing the
user's clipboard, selection preservation, composed-character counts, visible
counter geometry, zoom reflow and unchanged export formatting, recoverable Clear,
restore Undo, list continuation and exit, shortcut persistence and conflicts,
and launch-item status transitions through an injected service.

The packaged temporary pad was also inspected through the native UI connector.
The counter rendered in the footer and text at 110% zoom fit inside the pad.
Through real key events, Return added a bullet, Return on an empty bullet returned
to normal writing, and selecting "One more thought" changed the counter to
"Selection: 3 words · 16 characters".
The shortcut recorder accepted Command-Control-Option-Shift-L in an isolated
preference suite and visibly reported "Shortcut saved". Test hotkeys were released
when the test process exited.

No actual login item was enabled. Login after a real sign-out/restart and physical
global shortcut invocation from another app remain release acceptance checks.
These local checks do not mark the older release checklist complete.

The subsequent in-window options card passed `make check`, including checks for
outside-click interception, dismissal before action dispatch, disabled actions,
keyboard focus containment, restored editor accessibility, and draft/selection
preservation. Native UI inspection confirmed light and dark appearance, dismissal
by an outside click or Escape, and closing after toggling the counter. The preview
used a temporary document and preferences; it did not change the real login item.

The keyboard-shortcut update passed `make check` with 25 core tests and 117 runtime
checks. Each menu action has a hint, local bindings are unique, and the displayed
bindings match the native menu. Native key dispatch, recovery shortcuts, collapsed
formatting shortcuts, and link-field cancellation passed. UI checks confirmed
readable hints in light and dark appearance, scrolling expanded groups,
Command-/ opening options, Command-Shift-W closing the card and toggling counts,
Command-B applying bold from a collapsed group, and Command-K opening the link
field with Escape returning to the selected text.

The menu spacing refinement passed `make check` with 25 core tests and 122 runtime
checks. Native UI inspection confirmed the filled state dot and smaller chevrons,
one expanded submenu at a time, and a clear gap between shortcuts and the visible
scrollbar in a 600-point-high dark preview. Switching groups after scrolling also
closed the previous group. The preview used temporary text and preferences.
