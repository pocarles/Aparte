# V1 manual acceptance

Run this checklist against `dist/Aparte.app`. Record the date, macOS version, commit, and result before tagging V1.

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

