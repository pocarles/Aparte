import AppKit
import AparteCore
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private var documentController: DocumentController?
    private var padController: PadWindowController?
    private var hotKeyController: HotKeyController?
    private var menuBarController: MenuBarController?
    private var preferencesController: PreferencesController?
    private var escapeMonitor: Any?
    private let overlays = FocusOverlayController()
    #if APARTE_DIRECT_UPDATES
    var updateController: (any UpdateChecking)?
    #endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.mainMenu = MainMenu.make()
        #if APARTE_DIRECT_UPDATES
        updateController = UpdateController()
        #endif

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

        hotKeyController = HotKeyController(action: { [weak self] in self?.togglePad() })
        preferencesController = PreferencesController(hotKeyController: hotKeyController)
        hotKeyController?.onShortcutChanged = { [weak self] _ in
            self?.menuBarController?.updateShortcutDescription()
        }
        menuBarController = MenuBarController(delegate: self)

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
            let dismissed = MainActor.assumeIsolated {
                guard NSApp.modalWindow == nil,
                      self?.preferencesController?.isCapturingShortcut != true,
                      self?.padController?.isVisible == true else { return false }
                if event.keyCode != 53 {
                    return self?.padController?.performOptionsKeyEquivalent(event) == true
                }
                if self?.padController?.dismissTransientUI() == true {
                    return true
                }
                self?.hidePad()
                return true
            }
            return dismissed ? nil : event
        }

        if ProcessInfo.processInfo.arguments.contains("--show-for-acceptance") {
            showPad()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        documentController?.saveNow()
        hotKeyController?.invalidate()
        preferencesController?.closeShortcutRecorder()
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
        preferencesController?.closeShortcutRecorder()
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

    @objc func copyAll() { padController?.copyAll() }
    @objc func clearPad() { padController?.clearPad() }
    @objc func toggleOptions() {
        if padController?.isVisible != true { showPad() }
        padController?.toggleOptions()
    }

    @objc func showAbout() {
        hidePad()
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc func saveMarkdownAs() {
        padController?.saveMarkdownAs()
    }

    var shortcutDescription: String {
        guard let hotKeyController else { return "Shortcut unavailable" }
        return hotKeyController.isRegistered ? hotKeyController.shortcutDescription : "Shortcut unavailable"
    }

    @objc func configureShortcut() {
        hidePad()
        preferencesController?.showShortcutRecorder()
    }

    @objc func toggleLaunchAtLogin() {
        guard let result = preferencesController?.toggleLaunchAtLogin() else { return }
        let alert: NSAlert
        switch result {
        case .success(.requiresApproval):
            alert = NSAlert()
            alert.messageText = "Allow Aparte to launch at login"
            alert.informativeText = "macOS needs your approval in Login Items. You can turn launch at login off again from Aparte's menu."
            alert.addButton(withTitle: "Open Login Items")
            alert.addButton(withTitle: "Later")
        case let .failure(error):
            alert = NSAlert(error: error)
            alert.messageText = "Aparte could not change launch at login."
        default:
            return
        }
        alert.window.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn,
           case .success(.requiresApproval) = result {
            SMAppService.openSystemSettingsLoginItems()
        }
    }

    @objc func copyPlainText() { padController?.copyPlainText() }
    @objc func toggleCounts() { padController?.toggleCounts() }
    @objc func zoomIn() { padController?.zoomIn() }
    @objc func zoomOut() { padController?.zoomOut() }
    @objc func resetZoom() { padController?.resetZoom() }

    @objc func restoreLastCleared() {
        showPad()
        padController?.restoreLastCleared()
    }

    @objc func discardRecovery() { padController?.discardRecovery() }

    #if APARTE_DIRECT_UPDATES
    @objc func checkForUpdates() {
        guard updateController?.canCheckForUpdates == true else { return }
        padController?.hide()
        overlays.hide()
        documentController?.saveNow()
        updateController?.checkForUpdates()
    }
    #endif

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        #if APARTE_DIRECT_UPDATES
        case #selector(checkForUpdates):
            return updateController?.canCheckForUpdates == true
        #endif
        case #selector(toggleCounts):
            menuItem.state = padController?.showsCounts == true ? .on : .off
        case #selector(configureShortcut):
            menuItem.title = hotKeyController?.isRegistered == true ? "Keyboard shortcut…" : "Keyboard shortcut unavailable…"
        case #selector(toggleLaunchAtLogin):
            let needsApproval = preferencesController?.launchAtLoginRequiresApproval == true
            menuItem.title = needsApproval ? "Launch at login (approval required)…" : "Launch at login"
            menuItem.state = needsApproval ? .mixed : (preferencesController?.launchAtLoginEnabled == true ? .on : .off)
        case #selector(restoreLastCleared), #selector(discardRecovery):
            return padController?.hasRecovery == true
        default:
            break
        }
        return true
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
