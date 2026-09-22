import AppKit
import AparteCore

@MainActor
@main struct PerformanceBenchmark {
    static var sink = 0
    static func measure(_ name: String, _ repetitions: Int = 11, _ body: () -> Int) {
        sink &+= autoreleasepool(invoking: body)
        var times: [Double] = []
        for _ in 0..<repetitions {
            let start = DispatchTime.now().uptimeNanoseconds
            sink &+= autoreleasepool(invoking: body)
            times.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
        }
        times.sort()
        print(String(format: "%@ median_ms=%.3f p90_ms=%.3f", name, times[times.count/2], times[min(times.count-1, Int(Double(times.count) * 0.9))]))
        fflush(stdout)
    }
    private static func reportMemory() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/vmmap")
        process.arguments = ["-summary", String(ProcessInfo.processInfo.processIdentifier)]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let output = String(decoding: data, as: UTF8.self)
            print(output.split(separator: "\n").filter { $0.contains("Physical footprint") }.joined(separator: "\n"))
        } catch { print("memory-measurement-error=\(error)") }
    }

    static func main() async throws {
        if CommandLine.arguments.dropFirst().first == "--memory-endpoint" {
            guard CommandLine.arguments.count == 3,
                  let url = URL(string: CommandLine.arguments[2]),
                  url.scheme == "http", url.host == "127.0.0.1" else {
                fatalError("Use --memory-endpoint with a synthetic http://127.0.0.1 endpoint")
            }
            let result = await EndpointSender().send(
                EndpointPayload(markdown: "Synthetic benchmark", title: "Benchmark"), to: url
            )
            print("endpoint-result=\(result)")
            reportMemory()
            return
        }
        if CommandLine.arguments.dropFirst().first == "--memory-paste" {
            NSApplication.shared.setActivationPolicy(.accessory)
            let input = NSMutableAttributedString()
            for index in 0..<12_500 {
                input.append(NSAttributedString(
                    string: "Paragraph \(index): a long rich paste with ordinary words, café, and 👩🏽‍💻.\n\n",
                    attributes: AparteTypography.baseAttributes
                ))
            }
            for index in stride(from: 0, to: input.length - 5, by: 140) {
                input.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: 17), range: NSRange(location: index, length: 5))
            }
            let start = DispatchTime.now().uptimeNanoseconds
            let result = autoreleasepool { PasteNormalizer.normalized(input) }
            print("paste-utf16=\(result.length) duration_ms=\(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)")
            withExtendedLifetime(result) { reportMemory() }
            return
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.finishLaunching()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("AparteBenchmark-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        for n in [50, 500, 2500] {
            let markdown = (0..<n).map { i in
                i % 10 == 0 ? "## Heading \(i)" : "Paragraph \(i) has ordinary words, **bold writing**, and a [useful link](https://example.com)."
            }.joined(separator: "\n\n")
            let rendered = MarkdownCodec.render(markdown)
            print("fixture paragraphs=\(n) words=\(PadWindowController.wordCount(in: rendered.string)) utf16=\(rendered.length)")
            measure("render-\(n)", 7) { MarkdownCodec.render(markdown).length }
            measure("serialize-\(n)") { MarkdownCodec.markdown(from: rendered).utf8.count }
            let mutable = NSMutableAttributedString(attributedString: rendered)
            let edit = NSRange(location: mutable.length / 2, length: 1)
            measure("spacing-single-edit-\(n)") { ParagraphFormatting.applyStructuralSpacing(to: mutable, edited: edit) }
            measure("word-character-count-\(n)") {
                let s = rendered.string
                return PadWindowController.wordCount(in: s) + s.count + s.count
            }
            measure("normalize-rich-paste-\(n)", 7) { PasteNormalizer.normalized(rendered).length }
            measure("copy-export-pair-\(n)") { ParagraphFormatting.plainText(from: rendered).utf8.count + ParagraphFormatting.html(from: rendered).utf8.count }
            let fixtureRoot = root.appendingPathComponent("fixture-\(n)")
            let doc = try DocumentController(store: PersistenceStore(fileURL: fixtureRoot.appendingPathComponent("aparte.md")))
            let suite = "ApartePerfAudit-\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            let pad = PadWindowController(document: doc, defaults: defaults, optionsMenu: { NSMenu() })
            pad.setMarkdownForRuntimeCheck(markdown)
            let editor = pad.editorForRuntimeCheck
            doc.textDidChange(editor.textStorage!)
            measure("save-unchanged-\(n)") { doc.saveNow(); return doc.lastSaveError == nil ? 1 : 0 }
            let clipboard = NSPasteboard.withUniqueName()
            measure("copy-whole-pad-\(n)", 7) {
                pad.copyAllForRuntimeCheck(to: clipboard)
                return clipboard.string(forType: .string)?.utf8.count ?? 0
            }
            clipboard.releaseGlobally()
            let location = editor.textStorage!.length / 2
            measure("caret-counts-off-\(n)") {
                editor.setSelectedRange(NSRange(location: editor.selectedRange().location == location ? location + 1 : location, length: 0))
                return 1
            }
            editor.setSelectedRange(NSRange(location: location, length: 0))
            measure("typing-counts-off-\(n)") {
                editor.insertText("x", replacementRange: editor.selectedRange())
                return 1
            }
            measure("editor-word-character-count-\(n)") {
                let s = editor.string
                return PadWindowController.wordCount(in: s) + s.count + s.count
            }
            pad.toggleCounts()
            measure("caret-counts-on-\(n)") {
                editor.setSelectedRange(NSRange(location: editor.selectedRange().location == location ? location + 1 : location, length: 0))
                return 1
            }
            editor.setSelectedRange(NSRange(location: location, length: 0))
            measure("typing-counts-on-\(n)") {
                editor.insertText("x", replacementRange: editor.selectedRange())
                return 1
            }
            doc.saveNow()
            pad.hide()
            defaults.removePersistentDomain(forName: suite)
        }
        print("sink=\(sink)")
    }
}
