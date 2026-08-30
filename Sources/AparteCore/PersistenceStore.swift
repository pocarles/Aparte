import Foundation

public struct PersistenceStore: Sendable {
    public let fileURL: URL

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
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        if FileManager.default.fileExists(atPath: fileURL.path),
           try String(contentsOf: fileURL, encoding: .utf8) == markdown {
            return
        }
        try markdown.write(to: fileURL, atomically: true, encoding: .utf8)
    }
}

