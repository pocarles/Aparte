import AppKit
import AparteCore
import UniformTypeIdentifiers

@MainActor
final class PadWindowController: NSObject, NSTextViewDelegate {
    struct RuntimeSnapshot {
        let size: NSSize
        let isVisible: Bool
        let isKey: Bool
        let editorOwnsFocus: Bool
        let formattingBarIsVisible: Bool
        let editorCanScroll: Bool
        let editorHasSymmetricHorizontalPadding: Bool
        let level: NSWindow.Level
    }

    private static let preferredSize = NSSize(width: 1_032, height: 816)
    private let document: DocumentController
    private let panel: ApartePanel
    private let editor: EditorTextView
    private let rootView: PadBackgroundView
    private let formattingBar: FormattingBar
    private weak var copyButton: PadActionButton?
    private weak var saveButton: PadActionButton?
    private weak var clearButton: PadActionButton?
    private let countLabel = NSTextField(labelWithString: "")
    private let defaults: UserDefaults
    private let optionsMenu: () -> NSMenu
    private var zoom: CGFloat = 1
    private var optionsOverlay: OptionsOverlayView?
    var isOptionsMenuOpen: Bool { optionsOverlay != nil }
    var showsCounts: Bool { defaults.bool(forKey: "showWordCount") }

    var onDismiss: (() -> Void)?

    var isVisible: Bool { panel.isVisible }
    var window: NSWindow { panel }

    var shortcutHint: String? {
        get { editor.placeholderHint }
        set { editor.placeholderHint = newValue }
    }

    init(document: DocumentController, defaults: UserDefaults = .standard,
         optionsMenu: @escaping () -> NSMenu = { MenuBarController.makeOptionsMenu(target: NSApp.delegate as? AppDelegate) }) {
        self.optionsMenu = optionsMenu
        self.defaults = defaults
        self.document = document
        self.panel = ApartePanel(
            contentRect: NSRect(origin: .zero, size: Self.preferredSize),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        self.editor = EditorTextView(frame: .zero)
        self.rootView = PadBackgroundView(frame: NSRect(origin: .zero, size: Self.preferredSize))
        self.formattingBar = FormattingBar(editor: editor)
        super.init()
        configurePanel()
        configureEditor()
        configureContent()
        let savedZoom = defaults.double(forKey: "textZoom")
        setZoom(savedZoom == 0 ? 1 : savedZoom)
        updateCounts()
    }

    func show() {
        resetActionButtons()
        recenter()
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        panel.makeFirstResponder(editor)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        resetActionButtons()
        formattingBar.closeLinkPopover()
        closeOptions()
        formattingBar.isHidden = true
        // Ordering the pad out while a sheet is attached would orphan the sheet.
        if let sheet = panel.attachedSheet {
            panel.endSheet(sheet, returnCode: .cancel)
        }
        panel.orderOut(nil)
    }

    func recenter() {
        let screen = activeScreen() ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else { return }
        let width = min(Self.preferredSize.width, visibleFrame.width - 32)
        let height = min(Self.preferredSize.height, visibleFrame.height - 32)
        panel.setFrame(
            NSRect(
                x: visibleFrame.midX - width / 2,
                y: visibleFrame.midY - height / 2,
                width: width,
                height: height
            ),
            display: true
        )
        layoutZoomedEditor()
    }

    func copyMarkdown() {
        editor.copyAsMarkdown(nil)
    }

    @objc func copyAll() {
        performCopyAll(to: .general)
    }

    private func performCopyAll(to pasteboard: NSPasteboard) {
        panel.makeFirstResponder(editor)
        guard !editor.string.isEmpty else {
            copyButton?.acknowledge("Empty", symbol: "exclamationmark.circle", detail: "The pad is empty. Nothing was copied.")
            return
        }
        let content = editor.attributedString()
        let expectedPlainText = ParagraphFormatting.plainText(from: content)
        let expectedHTML = ParagraphFormatting.html(from: content)
        let previousChange = pasteboard.changeCount
        editor.copyAllPreservingSelection(to: pasteboard)
        if pasteboard.changeCount != previousChange
            && pasteboard.string(forType: .string) == expectedPlainText
            && pasteboard.string(forType: .html) == expectedHTML {
            copyButton?.acknowledge("Copied", symbol: "checkmark", detail: "Copied the whole pad.")
        } else {
            copyButton?.acknowledge("Failed", symbol: "exclamationmark.circle", detail: "The pad could not be copied. Try again.")
            NSSound.beep()
        }
    }

    @objc private func showOptions(_ sender: NSButton) {
        toggleOptions()
    }

    func toggleOptions() {
        guard !isOptionsMenuOpen else { closeOptions(); return }
        formattingBar.closeLinkPopover()
        presentOptions(optionsMenu())
    }

    func dismissTransientUI() -> Bool {
        if isOptionsMenuOpen { closeOptions(); return true }
        if formattingBar.isShowingLink { formattingBar.closeLinkPopover(); return true }
        return false
    }

    func performOptionsKeyEquivalent(_ event: NSEvent) -> Bool {
        guard panel.isKeyWindow, let optionsOverlay else { return false }
        return optionsOverlay.performKeyEquivalent(with: event)
    }

    func presentOptions(_ menu: NSMenu) {
        closeOptions()
        let overlay = OptionsOverlayView(menu: menu)
        overlay.frame = rootView.bounds
        overlay.autoresizingMask = [.width, .height]
        overlay.onDismiss = { [weak self] in self?.closeOptions() }
        overlay.onChoose = { [weak self] item in
            guard let self, item.isEnabled else { return }
            closeOptions()
            guard item.action != #selector(AppDelegate.toggleOptions) else { return }
            if let action = item.action { NSApp.sendAction(action, to: item.target, from: item) }
        }
        optionsOverlay = overlay
        formattingBar.isHidden = true
        rootView.addSubview(overlay)
        rootView.optionsAccessibilityView = overlay
        NSAccessibility.post(element: panel, notification: .layoutChanged)
        rootView.layoutSubtreeIfNeeded()
        panel.makeFirstResponder(overlay)
    }

    func closeOptions() {
        guard let overlay = optionsOverlay else { return }
        optionsOverlay = nil
        overlay.removeFromSuperview()
        rootView.optionsAccessibilityView = nil
        NSAccessibility.post(element: panel, notification: .layoutChanged)
        panel.makeFirstResponder(editor)
    }

    var optionsOverlayForRuntimeCheck: OptionsOverlayView? { optionsOverlay }
    var linkIsVisibleForRuntimeCheck: Bool { formattingBar.isShowingLink }

    @objc func clearPad() {
        panel.makeFirstResponder(editor)
        guard !editor.string.isEmpty else {
            clearButton?.acknowledge("Empty", symbol: "exclamationmark.circle", detail: "The pad is already empty. Your recovery copy is unchanged.")
            return
        }
        do {
            try document.backupBeforeClear()
            editor.clearAll(nil)
            formattingBar.isHidden = true
            if editor.string.isEmpty {
                clearButton?.acknowledge("Cleared", symbol: "checkmark", detail: "Cleared the pad. Undo with Command-Z, or restore the last cleared text from the three-dot menu.")
            } else {
                clearButton?.acknowledge("Failed", symbol: "exclamationmark.circle", detail: "Your text was not cleared.")
            }
        } catch {
            presentError(error, message: "Your text was not cleared because its recovery copy could not be saved.")
            panel.makeFirstResponder(editor)
            clearButton?.acknowledge("Failed", symbol: "exclamationmark.circle", detail: "Your text was not cleared because its recovery copy could not be saved.")
        }
    }

    func copyPlainText() { editor.copyAsPlainText(nil) }

    func toggleCounts() {
        defaults.set(!showsCounts, forKey: "showWordCount")
        updateCounts()
    }

    func zoomIn() { setZoom(zoom + 0.1) }
    func zoomOut() { setZoom(zoom - 0.1) }
    func resetZoom() { setZoom(1) }

    var canZoomIn: Bool { zoom < 1.8 - 0.001 }
    var canZoomOut: Bool { zoom > 0.8 + 0.001 }
    var isDefaultZoom: Bool { abs(zoom - 1) < 0.001 }

    private func setZoom(_ value: CGFloat) {
        zoom = min(1.8, max(0.8, value))
        guard let scrollView = editor.enclosingScrollView else { return }
        scrollView.minMagnification = 0.8
        scrollView.maxMagnification = 1.8
        scrollView.magnification = zoom
        layoutZoomedEditor()
        editor.scrollRangeToVisible(editor.selectedRange())
        defaults.set(Double(zoom), forKey: "textZoom")
        updateFormattingBar()
    }

    private func layoutZoomedEditor() {
        guard let scrollView = editor.enclosingScrollView else { return }
        let visibleSize = scrollView.contentView.bounds.size
        // Magnification scales document coordinates. Reflow to the visible width
        // and keep the pad's physical margins constant as text grows.
        editor.textContainerInset = NSSize(width: min(200, visibleSize.width * zoom * 0.2) / zoom, height: 120 / zoom)
        editor.minSize = NSSize(width: 0, height: visibleSize.height)
        editor.maxSize = NSSize(width: visibleSize.width, height: .greatestFiniteMagnitude)
        editor.autoresizingMask = []
        editor.setFrameSize(NSSize(width: visibleSize.width, height: max(visibleSize.height, editor.frame.height)))
        editor.sizeToFit()
    }

    private func updateCounts() {
        countLabel.isHidden = !showsCounts
        guard showsCounts else { return }
        let selection = editor.selectedRange()
        let source = editor.string as NSString
        let selected = selection.length > 0 && NSMaxRange(selection) <= source.length
        let text = selected ? source.substring(with: selection) : editor.string
        var words = 0
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: [.byWords, .substringNotRequired]) {
            _, _, _, _ in words += 1
        }
        let prefix = selected ? "Selection: " : ""
        countLabel.stringValue = "\(prefix)\(words) \(words == 1 ? "word" : "words") · \(text.count) \(text.count == 1 ? "character" : "characters")"
        countLabel.toolTip = "Characters include spaces and line breaks. Select text to count only that passage."
    }

    var hasRecovery: Bool { document.hasRecovery }

    func restoreLastCleared() {
        do {
            guard let recovered = try document.loadRecovery() else { return }
            if !editor.string.isEmpty {
                let alert = NSAlert()
                alert.messageText = "Replace the current pad with the last cleared text?"
                alert.informativeText = "You can undo this replacement with Command-Z. Save the current pad first if you want to keep a separate copy."
                alert.addButton(withTitle: "Restore")
                alert.addButton(withTitle: "Cancel")
                alert.window.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)
                guard alert.runModal() == .alertFirstButtonReturn else { return }
            }
            editor.replaceAll(with: recovered)
            document.saveNow()
            if let error = document.lastSaveError { throw error }
            updateCounts()
        } catch {
            presentError(error, message: "Aparte could not restore the last cleared text.")
        }
    }

    func discardRecovery() {
        let alert = NSAlert()
        alert.messageText = "Discard the recovery copy?"
        alert.informativeText = "This removes the saved copy of your last cleared text. The current pad stays as it is."
        alert.addButton(withTitle: "Discard recovery copy")
        alert.addButton(withTitle: "Cancel")
        alert.window.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do { try document.discardRecovery() }
        catch { presentError(error, message: "Aparte could not discard the recovery copy.") }
    }

    private func presentError(_ error: Error, message: String) {
        let alert = NSAlert(error: error)
        alert.messageText = message
        alert.window.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)
        alert.runModal()
    }

    @objc func saveMarkdownAs() {
        panel.makeFirstResponder(editor)
        guard !document.markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            saveButton?.acknowledge("Empty", symbol: "exclamationmark.circle", detail: "The pad is empty. Nothing was saved.")
            return
        }

        saveButton?.resetFeedback()
        let savePanel = NSSavePanel()
        savePanel.nameFieldStringValue = "\(MarkdownFileExporter.suggestedBaseName(for: document.markdown)).md"
        savePanel.allowedContentTypes = [.markdown]
        savePanel.canCreateDirectories = true
        // The pad sits above the modal panel level, so a modal Save panel can open
        // behind it. A sheet stays attached to the pad instead.
        savePanel.beginSheetModal(for: panel) { [weak self] response in
            MainActor.assumeIsolated {
                guard let self else { return }
                defer { self.panel.makeFirstResponder(self.editor) }
                guard response == .OK, let destination = savePanel.url else { return }
                do {
                    try self.document.markdown.write(to: destination, atomically: true, encoding: .utf8)
                    self.saveButton?.acknowledge("Saved", symbol: "checkmark", detail: "Saved \(destination.lastPathComponent)")
                } catch {
                    self.saveButton?.acknowledge("Failed", symbol: "exclamationmark.circle", detail: error.localizedDescription)
                    NSSound.beep()
                }
            }
        }
    }

    private func resetActionButtons() {
        [copyButton, saveButton, clearButton].forEach { $0?.resetFeedback() }
    }

    var actionButtonsForRuntimeCheck: [PadActionButton] { [copyButton, saveButton, clearButton].compactMap { $0 } }
    func copyAllForRuntimeCheck(to pasteboard: NSPasteboard) { performCopyAll(to: pasteboard) }

    func runtimeSnapshot() -> RuntimeSnapshot {
        RuntimeSnapshot(
            size: panel.frame.size,
            isVisible: panel.isVisible,
            isKey: panel.isKeyWindow,
            editorOwnsFocus: panel.firstResponder === editor,
            formattingBarIsVisible: !formattingBar.isHidden,
            editorCanScroll: editorCanScroll,
            editorHasSymmetricHorizontalPadding: editorHasSymmetricHorizontalPadding,
            level: panel.level
        )
    }

    func expectedSizeForRuntimeCheck() -> NSSize {
        guard let visibleFrame = (activeScreen() ?? NSScreen.main)?.visibleFrame else {
            return Self.preferredSize
        }
        return NSSize(
            width: min(Self.preferredSize.width, visibleFrame.width - 32),
            height: min(Self.preferredSize.height, visibleFrame.height - 32)
        )
    }

    func setMarkdownForRuntimeCheck(_ markdown: String) {
        let rendered = MarkdownCodec.render(markdown)
        editor.textStorage?.setAttributedString(rendered)
        document.textDidChange(rendered)
        updateCounts()
    }

    func selectForRuntimeCheck(_ range: NSRange) {
        editor.setSelectedRange(range)
        updateFormattingBar()
    }

    func scrollToEndForRuntimeCheck() -> Bool {
        guard let scrollView = editor.enclosingScrollView else { return false }
        editor.scrollToEndOfDocument(nil)
        scrollView.contentView.layoutSubtreeIfNeeded()
        return scrollView.contentView.bounds.origin.y > 0
    }

    func applyLinkForRuntimeCheck(_ url: URL, range: NSRange) {
        editor.applyLink(url, to: range)
    }

    func clearForRuntimeCheck() {
        editor.undoManager?.removeAllActions()
        clearPad()
    }

    var editorForRuntimeCheck: EditorTextView { editor }
    var countForRuntimeCheck: String { countLabel.stringValue }
    var countIsVisibleForRuntimeCheck: Bool {
        rootView.layoutSubtreeIfNeeded()
        return !countLabel.isHidden && countLabel.frame.width > 10 && countLabel.frame.height > 5
            && rootView.bounds.contains(countLabel.frame) && !countLabel.hasAmbiguousLayout
    }
    var zoomForRuntimeCheck: CGFloat { editor.enclosingScrollView?.magnification ?? 1 }

    func undoForRuntimeCheck() {
        editor.undoManager?.undo()
    }

    func simulateEscapeForRuntimeCheck() {
        simulateKeyForRuntimeCheck(keyCode: 53, characters: "\u{1b}")
    }

    func simulateKeyForRuntimeCheck(keyCode: UInt16, characters: String) {
        guard let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: panel.windowNumber,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        ) else { return }
        panel.firstResponder?.keyDown(with: event)
    }

    func textDidChange(_ notification: Notification) {
        guard let textStorage = editor.textStorage else { return }
        document.textDidChange(textStorage)
        updateCounts()
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        updateFormattingBar()
        updateCounts()
    }

    private func configurePanel() {
        panel.title = "Aparte"
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isReleasedWhenClosed = false
        panel.contentView = rootView
    }

    private func configureEditor() {
        editor.delegate = self
        editor.isRichText = true
        editor.importsGraphics = false
        editor.allowsUndo = true
        editor.isAutomaticQuoteSubstitutionEnabled = true
        editor.isAutomaticDashSubstitutionEnabled = true
        editor.isAutomaticSpellingCorrectionEnabled = true
        editor.isContinuousSpellCheckingEnabled = true
        editor.drawsBackground = false
        editor.textContainerInset = NSSize(width: 200, height: 120)
        editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.lineFragmentPadding = 0
        editor.typingAttributes = AparteTypography.baseAttributes
        editor.linkTextAttributes = [.foregroundColor: NSColor.linkColor, .underlineStyle: NSUnderlineStyle.single.rawValue]
        editor.textStorage?.setAttributedString(document.attributedText)
        editor.onDismiss = { [weak self] in
            guard let self else { return }
            if dismissTransientUI() { return }
            else { onDismiss?() }
        }
        editor.onSelectionChanged = { [weak self] in self?.updateFormattingBar() }
        editor.onAddLink = { [weak self] in
            self?.updateFormattingBar()
            self?.formattingBar.showLinkPopover()
        }
    }

    private func configureContent() {
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        rootView.addSubview(scrollView)

        let copyAllButton = PadActionButton(title: "Copy", symbol: "doc.on.doc",
                                           feedbackTitles: ["Copied", "Empty", "Failed"],
                                           toolTip: "Copy the whole pad without moving the cursor. More copy options are in the three-dot menu.",
                                           target: self, action: #selector(copyAll))
        let copyMenu = NSMenu()
        copyMenu.addItem(MenuCommand.copyPlain.item(target: NSApp.delegate as? NSObject))
        copyMenu.addItem(MenuCommand.copyMarkdown.item(target: NSApp.delegate as? NSObject))
        copyAllButton.menu = copyMenu
        copyAllButton.setAccessibilityLabel("Copy all")
        rootView.addSubview(copyAllButton)
        self.copyButton = copyAllButton

        let saveButton = PadActionButton(title: "Save", symbol: "arrow.down.doc",
                                         feedbackTitles: ["Saved", "Empty", "Failed"],
                                         toolTip: "Choose where to save a Markdown file",
                                         target: self, action: #selector(saveMarkdownAs))
        saveButton.setAccessibilityLabel("Save Markdown")
        rootView.addSubview(saveButton)
        self.saveButton = saveButton

        let clearButton = PadActionButton(title: "Clear", symbol: "eraser",
                                          feedbackTitles: ["Cleared", "Empty", "Failed"],
                                          toolTip: "Clear the pad. Undo with Command-Z, or restore the last cleared text from the three-dot menu.",
                                          target: self, action: #selector(clearPad))
        clearButton.setAccessibilityLabel("Clear pad")
        rootView.addSubview(clearButton)
        self.clearButton = clearButton

        let optionsButton = NSButton(image: NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "More options")!, target: self, action: #selector(showOptions(_:)))
        optionsButton.translatesAutoresizingMaskIntoConstraints = false
        optionsButton.isBordered = false
        optionsButton.bezelStyle = .inline
        optionsButton.contentTintColor = .secondaryLabelColor
        optionsButton.toolTip = "More options"
        optionsButton.setAccessibilityLabel("More options")
        rootView.addSubview(optionsButton)

        countLabel.translatesAutoresizingMaskIntoConstraints = false
        countLabel.font = .systemFont(ofSize: 11)
        countLabel.textColor = .secondaryLabelColor
        countLabel.lineBreakMode = .byTruncatingTail
        countLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        rootView.addSubview(countLabel)

        formattingBar.isHidden = true
        rootView.addSubview(formattingBar)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: rootView.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: copyAllButton.topAnchor, constant: -8),
            copyAllButton.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 16),
            copyAllButton.bottomAnchor.constraint(equalTo: rootView.bottomAnchor, constant: -8),
            saveButton.leadingAnchor.constraint(equalTo: copyAllButton.trailingAnchor, constant: 12),
            saveButton.centerYAnchor.constraint(equalTo: copyAllButton.centerYAnchor),
            clearButton.leadingAnchor.constraint(equalTo: saveButton.trailingAnchor, constant: 12),
            clearButton.centerYAnchor.constraint(equalTo: saveButton.centerYAnchor),
            countLabel.leadingAnchor.constraint(greaterThanOrEqualTo: clearButton.trailingAnchor, constant: 16),
            countLabel.trailingAnchor.constraint(equalTo: optionsButton.leadingAnchor, constant: -10),
            optionsButton.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -12),
            optionsButton.centerYAnchor.constraint(equalTo: copyAllButton.centerYAnchor),
            optionsButton.widthAnchor.constraint(equalToConstant: 28),
            optionsButton.heightAnchor.constraint(equalToConstant: 20),
            countLabel.centerYAnchor.constraint(equalTo: copyAllButton.centerYAnchor),
        ])

        rootView.layoutSubtreeIfNeeded()
        let visibleSize = scrollView.contentSize
        editor.frame = NSRect(origin: .zero, size: visibleSize)
        editor.minSize = NSSize(width: 0, height: visibleSize.height)
        editor.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.textContainer?.containerSize = NSSize(
            width: max(1, visibleSize.width - editor.textContainerInset.width * 2),
            height: CGFloat.greatestFiniteMagnitude
        )
        editor.textContainer?.widthTracksTextView = true
        scrollView.documentView = editor
    }

    private var editorCanScroll: Bool {
        guard let scrollView = editor.enclosingScrollView else { return false }
        return editor.frame.height > scrollView.contentView.bounds.height + 1
    }

    private var editorHasSymmetricHorizontalPadding: Bool {
        guard let textContainer = editor.textContainer else { return false }
        let expectedWidth = max(1, editor.bounds.width - editor.textContainerInset.width * 2)
        return abs(textContainer.containerSize.width - expectedWidth) < 1
    }

    private func updateFormattingBar() {
        let selection = editor.selectedRange()
        guard selection.length > 0, panel.isVisible, !isOptionsMenuOpen else {
            formattingBar.isHidden = true
            return
        }

        var actualRange = NSRange()
        let screenRect = editor.firstRect(forCharacterRange: selection, actualRange: &actualRange)
        let windowRect = panel.convertFromScreen(screenRect)
        let selectionRect = rootView.convert(windowRect, from: nil)
        let barSize = formattingBar.frame.size
        let x = min(max(12, selectionRect.midX - barSize.width / 2), rootView.bounds.width - barSize.width - 12)
        var y = selectionRect.maxY + 8
        if y + barSize.height > rootView.bounds.height - 8 {
            y = max(40, selectionRect.minY - barSize.height - 8)
        }
        formattingBar.setFrameOrigin(NSPoint(x: x, y: y))
        formattingBar.isHidden = false
    }

    private func activeScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main
    }
}

@MainActor
final class PadActionButton: NSButton {
    private let restingTitle: String
    private let restingSymbol: String
    private let restingToolTip: String
    private var reservedWidth: CGFloat = 0
    private var hoverArea: NSTrackingArea?
    private var isHovered = false
    private var feedbackReset: DispatchWorkItem?
    private var feedbackGeneration: UInt = 0

    init(title: String, symbol: String, feedbackTitles: [String], toolTip: String,
         target: AnyObject, action: Selector) {
        restingTitle = title
        restingSymbol = symbol
        restingToolTip = toolTip
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        isBordered = false
        bezelStyle = .inline
        setButtonType(.momentaryChange)
        font = .systemFont(ofSize: 11, weight: .medium)
        contentTintColor = .secondaryLabelColor
        imagePosition = .imageLeading
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        self.target = target
        self.action = action
        // Keep all three hit targets in place when a result replaces a label.
        for candidate in [title] + feedbackTitles {
            self.title = candidate
            for candidateSymbol in [symbol, "checkmark", "exclamationmark.circle"] {
                image = NSImage(systemSymbolName: candidateSymbol, accessibilityDescription: nil)
                reservedWidth = max(reservedWidth, super.intrinsicContentSize.width + 12)
            }
        }
        resetFeedback()
    }

    required init?(coder: NSCoder) { nil }
    override var acceptsFirstResponder: Bool { isEnabled }
    override var mouseDownCanMoveWindow: Bool { false }
    override var intrinsicContentSize: NSSize { NSSize(width: reservedWidth, height: 26) }
    // SF Symbols have different optical insets. Feedback must not move the hit target.
    override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsetsZero }

    func acknowledge(_ title: String, symbol: String, detail: String) {
        feedbackReset?.cancel()
        feedbackGeneration &+= 1
        let generation = feedbackGeneration
        self.title = title
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        toolTip = detail
        setAccessibilityValue(detail)
        NSAccessibility.post(element: self, notification: .valueChanged)
        let reset = DispatchWorkItem { [weak self] in
            guard let self, self.feedbackGeneration == generation else { return }
            self.resetFeedback()
        }
        feedbackReset = reset
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: reset)
    }

    func resetFeedback() {
        feedbackGeneration &+= 1
        feedbackReset?.cancel()
        feedbackReset = nil
        title = restingTitle
        image = NSImage(systemSymbolName: restingSymbol, accessibilityDescription: nil)
        toolTip = restingToolTip
        setAccessibilityValue(nil)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        hoverArea = area
        // Layout or reopening the pad can move a button under a stationary pointer.
        isHovered = window.map { bounds.contains(convert($0.mouseLocationOutsideOfEventStream, from: nil)) } ?? false
        needsDisplay = true
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { isHovered = false; needsDisplay = true }

    override func highlight(_ flag: Bool) {
        super.highlight(flag)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        if isEnabled && (isHovered || isHighlighted || window?.firstResponder === self) {
            NSColor.labelColor.withAlphaComponent(isHighlighted ? 0.16 : 0.07).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
        }
        super.draw(dirtyRect)
    }
}

private extension UTType {
    static var markdown: UTType {
        UTType(filenameExtension: "md") ?? .plainText
    }
}

@MainActor
private final class ApartePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
private final class PadBackgroundView: NSView {
    weak var optionsAccessibilityView: NSView?
    override var isOpaque: Bool { false }

    // AppKit owns the heterogeneous accessibility tree; preserve its default filtering when the card closes.
    override func accessibilityChildren() -> [Any]? {
        if let optionsAccessibilityView { return [optionsAccessibilityView] }
        return super.accessibilityChildren()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        wantsLayer = true
        layer?.cornerRadius = 18
        layer?.masksToBounds = true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        NSColor.separatorColor.withAlphaComponent(0.45).setStroke()
        let border = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 18, yRadius: 18)
        border.lineWidth = 1
        border.stroke()
    }
}
