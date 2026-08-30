import AppKit
import AparteCore
import UniformTypeIdentifiers

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var documentController: DocumentController?
    private var padController: PadWindowController?
    private var hotKeyController: HotKeyController?
    private var menuBarController: MenuBarController?
    private let overlays = FocusOverlayController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.mainMenu = MainMenu.make()

        do {
            let document = try DocumentController()
            let pad = PadWindowController(document: document)
            pad.onDismiss = { [weak self] in self?.hidePad() }
            documentController = document
            padController = pad
        } catch {
            presentStartupError(error)
            return
        }

        hotKeyController = HotKeyController { [weak self] in self?.togglePad() }
        menuBarController = MenuBarController(
            toggle: { [weak self] in self?.togglePad() },
            copyMarkdown: { [weak self] in self?.copyMarkdown() },
            saveMarkdown: { [weak self] in self?.saveMarkdownAs() }
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenLayoutChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        documentController?.saveNow()
        hotKeyController?.invalidate()
    }

    @objc func togglePad() {
        if padController?.isVisible == true {
            hidePad()
        } else {
            showPad()
        }
    }

    @objc func showPad() {
        guard let padController else { return }
        overlays.show()
        padController.show()
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func hidePad() {
        documentController?.saveNow()
        padController?.hide()
        overlays.hide()
        NSApp.hide(nil)
    }

    @objc func copyMarkdown() {
        guard let padController else { return }
        padController.copyMarkdown()
    }

    @objc func saveMarkdownAs() {
        guard let markdown = documentController?.markdown else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "aparte.md"
        panel.allowedContentTypes = [.markdown]
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try markdown.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                NSApp.presentError(error)
            }
        }
    }

    @objc private func screenLayoutChanged() {
        guard padController?.isVisible == true else { return }
        overlays.show()
        padController?.recenter()
    }

    private func presentStartupError(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.messageText = "Aparte could not open its local document."
        alert.runModal()
        NSApp.terminate(nil)
    }
}

private extension UTType {
    static var markdown: UTType {
        UTType(filenameExtension: "md") ?? .plainText
    }
}
