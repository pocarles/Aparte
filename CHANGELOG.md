# Changelog

All notable changes appear here. The project follows semantic versioning.

## 1.6.0 - 2026-09-20

- Paragraph spacing comes from the document's structure, so the gap after a list is the same while typing and after the pad reloads.
- A heading is set off by twice the usual paragraph gap above and below, so a titled note breathes.
- A heading keeps one weight at its level, whether the line was plain or already bold. Bold on part of a heading still stands out.
- A list typed by hand ("- item") is spaced as a list. Wrapped list lines align under the item's text.
- The text column stays about 620 points wide on a wide window instead of stretching with it.
- Shift-Return inserts a line break inside the paragraph. Bold, italic, underline, and links that cross it stay intact when the pad reloads.
- A narrow window keeps the text column the proportional margin used to give. Only a wide window caps the column at about 620 points.
- Return at the end of an empty paragraph no longer adds a blank row.
- Snapshot, in the pad footer, copies the whole pad as an image, including text scrolled out of view.
- The snapshot page is a cool off-white in light appearance, and a matching dark tone in dark appearance, instead of the pad's grey.
- A second heading, at 24pt, sits next to H1 in the formatting bar and at Command-Option-2. Applying the same level again returns the line to body text.

## 1.5.0 - 2026-09-13

- The shortcut recorder refuses system-wide chords such as Command-Q, Command-C, Command-Tab, and Command-Space, which would otherwise stop working in every app.
- The rest of the screen dims more strongly while the pad is open.
- Bold, italic, underline, heading, list, and link are undoable. One Command-Z restores the previous text and its formatting.
- Bold, italic, and underline work without a selection: they change what you type next, like every other Mac editor.
- Heading and the list commands toggle. Running one again returns the lines to body text, and menu items show a checkmark for the formatting at the cursor.
- Backspace right after a bullet or number removes the whole marker.
- Deleting a marker by hand ends the list item. Exported Markdown and copied text no longer show a bullet the pad does not display.
- Bold inside a heading is visible and round-trips through Markdown as `# **word**`.
- Cut writes the same normalized text and HTML as copy, without Aparte's fonts.
- Pasting a large italic title keeps the italic inside the resulting heading.
- Save opens as a sheet on the pad instead of a panel that could appear behind it.
- The first launch, and reopening Aparte from Finder or Launchpad while it runs, shows the pad.
- Closing Settings returns you to the app you were using before.
- The shortcut name follows your keyboard layout, so a non-US layout shows the key you actually press.
- Changing the text size keeps the formatting bar in place, and the text size options grey out at their limits.
- The empty pad shows your shortcut, so a new install says how to open and close Aparte.

## 1.4.0 - 2026-09-11

- Settings… opens a native window for the global keyboard shortcut, launch at login, and update checks in direct-download builds. Command-comma opens the same window from the pad.
- Shortcut recording and login approval or errors stay in Settings. The writing-options card keeps its writing commands and has one Settings entry.

## 1.3.0 - 2026-09-11

- Direct-download builds check for updates daily through Sparkle and offer Check for Updates… in the main, status, and options menus. Updates do not install automatically by default.
- Updates verify signed feeds and archive signatures before extraction. Release preparation rejects invalid or mismatched signing keys.
- Local and App Store builds contain no Sparkle updater. Update requests send no writing or clipboard contents, and system profiling is disabled.
- Includes the 1.2.1 fixes for Markdown reopening, clipboard output, and list formatting. Links remain limited to HTTP and HTTPS, and HTML paste cannot load external resources.
- Existing users must install 1.3.0 manually to receive future updates through the app.

## 1.2.1 - 2026-09-11

- Saved Markdown preserves combined formatting, literal delimiters within formatted text, and backslashes when reopened.
- Copying part of a heading or list item keeps only the selected text and its inline formatting. Heading and list conversion preserves italic, and reapplying a list does not duplicate its marker.
- Pasted lists use consistent visible markers and retain their starting numbers. Plain text, Markdown, and HTML copy agree on list numbering.
- Links accept only HTTP and HTTPS destinations. HTML paste blocks subsidiary resource loads, including remote images and stylesheets.
- Copy as Markdown leaves the clipboard unchanged when the pad is empty.
- The privacy manifest declares UserDefaults access with reason CA92.1 for local preferences.

## 1.2.0 - 2026-09-11

- Return starts a visibly separated paragraph. Pasted and reopened drafts use consistent spacing without extra empty rows.
- Copy and plain-text copy include blank lines between prose paragraphs and keep consecutive list items compact.
- Formatted copy preserves headings, emphasis, links, and lists without forcing the editor's font or size into another app.
- Saved Markdown separates prose paragraphs with blank lines and preserves numbered-list starting values.
- Copy, Save, and Clear show hover and press states, then brief success, empty-pad, or failure feedback without moving the buttons or interrupting writing.

## 1.1.0 - 2026-09-07

- Every writing command has a keyboard shortcut, shown beside its option in the menu. Formatting, editing, recovery, and app commands expand within the card.
- Three-dot footer button opens an options card inside the pad. Choosing an option, clicking outside, or pressing Escape closes it.
- Smaller submenu arrows, distinct option indicators, one expanded group at a time, and space between shortcuts and the scrollbar.
- Plain-text copy and full-pad copy that preserves the cursor and selection.
- Optional word and character count for the pad or selected passage.
- Remembered display zoom with keyboard controls.
- One local recovery copy of the last cleared draft, with restore and discard actions.
- Automatic bullet and numbered-list continuation, with Return to leave an empty item.
- Configurable global shortcut and optional launch at login.

## 1.0.0 - 2026-09-03

- Signed and notarized Universal 2 direct-download release with a DMG and SHA-256 checksum.
- Public GitHub documentation, privacy and support pages, and a pocarles.com product page.
- Sandboxed, universal Mac App Store candidate with an app icon and privacy manifest.
- System Save panel for Markdown export so the app needs no direct Desktop entitlement.
- Local App Store validation, signed installer packaging, and Store metadata drafts.
- UTF-16-safe Markdown serialization for text ending in emoji.
- Native menu bar app with an Option-Space global hotkey.
- Floating 660 by 520 point writing pad and lightweight multi-display focus dimming.
- Native rich text editing for bold, italic, underline, headings, lists, and links.
- Selection-only contextual formatting bar.
- Normalized rich-text and HTML paste.
- Markdown copy, export, autosave, and relaunch restoration.
- Local-only operation with no external dependencies, accounts, cloud, analytics, or network code.
- Packaged AppKit runtime acceptance for geometry, focus, overlays, persistence, dismissal, and repeated invocation reliability.
