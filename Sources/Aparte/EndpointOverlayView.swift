import AppKit

/// The address field for Send to endpoint, presented as a card inside the pad.
@MainActor
final class EndpointOverlayView: NSView, NSTextFieldDelegate {
    private static let cardWidth: CGFloat = 460
    private static let restingHint = "Return to send · Esc to cancel"
    private let card = OptionsCardView()
    private let addressWell = EndpointAddressWell()
    private let statusLabel = NSTextField(labelWithString: EndpointOverlayView.restingHint)
    private let field: NSTextField

    var onCancel: (() -> Void)?
    var onSubmit: ((String) -> Void)?
    var addressField: NSTextField { field }

    override var acceptsFirstResponder: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    init(address: String, summary: String) {
        field = NSTextField(string: address)
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Send to endpoint")

        card.translatesAutoresizingMaskIntoConstraints = false
        addSubview(card)

        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        card.addSubview(stack)

        let title = NSTextField(labelWithString: "Send to endpoint")
        title.font = .systemFont(ofSize: 14, weight: .semibold)
        title.textColor = .labelColor
        title.setContentHuggingPriority(.required, for: .horizontal)
        title.setContentCompressionResistancePriority(.required, for: .horizontal)

        let summaryLabel = NSTextField(labelWithString: summary)
        summaryLabel.font = .systemFont(ofSize: 11)
        summaryLabel.textColor = .secondaryLabelColor
        summaryLabel.alignment = .right
        summaryLabel.lineBreakMode = .byTruncatingTail
        summaryLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        summaryLabel.setAccessibilityLabel(summary)

        let header = NSView()
        header.translatesAutoresizingMaskIntoConstraints = false
        title.translatesAutoresizingMaskIntoConstraints = false
        summaryLabel.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(title)
        header.addSubview(summaryLabel)
        stack.addArrangedSubview(header)

        addressWell.translatesAutoresizingMaskIntoConstraints = false
        field.translatesAutoresizingMaskIntoConstraints = false
        field.font = .systemFont(ofSize: 15)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.placeholderString = "Paste a webhook address"
        field.lineBreakMode = .byTruncatingTail
        field.delegate = self
        field.setAccessibilityLabel("Endpoint address")
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        addressWell.addSubview(field)
        stack.addArrangedSubview(addressWell)
        stack.setCustomSpacing(8, after: addressWell)

        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .tertiaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.maximumNumberOfLines = 1
        stack.addArrangedSubview(statusLabel)

        let send = NSButton(title: "Send", target: self, action: #selector(submit))
        send.bezelStyle = .rounded
        send.keyEquivalent = "\r"
        (send.cell as? NSButtonCell)?.keyEquivalent = "\r"
        send.toolTip = "Send the Markdown to this address"
        send.setAccessibilityLabel("Send")
        send.translatesAutoresizingMaskIntoConstraints = false
        let buttonRow = NSView()
        buttonRow.translatesAutoresizingMaskIntoConstraints = false
        buttonRow.addSubview(send)
        stack.addArrangedSubview(buttonRow)

        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: centerXAnchor),
            card.centerYAnchor.constraint(equalTo: centerYAnchor),
            card.widthAnchor.constraint(equalToConstant: Self.cardWidth),
            card.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 16),
            card.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),
            card.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 16),
            card.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -16),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -24),
            header.widthAnchor.constraint(equalTo: stack.widthAnchor),
            title.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            title.topAnchor.constraint(equalTo: header.topAnchor),
            title.bottomAnchor.constraint(equalTo: header.bottomAnchor),
            summaryLabel.firstBaselineAnchor.constraint(equalTo: title.firstBaselineAnchor),
            summaryLabel.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            summaryLabel.leadingAnchor.constraint(greaterThanOrEqualTo: title.trailingAnchor, constant: 12),
            addressWell.widthAnchor.constraint(equalTo: stack.widthAnchor),
            field.leadingAnchor.constraint(equalTo: addressWell.leadingAnchor, constant: 12),
            field.trailingAnchor.constraint(equalTo: addressWell.trailingAnchor, constant: -12),
            field.topAnchor.constraint(equalTo: addressWell.topAnchor, constant: 10),
            field.bottomAnchor.constraint(equalTo: addressWell.bottomAnchor, constant: -10),
            statusLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            buttonRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            send.trailingAnchor.constraint(equalTo: buttonRow.trailingAnchor),
            send.topAnchor.constraint(equalTo: buttonRow.topAnchor),
            send.bottomAnchor.constraint(equalTo: buttonRow.bottomAnchor),
            send.leadingAnchor.constraint(greaterThanOrEqualTo: buttonRow.leadingAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    func showError(_ message: String) {
        statusLabel.stringValue = message
        statusLabel.textColor = .systemRed
    }

    func controlTextDidBeginEditing(_ obj: Notification) {
        addressWell.isFocused = true
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        addressWell.isFocused = false
    }

    func controlTextDidChange(_ obj: Notification) {
        statusLabel.stringValue = Self.restingHint
        statusLabel.textColor = .tertiaryLabelColor
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard commandSelector == #selector(NSResponder.cancelOperation(_:)) else { return false }
        onCancel?()
        return true
    }

    @objc private func submit() { onSubmit?(field.stringValue) }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.08).setFill()
        bounds.fill()
    }

    override func mouseDown(with event: NSEvent) { onCancel?() }
    override func rightMouseDown(with event: NSEvent) { onCancel?() }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
        } else {
            super.keyDown(with: event)
        }
    }
}

@MainActor
private final class EndpointAddressWell: NSView {
    var isFocused = false {
        didSet { needsDisplay = true }
    }

    override var mouseDownCanMoveWindow: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let lineWidth: CGFloat = isFocused ? 1.5 : 1
        let outline = NSBezierPath(roundedRect: bounds.insetBy(dx: lineWidth / 2, dy: lineWidth / 2), xRadius: 8, yRadius: 8)
        NSColor.controlBackgroundColor.setFill()
        outline.fill()
        if isFocused {
            NSColor.controlAccentColor.setStroke()
        } else {
            NSColor.separatorColor.withAlphaComponent(0.6).setStroke()
        }
        outline.lineWidth = lineWidth
        outline.stroke()
    }
}
