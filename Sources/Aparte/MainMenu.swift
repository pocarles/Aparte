import AppKit

@MainActor
enum MainMenu {
    static func make(target: NSObject? = nil) -> NSMenu {
        let menu = NSMenu()
        func section(_ title: String, _ items: [NSMenuItem]) {
            let parent = NSMenuItem()
            let submenu = NSMenu(title: title)
            items.forEach { submenu.addItem($0) }
            parent.submenu = submenu
            menu.addItem(parent)
        }
        section("Aparte", [MenuCommand.about.item(target: target)] + MenuCommand.updates.map { $0.item(target: target) }
                + [.separator(), MenuCommand.hide.item(target: target), MenuCommand.quit.item()])
        section("File", [MenuCommand.save.item(target: target), MenuCommand.clear.item(target: target), .separator(),
                          MenuCommand.restore.item(target: target), MenuCommand.discard.item(target: target)])
        section("Edit", MenuCommand.editing.map { $0.item() } + [.separator(), MenuCommand.copyAll.item(target: target),
                           MenuCommand.copyMarkdown.item(target: target), MenuCommand.copyPlain.item(target: target)])
        section("Format", MenuCommand.formatting.map { $0.item() })
        let plusWithoutShift = MenuCommand.zoomIn.item(target: target)
        plusWithoutShift.keyEquivalent = "="
        plusWithoutShift.isHidden = true
        plusWithoutShift.allowsKeyEquivalentWhenHidden = true
        section("View", [MenuCommand.options.item(target: target), MenuCommand.counts.item(target: target), .separator(),
                          MenuCommand.zoomIn.item(target: target), plusWithoutShift, MenuCommand.zoomOut.item(target: target),
                          MenuCommand.resetZoom.item(target: target)])
        section("Settings", [MenuCommand.shortcut.item(target: target), MenuCommand.login.item(target: target)])
        return menu
    }
}
