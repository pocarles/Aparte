<p align="center">
  <img src="Support/AppIconSource.png" width="128" height="128" alt="Aparte app icon">
</p>

# Aparte

Aparte is a native macOS writing pad that is always one shortcut away. Press
Option-Space, write, copy or save what you need, then press Escape. The same
local document is waiting when you come back.

[Download the latest release](https://github.com/pocarles/Aparte/releases/latest/download/Aparte.dmg)
or read the [product page](https://pocarles.com/aparte/).

Version 1.2.0 adds paragraph spacing, ready-to-send copy, and feedback for Copy,
Save, and Clear. Read the [release notes](https://github.com/pocarles/Aparte/releases/tag/v1.2.0).

## What it does

- Opens from any app with Option-Space, or a shortcut you choose.
- Dims the rest of the screen without taking over your desktop.
- Supports headings, lists, links, bold, italic, and underline.
- Copies formatted text, plain text, or Markdown, and saves a Markdown file where you choose.
- Continues bullets and numbered lists when you press Return.
- Offers an optional word and character count and text zoom.
- Keeps one recovery copy of your last cleared draft.
- Autosaves one local document and restores it on relaunch.
- Settles near zero CPU while hidden.

Aparte has no account, cloud sync, analytics, advertising, updater, network
connection, or third-party package dependency.

## Install

Aparte requires macOS 14 or later and includes native Apple silicon and Intel
code.

1. Download [`Aparte.dmg`](https://github.com/pocarles/Aparte/releases/latest/download/Aparte.dmg)
   and [`Aparte.dmg.sha256`](https://github.com/pocarles/Aparte/releases/latest/download/Aparte.dmg.sha256).
2. Optionally verify the download in Terminal:

   ```sh
   shasum -a 256 -c Aparte.dmg.sha256
   ```

3. Open the disk image and drag Aparte to Applications.

Public release files come from the protected GitHub workflow. The app is signed
with Developer ID, notarized by Apple, and checked by Gatekeeper before GitHub
publishes it.

## Shortcuts

Every command shows its shortcut in small text in the three-dot menu. Editing,
formatting, recovery, and app commands are grouped there; click a group to expand
it. Only one group stays open at a time. A filled dot marks an option that is turned on.
Shortcuts work while writing and while the options card is open.

| Action | Shortcut |
| --- | --- |
| Show or hide Aparte | Option-Space, or your chosen global shortcut |
| Open or close writing options | Command-/ |
| Close the card or dismiss the pad | Escape |
| Copy whole pad | Command-Option-C |
| Copy as Markdown | Command-Shift-C |
| Copy as plain text | Command-Option-Shift-C |
| Save Markdown As | Command-Shift-S |
| Clear pad | Command-Option-Delete |
| Restore last cleared text | Command-Shift-R |
| Discard recovery copy, with confirmation | Command-Option-Shift-R |
| Show or hide word and character count | Command-Shift-W |
| Zoom in / out | Command-plus / Command-minus |
| Reset text size | Command-0 |
| Configure the global shortcut | Command-comma |
| Toggle launch at login | Command-Option-L |
| Bold / italic / underline | Command-B / I / U |
| Heading | Command-Option-1 |
| Bulleted / numbered list | Command-Shift-8 / 7 |
| Add a link to selected text | Command-K |
| Undo / redo | Command-Z / Command-Shift-Z |
| Cut / copy selection / paste / select all | Command-X / C / V / A |
| Hide Aparte | Command-H |
| About Aparte | Command-Control-A |
| Quit Aparte | Command-Q |

Only show/hide is global. The other shortcuts apply while working in Aparte.
Unavailable actions stay disabled. Clear keeps a recovery copy, and discarding
that copy still asks for confirmation.

## Small controls, when you need them

Click the three dots at the bottom right of the pad to show the word and character count, change
text size, choose a keyboard shortcut, or turn launch at login on or off. Options
open in a small card inside the pad. Choose an option, click outside the card, or
press Escape to close it and return to your writing. The
counter starts hidden. It counts the selected passage when you select text,
otherwise the whole pad. Characters include spaces and line breaks.

Copy at the bottom copies the whole pad without moving your cursor. The three-dot
menu offers plain text or Markdown; these use your selection when there is one,
otherwise the whole pad. Plain text removes formatting and does not add Markdown
syntax. Typed punctuation and visible list markers remain part of the text.

Press Return once to start a paragraph with space above it. Copied prose includes
a blank line between paragraphs, while consecutive list items stay together.
Formatted copy keeps headings, emphasis, links, and lists without specifying a
font or text size, so the receiving email or messaging app chooses its typography.
Pasted and reopened text uses the same paragraph spacing, even if the source has
extra blank lines.

Copy, Save, and Clear respond to hover and press, then briefly show whether the
action succeeded, the pad was empty, or something failed. The buttons stay in
place and return focus to your writing.

Text zoom changes only how the pad looks, not the formatting you copy or save.
Your zoom and counter choices are remembered. In a list, Return starts the next
item. Return on an empty item ends the list.

Clear saves one recovery copy before erasing the pad. Command-Z still undoes
Clear immediately. To recover after quitting, choose Restore last cleared text
from the menu. Restoring over current writing asks first and can be undone.
Clearing a new nonempty draft replaces the recovery copy. Discard recovery copy
removes it without changing your current pad.

## Privacy

Aparte stores its working Markdown document and, after Clear, one recovery copy in your macOS Application Support folder.
It does not send the document, usage data, or diagnostics anywhere. Read the
[privacy statement](PRIVACY.md) for the complete boundary.

## Build from source

Install Xcode 16 or a newer Swift 6 toolchain, then run:

```sh
git clone https://github.com/pocarles/Aparte.git
cd Aparte
make check
make run
```

`make check` runs the unit tests, builds the app, exercises its native runtime
acceptance checks, and verifies the package signature. `make check-direct`
also builds and verifies the Universal 2 disk-image shape without Apple
credentials.

The source-built app is ad-hoc signed for the Mac that built it. Use the
notarized GitHub release when installing Aparte on another Mac.

## Project boundary

Aparte is one focused document, not a notes library. The source stays native,
local, and quiet. See [CONTRIBUTING.md](CONTRIBUTING.md),
[SECURITY.md](SECURITY.md), and [docs/architecture.md](docs/architecture.md).

## License

MIT. Copyright © 2026 Pierre-Olivier Carles. See [LICENSE](LICENSE).
