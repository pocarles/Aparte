import AppKit
import AparteCore

@MainActor
final class FormattingBar: NSVisualEffectView, NSPopoverDelegate {
    private weak var editor: EditorTextView?
    private weak var linkButton: NSButton?
    private weak var linkField: NSTextField?
    private weak var linkError: NSTextField?
    private var linkSelection: NSRange?
    private var linkPopover: NSPopover?

    init(editor: EditorTextView) {
        self.editor = editor
        super.init(frame: NSRect(x: 0, y: 0, width: 286, height: 38))
        material = .menu
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.masksToBounds = true

        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 2
        addSubview(stack)

        let bold = button("B", help: "Bold") { editor.toggleBold(nil) }
        bold.font = .systemFont(ofSize: 13, weight: .bold)
        let italic = button("I", help: "Italic") { editor.toggleItalic(nil) }
        italic.font = NSFontManager.shared.convert(.systemFont(ofSize: 13), toHaveTrait: .italicFontMask)
        let underline = button("U", help: "Underline") { editor.toggleUnderline(nil) }
        underline.attributedTitle = NSAttributedString(
            string: "U",
            attributes: [.font: NSFont.systemFont(ofSize: 13), .underlineStyle: NSUnderlineStyle.single.rawValue]
        )

        stack.addArrangedSubview(bold)
        stack.addArrangedSubview(italic)
        stack.addArrangedSubview(underline)
        stack.addArrangedSubview(separator())
        stack.addArrangedSubview(button("H1", help: "Heading") { editor.applyHeading(level: 1) })
        stack.addArrangedSubview(button("•", help: "Bulleted list") { editor.applyList(.unordered) })
        stack.addArrangedSubview(button("1.", help: "Numbered list") { editor.applyList(.ordered) })
        stack.addArrangedSubview(separator())
        let link = button("Link", help: "Add link") { [weak self] in self?.showLinkPopover() }
        linkButton = link
        stack.addArrangedSubview(link)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    private func button(_ title: String, help: String, action: @escaping () -> Void) -> NSButton {
        let button = ClosureButton(title: title, action: action)
        button.isBordered = false
        button.bezelStyle = .inline
        button.font = .systemFont(ofSize: 12, weight: .medium)
        button.toolTip = help
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: title == "Link" ? 42 : 28).isActive = true
        return button
    }

    private func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        box.widthAnchor.constraint(equalToConstant: 1).isActive = true
        box.heightAnchor.constraint(equalToConstant: 18).isActive = true
        return box
    }

    private func showLinkPopover() {
        guard let editor, let linkButton else { return }
        let selection = editor.selectedRange()
        guard selection.length > 0 else { return }

        linkPopover?.performClose(nil)
        linkSelection = selection

        let content = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 94))
        let field = NSTextField(string: clipboardLinkSuggestion() ?? "")
        field.translatesAutoresizingMaskIntoConstraints = false
        field.placeholderString = "example.com"
        field.setAccessibilityLabel("Web address")
        content.addSubview(field)
        linkField = field

        let error = NSTextField(labelWithString: "")
        error.translatesAutoresizingMaskIntoConstraints = false
        error.font = .systemFont(ofSize: 11)
        error.textColor = .systemRed
        error.isHidden = true
        content.addSubview(error)
        linkError = error

        let cancel = ClosureButton(title: "Cancel") { [weak self] in self?.closeLinkPopover() }
        cancel.translatesAutoresizingMaskIntoConstraints = false
        cancel.bezelStyle = .rounded
        content.addSubview(cancel)

        let add = ClosureButton(title: "Add") { [weak self] in self?.applyPendingLink() }
        add.translatesAutoresizingMaskIntoConstraints = false
        add.bezelStyle = .rounded
        add.keyEquivalent = "\r"
        content.addSubview(add)

        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            field.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            field.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            error.leadingAnchor.constraint(equalTo: field.leadingAnchor),
            error.centerYAnchor.constraint(equalTo: cancel.centerYAnchor),
            cancel.trailingAnchor.constraint(equalTo: add.leadingAnchor, constant: -8),
            cancel.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -10),
            add.trailingAnchor.constraint(equalTo: field.trailingAnchor),
            add.bottomAnchor.constraint(equalTo: cancel.bottomAnchor),
        ])

        let controller = NSViewController()
        controller.view = content
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = content.frame.size
        popover.contentViewController = controller
        popover.delegate = self
        linkPopover = popover
        popover.show(relativeTo: linkButton.bounds, of: linkButton, preferredEdge: .maxY)
        linkButton.window?.makeFirstResponder(field)
        field.selectText(nil)
    }

    private func applyPendingLink() {
        guard
            let editor,
            let linkSelection,
            let field = linkField,
            let url = LinkURLNormalizer.normalize(field.stringValue)
        else {
            linkError?.stringValue = "Enter a valid web address."
            linkError?.isHidden = false
            NSSound.beep()
            return
        }

        editor.applyLink(url, to: linkSelection)
        closeLinkPopover()
        editor.window?.makeFirstResponder(editor)
    }

    private func closeLinkPopover() {
        linkPopover?.performClose(nil)
        linkPopover = nil
        linkSelection = nil
    }

    private func clipboardLinkSuggestion() -> String? {
        let pasteboard = NSPasteboard.general
        for type in [NSPasteboard.PasteboardType.URL, .string] {
            guard let value = pasteboard.string(forType: type) else { continue }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if LinkURLNormalizer.normalize(trimmed) != nil {
                return trimmed
            }
        }
        return nil
    }

    func popoverDidClose(_ notification: Notification) {
        linkPopover = nil
        linkSelection = nil
    }
}

@MainActor
private final class ClosureButton: NSButton {
    private let closure: () -> Void

    init(title: String, action: @escaping () -> Void) {
        self.closure = action
        super.init(frame: .zero)
        self.title = title
        target = self
        self.action = #selector(runAction)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    @objc private func runAction() { closure() }
}
