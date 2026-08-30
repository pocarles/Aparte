import AppKit
import AparteCore

@MainActor
final class FormattingBar: NSVisualEffectView {
    init(editor: EditorTextView) {
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
        stack.addArrangedSubview(button("Link", help: "Add link") { [weak self] in self?.promptForLink(editor: editor) })

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

    private func promptForLink(editor: EditorTextView) {
        guard editor.selectedRange().length > 0 else { return }
        let alert = NSAlert()
        alert.messageText = "Add link"
        alert.informativeText = "Enter a complete web address."
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(string: "https://")
        field.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
        alert.accessoryView = field
        if alert.runModal() == .alertFirstButtonReturn, let url = URL(string: field.stringValue) {
            editor.applyLink(url)
        }
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

