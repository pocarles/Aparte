import AppKit
import AparteCore

@MainActor
enum RuntimeAcceptance {
    static func run() -> Int32 {
        var passed: [String] = []
        var failed: [String] = []

        func check(_ condition: @autoclosure () -> Bool, _ name: String) {
            if condition() {
                passed.append(name)
            } else {
                failed.append(name)
            }
        }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AparteRuntimeAcceptance-\(UUID().uuidString)", isDirectory: true)
        let fileURL = root.appendingPathComponent("aparte.md")
        defer { try? FileManager.default.removeItem(at: root) }

        do {
            let store = try PersistenceStore(fileURL: fileURL)
            let document = try DocumentController(store: store)
            let pad = PadWindowController(document: document)
            let overlays = FocusOverlayController()
            var escapeDismissed = false
            pad.onDismiss = {
                escapeDismissed = true
                pad.hide()
                overlays.hide()
            }

            NSApp.activate(ignoringOtherApps: true)
            overlays.show()
            pad.show()
            drainRunLoop(for: 0.25)

            let initial = pad.runtimeSnapshot()
            check(initial.isVisible, "panel-visible")
            check(abs(initial.size.width - 860) < 1 && abs(initial.size.height - 680) < 1, "panel-860x680")
            check(initial.editorOwnsFocus, "editor-first-responder")
            check(initial.level == .popUpMenu, "panel-above-overlays")
            check(overlays.runtimeWindowCount == NSScreen.screens.count, "overlay-per-screen")
            check(overlays.runtimeWindowsArePassive, "overlays-passive-no-blur-window")

            let markdown = """
            # Runtime acceptance
            A **bold** and *italic* line with <u>underlining</u> and a [link](https://example.com).
            - First item
            1. Second item
            """
            pad.setMarkdownForRuntimeCheck(markdown)
            pad.selectForRuntimeCheck(NSRange(location: 0, length: 7))
            drainRunLoop(for: 0.05)
            check(pad.runtimeSnapshot().formattingBarIsVisible, "selection-formatting-bar")

            document.saveNow()
            check(document.lastSaveError == nil, "autosave-no-error")
            let savedMarkdown = try store.load()
            check(savedMarkdown == markdown, "markdown-written-cleanly")

            let restored = try DocumentController(store: store)
            check(restored.markdown == markdown, "markdown-restored-on-relaunch")

            let longMarkdown = (1...120)
                .map { "Paragraph \($0): enough text to exercise the native scroll view." }
                .joined(separator: "\n\n")
            pad.setMarkdownForRuntimeCheck(longMarkdown)
            drainRunLoop(for: 0.1)
            check(pad.runtimeSnapshot().editorCanScroll, "long-document-is-scrollable")
            check(pad.scrollToEndForRuntimeCheck(), "long-document-scrolls-to-end")

            pad.simulateEscapeForRuntimeCheck()
            drainRunLoop(for: 0.2)
            check(escapeDismissed && !pad.runtimeSnapshot().isVisible, "escape-dismisses")
            check(overlays.runtimeWindowCount == 0, "escape-removes-overlays")

            var reliable = true
            for _ in 0..<20 {
                overlays.show()
                pad.show()
                pad.hide()
                overlays.hide()
                reliable = reliable && !pad.runtimeSnapshot().isVisible && overlays.runtimeWindowCount == 0
            }
            drainRunLoop(for: 0.3)
            check(reliable, "twenty-show-hide-cycles")
        } catch {
            failed.append("unexpected-error:\(String(describing: error))")
        }

        let report: [String: Any] = [
            "passed": passed,
            "failed": failed,
            "manualStillRequired": [
                "global Option-Space invocation from another app",
                "visual quality on each connected display",
                "light and dark appearance review",
                "real rich paste through the UI",
            ],
        ]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]),
           let output = String(data: data, encoding: .utf8) {
            print(output)
        }
        return failed.isEmpty ? 0 : 1
    }

    private static func drainRunLoop(for seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }
}
