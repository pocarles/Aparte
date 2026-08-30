import Foundation
import XCTest
@testable import AparteCore

final class PersistenceStoreTests: XCTestCase {
    func testSaveCreatesParentAndLoadRestoresMarkdown() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AparteTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("nested/aparte.md")
        let store = try PersistenceStore(fileURL: file)

        XCTAssertEqual(try store.load(), "")
        try store.save("# Persisted\n\nBody")

        XCTAssertEqual(try store.load(), "# Persisted\n\nBody")
    }

    func testSaveUsesUtf8Markdown() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AparteTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("aparte.md")
        let store = try PersistenceStore(fileURL: file)

        try store.save("Café — local")
        let data = try Data(contentsOf: file)

        XCTAssertEqual(String(data: data, encoding: .utf8), "Café — local")
    }
}

