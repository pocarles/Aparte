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
    private var recorderPanel: NSPanel?
    private var recorderField: NSTextField?
    private var statusLabel: NSTextField?
    private var resetButton: NSButton?
    private var recordingMonitor: Any?
    private var isRecording = false

    private(set) var lastLaunchAtLoginError: Error?

    var onShortcutChanged: ((HotKeyController.Shortcut) -> Void)?
    var onLaunchAtLoginStateChanged: ((LaunchAtLoginState) -> Void)?

    init(
        hotKeyController: HotKeyController?,
        launchAtLoginService: any LaunchAtLoginService = SystemLaunchAtLoginService()
    ) {
        self.hotKeyController = hotKeyController
        self.launchAtLoginService = launchAtLoginService
        super.init()
    }

    var isCapturingShortcut: Bool {
        isRecording && recorderPanel?.isVisible == true
    }

    var launchAtLoginState: LaunchAtLoginState {
        Self.state(for: launchAtLoginService.status)
    }

    var launchAtLoginEnabled: Bool {
        launchAtLoginState == .enabled
    }

    var launchAtLoginRequiresApproval: Bool {
        launchAtLoginState == .requiresApproval
    }

    @discardableResult
    func setLaunchAtLoginEnabled(_ enabled: Bool) -> Result<LaunchAtLoginState, Error> {
        let state = launchAtLoginState
        if (enabled && state == .enabled) || (!enabled && state == .disabled) {
            lastLaunchAtLoginError = nil
            onLaunchAtLoginStateChanged?(state)
            return .success(state)
        }

        do {
            if enabled {
                try launchAtLoginService.register()
            } else {
                try launchAtLoginService.unregister()
            }
            lastLaunchAtLoginError = nil
            let updatedState = launchAtLoginState
            onLaunchAtLoginStateChanged?(updatedState)
            return .success(updatedState)
        } catch {
            lastLaunchAtLoginError = error
            let currentState = launchAtLoginState
            onLaunchAtLoginStateChanged?(currentState)
            return .failure(error)
        }
    }

    @discardableResult
    func toggleLaunchAtLogin() -> Result<LaunchAtLoginState, Error> {
        switch launchAtLoginState {
        case .enabled, .requiresApproval:
            return setLaunchAtLoginEnabled(false)
        case .disabled, .unavailable:
            return setLaunchAtLoginEnabled(true)
        }
    }

    func showShortcutRecorder() {
        guard hotKeyController != nil else { return }
        let panel = makeRecorderPanelIfNeeded()
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        beginRecording()
    }

    func closeShortcutRecorder() {
        isRecording = false
        stopRecordingMonitor()
        recorderPanel?.orderOut(nil)
    }

    private func makeRecorderPanelIfNeeded() -> NSPanel {
        if let recorderPanel { return recorderPanel }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 178),
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "Keyboard shortcut"
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.delegate = self

        let content = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = content

        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(root)

        let explanation = NSTextField(
            wrappingLabelWithString: "Press a key with Command, Control, or Option."
        )
        explanation.textColor = .secondaryLabelColor
        explanation.alignment = .center

        let field = NSTextField(labelWithString: "")
        field.font = .systemFont(ofSize: 15, weight: .medium)
        field.alignment = .center
        field.isBordered = true
        field.isBezeled = true
        field.drawsBackground = true
        field.backgroundColor = .textBackgroundColor
        field.textColor = .labelColor

        let reset = NSButton(
            title: "Reset to Option-Space",
            target: self,
            action: #selector(resetShortcut)
        )
        reset.bezelStyle = .rounded

        let cancel = NSButton(
            title: "Done",
            target: self,
            action: #selector(closeRecorder)
        )
        cancel.bezelStyle = .rounded

        let status = NSTextField(labelWithString: "")
        status.alignment = .center
        status.textColor = .secondaryLabelColor
        status.isHidden = true

        [explanation, field, reset, cancel, status].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview($0)
        }

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            root.topAnchor.constraint(equalTo: content.topAnchor, constant: 18),
            root.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),

            explanation.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            explanation.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            explanation.topAnchor.constraint(equalTo: root.topAnchor),

            field.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 56),
            field.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -56),
            field.topAnchor.constraint(equalTo: explanation.bottomAnchor, constant: 12),
            field.heightAnchor.constraint(equalToConstant: 32),

            status.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            status.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            status.topAnchor.constraint(equalTo: field.bottomAnchor, constant: 5),
            status.heightAnchor.constraint(equalToConstant: 16),

            reset.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            reset.bottomAnchor.constraint(equalTo: root.bottomAnchor),

            cancel.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            cancel.bottomAnchor.constraint(equalTo: root.bottomAnchor),

            reset.topAnchor.constraint(greaterThanOrEqualTo: status.bottomAnchor, constant: 4),
            cancel.topAnchor.constraint(greaterThanOrEqualTo: status.bottomAnchor, constant: 4)
        ])

        recorderPanel = panel
        recorderField = field
        statusLabel = status
        resetButton = reset
        return panel
    }

    private func beginRecording() {
        guard let field = recorderField else { return }
        stopRecordingMonitor()
        isRecording = true
        field.stringValue = "Press a key…"
        resetButton?.isEnabled = true

        if let controller = hotKeyController,
           let failure = controller.startupRegistrationFailure {
            showError(
                "Current shortcut \(controller.shortcutDescription) is unavailable. \(failure.localizedDescription)"
            )
        } else {
            statusLabel?.stringValue = ""
            statusLabel?.isHidden = true
        }

        recordingMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let consumed = MainActor.assumeIsolated {
                self.handleShortcutEvent(event)
            }
            return consumed ? nil : event
        }
        recorderPanel?.makeFirstResponder(field)
    }

    @discardableResult
    private func handleShortcutEvent(_ event: NSEvent) -> Bool {
        guard isCapturingShortcut, event.window === recorderPanel else { return false }

        if event.keyCode == 53 {
            closeShortcutRecorder()
            return true
        }

        guard let shortcut = HotKeyController.shortcut(
            keyCode: event.keyCode,
            modifierFlags: event.modifierFlags
        ) else {
            showError("Use Command, Control, or Option with another key.")
            NSSound.beep()
            return true
        }

        guard let hotKeyController else { return false }
        switch hotKeyController.updateShortcut(shortcut) {
        case .success:
            recorderField?.stringValue = hotKeyController.shortcutDescription
            statusLabel?.stringValue = "Shortcut saved"
            statusLabel?.textColor = .systemGreen
            statusLabel?.isHidden = false
            isRecording = false
            stopRecordingMonitor()
            onShortcutChanged?(shortcut)
            return true
        case let .failure(error):
            showError(error.localizedDescription)
            NSSound.beep()
            return true
        }
    }

    private func showError(_ message: String) {
        statusLabel?.stringValue = message
        statusLabel?.textColor = .systemRed
        statusLabel?.isHidden = false
    }

    private func stopRecordingMonitor() {
        if let recordingMonitor {
            NSEvent.removeMonitor(recordingMonitor)
        }
        recordingMonitor = nil
    }

    @objc private func resetShortcut() {
        guard let hotKeyController else { return }
        switch hotKeyController.resetToDefault() {
        case .success:
            isRecording = false
            stopRecordingMonitor()
            recorderField?.stringValue = hotKeyController.shortcutDescription
            statusLabel?.stringValue = "Shortcut reset"
            statusLabel?.textColor = .systemGreen
            statusLabel?.isHidden = false
            onShortcutChanged?(HotKeyController.defaultShortcut)
        case let .failure(error):
            showError(error.localizedDescription)
            NSSound.beep()
        }
    }

    @objc private func closeRecorder() {
        closeShortcutRecorder()
    }

    func windowWillClose(_ notification: Notification) {
        isRecording = false
        stopRecordingMonitor()
    }

    private static func state(for status: SMAppService.Status) -> LaunchAtLoginState {
        switch status {
        case .notRegistered:
            return .disabled
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notFound:
            return .unavailable
        @unknown default:
            return .unavailable
        }
    }
}
