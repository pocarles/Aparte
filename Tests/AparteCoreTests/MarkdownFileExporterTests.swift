import Foundation
import XCTest
@testable import AparteCore

final class MarkdownFileExporterTests: XCTestCase {
    func testExportUsesFirstHeadingAndWritesMarkdown() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let markdown = "# Focused writing\n\nBody with **meaning**."

        let file = try MarkdownFileExporter.export(markdown, to: directory)

        XCTAssertEqual(file.lastPathComponent, "Focused writing.md")
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), markdown)
    }

    func testExportAddsNumberInsteadOfOverwriting() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let markdown = "# New thought"

        let first = try MarkdownFileExporter.export(markdown, to: directory)
        let second = try MarkdownFileExporter.export(markdown, to: directory)

        XCTAssertEqual(first.lastPathComponent, "New thought.md")
        XCTAssertEqual(second.lastPathComponent, "New thought 2.md")
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("AparteExportTests-\(UUID().uuidString)", isDirectory: true)
    }
}
