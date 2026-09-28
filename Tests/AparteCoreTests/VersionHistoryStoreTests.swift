import Foundation
import XCTest
@testable import AparteCore

final class VersionHistoryStoreTests: XCTestCase {
    private func withStore(_ body: (VersionHistoryStore, URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("AparteVersions-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let documentURL = root.appendingPathComponent("aparte.md")
        try body(VersionHistoryStore(documentURL: documentURL), documentURL)
    }

    func testVersionsPersistNewestFirstWithoutChangingDocumentOrRecovery() throws {
        try withStore { history, url in
            let document = try PersistenceStore(fileURL: url)
            try document.save("Current writing")
            try document.backupBeforeClear("Cleared writing")
            try history.record("# Café 👋", at: Date(timeIntervalSince1970: 10))
            try history.record("**Revision**", at: Date(timeIntervalSince1970: 20))
            let loaded = try VersionHistoryStore(documentURL: url).load()
            XCTAssertEqual(loaded.map(\.markdown), ["**Revision**", "# Café 👋"])
            XCTAssertEqual(loaded.last?.createdAt, Date(timeIntervalSince1970: 10))
            XCTAssertEqual(try document.load(), "Current writing")
            XCTAssertEqual(try document.loadRecovery(), "Cleared writing")
        }
    }

    func testRollingLimitBlankDraftsAndDuplicateCheckpoints() throws {
        try withStore { history, _ in
            for index in 0..<25 { try history.record("Draft \(index)", preservingExactDraft: true) }
            let original = try history.load()
            try history.record("Draft 24")
            try history.record(" \n\t")
            XCTAssertEqual(try history.load(), original)
            XCTAssertEqual(original.count, 20)
            XCTAssertEqual(original.last?.markdown, "Draft 5")
            // Returning to older wording is a new event, not a global deduplication.
            try history.record("Draft 10")
            XCTAssertEqual(try history.load().first?.markdown, "Draft 10")
        }
    }

    func testSmallEditsAccumulateAgainstLastCheckpoint() throws {
        try withStore { history, _ in
            let original = (0..<100).map { "word\($0)" }.joined(separator: " ")
            try history.record(original)
            for count in 1...11 {
                let edited = (0..<100).map { $0 < count ? "changed\($0)" : "word\($0)" }.joined(separator: " ")
                try history.record(edited)
                XCTAssertEqual(try history.load().count, 1)
            }
            let meaningful = (0..<100).map { $0 < 12 ? "changed\($0)" : "word\($0)" }.joined(separator: " ")
            try history.record(meaningful)
            XCTAssertEqual(try history.load().map(\.markdown), [meaningful, original])
        }
    }

    func testPunctuationWhitespaceAndSmallFormattingChangesDoNotAddSteps() throws {
        try withStore { history, _ in
            try history.record("Bonjour le monde, voici le café.")
            try history.record("# Bonjour le monde!\n\nVoici le **café**.")
            XCTAssertEqual(try history.load().count, 1)
            XCTAssertTrue(VersionHistoryStore.isMeaningfullyDifferent("Buy milk", from: "Call mum"))
            XCTAssertTrue(VersionHistoryStore.isMeaningfullyDifferent("😎", from: "🙂"))
        }
    }

    func testExplicitSafetyCopiesKeepMinorEditsAndRestores() throws {
        try withStore { history, _ in
            let original = String(repeating: "some words for a longer note ", count: 10)
            let edit = original + "extra"
            try history.record(original)
            try history.record(edit, preservingExactDraft: true)
            try history.record(original, preservingExactDraft: true)
            let versions = try history.load()
            XCTAssertEqual(versions.map(\.markdown), [original, edit, original])
            XCTAssertNotEqual(versions[0].id, versions[2].id)
        }
    }

    func testBrowsingGroupsLegacyNearDuplicatesWithoutChangingHistoryFile() throws {
        try withStore { history, _ in
            let original = (0..<100).map { "word\($0)" }.joined(separator: " ")
            for count in [0, 1, 3, 5, 15, 16, 18] {
                let edited = (0..<100).map { $0 < count ? "changed\($0)" : "word\($0)" }.joined(separator: " ")
                try history.record(edited, preservingExactDraft: true)
            }
            let bytes = try Data(contentsOf: history.fileURL)
            let current = try history.load()[0].markdown
            let visible = try history.versionsForBrowsing(current: current)
            XCTAssertEqual(visible.count, 1)
            XCTAssertEqual(visible[0].markdown.components(separatedBy: " ").filter { $0.hasPrefix("changed") }.count, 5)
            XCTAssertEqual(try Data(contentsOf: history.fileURL), bytes)
        }
    }

    func testLongDocumentsAndSeparatedEdits() {
        let words = (0..<10_000).map { "word\($0)" }
        var changed = words
        for index in stride(from: 0, to: 10_000, by: 250) { changed[index] = "replacement" }
        XCTAssertTrue(VersionHistoryStore.isMeaningfullyDifferent(changed.joined(separator: " "), from: words.joined(separator: " ")))
        changed[0] = words[0]
        XCTAssertFalse(VersionHistoryStore.isMeaningfullyDifferent(changed.joined(separator: " "), from: words.joined(separator: " ")))
        XCTAssertTrue(VersionHistoryStore.isMeaningfullyDifferent("", from: "A cleared note"))
    }

    func testClearLeavesCurrentAndRecoveryIntact() throws {
        try withStore { history, url in
            let document = try PersistenceStore(fileURL: url)
            try document.save("Current")
            try document.backupBeforeClear("Recovery")
            try history.record("Old")
            try history.clear()
            try history.clear()
            XCTAssertTrue(try history.load().isEmpty)
            XCTAssertEqual(try document.load(), "Current")
            XCTAssertEqual(try document.loadRecovery(), "Recovery")
        }
    }

    func testCorruptHistoryIsNotSilentlyOverwrittenAndCanBeDiscarded() throws {
        try withStore { history, _ in
            try history.record("Original")
            let broken = Data("not JSON".utf8)
            try broken.write(to: history.fileURL)
            XCTAssertThrowsError(try history.record("Replacement"))
            XCTAssertEqual(try Data(contentsOf: history.fileURL), broken)
            try history.clear()
            try history.record("Fresh")
            XCTAssertEqual(try history.load().first?.markdown, "Fresh")
        }
    }

    func testWriteFailureDoesNotChangeCurrentDocument() throws {
        try withStore { history, url in
            let document = try PersistenceStore(fileURL: url)
            try document.save("Keep this")
            try FileManager.default.createDirectory(at: history.fileURL, withIntermediateDirectories: false)
            XCTAssertThrowsError(try history.record("Cannot checkpoint"))
            XCTAssertEqual(try document.load(), "Keep this")
        }
    }
}
