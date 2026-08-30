# V1 manual acceptance

Run this checklist against `dist/Aparte.app`. Record the date, macOS version, commit, and result before tagging V1.

## Automated release-harness evidence

On August 30, 2026, commit `da9657a` passed `make check` on macOS 26.5.2. The command built and ad-hoc signed the release app, then ran `dist/Aparte.app/Contents/MacOS/Aparte --runtime-acceptance` against temporary test data.

The packaged AppKit runtime passed all 13 checks:

- panel visible at 660 by 520 points;
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

## Invocation and focus

- [ ] Aparte appears in the menu bar and not the Dock.
- [ ] Option-Space opens a centered pad near 660 by 520 points from another app.
- [ ] The editor receives keyboard focus without an extra click.
- [ ] Each connected display dims subtly without blur or an opaque flash.
- [ ] Option-Space and Escape dismiss the pad and remove every dimming window.

## Editing and formatting

- [ ] Plain typing, selection, undo, redo, find, spelling, and keyboard navigation behave like a macOS text editor.
- [ ] The selection bar appears only for a non-empty selection.
- [ ] Bold, italic, underline, headings, unordered lists, ordered lists, and links work.
- [ ] No permanent formatting toolbar remains when there is no selection.

## Paste and Markdown

- [ ] Pasting rich text preserves basic bold, italic, underline, links, headings, and lists.
- [ ] Pasted fonts, sizes, colors, and spacing normalize to Aparte's typography.
- [ ] Pasting plain text stays plain.
- [ ] Copy as Markdown produces clean Markdown for the selected text or full document.
- [ ] Save Markdown As writes a readable `.md` file.

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
