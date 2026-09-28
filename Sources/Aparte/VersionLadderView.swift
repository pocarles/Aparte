import AppKit
import AparteCore

/// The left-edge hit area remains present while its marks are out of sight.
/// Hovering previews text in a separate view; only pressing a mark restores it.
@MainActor
final class VersionLadderView: NSView {
    var onRequestVersions: (() -> [VersionHistoryStore.Version]?)?
    var onPreview: ((VersionHistoryStore.Version?) -> Void)?
    var onRestore: ((VersionHistoryStore.Version) -> Void)?
    var onDismiss: (() -> Void)?
    var onScroll: ((NSEvent) -> Void)?
    private(set) var isExpanded = false
    private(set) var versions: [VersionHistoryStore.Version] = []
    private(set) var selectedIndex = 0
    private var marks: [VersionMarkButton] = []
    private var hoverArea: NSTrackingArea?

    override var acceptsFirstResponder: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Recent versions")
        setAccessibilityHelp("Use Up and Down to preview a version, Return to restore it, or Escape to return to the current draft.")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    func reveal() {
        guard !isExpanded, let versions = onRequestVersions?() else { return }
        self.versions = versions
        isExpanded = true
        selectedIndex = 0
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        for index in 0...versions.count {
            let button = VersionMarkButton(frame: .zero)
            button.tag = index
            button.isCurrentDraft = index == 0
            let label = index == 0 ? "Current draft" : "Restore version from \(formatter.string(from: versions[index - 1].createdAt))"
            button.setAccessibilityLabel(label)
            button.toolTip = label
            button.target = self
            button.action = #selector(choose(_:))
            addSubview(button)
            marks.append(button)
        }
        needsLayout = true
        layoutSubtreeIfNeeded()
        preview(index: 0)
        needsDisplay = true
        NSAccessibility.post(element: self, notification: .layoutChanged)
    }

    func collapse() {
        isExpanded = false
        marks.forEach { $0.removeFromSuperview() }
        marks.removeAll()
        versions.removeAll()
        selectedIndex = 0
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        let step = min(16, bounds.height / CGFloat(max(1, marks.count)))
        let top = bounds.midY + CGFloat(marks.count) * step / 2
        for (index, mark) in marks.enumerated() {
            mark.frame = NSRect(x: 0, y: top - CGFloat(index + 1) * step, width: bounds.width, height: step)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        reveal()
        mouseMoved(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        guard isExpanded else { return }
        let point = convert(event.locationInWindow, from: nil)
        if let index = marks.firstIndex(where: { $0.frame.contains(point) }), index != selectedIndex {
            preview(index: index)
        }
    }

    override func mouseExited(with event: NSEvent) { onDismiss?() }
    override func mouseDown(with event: NSEvent) { }
    override func scrollWheel(with event: NSEvent) { onScroll?(event) }

    func preview(index: Int) {
        guard isExpanded, marks.indices.contains(index) else { return }
        selectedIndex = index
        for (position, mark) in marks.enumerated() {
            mark.isPreviewed = position == index
            mark.needsDisplay = true
        }
        onPreview?(index == 0 ? nil : versions[index - 1])
    }

    @objc private func choose(_ sender: NSButton) {
        guard isExpanded, marks.indices.contains(sender.tag) else { return }
        if sender.tag == 0 { onDismiss?() }
        else { onRestore?(versions[sender.tag - 1]) }
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: onDismiss?()
        case 125: preview(index: min(versions.count, selectedIndex + 1))
        case 126: preview(index: max(0, selectedIndex - 1))
        case 36, 76:
            if marks.indices.contains(selectedIndex) { choose(marks[selectedIndex]) }
        default: super.keyDown(with: event)
        }
    }

    var marksForRuntimeCheck: [NSButton] { marks }
}

@MainActor
private final class VersionMarkButton: NSButton {
    var isPreviewed = false
    var isCurrentDraft = false
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override init(frame: NSRect) {
        super.init(frame: frame)
        title = ""
        isBordered = false
        setButtonType(.momentaryPushIn)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    override func draw(_ dirtyRect: NSRect) {
        let color = isPreviewed ? NSColor.controlAccentColor : NSColor.secondaryLabelColor
        color.setStroke()
        let path = NSBezierPath()
        if isCurrentDraft {
            path.appendOval(in: NSRect(x: 10, y: bounds.midY - 3, width: 6, height: 6))
        } else {
            path.move(to: NSPoint(x: 7, y: bounds.midY))
            path.line(to: NSPoint(x: isPreviewed ? 26 : 21, y: bounds.midY))
        }
        path.lineWidth = isPreviewed ? 2 : 1.5
        path.lineCapStyle = .round
        path.stroke()
    }
}

/// Preview paint never takes a click away from the live editor. Leaving the
/// ladder removes the preview before the user can edit the current draft.
@MainActor
final class VersionPreviewScrollView: NSScrollView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
