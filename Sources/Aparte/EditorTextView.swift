import AppKit
import AparteCore

@MainActor
final class EditorTextView: NSTextView {
    var onDismiss: (() -> Void)?
    var onSelectionChanged: (() -> Void)?
    var onAddLink: (() -> Void)?

    @objc func makeHeading(_ sender: Any?) { applyHeading(level: 1) }
    @objc func makeBulletedList(_ sender: Any?) { applyList(.unordered) }
    @objc func makeNumberedList(_ sender: Any?) { applyList(.ordered) }
    @objc func addLink(_ sender: Any?) { onAddLink?() }

    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        switch item.action {
        case #selector(toggleBold(_:)), #selector(toggleItalic(_:)), #selector(toggleUnderline(_:)), #selector(addLink(_:)):
            return selectedRange().length > 0
        case #selector(makeHeading(_:)), #selector(makeBulletedList(_:)), #selector(makeNumberedList(_:)):
            return !string.isEmpty
        default: return super.validateUserInterfaceItem(item)
        }
    }

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

    override func insertNewline(_ sender: Any?) {
        guard continueListIfNeeded() else {
            super.insertNewline(sender)
            return
        }
    }

    override func paste(_ sender: Any?) {
        guard let normalized = PasteNormalizer.read(from: .general) else {
            super.paste(sender)
            return
        }
        replaceSelection(with: normalized)
    }

    @objc func copyAsPlainText(_ sender: Any?) {
        copyPlainText(to: .general)
    }

    func copyPlainText(to pasteboard: NSPasteboard) {
        guard let textStorage, textStorage.length > 0 else { return }
        let selection = selectedRange()
        let range = selection.length > 0
            ? selection
            : NSRange(location: 0, length: textStorage.length)
        guard NSMaxRange(range) <= textStorage.length else { return }

        let plainText = textStorage.attributedSubstring(from: range).string
        pasteboard.clearContents()
        pasteboard.setString(plainText, forType: .string)
    }

    func copyAllPreservingSelection(to pasteboard: NSPasteboard = .general) {
        guard let textStorage, textStorage.length > 0 else { return }
        let attributed = textStorage.attributedSubstring(
            from: NSRange(location: 0, length: textStorage.length)
        )
        writeToPasteboard(attributed, pasteboard: pasteboard)
    }

    func replaceAll(with attributedString: NSAttributedString) {
        guard let textStorage else { return }
        let fullRange = NSRange(location: 0, length: textStorage.length)
        let selectionAfter = NSRange(location: attributedString.length, length: 0)
        guard replaceText(in: fullRange, with: attributedString, selecting: selectionAfter) else { return }
        typingAttributes = AparteTypography.baseAttributes
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

    @objc func clearAll(_ sender: Any?) {
        guard let textStorage, textStorage.length > 0 else { return }
        let fullRange = NSRange(location: 0, length: textStorage.length)
        guard shouldChangeText(in: fullRange, replacementString: "") else { return }
        textStorage.replaceCharacters(in: fullRange, with: "")
        setSelectedRange(NSRange(location: 0, length: 0))
        typingAttributes = AparteTypography.baseAttributes
        didChangeText()
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
        let selectionAfter = NSRange(location: range.location + attributedString.length, length: 0)
        _ = replaceText(in: range, with: attributedString, selecting: selectionAfter)
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

    @discardableResult
    private func replaceText(
        in range: NSRange,
        with attributedString: NSAttributedString,
        selecting selection: NSRange
    ) -> Bool {
        guard let textStorage,
              range.location >= 0,
              range.length >= 0,
              NSMaxRange(range) <= textStorage.length,
              shouldChangeText(in: range, replacementString: attributedString.string)
        else {
            return false
        }

        textStorage.replaceCharacters(in: range, with: attributedString)
        setSelectedRange(selection)
        didChangeText()
        return true
    }

    private func continueListIfNeeded() -> Bool {
        guard let textStorage else { return false }
        let selection = selectedRange()
        guard let paragraphRange = paragraphRange(for: selection),
              NSMaxRange(selection) <= NSMaxRange(paragraphRange)
        else {
            return false
        }

        let source = textStorage.string as NSString
        let contentRange = contentRange(of: paragraphRange, in: source)
        guard NSMaxRange(selection) <= NSMaxRange(contentRange) else {
            return false
        }
        let line = source.substring(with: contentRange)
        let storedKind = storedListKind(in: contentRange, from: textStorage)
        guard let marker = ListContinuation.marker(in: line, listKind: storedKind) else {
            return false
        }

        let markerEnd = contentRange.location + marker.utf16Length
        guard selection.location >= markerEnd else { return false }

        if selection.length == 0,
           selection.location == NSMaxRange(contentRange),
           ListContinuation.isEmptyItem(in: line, marker: marker) {
            var base = AparteTypography.baseAttributes
            base.removeValue(forKey: .aparteListKind)
            let empty = NSAttributedString(string: "", attributes: base)
            guard replaceText(
                in: contentRange,
                with: empty,
                selecting: NSRange(location: contentRange.location, length: 0)
            ) else {
                return false
            }
            typingAttributes = base
            return true
        }

        let continuationMarker = markerForContinuation(
            marker,
            storedKind: storedKind,
            paragraphRange: paragraphRange,
            in: textStorage
        )
        let nextMarker = ListContinuation.nextMarker(after: continuationMarker)
        var markerAttributes = AparteTypography.baseAttributes
        if let storedKind {
            markerAttributes[.aparteListKind] = storedKind.rawValue
        }

        let replacement = NSMutableAttributedString(
            string: "\n",
            attributes: AparteTypography.baseAttributes
        )
        if !nextMarker.isEmpty {
            replacement.append(NSAttributedString(string: nextMarker, attributes: markerAttributes))
        }

        let selectionAfter = NSRange(
            location: selection.location + replacement.length,
            length: 0
        )
        guard replaceText(in: selection, with: replacement, selecting: selectionAfter) else {
            return false
        }
        typingAttributes = markerAttributes
        return true
    }

    private func paragraphRange(for selection: NSRange) -> NSRange? {
        guard let textStorage else { return nil }
        let source = textStorage.string as NSString
        let location = min(max(selection.location, 0), source.length)

        if location == source.length,
           source.length > 0,
           source.character(at: source.length - 1) == 10 {
            return NSRange(location: source.length, length: 0)
        }

        let probe = min(location, max(0, source.length - 1))
        return source.paragraphRange(for: NSRange(location: probe, length: 0))
    }

    private func contentRange(of paragraphRange: NSRange, in source: NSString) -> NSRange {
        var result = paragraphRange
        while result.length > 0 {
            let last = NSMaxRange(result) - 1
            let characterRange = source.rangeOfComposedCharacterSequence(at: last)
            let character = source.substring(with: characterRange)
            guard character.unicodeScalars.allSatisfy(CharacterSet.newlines.contains) else {
                break
            }
            result.length -= characterRange.length
        }
        return result
    }

    private func markerForContinuation(
        _ marker: ListContinuation.Marker,
        storedKind: AparteListKind?,
        paragraphRange: NSRange,
        in textStorage: NSTextStorage
    ) -> ListContinuation.Marker {
        guard marker.kind == .ordered,
              marker.number == nil,
              storedKind == .ordered
        else {
            return marker
        }

        let source = textStorage.string as NSString
        var precedingItems = 0
        var cursor = paragraphRange.location
        while cursor > 0 {
            let previousParagraph = source.paragraphRange(
                for: NSRange(location: cursor - 1, length: 0)
            )
            let previousContent = contentRange(of: previousParagraph, in: source)
            guard storedListKind(in: previousContent, from: textStorage) == .ordered else {
                break
            }
            precedingItems += 1
            cursor = previousParagraph.location
        }

        let currentNumber = precedingItems == Int.max ? Int.max : precedingItems + 1
        return ListContinuation.Marker(
            kind: .ordered,
            number: currentNumber,
            prefix: marker.prefix
        )
    }

    private func writeToPasteboard(
        _ attributedString: NSAttributedString,
        pasteboard: NSPasteboard
    ) {
        pasteboard.clearContents()
        pasteboard.setString(attributedString.string, forType: .string)
        guard attributedString.length > 0,
              let rtf = try? attributedString.data(
                  from: NSRange(location: 0, length: attributedString.length),
                  documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
              )
        else {
            return
        }
        pasteboard.setData(rtf, forType: .rtf)
    }

    private func storedListKind(
        in range: NSRange,
        from textStorage: NSTextStorage
    ) -> AparteListKind? {
        guard range.length > 0 else { return nil }
        var result: AparteListKind?
        textStorage.enumerateAttribute(.aparteListKind, in: range) { value, _, stop in
            guard result == nil, let rawValue = value as? String else { return }
            result = AparteListKind(rawValue: rawValue)
            if result != nil { stop.pointee = true }
        }
        return result
    }
}
