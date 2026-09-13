import AppKit
import ServiceManagement

@MainActor
final class PreferencesController: NSObject, NSWindowDelegate {
    enum LaunchAtLoginState: Equatable {
        case disabled
        case enabled
        case requiresApproval
        case unavailable
    }

    protocol LaunchAtLoginService {
        var status: SMAppService.Status { get }
        func register() throws
        func unregister() throws
    }

    private final class SystemLaunchAtLoginService: LaunchAtLoginService {
        private let service = SMAppService.mainApp

        var status: SMAppService.Status { service.status }

        func register() throws {
            try service.register()
        }

        func unregister() throws {
            try service.unregister()
        }
    }

    private weak var hotKeyController: HotKeyController?
    private let launchAtLoginService: any LaunchAtLoginService
    private let openLoginItems: () -> Void
    private var settingsStack: NSStackView?
    private var recordingMonitor: Any?
    private var isRecording = false

    private(set) var window: NSWindow?
    private(set) var shortcutButton: NSButton?
    private(set) var shortcutStatusLabel: NSTextField?
    private(set) var resetButton: NSButton?
    private(set) var loginButton: NSButton?
    private(set) var loginStatusLabel: NSTextField?
    private(set) var loginApprovalButton: NSButton?
    private(set) var lastLaunchAtLoginError: Error?
    #if APARTE_DIRECT_UPDATES
    weak var updateController: (any UpdateChecking)?
    var onCheckForUpdates: (() -> Void)?
    private(set) var updateButton: NSButton?
    #endif

    var onShortcutChanged: ((HotKeyController.Shortcut) -> Void)?
    var onLaunchAtLoginStateChanged: ((LaunchAtLoginState) -> Void)?
    var onUserClose: (() -> Void)?

    init(
        hotKeyController: HotKeyController?,
        launchAtLoginService: any LaunchAtLoginService = SystemLaunchAtLoginService(),
        openLoginItems: @escaping () -> Void = { SMAppService.openSystemSettingsLoginItems() }
    ) {
        self.hotKeyController = hotKeyController
        self.launchAtLoginService = launchAtLoginService
        self.openLoginItems = openLoginItems
        super.init()
    }

    var isCapturingShortcut: Bool { isRecording && window?.isVisible == true }
    var launchAtLoginState: LaunchAtLoginState { Self.state(for: launchAtLoginService.status) }
    var launchAtLoginEnabled: Bool { launchAtLoginState == .enabled }
    var launchAtLoginRequiresApproval: Bool { launchAtLoginState == .requiresApproval }

    @discardableResult
    func setLaunchAtLoginEnabled(_ enabled: Bool) -> Result<LaunchAtLoginState, Error> {
        let state = launchAtLoginState
        if (enabled && state == .enabled) || (!enabled && state == .disabled) {
            lastLaunchAtLoginError = nil
            refreshLoginState()
            onLaunchAtLoginStateChanged?(state)
            return .success(state)
        }
        do {
            if enabled { try launchAtLoginService.register() }
            else { try launchAtLoginService.unregister() }
            lastLaunchAtLoginError = nil
            let updatedState = launchAtLoginState
            refreshLoginState()
            onLaunchAtLoginStateChanged?(updatedState)
            return .success(updatedState)
        } catch {
            lastLaunchAtLoginError = error
            refreshLoginState()
            onLaunchAtLoginStateChanged?(launchAtLoginState)
            return .failure(error)
        }
    }

    @discardableResult
    func toggleLaunchAtLogin() -> Result<LaunchAtLoginState, Error> {
        setLaunchAtLoginEnabled(![.enabled, .requiresApproval].contains(launchAtLoginState))
    }

    func showSettings() {
        let settings = makeWindowIfNeeded()
        refreshShortcut()
        refreshLoginState()
        refreshUpdates()
        settings.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func closeSettings() {
        stopRecording()
        window?.close()
    }

    private func makeWindowIfNeeded() -> NSWindow {
        if let window { return window }
        let settings = SettingsWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 330),
            styleMask: [.titled, .closable], backing: .buffered, defer: false
        )
        settings.title = "Settings"
        settings.isReleasedWhenClosed = false
        settings.delegate = self
        settings.onCancel = { [weak self] in self?.cancelShortcutOrClose() }
        let content = NSView()
        settings.contentView = content
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        settingsStack = stack
        content.addSubview(stack)

        func label(_ text: String, heading: Bool = false) -> NSTextField {
            let label = NSTextField(wrappingLabelWithString: text)
            label.font = .systemFont(ofSize: heading ? 13 : 12, weight: heading ? .semibold : .regular)
            label.textColor = heading ? .labelColor : .secondaryLabelColor
            label.preferredMaxLayoutWidth = 412
            label.setContentCompressionResistancePriority(.required, for: .vertical)
            return label
        }
        func add(_ view: NSView) {
            stack.addArrangedSubview(view)
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        func button(_ title: String, _ action: Selector) -> NSButton {
            let button = NSButton(title: title, target: self, action: action)
            button.bezelStyle = .rounded
            return button
        }
        func divider() {
            let line = NSBox()
            line.boxType = .separator
            add(line)
            stack.setCustomSpacing(18, after: line)
        }

        add(label("Keyboard shortcut", heading: true))
        add(label("Show or hide Aparte from any app."))
        let shortcut = button("", #selector(recordShortcut))
        shortcut.setAccessibilityLabel("Record keyboard shortcut")
        let reset = button("Reset to Option-Space", #selector(resetShortcut))
        let shortcutRow = NSStackView(views: [shortcut, reset])
        shortcutRow.spacing = 12
        stack.addArrangedSubview(shortcutRow)
        let shortcutStatus = label("")
        add(shortcutStatus)
        divider()

        let login = NSButton(checkboxWithTitle: "Launch Aparte at login", target: self, action: #selector(changeLaunchAtLogin))
        login.allowsMixedState = true
        stack.addArrangedSubview(login)
        let loginStatus = label("")
        add(loginStatus)
        let approval = button("Open Login Items…", #selector(openLoginItemsSettings))
        stack.addArrangedSubview(approval)

        #if APARTE_DIRECT_UPDATES
        divider()
        add(label("Updates", heading: true))
        let update = button("Check for Updates…", #selector(checkForUpdates))
        stack.addArrangedSubview(update)
        updateButton = update
        #endif

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 24)
        ])
        window = settings
        shortcutButton = shortcut
        resetButton = reset
        shortcutStatusLabel = shortcutStatus
        loginButton = login
        loginStatusLabel = loginStatus
        loginApprovalButton = approval
        refreshShortcut()
        refreshLoginState()
        fitWindowToContent()
        settings.center()
        return settings
    }

    private func fitWindowToContent() {
        guard let window, let content = window.contentView, let settingsStack else { return }
        // Revealing an arranged view can defer NSStackView's constraints until the
        // next layout pass. Settle them before fitting, including on macOS 15.
        settingsStack.invalidateIntrinsicContentSize()
        settingsStack.needsUpdateConstraints = true
        content.updateConstraintsForSubtreeIfNeeded()
        settingsStack.needsLayout = true
        content.layoutSubtreeIfNeeded()
        let visibleFrames = settingsStack.arrangedSubviews.filter { !$0.isHidden }
            .map { $0.convert($0.bounds, to: settingsStack) }
        let visibleHeight = (visibleFrames.map(\.maxY).max() ?? 0) - (visibleFrames.map(\.minY).min() ?? 0)
        let height = ceil(max(settingsStack.fittingSize.height, visibleHeight)) + 48
        if abs(content.bounds.height - height) > 0.5 {
            let top = window.frame.maxY
            window.setContentSize(NSSize(width: 460, height: height))
            window.setFrameOrigin(NSPoint(x: window.frame.minX, y: top - window.frame.height))
        }
        content.layoutSubtreeIfNeeded()
    }

    private func refreshShortcut() {
        guard !isRecording else { return }
        defer { fitWindowToContent() }
        shortcutButton?.title = hotKeyController?.shortcutDescription ?? "Unavailable"
        shortcutButton?.isEnabled = hotKeyController != nil
        resetButton?.isEnabled = hotKeyController != nil && hotKeyController?.currentShortcut != HotKeyController.defaultShortcut
        if let failure = hotKeyController?.startupRegistrationFailure {
            showShortcutError("This shortcut is unavailable. \(failure.localizedDescription)")
        } else {
            shortcutStatusLabel?.stringValue = "Click the shortcut to change it."
            shortcutStatusLabel?.textColor = .secondaryLabelColor
        }
    }

    private func refreshLoginState() {
        defer { fitWindowToContent() }
        let state = launchAtLoginState
        loginButton?.state = state == .requiresApproval ? .mixed : (state == .enabled ? .on : .off)
        loginButton?.isEnabled = state != .unavailable
        loginApprovalButton?.isHidden = state != .requiresApproval
        let description: String
        switch state {
        case .disabled: description = "Aparte won’t open automatically when you log in."
        case .enabled: description = "Aparte opens in the menu bar when you log in."
        case .requiresApproval: description = "Allow Aparte in System Settings → Login Items."
        case .unavailable: description = "Launch at login is unavailable. Install Aparte in Applications and reopen it."
        }
        if let error = lastLaunchAtLoginError {
            loginStatusLabel?.stringValue = "Couldn’t change launch at login. \(error.localizedDescription)"
            loginStatusLabel?.textColor = .systemRed
        } else {
            loginStatusLabel?.stringValue = description
            loginStatusLabel?.textColor = .secondaryLabelColor
        }
    }

    private func refreshUpdates() {
        #if APARTE_DIRECT_UPDATES
        updateButton?.isEnabled = updateController?.canCheckForUpdates == true
        #endif
    }

    @objc private func recordShortcut() {
        defer { fitWindowToContent() }
        guard window?.isVisible == true, hotKeyController != nil else { return }
        if isRecording { stopRecording(); refreshShortcut(); return }
        stopRecording()
        isRecording = true
        shortcutButton?.title = "Cancel recording"
        shortcutStatusLabel?.stringValue = "Press a key with Command, Control, or Option. Escape cancels."
        shortcutStatusLabel?.textColor = .secondaryLabelColor
        recordingMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let consumed = MainActor.assumeIsolated { self.handleShortcutEvent(event) }
            return consumed ? nil : event
        }
        window?.makeFirstResponder(shortcutButton)
    }

    @discardableResult
    func handleShortcutEvent(_ event: NSEvent) -> Bool {
        defer { fitWindowToContent() }
        guard isCapturingShortcut, event.window === window else { return false }
        if event.keyCode == 53 {
            cancelShortcutOrClose()
            return true
        }
        guard let shortcut = HotKeyController.shortcut(keyCode: event.keyCode, modifierFlags: event.modifierFlags) else {
            showShortcutError("Use Command, Control, or Option with another key.")
            NSSound.beep()
            return true
        }
        guard let hotKeyController else { return false }
        switch hotKeyController.updateShortcut(shortcut) {
        case .success:
            stopRecording()
            refreshShortcut()
            shortcutStatusLabel?.stringValue = "Shortcut saved."
            onShortcutChanged?(shortcut)
        case let .failure(error):
            showShortcutError(error.localizedDescription)
            NSSound.beep()
        }
        return true
    }

    private func showShortcutError(_ message: String) {
        defer { fitWindowToContent() }
        shortcutStatusLabel?.stringValue = message
        shortcutStatusLabel?.textColor = .systemRed
    }

    private func stopRecording() {
        isRecording = false
        if let recordingMonitor { NSEvent.removeMonitor(recordingMonitor) }
        recordingMonitor = nil
    }

    private func cancelShortcutOrClose() {
        if isRecording {
            stopRecording()
            refreshShortcut()
        } else {
            // Escape closes the window the same way its close button does, so
            // the app hands focus back to the app the user came from.
            window?.performClose(nil)
        }
    }

    @objc private func resetShortcut() {
        defer { fitWindowToContent() }
        guard let hotKeyController else { return }
        switch hotKeyController.resetToDefault() {
        case .success:
            stopRecording()
            refreshShortcut()
            shortcutStatusLabel?.stringValue = "Shortcut reset."
            onShortcutChanged?(HotKeyController.defaultShortcut)
        case let .failure(error):
            showShortcutError(error.localizedDescription)
            NSSound.beep()
        }
    }

    @objc private func changeLaunchAtLogin() { _ = toggleLaunchAtLogin() }
    @objc private func openLoginItemsSettings() { openLoginItems() }
    #if APARTE_DIRECT_UPDATES
    @objc private func checkForUpdates() {
        guard updateController?.canCheckForUpdates == true else { refreshUpdates(); return }
        onCheckForUpdates?()
        refreshUpdates()
    }
    #endif

    func windowDidBecomeKey(_ notification: Notification) {
        refreshLoginState()
        refreshUpdates()
    }

    func windowDidResignKey(_ notification: Notification) {
        stopRecording()
        refreshShortcut()
    }

    func windowWillClose(_ notification: Notification) { stopRecording() }

    // Aparte is an accessory app with no other window, so a close the user asked
    // for must return focus to whatever they were using before Settings.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        onUserClose?()
        return true
    }

    private static func state(for status: SMAppService.Status) -> LaunchAtLoginState {
        switch status {
        case .notRegistered: return .disabled
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notFound: return .unavailable
        @unknown default: return .unavailable
        }
    }
}

@MainActor
private final class SettingsWindow: NSWindow {
    var onCancel: (() -> Void)?
    override func cancelOperation(_ sender: Any?) { onCancel?() }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == [.command],
           event.charactersIgnoringModifiers?.lowercased() == "w" {
            performClose(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
