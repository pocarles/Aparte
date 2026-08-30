import AppKit
import Darwin

@main
enum AparteMain {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        if ProcessInfo.processInfo.arguments.contains("--runtime-acceptance") {
            application.setActivationPolicy(.accessory)
            exit(RuntimeAcceptance.run())
        }
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
        _ = delegate
    }
}
