import AppKit
import AparteCore

@MainActor
final class DocumentController {
    private let store: PersistenceStore
    private var saveWorkItem: DispatchWorkItem?
    private(set) var attributedText: NSMutableAttributedString
    private(set) var lastSaveError: Error?

    var markdown: String {
        MarkdownCodec.markdown(from: attributedText)
    }

    init(store: PersistenceStore? = nil) throws {
        self.store = try store ?? PersistenceStore()
        let saved = try self.store.load()
        self.attributedText = NSMutableAttributedString(attributedString: MarkdownCodec.render(saved))
    }

    func replace(with attributedString: NSAttributedString) {
        attributedText = NSMutableAttributedString(attributedString: attributedString)
        scheduleSave()
    }

    func textDidChange(_ attributedString: NSAttributedString) {
        attributedText = NSMutableAttributedString(attributedString: attributedString)
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
}

