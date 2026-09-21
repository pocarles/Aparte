import AppKit

@MainActor
final class MenuBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private weak var delegate: AppDelegate?

    init(delegate: AppDelegate) {
        self.delegate = delegate
        super.init()
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "text.cursor", accessibilityDescription: "Aparte")
            button.image?.isTemplate = true
            button.target = self
            button.action = #selector(clicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        updateShortcutDescription()
    }

    func updateShortcutDescription() {
        statusItem.button?.toolTip = "Open or close Aparte · \(delegate?.shortcutDescription ?? "Option-Space")"
    }

    @objc private func clicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            statusItem.menu = makeMenu()
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            delegate?.togglePad()
        }
    }

    private func makeMenu() -> NSMenu {
        Self.makeOptionsMenu(target: delegate, forPad: false)
    }

    static func makeOptionsMenu(target: NSObject?, forPad: Bool = true) -> NSMenu {
        let menu = NSMenu()
        func add(_ command: MenuCommand) { menu.addItem(command.item(target: target)) }
        func group(_ title: String, _ items: [NSMenuItem]) {
            let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let submenu = NSMenu(title: title)
            items.forEach { submenu.addItem($0) }
            parent.submenu = submenu
            menu.addItem(parent)
        }
        [MenuCommand.copyAll, .copyPlain, .copyMarkdown, .save, .send, .clear].forEach(add)
        menu.addItem(.separator())
        add(.counts)
        group("Text size", [MenuCommand.zoomOut, .resetZoom, .zoomIn].map { $0.item(target: target) })
        group("Formatting", MenuCommand.formatting.map { $0.item() })
        group("Editing", MenuCommand.editing.map { $0.item() })
        group("Recovery", [MenuCommand.restore, .discard].map { $0.item(target: target) })
        menu.addItem(.separator())
        add(.settings)
        let toggle = NSMenuItem(title: "Show or hide Aparte", action: #selector(AppDelegate.togglePad), keyEquivalent: "")
        toggle.target = target
        toggle.representedObject = (target as? AppDelegate)?.shortcutDescription ?? "⌥Space"
        group("Aparte", [toggle, MenuCommand.hide.item(target: target), MenuCommand.about.item(target: target)]
              + MenuCommand.updates.map { $0.item(target: target) } + [MenuCommand.quit.item()])
        let options = MenuCommand.options.item(target: target)
        if forPad { options.title = "Close options" }
        menu.addItem(options)
        return menu
    }
}
