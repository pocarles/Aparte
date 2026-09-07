import Foundation

public struct PersistenceStore: Sendable {
    public let fileURL: URL

    /// The one local recovery slot beside the document.
    public var recoveryFileURL: URL {
        fileURL
            .deletingPathExtension()
            .appendingPathExtension("recovery.md")
    }

    public var hasRecovery: Bool {
        FileManager.default.fileExists(atPath: recoveryFileURL.path)
    }

    public init(fileURL: URL? = nil) throws {
        if let fileURL {
            self.fileURL = fileURL
            return
        }

        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        self.fileURL = base
            .appendingPathComponent("Aparte", isDirectory: true)
            .appendingPathComponent("aparte.md", isDirectory: false)
    }

    public func load() throws -> String {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return "" }
        return try String(contentsOf: fileURL, encoding: .utf8)
    }

    public func save(_ markdown: String) throws {
        if FileManager.default.fileExists(atPath: fileURL.path),
           try String(contentsOf: fileURL, encoding: .utf8) == markdown {
            return
        }
        try writeAtomically(markdown, to: fileURL)
    }

    /// The one recovery slot is replaced only by nonblank Markdown.
    /// An empty or whitespace-only document does not replace an existing slot.
    public func backupBeforeClear(_ markdown: String) throws {
        guard !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        try writeAtomically(markdown, to: recoveryFileURL)
    }

    public func loadRecovery() throws -> String? {
        guard hasRecovery else { return nil }
        return try String(contentsOf: recoveryFileURL, encoding: .utf8)
    }

    public func discardRecovery() throws {
        guard hasRecovery else { return }
        try FileManager.default.removeItem(at: recoveryFileURL)
    }

    private func writeAtomically(_ markdown: String, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(markdown.utf8).write(to: url, options: .atomic)
    }
}
