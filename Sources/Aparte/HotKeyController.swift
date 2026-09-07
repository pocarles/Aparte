@preconcurrency import Carbon
import AppKit
import Foundation

@MainActor
final class HotKeyController {
    struct Shortcut: Codable, Equatable, Sendable {
        let keyCode: UInt32
        let modifiers: UInt32

        init(keyCode: UInt32, modifiers: UInt32) {
            self.keyCode = keyCode
            self.modifiers = modifiers
        }
    }

    enum ShortcutError: LocalizedError, Equatable {
        case invalidShortcut
        case registrationFailed(OSStatus)

        var errorDescription: String? {
            switch self {
            case .invalidShortcut:
                return "Choose a key with Command, Control, or Option."
            case let .registrationFailed(status):
                if status == eventHotKeyExistsErr {
                    return "That shortcut is already reserved by another app."
                }
                return "Aparte could not register that shortcut (error \(status))."
            }
        }
    }

    enum RegistrationState: Equatable {
        case active(Shortcut)
        case unavailable(Shortcut, status: OSStatus)
        case inactive

        var isActive: Bool {
            if case .active = self { return true }
            return false
        }

        var shortcut: Shortcut? {
            switch self {
            case let .active(shortcut), let .unavailable(shortcut, _):
                return shortcut
            case .inactive:
                return nil
            }
        }
    }

    static let defaultShortcut = Shortcut(
        keyCode: UInt32(kVK_Space),
        modifiers: UInt32(optionKey)
    )

    private static let keyCodeDefaultsKey = "Aparte.globalShortcut.keyCode"
    private static let modifiersDefaultsKey = "Aparte.globalShortcut.modifiers"
    private static let eventID = EventHotKeyID(signature: signature, id: 1)
    private static let allowedModifiers = UInt32(cmdKey | controlKey | optionKey | shiftKey)
    private static let requiredModifiers = UInt32(cmdKey | controlKey | optionKey)

    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var eventHandlerStatus: OSStatus = noErr
    private let action: () -> Void
    private let defaults: UserDefaults

    private(set) var currentShortcut: Shortcut
    private(set) var activeShortcut: Shortcut?
    private(set) var registrationState: RegistrationState = .inactive
    private(set) var startupRegistrationFailure: ShortcutError?

    var onShortcutChanged: ((Shortcut) -> Void)?
    var onRegistrationStateChanged: ((RegistrationState) -> Void)?

    init(
        action: @escaping () -> Void,
        defaults: UserDefaults = .standard
    ) {
        self.action = action
        self.defaults = defaults
        self.currentShortcut = Self.loadShortcut(from: defaults) ?? Self.defaultShortcut

        let specification = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        var installedHandler: EventHandlerRef?
        self.eventHandlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return noErr }
                var receivedID = EventHotKeyID()
                let parameterStatus = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &receivedID
                )
                guard parameterStatus == noErr,
                      receivedID.signature == HotKeyController.signature,
                      receivedID.id == HotKeyController.eventID.id
                else { return OSStatus(eventNotHandledErr) }
                let controller = Unmanaged<HotKeyController>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                MainActor.assumeIsolated { controller.action() }
                return noErr
            },
            1,
            [specification],
            pointer,
            &installedHandler
        )
        self.handler = installedHandler

        guard eventHandlerStatus == noErr else {
            registrationState = .unavailable(currentShortcut, status: eventHandlerStatus)
            startupRegistrationFailure = .registrationFailed(eventHandlerStatus)
            return
        }

        let savedShortcut = Self.loadShortcut(from: defaults)
        if let savedShortcut {
            currentShortcut = savedShortcut
        }

        switch register(shortcut: currentShortcut) {
        case let .success(reference):
            hotKey = reference
            activeShortcut = currentShortcut
            setRegistrationState(.active(currentShortcut))
        case let .failure(error):
            // Keep the saved choice visible to the user, but do not claim it is active.
            // The user can reset it or record another shortcut from Preferences.
            startupRegistrationFailure = error
            setRegistrationState(.unavailable(currentShortcut, status: error.statusCode))
        }
    }

    var isRegistered: Bool { activeShortcut != nil }

    var shortcutDescription: String {
        Self.displayName(for: currentShortcut)
    }

    @discardableResult
    func updateShortcut(_ shortcut: Shortcut) -> Result<Shortcut, ShortcutError> {
        guard Self.isValid(shortcut) else {
            return .failure(.invalidShortcut)
        }

        if activeShortcut == shortcut {
            persist(shortcut)
            currentShortcut = shortcut
            startupRegistrationFailure = nil
            setRegistrationState(.active(shortcut))
            return .success(shortcut)
        }

        switch register(shortcut: shortcut) {
        case let .failure(error):
            // Registration is attempted before touching the old reference or defaults.
            // A failed choice therefore leaves the current shortcut usable and persisted.
            setRegistrationState(
                activeShortcut.map { .active($0) }
                    ?? .unavailable(currentShortcut, status: error.statusCode)
            )
            return .failure(error)

        case let .success(reference):
            if let hotKey {
                let unregisterStatus = UnregisterEventHotKey(hotKey)
                guard unregisterStatus == noErr else {
                    _ = UnregisterEventHotKey(reference)
                    let error = ShortcutError.registrationFailed(unregisterStatus)
                    if let activeShortcut {
                        setRegistrationState(.active(activeShortcut))
                    } else {
                        setRegistrationState(.unavailable(currentShortcut, status: unregisterStatus))
                    }
                    return .failure(error)
                }
            }
            hotKey = reference
            activeShortcut = shortcut
            currentShortcut = shortcut
            startupRegistrationFailure = nil
            persist(shortcut)
            setRegistrationState(.active(shortcut))
            onShortcutChanged?(shortcut)
            return .success(shortcut)
        }
    }

    @discardableResult
    func resetToDefault() -> Result<Shortcut, ShortcutError> {
        updateShortcut(Self.defaultShortcut)
    }

    func invalidate() {
        if let hotKey {
            _ = UnregisterEventHotKey(hotKey)
        }
        if let handler {
            _ = RemoveEventHandler(handler)
        }
        hotKey = nil
        handler = nil
        activeShortcut = nil
        setRegistrationState(.inactive)
    }

    static func isValid(_ shortcut: Shortcut) -> Bool {
        guard shortcut.keyCode <= 127 else { return false }
        guard !modifierOnlyOrEscapeKeyCodes.contains(shortcut.keyCode) else { return false }
        guard shortcut.modifiers & requiredModifiers != 0 else { return false }
        return shortcut.modifiers & ~allowedModifiers == 0
    }

    static func shortcut(
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags
    ) -> Shortcut? {
        let unsupportedFlags: NSEvent.ModifierFlags = [
            .capsLock,
            .numericPad,
            .help,
            .function
        ]
        guard modifierFlags.intersection(unsupportedFlags).isEmpty else { return nil }

        let modifiers = carbonModifiers(for: modifierFlags)
        let shortcut = Shortcut(keyCode: UInt32(keyCode), modifiers: modifiers)
        return isValid(shortcut) ? shortcut : nil
    }

    static func carbonModifiers(for flags: NSEvent.ModifierFlags) -> UInt32 {
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        return modifiers
    }

    static func displayName(for shortcut: Shortcut) -> String {
        var result = ""
        if shortcut.modifiers & UInt32(cmdKey) != 0 { result += "⌘" }
        if shortcut.modifiers & UInt32(controlKey) != 0 { result += "⌃" }
        if shortcut.modifiers & UInt32(optionKey) != 0 { result += "⌥" }
        if shortcut.modifiers & UInt32(shiftKey) != 0 { result += "⇧" }
        result += keyName(for: shortcut.keyCode)
        return result
    }

    private func register(shortcut: Shortcut) -> Result<EventHotKeyRef, ShortcutError> {
        guard Self.isValid(shortcut), eventHandlerStatus == noErr else {
            let status = eventHandlerStatus == noErr ? OSStatus(eventHotKeyInvalidErr) : eventHandlerStatus
            return .failure(.registrationFailed(status))
        }

        var candidate: EventHotKeyRef?
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            Self.eventID,
            GetApplicationEventTarget(),
            UInt32(kEventHotKeyExclusive),
            &candidate
        )
        guard status == noErr, let candidate else {
            return .failure(.registrationFailed(status == noErr ? OSStatus(eventHotKeyInvalidErr) : status))
        }
        return .success(candidate)
    }

    private func persist(_ shortcut: Shortcut) {
        defaults.set(Int(shortcut.keyCode), forKey: Self.keyCodeDefaultsKey)
        defaults.set(Int(shortcut.modifiers), forKey: Self.modifiersDefaultsKey)
    }

    private func setRegistrationState(_ state: RegistrationState) {
        registrationState = state
        onRegistrationStateChanged?(state)
    }

    private static func loadShortcut(from defaults: UserDefaults) -> Shortcut? {
        guard defaults.object(forKey: keyCodeDefaultsKey) != nil,
              defaults.object(forKey: modifiersDefaultsKey) != nil
        else { return nil }

        guard let keyCode = UInt32(exactly: defaults.integer(forKey: keyCodeDefaultsKey)),
              let modifiers = UInt32(exactly: defaults.integer(forKey: modifiersDefaultsKey))
        else {
            defaults.removeObject(forKey: keyCodeDefaultsKey)
            defaults.removeObject(forKey: modifiersDefaultsKey)
            return nil
        }

        let shortcut = Shortcut(keyCode: keyCode, modifiers: modifiers)
        guard isValid(shortcut) else {
            defaults.removeObject(forKey: keyCodeDefaultsKey)
            defaults.removeObject(forKey: modifiersDefaultsKey)
            return nil
        }
        return shortcut
    }

    private static func keyName(for keyCode: UInt32) -> String {
        switch keyCode {
        case UInt32(kVK_Space): return "Space"
        case UInt32(kVK_Return): return "Return"
        case UInt32(kVK_Tab): return "Tab"
        case UInt32(kVK_Delete): return "Delete"
        case UInt32(kVK_Escape): return "Escape"
        case UInt32(kVK_LeftArrow): return "←"
        case UInt32(kVK_RightArrow): return "→"
        case UInt32(kVK_UpArrow): return "↑"
        case UInt32(kVK_DownArrow): return "↓"
        case UInt32(kVK_ForwardDelete): return "Forward Delete"
        case UInt32(kVK_Home): return "Home"
        case UInt32(kVK_End): return "End"
        case UInt32(kVK_PageUp): return "Page Up"
        case UInt32(kVK_PageDown): return "Page Down"
        case UInt32(kVK_F1): return "F1"
        case UInt32(kVK_F2): return "F2"
        case UInt32(kVK_F3): return "F3"
        case UInt32(kVK_F4): return "F4"
        case UInt32(kVK_F5): return "F5"
        case UInt32(kVK_F6): return "F6"
        case UInt32(kVK_F7): return "F7"
        case UInt32(kVK_F8): return "F8"
        case UInt32(kVK_F9): return "F9"
        case UInt32(kVK_F10): return "F10"
        case UInt32(kVK_F11): return "F11"
        case UInt32(kVK_F12): return "F12"
        case 0: return "A"
        case 1: return "S"
        case 2: return "D"
        case 3: return "F"
        case 4: return "H"
        case 5: return "G"
        case 6: return "Z"
        case 7: return "X"
        case 8: return "C"
        case 9: return "V"
        case 11: return "B"
        case 12: return "Q"
        case 13: return "W"
        case 14: return "E"
        case 15: return "R"
        case 16: return "Y"
        case 17: return "T"
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 22: return "6"
        case 23: return "5"
        case 25: return "9"
        case 26: return "7"
        case 28: return "8"
        case 29: return "0"
        case 31: return "O"
        case 32: return "U"
        case 34: return "I"
        case 35: return "P"
        case 37: return "L"
        case 38: return "J"
        case 40: return "K"
        case 45: return "N"
        case 46: return "M"
        default: return "Key \(keyCode)"
        }
    }

    private static let modifierOnlyOrEscapeKeyCodes: Set<UInt32> = [
        53, // Escape
        54, 55, 56, 57, 58, 59, 60, 61, 62, 63 // modifier and Fn keys
    ]

    private static let signature: OSType = {
        let bytes = Array("APRT".utf8)
        return bytes.reduce(0) { ($0 << 8) + OSType($1) }
    }()
}

private extension HotKeyController.ShortcutError {
    var statusCode: OSStatus {
        switch self {
        case .invalidShortcut:
            return OSStatus(eventHotKeyInvalidErr)
        case let .registrationFailed(status):
            return status
        }
    }
}
