import Foundation

/// A bounded history of Markdown checkpoints beside the working document.
public struct VersionHistoryStore: Sendable {
    public struct Version: Codable, Identifiable, Equatable, Sendable {
        public let id: UUID
        public let createdAt: Date
        public let markdown: String
    }

    public static let maximumVersions = 20
    public let fileURL: URL

    public init(documentURL: URL) {
        fileURL = documentURL.deletingPathExtension().appendingPathExtension("versions.json")
    }

    public func load() throws -> [Version] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        return Array(try JSONDecoder().decode([Version].self, from: Data(contentsOf: fileURL))
            .prefix(Self.maximumVersions))
    }

    public func record(_ markdown: String, at date: Date = Date(), preservingExactDraft: Bool = false) throws {
        guard !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        var versions = try load()
        guard versions.first?.markdown != markdown else { return }
        if !preservingExactDraft, let latest = versions.first,
           !Self.isMeaningfullyDifferent(markdown, from: latest.markdown) { return }
        versions.insert(Version(id: UUID(), createdAt: date, markdown: markdown), at: 0)
        versions = Array(versions.prefix(Self.maximumVersions))
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(versions).write(to: fileURL, options: .atomic)
    }

    /// Group existing checkpoints for browsing without deleting any stored wording.
    /// Compare with the last visible version so small edits can accumulate.
    public func versionsForBrowsing(current: String) throws -> [Version] {
        var previous = current
        return try load().filter { version in
            guard Self.isMeaningfullyDifferent(version.markdown, from: previous) else { return false }
            previous = version.markdown
            return true
        }
    }

    /// Ignore typography and punctuation tweaks. Save when roughly 12% of words
    /// change, capped at 40 words so a new paragraph in a long draft still counts.
    /// Short notes use a smaller threshold. This measures edits, not meaning.
    public static func isMeaningfullyDifferent(_ markdown: String, from previous: String) -> Bool {
        func words(_ text: String) -> [Substring] {
            text.lowercased().split { !$0.isLetter && !$0.isNumber && !$0.isSymbol }
        }
        let old = words(previous)
        let new = words(markdown)
        guard old != new else { return false }
        let threshold = max(1, min(40, Int(ceil(Double(max(old.count, new.count)) * 0.12))))
        if abs(old.count - new.count) >= threshold { return true }

        // Trim unchanged ends, then use a bounded edit-distance band. Work stays
        // proportional to draft length, even for a long pasted document.
        var start = 0
        while start < min(old.count, new.count), old[start] == new[start] { start += 1 }
        var oldEnd = old.count
        var newEnd = new.count
        while oldEnd > start, newEnd > start, old[oldEnd - 1] == new[newEnd - 1] {
            oldEnd -= 1
            newEnd -= 1
        }
        let a = Array(old[start..<oldEnd])
        let b = Array(new[start..<newEnd])
        if a.isEmpty || b.isEmpty { return max(a.count, b.count) >= threshold }
        var previousRow = (0...b.count).map { min($0, threshold) }
        var row = Array(repeating: threshold, count: b.count + 1)
        for i in 1...a.count {
            let lower = max(1, i - threshold + 1)
            let upper = min(b.count, i + threshold - 1)
            guard lower <= upper else { return true }
            row[0] = min(i, threshold)
            if lower > 1 { row[lower - 1] = threshold }
            var minimum = row[0]
            for j in lower...upper {
                row[j] = min(threshold, min(previousRow[j] + 1,
                    min(row[j - 1] + 1, previousRow[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))))
                minimum = min(minimum, row[j])
            }
            if upper < b.count { row[upper + 1] = threshold }
            if minimum >= threshold { return true }
            swap(&row, &previousRow)
        }
        return previousRow[b.count] >= threshold
    }

    public func clear() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }
}
