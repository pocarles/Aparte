import AppKit

@MainActor
final class FocusOverlayController {
    private static let dimmingAlpha: CGFloat = 0.30
    private var windows: [NSWindow] = []

    var runtimeWindowCount: Int { windows.count }

    var runtimeWindowsArePassive: Bool {
        windows.allSatisfy { $0.ignoresMouseEvents && $0.level == .floating && !$0.isOpaque }
    }

    func show() {
        hideImmediately()
        windows = NSScreen.screens.map(makeWindow)
        for window in windows {
            window.alphaValue = 0
            window.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().alphaValue = 1
            }
        }
    }

    func hide() {
        let currentWindows = windows
        windows.removeAll()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            currentWindows.forEach { $0.animator().alphaValue = 0 }
        } completionHandler: {
            Task { @MainActor in
                currentWindows.forEach { $0.orderOut(nil) }
            }
        }
    }

    private func hideImmediately() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
    }

    private func makeWindow(for screen: NSScreen) -> NSWindow {
        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.backgroundColor = NSColor.black.withAlphaComponent(Self.dimmingAlpha)
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.isReleasedWhenClosed = false
        return window
    }
}
