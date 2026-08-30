import AppKit
import AparteCore
import UniformTypeIdentifiers

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var documentController: DocumentController?
    private var padController: PadWindowController?
    private var hotKeyController: HotKeyController?
    private var menuBarController: MenuBarController?
    private var escapeMonitor: Any?
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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationResignedActive),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            let dismissed = MainActor.assumeIsolated {
                guard self?.padController?.isVisible == true else { return false }
                self?.hidePad()
                return true
            }
            return dismissed ? nil : event
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        documentController?.saveNow()
        hotKeyController?.invalidate()
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
        }
        NotificationCenter.default.removeObserver(self)
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
        padController?.hide()
        overlays.hide()
        documentController?.saveNow()
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

    @objc private func applicationResignedActive() {
        guard padController?.isVisible == true else { return }
        hidePad()
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
