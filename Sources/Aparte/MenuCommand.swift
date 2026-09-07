import AppKit

/// One definition supplies both the working key equivalent and its menu hint.
@MainActor
struct MenuCommand {
    let title: String
    let action: Selector
    let key: String
    var modifiers: NSEvent.ModifierFlags = [.command]

    func item(target: NSObject? = nil) -> NSMenuItem {
        let shiftedKeys = ["7": "&", "8": "*"]
        let equivalent = modifiers.contains(.shift) ? shiftedKeys[key] ?? key.uppercased() : key
        let item = NSMenuItem(title: title, action: action, keyEquivalent: equivalent)
        item.keyEquivalentModifierMask = modifiers
        item.target = target
        return item
    }

    static func shortcutLabel(for item: NSMenuItem) -> String {
        // The configurable global shortcut is registered with Carbon, not the local menu.
        if let globalShortcut = item.representedObject as? String { return globalShortcut }
        guard !item.keyEquivalent.isEmpty else { return "" }
        let flags = item.keyEquivalentModifierMask
        var label = ""
        if flags.contains(.control) { label += "⌃" }
        if flags.contains(.option) { label += "⌥" }
        if flags.contains(.shift) { label += "⇧" }
        if flags.contains(.command) { label += "⌘" }
        switch item.keyEquivalent {
        case "&" where flags.contains(.shift): label += "7"
        case "*" where flags.contains(.shift): label += "8"
        case "\u{8}", "\u{7f}": label += "⌫"
        case "\u{1b}": label += "Esc"
        case " ": label += "Space"
        default: label += item.keyEquivalent.uppercased()
        }
        return label
    }

    static let copyAll = Self(title: "Copy whole pad", action: #selector(AppDelegate.copyAll), key: "c", modifiers: [.command, .option])
    static let copyPlain = Self(title: "Copy as plain text", action: #selector(AppDelegate.copyPlainText), key: "c", modifiers: [.command, .option, .shift])
    static let copyMarkdown = Self(title: "Copy as Markdown", action: #selector(AppDelegate.copyMarkdown), key: "c", modifiers: [.command, .shift])
    static let save = Self(title: "Save Markdown As…", action: #selector(AppDelegate.saveMarkdownAs), key: "s", modifiers: [.command, .shift])
    static let clear = Self(title: "Clear pad", action: #selector(AppDelegate.clearPad), key: "\u{7f}", modifiers: [.command, .option])
    static let restore = Self(title: "Restore last cleared text", action: #selector(AppDelegate.restoreLastCleared), key: "r", modifiers: [.command, .shift])
    static let discard = Self(title: "Discard recovery copy…", action: #selector(AppDelegate.discardRecovery), key: "r", modifiers: [.command, .option, .shift])
    static let counts = Self(title: "Show word and character count", action: #selector(AppDelegate.toggleCounts), key: "w", modifiers: [.command, .shift])
    static let zoomIn = Self(title: "Zoom in", action: #selector(AppDelegate.zoomIn), key: "+")
    static let zoomOut = Self(title: "Zoom out", action: #selector(AppDelegate.zoomOut), key: "-")
    static let resetZoom = Self(title: "Actual size", action: #selector(AppDelegate.resetZoom), key: "0")
    static let shortcut = Self(title: "Keyboard shortcut…", action: #selector(AppDelegate.configureShortcut), key: ",")
    static let login = Self(title: "Launch at login", action: #selector(AppDelegate.toggleLaunchAtLogin), key: "l", modifiers: [.command, .option])
    static let options = Self(title: "Writing options", action: #selector(AppDelegate.toggleOptions), key: "/")
    static let hide = Self(title: "Hide Aparte", action: #selector(AppDelegate.hidePad), key: "h")
    static let quit = Self(title: "Quit Aparte", action: #selector(NSApplication.terminate(_:)), key: "q")
    static let about = Self(title: "About Aparte", action: #selector(AppDelegate.showAbout), key: "a", modifiers: [.command, .control])

    static let undo = Self(title: "Undo", action: Selector(("undo:")), key: "z")
    static let redo = Self(title: "Redo", action: Selector(("redo:")), key: "z", modifiers: [.command, .shift])
    static let cut = Self(title: "Cut", action: #selector(NSText.cut(_:)), key: "x")
    static let copy = Self(title: "Copy selection", action: #selector(NSText.copy(_:)), key: "c")
    static let paste = Self(title: "Paste", action: #selector(NSText.paste(_:)), key: "v")
    static let selectAll = Self(title: "Select all", action: #selector(NSText.selectAll(_:)), key: "a")
    static let bold = Self(title: "Bold", action: #selector(EditorTextView.toggleBold(_:)), key: "b")
    static let italic = Self(title: "Italic", action: #selector(EditorTextView.toggleItalic(_:)), key: "i")
    static let underline = Self(title: "Underline", action: #selector(EditorTextView.toggleUnderline(_:)), key: "u")
    static let heading = Self(title: "Heading", action: #selector(EditorTextView.makeHeading(_:)), key: "1", modifiers: [.command, .option])
    static let bullets = Self(title: "Bulleted list", action: #selector(EditorTextView.makeBulletedList(_:)), key: "8", modifiers: [.command, .shift])
    static let numbers = Self(title: "Numbered list", action: #selector(EditorTextView.makeNumberedList(_:)), key: "7", modifiers: [.command, .shift])
    static let link = Self(title: "Add link…", action: #selector(EditorTextView.addLink(_:)), key: "k")

    static let editing = [undo, redo, cut, copy, paste, selectAll]
    static let formatting = [bold, italic, underline, heading, bullets, numbers, link]
}
