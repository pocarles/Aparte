import AppKit
import AparteCore

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
        #if APARTE_DIRECT_UPDATES
        preferencesController?.updateController = updateController
        preferencesController?.onCheckForUpdates = { [weak self] in self?.checkForUpdates() }
        #endif
        preferencesController?.onUserClose = { NSApp.hide(nil) }
        hotKeyController?.onShortcutChanged = { [weak self] _ in
            self?.refreshShortcutPresentation()
        }
        if let hotKeyController {
            padController?.shortcutHint = Self.shortcutHint(for: hotKeyController)
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
                      self?.padController?.isVisible == true,
                      event.window === self?.padController?.window else { return false }
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

        if UserDefaults.standard.bool(forKey: "Aparte.hasLaunched") == false {
            // A fresh install would otherwise show only a menu bar icon.
            UserDefaults.standard.set(true, forKey: "Aparte.hasLaunched")
            showPad()
        }

        if ProcessInfo.processInfo.arguments.contains("--show-for-acceptance") {
            showPad()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPad()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        documentController?.saveNow()
        hotKeyController?.invalidate()
        preferencesController?.closeSettings()
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
        preferencesController?.closeSettings()
        // Showing a pad that is already open would replay the fade-in as a flash.
        guard let padController, !padController.isVisible else { return }
        if NSApp.isHidden { NSApp.unhide(nil) }
        overlays.show()
        padController.show()
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func hidePad() {
        hidePad(deactivating: true)
    }

    private func hidePad(deactivating: Bool) {
        padController?.hide()
        overlays.hide()
        documentController?.saveNow()
        if deactivating { NSApp.hide(nil) }
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

    @objc func showSettings() {
        hidePad(deactivating: false)
        preferencesController?.showSettings()
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
        hidePad(deactivating: false)
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
        case #selector(restoreLastCleared), #selector(discardRecovery):
            return padController?.hasRecovery == true
        case #selector(zoomIn):
            return padController?.canZoomIn == true
        case #selector(zoomOut):
            return padController?.canZoomOut == true
        case #selector(resetZoom):
            return padController?.isDefaultZoom == false
        default:
            break
        }
        return true
    }

    private func refreshShortcutPresentation() {
        menuBarController?.updateShortcutDescription()
        guard let hotKeyController else { return }
        padController?.shortcutHint = Self.shortcutHint(for: hotKeyController)
    }

    private static func shortcutHint(for hotKeyController: HotKeyController) -> String {
        guard hotKeyController.isRegistered else {
            return "Set a global shortcut in Settings (⌘,) to open Aparte from any app."
        }
        return "\(hotKeyController.shortcutDescription) shows or hides Aparte. Escape closes it."
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
