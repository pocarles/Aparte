import AppKit

@MainActor
enum MainMenu {
    static func make() -> NSMenu {
        let menu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "Aparte")
        appMenu.addItem(withTitle: "About Aparte", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Aparte", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit Aparte", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        menu.addItem(appItem)

        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        let saveMarkdown = NSMenuItem(title: "Save Markdown As…", action: #selector(AppDelegate.saveMarkdownAs), keyEquivalent: "s")
        saveMarkdown.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(saveMarkdown)
        fileItem.submenu = fileMenu
        menu.addItem(fileItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenu.addItem(.separator())
        let copyMarkdown = NSMenuItem(title: "Copy as Markdown", action: #selector(EditorTextView.copyAsMarkdown(_:)), keyEquivalent: "C")
        copyMarkdown.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(copyMarkdown)
        editItem.submenu = editMenu
        menu.addItem(editItem)

        let formatItem = NSMenuItem()
        let formatMenu = NSMenu(title: "Format")
        formatMenu.addItem(withTitle: "Bold", action: #selector(EditorTextView.toggleBold(_:)), keyEquivalent: "b")
        formatMenu.addItem(withTitle: "Italic", action: #selector(EditorTextView.toggleItalic(_:)), keyEquivalent: "i")
        formatMenu.addItem(withTitle: "Underline", action: #selector(EditorTextView.toggleUnderline(_:)), keyEquivalent: "u")
        formatItem.submenu = formatMenu
        menu.addItem(formatItem)
        return menu
    }
}
