@preconcurrency import Carbon
import Foundation

@MainActor
final class HotKeyController {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action

        var specification = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                let controller = Unmanaged<HotKeyController>.fromOpaque(userData).takeUnretainedValue()
                MainActor.assumeIsolated { controller.action() }
                return noErr
            },
            1,
            &specification,
            pointer,
            &handler
        )

        let identifier = EventHotKeyID(signature: Self.signature, id: 1)
        RegisterEventHotKey(
            UInt32(kVK_Space),
            UInt32(optionKey),
            identifier,
            GetApplicationEventTarget(),
            0,
            &hotKey
        )
    }

    func invalidate() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
        hotKey = nil
        handler = nil
    }

    private static let signature: OSType = {
        let bytes = Array("APRT".utf8)
        return bytes.reduce(0) { ($0 << 8) + OSType($1) }
    }()
}
