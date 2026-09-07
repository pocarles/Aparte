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

    func testBackupBeforeClearPersistsAndLoadsAcrossStoreInstances() throws {
        let root = makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("nested/aparte.md")
        let store = try PersistenceStore(fileURL: file)

        XCTAssertFalse(store.hasRecovery)
        XCTAssertNil(try store.loadRecovery())

        try store.backupBeforeClear("# Recoverable\n\nBody")

        XCTAssertTrue(store.hasRecovery)
        XCTAssertEqual(try store.loadRecovery(), "# Recoverable\n\nBody")
        XCTAssertEqual(try PersistenceStore(fileURL: file).loadRecovery(), "# Recoverable\n\nBody")
        XCTAssertEqual(store.recoveryFileURL.lastPathComponent, "aparte.recovery.md")
    }

    func testBackupBeforeClearReplacesTheSingleRecoverySlot() throws {
        let root = makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try PersistenceStore(fileURL: root.appendingPathComponent("aparte.md"))

        try store.backupBeforeClear("First")
        try store.backupBeforeClear("Second")

        XCTAssertEqual(try store.loadRecovery(), "Second")
    }

    func testEmptyBackupBeforeClearDoesNotOverwriteExistingRecovery() throws {
        let root = makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try PersistenceStore(fileURL: root.appendingPathComponent("aparte.md"))

        try store.backupBeforeClear("Keep this")
        try store.backupBeforeClear("")
        try store.backupBeforeClear(" \n\t")

        XCTAssertEqual(try store.loadRecovery(), "Keep this")
    }

    func testMissingAndDiscardedRecoveryAreSafe() throws {
        let root = makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try PersistenceStore(fileURL: root.appendingPathComponent("aparte.md"))

        XCTAssertNil(try store.loadRecovery())
        XCTAssertNoThrow(try store.discardRecovery())

        try store.backupBeforeClear("Discard me")
        try store.discardRecovery()

        XCTAssertFalse(store.hasRecovery)
        XCTAssertNil(try store.loadRecovery())
        XCTAssertNoThrow(try store.discardRecovery())
    }

    func testBackupBeforeClearThrowsWhenItsParentCannotBeCreated() throws {
        let root = makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let blockedParent = root.appendingPathComponent("blocked")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("not a directory".utf8).write(to: blockedParent)
        let store = try PersistenceStore(fileURL: blockedParent.appendingPathComponent("aparte.md"))

        XCTAssertThrowsError(try store.backupBeforeClear("Cannot write"))
        XCTAssertFalse(store.hasRecovery)
    }

    private func makeTemporaryRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("AparteTests-\(UUID().uuidString)", isDirectory: true)
    }
}
