import AppKit
import AparteCore

@MainActor
final class DocumentController {
    private let store: PersistenceStore
    private var saveWorkItem: DispatchWorkItem?
    /// The live editor storage, not a copy: nothing is duplicated per keystroke.
    private(set) var attributedText: NSAttributedString
    private(set) var lastSaveError: Error?

    var markdown: String {
        MarkdownCodec.markdown(from: attributedText)
    }

    var hasRecovery: Bool {
        store.hasRecovery
    }

    init(store: PersistenceStore? = nil) throws {
        self.store = try store ?? PersistenceStore()
        let saved = try self.store.load()
        self.attributedText = MarkdownCodec.render(saved)
    }

    func textDidChange(_ attributedString: NSAttributedString) {
        attributedText = attributedString
        scheduleSave()
    }

    func scheduleSave() {
        saveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    func saveNow() {
        saveWorkItem?.cancel()
        saveWorkItem = nil
        do {
            try store.save(markdown)
            lastSaveError = nil
        } catch {
            lastSaveError = error
        }
    }

    func backupBeforeClear() throws {
        try store.backupBeforeClear(markdown)
    }

    func loadRecovery() throws -> NSAttributedString? {
        guard let markdown = try store.loadRecovery() else { return nil }
        return MarkdownCodec.render(markdown)
    }

    func discardRecovery() throws {
        try store.discardRecovery()
    }
}
