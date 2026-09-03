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

- [ ] Plain typing, selection, undo, redo, find, spelling, and keyboard navigation behave like a macOS text editor.
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
- [ ] Copy selects the full document and places its normal rich and plain representations on the clipboard.
- [ ] Save and Save Markdown As open a system Save panel with a useful filename derived from the first non-empty line.
- [ ] Saving writes readable Markdown to a user-selected folder and handles overwrite confirmation through the system panel.
- [ ] Copy, Save, Clear, and every abbreviated formatting control explain their action on hover.

## Persistence and appearance

- [ ] Content autosaves locally after editing.
- [ ] Content restores after quitting and relaunching.
- [ ] Light and dark mode both remain readable.
- [ ] The pad fits on the smallest connected screen and recenters on the active screen.

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
