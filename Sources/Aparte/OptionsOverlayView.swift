import AppKit

/// The footer and status menu share their actions and validation. Only their presentation differs.
@MainActor
final class OptionsOverlayView: NSView {
    private static let cardWidth: CGFloat = 420
    private static let scrollbarGutter: CGFloat = 18
    let card = OptionsCardView()
    private(set) var actionButtons: [OptionsActionButton] = []
    var onDismiss: (() -> Void)?
    var onChoose: ((NSMenuItem) -> Void)?

    private let scrollView = NSScrollView()
    private let documentView = OptionsDocumentView()
    private let contentStack = NSStackView()
    private var cardHeightConstraint: NSLayoutConstraint!
    private var isLayingOut = false
    private var hasPositionedDocument = false

    private struct ActionEntry {
        let button: OptionsActionButton
        let row: OptionsActionRowView
        let groups: [OptionsGroupView]
    }

    private var actionEntries: [ActionEntry] = []
    private var groupEntries: [(group: OptionsGroupView, parents: [OptionsGroupView])] = []
    private var focusOrder: [NSView] = []

    override var acceptsFirstResponder: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    var hasUsableContentLayoutForRuntimeCheck: Bool {
        let expectedWidth = max(1, (card.bounds.width > 1 ? card.bounds.width : Self.cardWidth) - 40)
        let visibleEntries = actionEntries.filter { !$0.row.isHidden }
        return abs(documentView.bounds.width - expectedWidth) < 2 &&
            visibleEntries.allSatisfy { $0.row.bounds.width > 40 && $0.button.bounds.width > 40 }
    }

    init(menu: NSMenu) {
        super.init(frame: .zero)
        menu.update()
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Writing options")

        card.translatesAutoresizingMaskIntoConstraints = false
        addSubview(card)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.verticalScrollElasticity = .allowed
        scrollView.documentView = documentView
        card.addSubview(scrollView)

        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 4
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(contentStack)

        let title = NSTextField(labelWithString: "Writing options")
        title.font = .systemFont(ofSize: 14, weight: .semibold)
        title.textColor = .labelColor
        contentStack.addArrangedSubview(title)
        contentStack.setCustomSpacing(12, after: title)

        buildItems(menu.items, into: contentStack, groups: [])
        refreshActionVisibility()

        cardHeightConstraint = card.heightAnchor.constraint(equalToConstant: 220)
        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: centerXAnchor),
            card.centerYAnchor.constraint(equalTo: centerYAnchor),
            card.widthAnchor.constraint(equalToConstant: Self.cardWidth),
            card.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 16),
            card.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),
            card.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 16),
            card.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -16),
            cardHeightConstraint,
            scrollView.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
            scrollView.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),
            scrollView.topAnchor.constraint(equalTo: card.topAnchor, constant: 20),
            scrollView.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16),
            contentStack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -Self.scrollbarGutter),
            contentStack.topAnchor.constraint(equalTo: documentView.topAnchor),
            contentStack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor),
        ])

        if actionEntries.isEmpty {
            let empty = NSTextField(labelWithString: "No options available")
            empty.textColor = .secondaryLabelColor
            contentStack.addArrangedSubview(empty)
        }
    }

    required init?(coder: NSCoder) { nil }

    private func buildItems(_ items: [NSMenuItem], into stack: NSStackView, groups: [OptionsGroupView]) {
        for item in items {
            guard !item.isHidden else { continue }
            if item.isSeparatorItem {
                let divider = NSBox()
                divider.boxType = .separator
                divider.translatesAutoresizingMaskIntoConstraints = false
                stack.addArrangedSubview(divider)
                divider.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
                stack.setCustomSpacing(8, after: divider)
            } else if let submenu = item.submenu {
                submenu.update()
                let group = OptionsGroupView(title: item.title, initiallyExpanded: isExpandedByDefault(item))
                groupEntries.append((group: group, parents: groups))
                focusOrder.append(group.header)
                group.onDismiss = { [weak self] in self?.onDismiss?() }
                group.onExpansionChanged = { [weak self, weak group] in
                    guard let self, let group else { return }
                    if group.isExpanded {
                        for entry in groupEntries where entry.group !== group {
                            entry.group.setExpanded(false, notify: false)
                        }
                    }
                    refreshActionVisibility()
                    if let focusedView = window?.firstResponder as? NSView, focusedView.isHiddenOrHasHiddenAncestor {
                        window?.makeFirstResponder(group.header)
                    }
                }
                stack.addArrangedSubview(group)
                group.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
                buildItems(submenu.items, into: group.contentStack, groups: groups + [group])
                group.finishBuilding()
            } else {
                let row = makeActionRow(item, groups: groups)
                stack.addArrangedSubview(row)
                row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
                if let button = row.button { focusOrder.append(button) }
            }
        }
    }

    private func isExpandedByDefault(_ item: NSMenuItem) -> Bool {
        item.title == "Text size"
    }

    var expandedGroupsForRuntimeCheck: [String] {
        groupEntries.filter { $0.group.isExpanded }.map { $0.group.header.title }
    }

    func toggleGroupForRuntimeCheck(_ title: String) {
        groupEntries.first { $0.group.header.title == title }?.group.header.performClick(nil)
        layoutSubtreeIfNeeded()
    }

    var shortcutsClearScrollbarForRuntimeCheck: Bool {
        let visibleRows = actionEntries.filter { !$0.row.isHidden }.map(\.row)
        return !visibleRows.isEmpty && visibleRows.allSatisfy { row in
            guard let hint = row.subviews.first(where: { $0 is OptionsShortcutLabel }) else { return false }
            return documentView.bounds.maxX - hint.convert(hint.bounds, to: documentView).maxX >= Self.scrollbarGutter
        }
    }

    private func makeActionRow(_ item: NSMenuItem, groups: [OptionsGroupView]) -> OptionsActionRowView {
        let row = OptionsActionRowView()
        let button = makeButton(item)
        let hint = OptionsShortcutLabel(string: MenuCommand.shortcutLabel(for: item))
        hint.onClick = { [weak button] in button?.performClick(nil) }
        row.onClick = { [weak button] in button?.performClick(nil) }
        row.button = button
        row.addSubview(button)
        row.addSubview(hint)
        button.translatesAutoresizingMaskIntoConstraints = false
        hint.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 30),
            button.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            button.topAnchor.constraint(equalTo: row.topAnchor),
            button.bottomAnchor.constraint(equalTo: row.bottomAnchor),
            button.trailingAnchor.constraint(lessThanOrEqualTo: hint.leadingAnchor, constant: -8),
            hint.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -2),
            hint.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            hint.widthAnchor.constraint(greaterThanOrEqualToConstant: 42),
        ])
        actionEntries.append(ActionEntry(button: button, row: row, groups: groups))
        return row
    }

    private func makeButton(_ item: NSMenuItem) -> OptionsActionButton {
        let button = OptionsActionButton(item: item)
        button.onChoose = { [weak self] in self?.onChoose?(item) }
        button.onDismiss = { [weak self] in self?.onDismiss?() }
        actionButtons.append(button)
        return button
    }

    private func refreshActionVisibility() {
        for entry in groupEntries {
            entry.group.isHidden = !entry.parents.allSatisfy(\.isExpanded)
        }
        for entry in actionEntries {
            let isVisible = entry.groups.allSatisfy(\.isExpanded)
            entry.button.isHidden = !isVisible
            entry.row.isHidden = !isVisible
        }

        let focusable = focusOrder.filter { view in
            if let button = view as? OptionsActionButton {
                return !button.isHidden && button.isEnabled
            }
            guard let header = view as? NSButton,
                  let group = groupEntries.first(where: { $0.group.header === header }) else { return false }
            return !group.group.isHidden
        }
        for (index, view) in focusable.enumerated() {
            view.nextKeyView = focusable[(index + 1) % focusable.count]
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        guard !isLayingOut else { return }
        isLayingOut = true

        let documentWidth = max(1, (card.bounds.width > 1 ? card.bounds.width : Self.cardWidth) - 40)
        documentView.frame = NSRect(x: 0, y: 0, width: documentWidth, height: 1)
        documentView.layoutSubtreeIfNeeded()
        let contentHeight = max(1, contentStack.fittingSize.height)
        documentView.frame = NSRect(x: 0, y: 0, width: documentWidth, height: contentHeight)
        if !hasPositionedDocument {
            scrollView.contentView.scroll(to: .zero)
            scrollView.reflectScrolledClipView(scrollView.contentView)
            hasPositionedDocument = true
        }

        let availableHeight = max(176, bounds.height - 32)
        let preferredHeight = contentHeight + 36
        let nextHeight = min(availableHeight, preferredHeight)
        if abs(cardHeightConstraint.constant - nextHeight) > 0.5 {
            cardHeightConstraint.constant = nextHeight
            super.layout()
        }
        isLayingOut = false
    }

    /// The parent can call this before the application menu sees a key event. NSButton
    /// performs the same key-equivalent matching AppKit uses for regular menus.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        for entry in actionEntries where entry.button.isEnabled {
            if !entry.button.isHidden && entry.button.performKeyEquivalent(with: event) { return true }
            if entry.button.matchesKeyEquivalent(event) {
                entry.button.invokeActionIfEnabled()
                return true
            }
        }
        return super.performKeyEquivalent(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.08).setFill()
        bounds.fill()
    }

    override func mouseDown(with event: NSEvent) { onDismiss?() }
    override func rightMouseDown(with event: NSEvent) { onDismiss?() }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onDismiss?()
        } else if event.keyCode == 48 || event.keyCode == 125 {
            if let view = focusOrder.first(where: {
                if let button = $0 as? OptionsActionButton { return !button.isHidden && button.isEnabled }
                if let header = $0 as? NSButton,
                   let group = groupEntries.first(where: { $0.group.header === header }) {
                    return !group.group.isHidden
                }
                return false
            }) {
                window?.makeFirstResponder(view)
            }
        } else {
            super.keyDown(with: event)
        }
    }
}

@MainActor
final class OptionsDocumentView: NSView {
    override var isFlipped: Bool { true }
}

@MainActor
final class OptionsCardView: NSView {
    override var mouseDownCanMoveWindow: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let outline = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 16, yRadius: 16)
        NSColor.windowBackgroundColor.setFill()
        outline.fill()
        NSColor.separatorColor.withAlphaComponent(0.45).setStroke()
        outline.stroke()
    }

    // Blank space inside the card consumes clicks instead of dismissing it.
    override func mouseDown(with event: NSEvent) { }
    override func rightMouseDown(with event: NSEvent) { }
}

@MainActor
final class OptionsGroupView: NSView {
    let contentStack = NSStackView()
    var onExpansionChanged: (() -> Void)?
    var onDismiss: (() -> Void)? {
        didSet { header.onDismiss = { [weak self] in self?.onDismiss?() } }
    }
    private(set) var header: OptionsGroupButton
    private(set) var isExpanded: Bool

    init(title: String, initiallyExpanded: Bool) {
        self.isExpanded = initiallyExpanded
        self.header = OptionsGroupButton(title: title, target: nil, action: nil)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(title)

        header.translatesAutoresizingMaskIntoConstraints = false
        header.target = self
        header.action = #selector(toggle)
        header.isBordered = false
        header.bezelStyle = .inline
        header.alignment = .left
        header.font = .systemFont(ofSize: 12, weight: .semibold)
        header.contentTintColor = .secondaryLabelColor
        header.imagePosition = .imageLeading
        header.imageScaling = .scaleProportionallyDown
        header.image = Self.disclosureImage(expanded: initiallyExpanded)
        header.setAccessibilityLabel("\(title), \(initiallyExpanded ? "expanded" : "collapsed")")
        header.onExpand = { [weak self] in self?.setExpanded(true) }
        header.onCollapse = { [weak self] in self?.setExpanded(false) }

        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 4
        contentStack.isHidden = !initiallyExpanded

        addSubview(header)
        addSubview(contentStack)
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: leadingAnchor),
            header.trailingAnchor.constraint(equalTo: trailingAnchor),
            header.topAnchor.constraint(equalTo: topAnchor),
            header.heightAnchor.constraint(equalToConstant: 26),
            contentStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentStack.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 2),
            contentStack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { nil }

    func finishBuilding() {
        contentStack.isHidden = !isExpanded
    }

    @objc private func toggle() {
        setExpanded(!isExpanded)
    }

    func setExpanded(_ expanded: Bool, notify: Bool = true) {
        guard isExpanded != expanded else { return }
        isExpanded = expanded
        contentStack.isHidden = !isExpanded
        header.image = Self.disclosureImage(expanded: isExpanded)
        header.setAccessibilityLabel("\(header.title), \(isExpanded ? "expanded" : "collapsed")")
        if notify { onExpansionChanged?() }
    }

    private static func disclosureImage(expanded: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 24, height: 14), flipped: false) { _ in
            let path = NSBezierPath()
            if expanded {
                path.move(to: NSPoint(x: 4, y: 8.5))
                path.line(to: NSPoint(x: 7, y: 5.5))
                path.line(to: NSPoint(x: 10, y: 8.5))
            } else {
                path.move(to: NSPoint(x: 5.5, y: 4))
                path.line(to: NSPoint(x: 8.5, y: 7))
                path.line(to: NSPoint(x: 5.5, y: 10))
            }
            path.lineWidth = 1
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            NSColor.black.setStroke()
            path.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }
}

@MainActor
final class OptionsGroupButton: NSButton {
    var onDismiss: (() -> Void)?
    var onExpand: (() -> Void)?
    var onCollapse: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53:
            onDismiss?()
        case 48:
            if event.modifierFlags.contains(.shift) { window?.selectPreviousKeyView(self) }
            else { window?.selectNextKeyView(self) }
        case 125:
            window?.selectNextKeyView(self)
        case 126:
            window?.selectPreviousKeyView(self)
        case 123:
            onCollapse?()
        case 124:
            onExpand?()
        default:
            super.keyDown(with: event)
        }
    }

    override func rightMouseDown(with event: NSEvent) { }
}

@MainActor
final class OptionsActionRowView: NSView {
    var onClick: (() -> Void)?
    fileprivate var button: OptionsActionButton?
    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) { onClick?() }
    override func rightMouseDown(with event: NSEvent) { }
}

@MainActor
final class OptionsShortcutLabel: NSTextField {
    var onClick: (() -> Void)?

    init(string: String) {
        super.init(frame: .zero)
        self.stringValue = string
        isEditable = false
        isSelectable = false
        isBordered = false
        drawsBackground = false
        alignment = .right
        lineBreakMode = .byTruncatingHead
        textColor = .secondaryLabelColor
        font = .systemFont(ofSize: 10.5, weight: .medium)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel("Keyboard shortcut \(string)")
    }

    required init?(coder: NSCoder) { nil }
    override func mouseDown(with event: NSEvent) { onClick?() }
    override func rightMouseDown(with event: NSEvent) { }
}

@MainActor
final class OptionsActionButton: NSButton {
    let menuItem: NSMenuItem
    var onChoose: (() -> Void)?
    var onDismiss: (() -> Void)?
    private var hoverArea: NSTrackingArea?
    private var isHovered = false

    init(item: NSMenuItem) {
        self.menuItem = item
        super.init(frame: .zero)
        title = item.title
        setAccessibilityLabel(item.title)
        if item.state != .off { setAccessibilityValue(item.state == .on ? "On" : "Pending approval") }
        isEnabled = item.isEnabled
        font = .systemFont(ofSize: 13)
        contentTintColor = .labelColor
        alignment = .left
        isBordered = false
        bezelStyle = .inline
        setButtonType(.momentaryChange)
        imagePosition = .imageLeading
        let state = item.state
        let indicator = NSImage(size: NSSize(width: 24, height: 14), flipped: false) { _ in
            let dot = NSBezierPath(ovalIn: NSRect(x: 4, y: 4, width: 6, height: 6))
            NSColor.black.setFill()
            NSColor.black.setStroke()
            if state == .on { dot.fill() }
            else if state == .mixed { dot.lineWidth = 1; dot.stroke() }
            return true
        }
        indicator.isTemplate = true
        image = indicator
        imageScaling = .scaleProportionallyDown
        keyEquivalent = item.keyEquivalent
        keyEquivalentModifierMask = item.keyEquivalentModifierMask
        target = self
        action = #selector(choose)
    }

    required init?(coder: NSCoder) { nil }
    override var acceptsFirstResponder: Bool { isEnabled }
    override var mouseDownCanMoveWindow: Bool { false }
    override func rightMouseDown(with event: NSEvent) { }

    @objc private func choose() { invokeActionIfEnabled() }

    func invokeActionIfEnabled() {
        guard isEnabled else { return }
        onChoose?()
    }

    func matchesKeyEquivalent(_ event: NSEvent) -> Bool {
        guard isEnabled, !keyEquivalent.isEmpty else { return false }
        let relevantFlags: NSEvent.ModifierFlags = [.control, .option, .shift, .command, .function, .numericPad, .help]
        let requiredFlags = keyEquivalentModifierMask.intersection(relevantFlags)
        let actualFlags = event.modifierFlags.intersection(relevantFlags)
        let allowsShiftForPlus = keyEquivalent == "+" && actualFlags.contains(.shift) && !requiredFlags.contains(.shift)
        guard actualFlags == requiredFlags || (allowsShiftForPlus && actualFlags.subtracting(.shift) == requiredFlags) else { return false }

        let expected = keyEquivalent.lowercased()
        let eventKeys = [event.charactersIgnoringModifiers, event.characters].compactMap { $0?.lowercased() }
        if eventKeys.contains(expected) { return true }
        // macOS reports the unshifted key for shifted symbols on some keyboards.
        let aliases: [String: [String]] = [
            "+": ["="],
            "=": ["+"],
            "*": ["8"],
            "&": ["7"],
        ]
        if aliases[expected, default: []].contains(where: eventKeys.contains) { return true }
        return false
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { isHovered = false; needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        if isEnabled && (isHovered || isHighlighted || window?.firstResponder === self) {
            NSColor.labelColor.withAlphaComponent(0.07).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
        }
        super.draw(dirtyRect)
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: onDismiss?()
        case 36, 76: performClick(nil)
        case 48:
            if event.modifierFlags.contains(.shift) { window?.selectPreviousKeyView(self) }
            else { window?.selectNextKeyView(self) }
        case 125: window?.selectNextKeyView(self)
        case 126: window?.selectPreviousKeyView(self)
        default: super.keyDown(with: event)
        }
    }
}
