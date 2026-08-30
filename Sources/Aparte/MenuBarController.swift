import AppKit

@MainActor
final class MenuBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let toggle: () -> Void
    private let copyMarkdown: () -> Void
    private let saveMarkdown: () -> Void

    init(
        toggle: @escaping () -> Void,
        copyMarkdown: @escaping () -> Void,
        saveMarkdown: @escaping () -> Void
    ) {
        self.toggle = toggle
        self.copyMarkdown = copyMarkdown
        self.saveMarkdown = saveMarkdown
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "text.cursor", accessibilityDescription: "Aparte")
            button.image?.isTemplate = true
            button.toolTip = "Open or close Aparte · Option-Space"
            button.target = self
            button.action = #selector(clicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    @objc private func clicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            statusItem.menu = makeMenu()
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            toggle()
        }
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "Show or hide Aparte", action: #selector(toggleFromMenu), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Copy as Markdown", action: #selector(copyFromMenu), keyEquivalent: "")
        menu.addItem(withTitle: "Save Markdown As…", action: #selector(saveFromMenu), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Aparte", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        menu.items.last?.target = NSApp
        return menu
    }

    @objc private func toggleFromMenu() { toggle() }
    @objc private func copyFromMenu() { copyMarkdown() }
    @objc private func saveFromMenu() { saveMarkdown() }
}
