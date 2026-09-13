import AppKit
import AparteCore

@MainActor
final class EditorTextView: NSTextView {
    var onDismiss: (() -> Void)?
    var onSelectionChanged: (() -> Void)?
    var onAddLink: (() -> Void)?
    var placeholderHint: String? {
        didSet { needsDisplay = true }
    }

    @objc func makeHeading(_ sender: Any?) { applyHeading(level: 1) }
    @objc func makeBulletedList(_ sender: Any?) { applyList(.unordered) }
    @objc func makeNumberedList(_ sender: Any?) { applyList(.ordered) }
    @objc func addLink(_ sender: Any?) { onAddLink?() }

    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        let enabled: Bool
        switch item.action {
        // Inline traits also apply to what is typed next, so a selection is optional.
        case #selector(toggleBold(_:)), #selector(toggleItalic(_:)), #selector(toggleUnderline(_:)):
            enabled = true
        case #selector(addLink(_:)):
            enabled = selectedRange().length > 0
        case #selector(makeHeading(_:)), #selector(makeBulletedList(_:)), #selector(makeNumberedList(_:)):
            enabled = !string.isEmpty
        default:
            return super.validateUserInterfaceItem(item)
        }
        if let menuItem = item as? NSMenuItem {
            menuItem.state = commandIsActive(item.action) ? .on : .off
        }
        return enabled
    }

    private func commandIsActive(_ action: Selector?) -> Bool {
        switch action {
        case #selector(toggleBold(_:)):
            return AparteTypography.inlineTraits(in: attributesForCommandState()).contains(.boldFontMask)
        case #selector(toggleItalic(_:)):
            return AparteTypography.inlineTraits(in: attributesForCommandState()).contains(.italicFontMask)
        case #selector(toggleUnderline(_:)):
            return (attributesForCommandState()[.underlineStyle] as? Int ?? 0) != 0
        case #selector(makeHeading(_:)):
            guard let line = lineAtSelectionStart(), let textStorage, line.length > 0 else { return false }
            return textStorage.attribute(.aparteHeadingLevel, at: line.location, effectiveRange: nil) != nil
        case #selector(makeBulletedList(_:)):
            return markerAtSelectionStart()?.kind == .unordered
        case #selector(makeNumberedList(_:)):
            return markerAtSelectionStart()?.kind == .ordered
        default:
            return false
        }
    }

    private func attributesForCommandState() -> [NSAttributedString.Key: Any] {
        let range = selectedRange()
        guard range.length > 0, let textStorage, range.location < textStorage.length else {
            return typingAttributes
        }
        return textStorage.attributes(at: range.location, effectiveRange: nil)
    }

    private func lineAtSelectionStart() -> NSRange? {
        guard let textStorage, textStorage.length > 0,
              let paragraph = paragraphRange(for: NSRange(location: selectedRange().location, length: 0))
        else { return nil }
        return contentRange(of: paragraph, in: textStorage.string as NSString)
    }

    private func markerAtSelectionStart() -> ListContinuation.Marker? {
        guard let textStorage, let line = lineAtSelectionStart() else { return nil }
        return ListContinuation.marker(in: (textStorage.string as NSString).substring(with: line))
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty else { return }
        let bodyFont = AparteTypography.bodyFont
        let origin = NSPoint(x: textContainerInset.width, y: textContainerInset.height)
        NSString(string: "Type or paste here…").draw(
            at: origin,
            withAttributes: [
                .font: bodyFont,
                .foregroundColor: NSColor.placeholderTextColor,
            ]
        )
        guard let placeholderHint, !placeholderHint.isEmpty else { return }
        let bodyLineHeight = bodyFont.ascender - bodyFont.descender + bodyFont.leading
        NSString(string: placeholderHint).draw(
            at: NSPoint(x: origin.x, y: origin.y + bodyLineHeight + 6),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 13),
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
            typingAttributes = AparteTypography.baseAttributes
            return
        }
    }

    override func deleteBackward(_ sender: Any?) {
        guard deleteListMarker() else {
            super.deleteBackward(sender)
            return
        }
    }

    override func copy(_ sender: Any?) {
        copySelection(to: .general)
    }

    func copySelection(to pasteboard: NSPasteboard) {
        let range = selectedRange()
        guard let textStorage, range.length > 0,
              NSMaxRange(range) <= textStorage.length else { return }
        writeToPasteboard(ParagraphFormatting.copyText(from: textStorage, range: range), pasteboard: pasteboard)
    }

    override func cut(_ sender: Any?) {
        guard selectedRange().length > 0 else {
            super.cut(sender)
            return
        }
        cutSelection(to: .general)
    }

    /// Cut writes the same normalized content as copy, never Aparte's own fonts.
    func cutSelection(to pasteboard: NSPasteboard) {
        guard selectedRange().length > 0 else { return }
        copySelection(to: pasteboard)
        delete(nil)
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

        let plainText = ParagraphFormatting.plainText(from: ParagraphFormatting.copyText(from: textStorage, range: range))
        pasteboard.clearContents()
        pasteboard.setString(plainText, forType: .string)
    }

    func copyAllPreservingSelection(to pasteboard: NSPasteboard = .general) {
        guard let textStorage, textStorage.length > 0 else { return }
        let attributed = ParagraphFormatting.copyText(from: textStorage, range: NSRange(location: 0, length: textStorage.length))
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
        copyMarkdown(to: .general)
    }

    func copyMarkdown(to pasteboard: NSPasteboard) {
        guard let textStorage, textStorage.length > 0 else { return }
        let range = selectedRange().length > 0
            ? selectedRange()
            : NSRange(location: 0, length: textStorage.length)
        guard NSMaxRange(range) <= textStorage.length else { return }
        let attributed = ParagraphFormatting.copyText(from: textStorage, range: range)
        let markdown = MarkdownCodec.markdown(from: attributed)
        pasteboard.clearContents()
        pasteboard.setString(markdown, forType: .string)
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
        guard let textStorage, NSMaxRange(range) <= textStorage.length else { return }
        guard range.length > 0 else {
            var attributes = typingAttributes
            let current = attributes[.underlineStyle] as? Int ?? 0
            attributes[.underlineStyle] = current == 0 ? NSUnderlineStyle.single.rawValue : 0
            typingAttributes = attributes
            return
        }
        guard shouldChangeText(in: range, replacementString: nil) else { return }
        let current = textStorage.attribute(.underlineStyle, at: range.location, effectiveRange: nil) as? Int ?? 0
        textStorage.addAttribute(
            .underlineStyle,
            value: current == 0 ? NSUnderlineStyle.single.rawValue : 0,
            range: range
        )
        didChangeText()
    }

    func applyHeading(level: Int) {
        guard let textStorage, textStorage.length > 0 else { return }
        let lines = selectedLineRanges()
        let alreadyHeading = !lines.isEmpty && lines.allSatisfy { line in
            guard line.length > 0 else { return false }
            return textStorage.attribute(.aparteHeadingLevel, at: line.location, effectiveRange: nil) as? Int == level
        }

        applyBlockCommand { _, line, marker in
            let text = NSMutableAttributedString(attributedString: line)
            if alreadyHeading {
                let range = NSRange(location: 0, length: text.length)
                var fonts: [(NSRange, NSFont)] = []
                text.enumerateAttributes(in: range) { attributes, run, _ in
                    fonts.append((run, AparteTypography.font(headingLevel: nil,
                                                             traits: AparteTypography.inlineTraits(in: attributes))))
                }
                for (run, font) in fonts { text.addAttribute(.font, value: font, range: run) }
                if text.length > 0 {
                    text.removeAttribute(.aparteHeadingLevel, range: range)
                    text.removeAttribute(.aparteInlineBold, range: range)
                    text.removeAttribute(.aparteInlineOnly, range: range)
                    text.addAttribute(.paragraphStyle, value: AparteTypography.bodyParagraphStyle, range: range)
                }
                return (text, marker?.utf16Length ?? 0)
            }

            if let marker { text.deleteCharacters(in: NSRange(location: 0, length: marker.utf16Length)) }
            let range = NSRange(location: 0, length: text.length)
            var updates: [(NSRange, [NSAttributedString.Key: Any])] = []
            text.enumerateAttributes(in: range) { attributes, run, _ in
                var updated = attributes
                let traits = AparteTypography.inlineTraits(in: attributes)
                updated.removeValue(forKey: .aparteInlineOnly)
                updated[.aparteHeadingLevel] = level
                AparteTypography.applyInlineTraits(traits, to: &updated)
                updated[.paragraphStyle] = AparteTypography.bodyParagraphStyle
                updates.append((run, updated))
            }
            for (run, attributes) in updates { text.setAttributes(attributes, range: run) }
            return (text, 0)
        }
    }

    func applyList(_ kind: AparteListKind) {
        guard let textStorage, textStorage.length > 0 else { return }
        let source = textStorage.string as NSString
        let lines = selectedLineRanges()
        let alreadyList = !lines.isEmpty && lines.allSatisfy { line in
            ListContinuation.marker(in: source.substring(with: line))?.kind == kind
        }
        var markerAttributes = AparteTypography.baseAttributes
        markerAttributes[.paragraphStyle] = AparteTypography.listParagraphStyle

        applyBlockCommand { index, line, marker in
            let text = NSMutableAttributedString(attributedString: line)
            if let marker { text.deleteCharacters(in: NSRange(location: 0, length: marker.utf16Length)) }
            if alreadyList {
                if text.length > 0 {
                    text.addAttribute(.paragraphStyle, value: AparteTypography.bodyParagraphStyle,
                                      range: NSRange(location: 0, length: text.length))
                }
                return (text, 0)
            }

            let content = NSRange(location: 0, length: text.length)
            var fonts: [(NSRange, NSFont)] = []
            text.enumerateAttributes(in: content) { attributes, run, _ in
                if attributes[.aparteHeadingLevel] != nil {
                    fonts.append((run, AparteTypography.font(headingLevel: nil,
                                                             traits: AparteTypography.inlineTraits(in: attributes))))
                }
            }
            for (run, font) in fonts { text.addAttribute(.font, value: font, range: run) }
            if text.length > 0 {
                text.removeAttribute(.aparteHeadingLevel, range: content)
                text.removeAttribute(.aparteInlineBold, range: content)
                text.removeAttribute(.aparteInlineOnly, range: content)
            }
            let prefix = marker?.kind == kind
                ? marker!.prefix
                : kind == .unordered ? "• " : "\(index + 1). "
            text.insert(NSAttributedString(string: prefix, attributes: markerAttributes), at: 0)
            text.addAttribute(.paragraphStyle, value: AparteTypography.listParagraphStyle,
                              range: NSRange(location: 0, length: text.length))
            return (text, prefix.utf16.count)
        }
    }

    /// Block commands rewrite their paragraphs in one replacement, so a single
    /// undo restores the previous characters and attributes together.
    private func applyBlockCommand(
        _ transform: (Int, NSAttributedString, ListContinuation.Marker?) -> (text: NSAttributedString, prefixLength: Int)
    ) {
        guard let textStorage, textStorage.length > 0 else { return }
        let source = textStorage.string as NSString
        let paragraphRange = source.paragraphRange(for: selectedRange())
        let lines = selectedLineRanges()
        guard !lines.isEmpty else { return }

        let replacement = NSMutableAttributedString()
        var oldPrefixLengths: [Int] = []
        var newPrefixLengths: [Int] = []
        var newStarts: [Int] = []
        var newEnds: [Int] = []
        for (index, line) in lines.enumerated() {
            let marker = ListContinuation.marker(in: source.substring(with: line))
            let (text, prefixLength) = transform(index, textStorage.attributedSubstring(from: line), marker)
            oldPrefixLengths.append(marker?.utf16Length ?? 0)
            newPrefixLengths.append(prefixLength)
            newStarts.append(paragraphRange.location + replacement.length)
            replacement.append(text)
            newEnds.append(paragraphRange.location + replacement.length)

            let terminatorStart = NSMaxRange(line)
            let terminatorEnd = index + 1 < lines.count ? lines[index + 1].location : NSMaxRange(paragraphRange)
            if terminatorEnd > terminatorStart {
                replacement.append(textStorage.attributedSubstring(
                    from: NSRange(location: terminatorStart, length: terminatorEnd - terminatorStart)
                ))
            }
        }

        // Each selection endpoint stays on the same content character of its line.
        func mapped(_ location: Int) -> Int {
            guard let index = lines.firstIndex(where: { location <= NSMaxRange($0) }) else {
                return paragraphRange.location + replacement.length
            }
            let offset = max(0, location - (lines[index].location + oldPrefixLengths[index]))
            return min(newStarts[index] + newPrefixLengths[index] + offset, newEnds[index])
        }
        let selection = selectedRange()
        let start = mapped(selection.location)
        let end = selection.length == 0 ? start : max(start, mapped(NSMaxRange(selection)))
        let newSelection = NSRange(location: start, length: end - start)

        guard replaceText(in: paragraphRange, with: replacement, selecting: newSelection) else { return }
        typingAttributes = blockTypingAttributes(at: newSelection.location)
    }

    /// Typing continues the attributes beside the caret, including inline traits.
    /// At a paragraph start the line's own first character decides, as AppKit does.
    private func blockTypingAttributes(at location: Int) -> [NSAttributedString.Key: Any] {
        guard let textStorage, textStorage.length > 0 else { return AparteTypography.baseAttributes }
        let source = textStorage.string as NSString
        let clamped = min(max(location, 0), source.length)
        let paragraphStart = source.paragraphRange(for: NSRange(location: clamped, length: 0)).location
        let probe = clamped == paragraphStart ? clamped : clamped - 1
        guard probe < textStorage.length else { return AparteTypography.baseAttributes }
        var typing = textStorage.attributes(at: probe, effectiveRange: nil)
        typing.removeValue(forKey: .aparteInlineOnly)
        return typing
    }

    private func selectedLineRanges() -> [NSRange] {
        let paragraphRange = (string as NSString).paragraphRange(for: selectedRange())
        let source = string as NSString
        var lineRanges: [NSRange] = []
        source.enumerateSubstrings(in: paragraphRange, options: [.byLines, .substringNotRequired]) {
            _, lineRange, _, _ in lineRanges.append(lineRange)
        }
        if lineRanges.isEmpty { lineRanges = [paragraphRange] }

        return lineRanges
    }

    func applyLink(_ url: URL, to range: NSRange? = nil) {
        let range = range ?? selectedRange()
        guard range.length > 0, let textStorage else { return }
        guard NSMaxRange(range) <= textStorage.length else { return }
        guard shouldChangeText(in: range, replacementString: nil) else { return }
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
        guard let textStorage, NSMaxRange(range) <= textStorage.length else { return }
        guard range.length > 0 else {
            typingAttributes = toggling(trait, in: typingAttributes)
            return
        }
        guard shouldChangeText(in: range, replacementString: nil) else { return }

        var updates: [(NSRange, [NSAttributedString.Key: Any])] = []
        textStorage.enumerateAttributes(in: range) { attributes, runRange, _ in
            updates.append((runRange, toggling(trait, in: attributes)))
        }
        textStorage.beginEditing()
        for (runRange, attributes) in updates {
            if let font = attributes[.font] {
                textStorage.addAttribute(.font, value: font, range: runRange)
            }
            if let inlineBold = attributes[.aparteInlineBold] {
                textStorage.addAttribute(.aparteInlineBold, value: inlineBold, range: runRange)
            } else {
                textStorage.removeAttribute(.aparteInlineBold, range: runRange)
            }
        }
        textStorage.endEditing()
        didChangeText()
    }

    /// One transform for runs and for typing attributes, so a caret toggle and a
    /// selection toggle cannot disagree.
    private func toggling(
        _ trait: NSFontTraitMask,
        in attributes: [NSAttributedString.Key: Any]
    ) -> [NSAttributedString.Key: Any] {
        var result = attributes
        let next = AparteTypography.inlineTraits(in: attributes).symmetricDifference(trait)
        AparteTypography.applyInlineTraits(next, to: &result)
        return result
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
        guard let marker = ListContinuation.marker(in: line) else {
            return false
        }

        let markerEnd = contentRange.location + marker.utf16Length
        guard selection.location >= markerEnd else { return false }

        if selection.length == 0,
           selection.location == NSMaxRange(contentRange),
           ListContinuation.isEmptyItem(in: line, marker: marker) {
            let base = AparteTypography.baseAttributes
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

        let nextMarker = ListContinuation.nextMarker(after: marker)
        var markerAttributes = AparteTypography.baseAttributes
        markerAttributes[.paragraphStyle] = AparteTypography.listParagraphStyle

        let replacement = NSMutableAttributedString(
            string: "\n",
            attributes: AparteTypography.baseAttributes
        )
        replacement.append(NSAttributedString(string: nextMarker, attributes: markerAttributes))

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

    /// Backspace immediately after a marker removes the whole marker, and the
    /// line stops being a list item.
    private func deleteListMarker() -> Bool {
        guard let textStorage, textStorage.length > 0 else { return false }
        let selection = selectedRange()
        guard selection.length == 0,
              selection.location > 0,
              selection.location <= textStorage.length
        else {
            return false
        }

        let source = textStorage.string as NSString
        let line = contentRange(
            of: source.paragraphRange(for: NSRange(location: selection.location, length: 0)),
            in: source
        )
        guard let marker = ListContinuation.marker(in: source.substring(with: line)),
              selection.location == line.location + marker.utf16Length
        else {
            return false
        }

        guard replaceText(
            in: NSRange(location: line.location, length: marker.utf16Length),
            with: NSAttributedString(string: "", attributes: AparteTypography.baseAttributes),
            selecting: NSRange(location: line.location, length: 0)
        ) else {
            return false
        }

        let paragraph = (textStorage.string as NSString)
            .paragraphRange(for: NSRange(location: line.location, length: 0))
        if paragraph.length > 0, shouldChangeText(in: paragraph, replacementString: nil) {
            textStorage.addAttribute(.paragraphStyle, value: AparteTypography.bodyParagraphStyle, range: paragraph)
            didChangeText()
        }
        typingAttributes = AparteTypography.baseAttributes
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

    private func writeToPasteboard(
        _ attributedString: NSAttributedString,
        pasteboard: NSPasteboard
    ) {
        pasteboard.clearContents()
        pasteboard.setString(ParagraphFormatting.plainText(from: attributedString), forType: .string)
        pasteboard.setString(ParagraphFormatting.html(from: attributedString), forType: .html)
    }
}
