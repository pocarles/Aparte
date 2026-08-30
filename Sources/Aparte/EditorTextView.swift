import AppKit
import AparteCore

@MainActor
final class EditorTextView: NSTextView {
    var onDismiss: (() -> Void)?
    var onSelectionChanged: (() -> Void)?

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty else { return }
        NSString(string: "Type or paste here...").draw(
            at: NSPoint(x: textContainerInset.width, y: textContainerInset.height),
            withAttributes: [
                .font: AparteTypography.bodyFont,
                .foregroundColor: NSColor.placeholderTextColor,
            ]
        )
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onDismiss?()
            return
        }
        super.keyDown(with: event)
    }

    override func paste(_ sender: Any?) {
        guard let normalized = PasteNormalizer.read(from: .general) else {
            super.paste(sender)
            return
        }
        replaceSelection(with: normalized)
    }

    @objc func copyAsMarkdown(_ sender: Any?) {
        let range = selectedRange().length > 0
            ? selectedRange()
            : NSRange(location: 0, length: textStorage?.length ?? 0)
        guard let attributed = textStorage?.attributedSubstring(from: range) else { return }
        let markdown = MarkdownCodec.markdown(from: attributed)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdown, forType: .string)
    }

    @objc func toggleBold(_ sender: Any?) {
        toggleFontTrait(.boldFontMask)
    }

    @objc func toggleItalic(_ sender: Any?) {
        toggleFontTrait(.italicFontMask)
    }

    @objc func toggleUnderline(_ sender: Any?) {
        let range = selectedRange()
        guard range.length > 0, let textStorage else { return }
        let current = textStorage.attribute(.underlineStyle, at: range.location, effectiveRange: nil) as? Int ?? 0
        textStorage.addAttribute(
            .underlineStyle,
            value: current == 0 ? NSUnderlineStyle.single.rawValue : 0,
            range: range
        )
        didChangeText()
    }

    func applyHeading(level: Int) {
        guard let textStorage else { return }
        let paragraphs = (string as NSString).paragraphRange(for: selectedRange())
        textStorage.addAttributes(
            [.font: AparteTypography.headingFont(level: level), .aparteHeadingLevel: level],
            range: paragraphs
        )
        didChangeText()
    }

    func applyList(_ kind: AparteListKind) {
        guard let textStorage else { return }
        let paragraphRange = (string as NSString).paragraphRange(for: selectedRange())
        let source = string as NSString
        var lineRanges: [NSRange] = []
        source.enumerateSubstrings(in: paragraphRange, options: [.byLines, .substringNotRequired]) {
            _, lineRange, _, _ in lineRanges.append(lineRange)
        }
        if lineRanges.isEmpty { lineRanges = [paragraphRange] }

        textStorage.beginEditing()
        for (offset, lineRange) in lineRanges.enumerated().reversed() {
            let marker = kind == .unordered ? "• " : "\(offset + 1). "
            textStorage.insert(NSAttributedString(string: marker, attributes: AparteTypography.baseAttributes), at: lineRange.location)
            let resultingRange = NSRange(location: lineRange.location, length: lineRange.length + marker.utf16.count)
            textStorage.addAttribute(.aparteListKind, value: kind.rawValue, range: resultingRange)
        }
        textStorage.endEditing()
        didChangeText()
    }

    func applyLink(_ url: URL, to range: NSRange? = nil) {
        let range = range ?? selectedRange()
        guard range.length > 0, let textStorage else { return }
        guard NSMaxRange(range) <= textStorage.length else { return }
        textStorage.addAttributes(
            [.link: url, .foregroundColor: NSColor.linkColor, .underlineStyle: NSUnderlineStyle.single.rawValue],
            range: range
        )
        setSelectedRange(range)
        didChangeText()
    }

    private func replaceSelection(with attributedString: NSAttributedString) {
        let range = selectedRange()
        guard shouldChangeText(in: range, replacementString: attributedString.string), let textStorage else { return }
        textStorage.replaceCharacters(in: range, with: attributedString)
        setSelectedRange(NSRange(location: range.location + attributedString.length, length: 0))
        didChangeText()
    }

    private func toggleFontTrait(_ trait: NSFontTraitMask) {
        let range = selectedRange()
        guard range.length > 0, let textStorage else { return }
        textStorage.beginEditing()
        textStorage.enumerateAttribute(.font, in: range) { value, runRange, _ in
            let font = value as? NSFont ?? AparteTypography.bodyFont
            let currentTraits = NSFontManager.shared.traits(of: font)
            let converted: NSFont
            if currentTraits.contains(trait) {
                converted = NSFontManager.shared.convert(font, toNotHaveTrait: trait)
            } else {
                converted = NSFontManager.shared.convert(font, toHaveTrait: trait)
            }
            textStorage.addAttribute(.font, value: converted, range: runRange)
        }
        textStorage.endEditing()
        didChangeText()
    }
}
