import AppKit
import AparteCore

@MainActor
final class PadWindowController: NSObject, NSTextViewDelegate {
    private static let preferredSize = NSSize(width: 660, height: 520)
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
        editor.textContainerInset = NSSize(width: 38, height: 34)
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
        scrollView.documentView = editor

        editor.translatesAutoresizingMaskIntoConstraints = false
        rootView.addSubview(scrollView)

        let footer = NSTextField(labelWithString: "Markdown · local")
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
            editor.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            editor.heightAnchor.constraint(greaterThanOrEqualTo: scrollView.contentView.heightAnchor),
            footer.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -20),
            footer.bottomAnchor.constraint(equalTo: rootView.bottomAnchor, constant: -13),
        ])
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

