import AppKit
import AparteCore

@MainActor
final class DocumentController {
    private let store: PersistenceStore
    private let history: VersionHistoryStore
    private var lastCheckpointAt: Date?
    private var hasEdited = false
    private var initialMarkdown: String?
    private var lastCheckpointMarkdown: String?
    private(set) var lastHistoryError: Error?
    private var saveWorkItem: DispatchWorkItem?
    /// The live editor storage, not a copy: nothing is duplicated per keystroke.
    private(set) var attributedText: NSAttributedString
    private(set) var lastSaveError: Error?
    private var cachedMarkdown: String?
    private var savedFileState: PersistenceStore.FileState?

    var markdown: String {
        if let cachedMarkdown { return cachedMarkdown }
        let value = MarkdownCodec.markdown(from: attributedText)
        cachedMarkdown = value
        return value
    }

    var hasRecovery: Bool {
        store.hasRecovery
    }

    init(store: PersistenceStore? = nil) throws {
        self.store = try store ?? PersistenceStore()
        history = VersionHistoryStore(documentURL: self.store.fileURL)
        let saved = try self.store.load()
        initialMarkdown = saved
        self.attributedText = MarkdownCodec.render(saved)
    }

    func textDidChange(_ attributedString: NSAttributedString) {
        hasEdited = true
        attributedText = attributedString
        cachedMarkdown = nil
        savedFileState = nil
        scheduleSave()
    }

    func scheduleSave() {
        saveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    func saveNow(checkpoint: Bool = false, preservingExactDraft: Bool = false) {
        saveWorkItem?.cancel()
        saveWorkItem = nil
        // Opening or dismissing an untouched pad must not recreate cleared history.
        // The first edit checkpoints the launch-time wording before saving the new text.
        do {
            let checkpointDue = lastCheckpointAt.map { Date().timeIntervalSince($0) >= 60 } ?? true
            if hasEdited && (checkpoint || checkpointDue) && markdown != lastCheckpointMarkdown { try checkpointNow(preservingExactDraft: preservingExactDraft) }
        } catch { lastHistoryError = error }
        if let savedFileState, savedFileState == store.fileState { return }
        do {
            try store.save(markdown)
            savedFileState = store.fileState
            lastSaveError = nil
        } catch {
            savedFileState = nil
            lastSaveError = error
        }
    }

    func backupBeforeClear() throws {
        try checkpointNow()
        try store.backupBeforeClear(markdown)
    }

    func recentVersions() throws -> [VersionHistoryStore.Version] { try history.load() }

    func versionsForBrowsing() throws -> [VersionHistoryStore.Version] {
        try history.versionsForBrowsing(current: markdown)
    }

    func checkpointNow(preservingExactDraft: Bool = true) throws {
        if let initialMarkdown {
            try history.record(initialMarkdown, preservingExactDraft: preservingExactDraft)
            self.initialMarkdown = nil
        }
        let current = markdown
        // Destructive actions re-read the history even when the draft is unchanged.
        // A deleted or damaged history file must not invalidate the safety copy.
        try history.record(current, preservingExactDraft: preservingExactDraft)
        lastCheckpointMarkdown = current
        lastCheckpointAt = Date()
        lastHistoryError = nil
    }

    func clearHistory() throws {
        try history.clear()
        initialMarkdown = nil
        lastCheckpointMarkdown = markdown
        lastCheckpointAt = Date()
        lastHistoryError = nil
    }

    func loadRecovery() throws -> NSAttributedString? {
        guard let markdown = try store.loadRecovery() else { return nil }
        return MarkdownCodec.render(markdown)
    }

    func discardRecovery() throws {
        try store.discardRecovery()
    }
}
