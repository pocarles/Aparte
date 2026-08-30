import AppKit
import AparteCore

@MainActor
final class PadWindowController: NSObject, NSTextViewDelegate {
    struct RuntimeSnapshot {
        let size: NSSize
        let isVisible: Bool
        let isKey: Bool
        let editorOwnsFocus: Bool
        let formattingBarIsVisible: Bool
        let editorCanScroll: Bool
        let level: NSWindow.Level
    }

    private static let preferredSize = NSSize(width: 860, height: 680)
    private let document: DocumentController
    private let panel: ApartePanel
    private let editor: EditorTextView
    private let rootView: PadBackgroundView
    private let formattingBar: FormattingBar
    var onDismiss: (() -> Void)?

    var isVisible: Bool { panel.isVisible }

    init(document: DocumentController) {
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
    }

    func show() {
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
        formattingBar.isHidden = true
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
    }

    func copyMarkdown() {
        editor.copyAsMarkdown(nil)
    }

    @objc private func copyAll() {
        panel.makeFirstResponder(editor)
        editor.selectAll(nil)
        editor.copy(nil)
        updateFormattingBar()
    }

    func runtimeSnapshot() -> RuntimeSnapshot {
        RuntimeSnapshot(
            size: panel.frame.size,
            isVisible: panel.isVisible,
            isKey: panel.isKeyWindow,
            editorOwnsFocus: panel.firstResponder === editor,
            formattingBarIsVisible: !formattingBar.isHidden,
            editorCanScroll: editorCanScroll,
            level: panel.level
        )
    }

    func setMarkdownForRuntimeCheck(_ markdown: String) {
        let rendered = MarkdownCodec.render(markdown)
        editor.textStorage?.setAttributedString(rendered)
        document.textDidChange(rendered)
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

    func simulateEscapeForRuntimeCheck() {
        guard let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: panel.windowNumber,
            context: nil,
            characters: "\u{1b}",
            charactersIgnoringModifiers: "\u{1b}",
            isARepeat: false,
            keyCode: 53
        ) else { return }
        editor.keyDown(with: event)
    }

    func textDidChange(_ notification: Notification) {
        guard let textStorage = editor.textStorage else { return }
        document.textDidChange(textStorage)
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        updateFormattingBar()
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
        editor.textContainerInset = NSSize(width: 82, height: 62)
        editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.lineFragmentPadding = 0
        editor.typingAttributes = AparteTypography.baseAttributes
        editor.linkTextAttributes = [.foregroundColor: NSColor.linkColor, .underlineStyle: NSUnderlineStyle.single.rawValue]
        editor.textStorage?.setAttributedString(document.attributedText)
        editor.onDismiss = { [weak self] in self?.onDismiss?() }
        editor.onSelectionChanged = { [weak self] in self?.updateFormattingBar() }
    }

    private func configureContent() {
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        rootView.addSubview(scrollView)

        let copyAllButton = NSButton(title: "Copy all", target: self, action: #selector(copyAll))
        copyAllButton.translatesAutoresizingMaskIntoConstraints = false
        copyAllButton.isBordered = false
        copyAllButton.bezelStyle = .inline
        copyAllButton.font = .systemFont(ofSize: 11, weight: .medium)
        copyAllButton.contentTintColor = .secondaryLabelColor
        copyAllButton.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
        copyAllButton.imagePosition = .imageLeading
        copyAllButton.toolTip = "Select everything and copy"
        copyAllButton.setAccessibilityLabel("Copy all")
        rootView.addSubview(copyAllButton)

        let footer = NSTextField(labelWithString: "Esc closes  ·  ⇧⌘C copies Markdown")
        footer.translatesAutoresizingMaskIntoConstraints = false
        footer.font = .systemFont(ofSize: 11, weight: .medium)
        footer.textColor = .tertiaryLabelColor
        rootView.addSubview(footer)

        formattingBar.isHidden = true
        rootView.addSubview(formattingBar)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: rootView.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -8),
            copyAllButton.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 16),
            copyAllButton.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
            footer.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -20),
            footer.bottomAnchor.constraint(equalTo: rootView.bottomAnchor, constant: -13),
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
            width: visibleSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )
        editor.textContainer?.widthTracksTextView = true
        scrollView.documentView = editor
    }

    private var editorCanScroll: Bool {
        guard let scrollView = editor.enclosingScrollView else { return false }
        return editor.frame.height > scrollView.contentView.bounds.height + 1
    }

    private func updateFormattingBar() {
        let selection = editor.selectedRange()
        guard selection.length > 0, panel.isVisible else {
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
private final class ApartePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
private final class PadBackgroundView: NSView {
    override var isOpaque: Bool { false }

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
