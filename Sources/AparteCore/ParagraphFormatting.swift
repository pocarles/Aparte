import AppKit

/// Shared paragraph boundaries for the editor, Markdown, and the clipboard.
public enum ParagraphFormatting {
    struct Block {
        let range: NSRange
        let marker: ListContinuation.Marker?
        let headingLevel: Int
    }

    /// U+2028 is a soft break inside a paragraph. `getParagraphStart` keeps it
    /// there; this walk is the one place that assumption is relied on.
    static func blocks(in text: NSAttributedString) -> [Block] {
        let source = text.string as NSString
        var result: [Block] = []
        var cursor = 0
        while cursor < source.length {
            var end = 0
            var contentsEnd = 0
            source.getParagraphStart(nil, end: &end, contentsEnd: &contentsEnd,
                                     for: NSRange(location: cursor, length: 0))
            if let block = block(in: text, source: source, start: cursor, contentsEnd: contentsEnd) {
                result.append(block)
            }
            cursor = end
        }
        return result
    }

    private static func block(
        in text: NSAttributedString,
        source: NSString,
        start: Int,
        contentsEnd: Int
    ) -> Block? {
        let range = NSRange(location: start, length: contentsEnd - start)
        let line = source.substring(with: range)
        // A soft break is content even when nothing follows it, so a block
        // that is only U+2028 survives. Other blank rows stay spacing.
        let hasContent = line.contains("\u{2028}")
            || !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard hasContent else { return nil }
        let attributes = text.attributes(at: start, effectiveRange: nil)
        let inlineOnly = attributes[.aparteInlineOnly] as? Bool == true
        return Block(
            range: range,
            marker: inlineOnly ? nil : ListContinuation.marker(in: line),
            headingLevel: inlineOnly ? 0 : attributes[.aparteHeadingLevel] as? Int ?? 0
        )
    }

    /// Spacing follows structure. A list item keeps the tight gap only while the
    /// next paragraph continues the same list. A heading takes twice the body
    /// gap, and so does the paragraph that precedes one, so the space above a
    /// heading matches the space below it. Anything else takes the body gap.
    static func paragraphStyle(for block: Block, next: Block?) -> NSParagraphStyle {
        let continuesList = block.marker != nil && block.marker?.kind == next?.marker?.kind
        let nextIsHeading = (next?.headingLevel ?? 0) > 0
        let spacing: CGFloat
        if continuesList {
            spacing = AparteTypography.listItemSpacing
        } else if block.headingLevel > 0 || nextIsHeading {
            spacing = AparteTypography.headingSpacing
        } else {
            spacing = AparteTypography.paragraphSpacing
        }
        let indent = block.marker.map { AparteTypography.markerIndent(for: $0.prefix) } ?? 0
        return AparteTypography.paragraphStyle(spacing: spacing, headIndent: indent)
    }

    /// Block meaning belongs to complete paragraphs, not copied fragments.
    public static func copyText(from text: NSAttributedString, range: NSRange) -> NSAttributedString {
        let output = NSMutableAttributedString(attributedString: text.attributedSubstring(from: range))
        let source = text.string as NSString
        var cursor = range.location
        while cursor < NSMaxRange(range) {
            var start = 0
            var end = 0
            var contentsEnd = 0
            source.getParagraphStart(&start, end: &end, contentsEnd: &contentsEnd,
                                     for: NSRange(location: cursor, length: 0))
            if range.location > start || NSMaxRange(range) < contentsEnd {
                let intersection = NSIntersectionRange(range, NSRange(location: start, length: end - start))
                let fragment = NSRange(location: intersection.location - range.location, length: intersection.length)
                output.enumerateAttributes(in: fragment) { attributes, run, _ in
                    if attributes[.aparteHeadingLevel] != nil {
                        let font = AparteTypography.font(headingLevel: nil,
                                                         traits: AparteTypography.inlineTraits(in: attributes))
                        output.addAttribute(.font, value: font, range: run)
                    }
                }
                output.removeAttribute(.aparteHeadingLevel, range: fragment)
                output.addAttribute(.aparteInlineOnly, value: true, range: fragment)
            }
            cursor = end
        }
        return output
    }

    /// Empty source lines are represented by paragraph spacing, not extra rows.
    public static func editorText(from text: NSAttributedString) -> NSAttributedString {
        let output = NSMutableAttributedString(attributedString: text)
        normalizeEditorTextInPlace(output, paragraphStylesAreCanonical: false)
        return output
    }

    /// Canonicalizes an owned editor buffer without making another complete
    /// attributed-string copy. Content attributes stay in place; only blank
    /// rows, paragraph separators, and structural paragraph styles change.
    static func normalizeEditorTextInPlace(
        _ storage: NSMutableAttributedString,
        paragraphStylesAreCanonical: Bool = true
    ) {
        let originalBlocks = blocks(in: storage)
        guard let first = originalBlocks.first, let last = originalBlocks.last else {
            storage.deleteCharacters(in: NSRange(location: 0, length: storage.length))
            return
        }
        let keepTrailingNewline = storage.string.last?.isNewline == true
        let baseAttributes = AparteTypography.baseAttributes
        let separator = NSAttributedString(string: "\n", attributes: baseAttributes)
        let empty = NSAttributedString(string: "")
        let source = storage.string as NSString

        func hasCanonicalSeparator(in range: NSRange) -> Bool {
            guard range.length == 1, source.character(at: range.location) == 0x0A else { return false }
            let attributes = storage.attributes(at: range.location, effectiveRange: nil)
            guard attributes.count == baseAttributes.count else { return false }
            return NSDictionary(dictionary: attributes).isEqual(to: baseAttributes)
        }

        func normalizeSeparator(in range: NSRange, keep: Bool = true) {
            if keep, range.length == 1, source.character(at: range.location) == 0x0A {
                if !hasCanonicalSeparator(in: range) {
                    storage.setAttributes(baseAttributes, range: range)
                }
            } else {
                storage.replaceCharacters(in: range, with: keep ? separator : empty)
            }
        }

        storage.beginEditing()
        defer { storage.endEditing() }

        let trailing = NSRange(location: NSMaxRange(last.range), length: storage.length - NSMaxRange(last.range))
        normalizeSeparator(in: trailing, keep: keepTrailingNewline)
        var batchCompaction = false
        if originalBlocks.count > 64 {
            for index in 1..<originalBlocks.count {
                let previousEnd = NSMaxRange(originalBlocks[index - 1].range)
                let gap = NSRange(location: previousEnd, length: originalBlocks[index].range.location - previousEnd)
                if !hasCanonicalSeparator(in: gap) {
                    batchCompaction = true
                    break
                }
            }
        }
        if batchCompaction {
            // Replacing thousands of tiny gaps makes NSMutableAttributedString
            // repeatedly rebalance its backing store. Rebuild bounded chunks
            // instead: peak memory stays small, while the number of character
            // mutations falls from one per paragraph to one per chunk.
            let batchSize = 256
            var upper = originalBlocks.count
            while upper > 0 {
                let lower = max(0, upper - batchSize)
                // Release Cocoa's temporary substring objects per chunk too.
                autoreleasepool {
                    let replacement = NSMutableAttributedString()
                    for index in lower..<upper {
                        replacement.append(storage.attributedSubstring(from: originalBlocks[index].range))
                        if index + 1 < originalBlocks.count {
                            replacement.append(separator)
                        }
                    }
                    let replacementEnd = upper < originalBlocks.count
                        ? originalBlocks[upper].range.location
                        : NSMaxRange(last.range)
                    storage.replaceCharacters(
                        in: NSRange(
                            location: originalBlocks[lower].range.location,
                            length: replacementEnd - originalBlocks[lower].range.location
                        ),
                        with: replacement
                    )
                }
                upper = lower
            }
        } else if originalBlocks.count > 1 {
            for index in stride(from: originalBlocks.count - 1, through: 1, by: -1) {
                let previousEnd = NSMaxRange(originalBlocks[index - 1].range)
                let gap = NSRange(location: previousEnd, length: originalBlocks[index].range.location - previousEnd)
                normalizeSeparator(in: gap)
            }
        }
        if first.range.location > 0 {
            storage.deleteCharacters(in: NSRange(location: 0, length: first.range.location))
        }

        // Compaction changes only the gaps. Reuse each block's meaning and
        // content length instead of parsing the entire normalized document again.
        var normalizedStart = 0
        for (index, block) in originalBlocks.enumerated() {
            let range = NSRange(location: normalizedStart, length: block.range.length)
            normalizedStart += block.range.length + 1
            let next = index + 1 < originalBlocks.count ? originalBlocks[index + 1] : nil
            let style = paragraphStyle(for: block, next: next)
            if paragraphStylesAreCanonical,
               paragraphStylesMatch(
                   storage.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle,
                   style
               ) {
                continue
            }
            storage.addAttribute(
                .paragraphStyle,
                value: style,
                range: range
            )
        }
    }

    /// Writes structural paragraph styles onto `storage` without changing
    /// characters. Only a style that actually differs is replaced. The caller
    /// groups this with the edit that caused it, so it adds no undo step.
    ///
    /// `edited` limits the work to blocks that intersect that range, plus one
    /// block on each side: a list item's gap depends on its neighbor. `nil`
    /// restyles the whole document, which load and a full replacement need.
    /// Returns how many blocks were visited.
    @discardableResult
    public static func applyStructuralSpacing(
        to storage: NSMutableAttributedString,
        edited: NSRange? = nil
    ) -> Int {
        let window: (visited: [Block], lookahead: Block?)
        if let edited {
            window = localBlockWindow(in: storage, edited: edited)
        } else {
            window = (blocks(in: storage), nil)
        }
        guard !window.visited.isEmpty else { return 0 }

        for (index, block) in window.visited.enumerated() {
            let next = index + 1 < window.visited.count ? window.visited[index + 1] : window.lookahead
            let style = paragraphStyle(for: block, next: next)
            var cursor = block.range.location
            let end = NSMaxRange(block.range)
            while cursor < end {
                var effective = NSRange()
                let current = storage.attribute(.paragraphStyle, at: cursor, effectiveRange: &effective) as? NSParagraphStyle
                let run = NSIntersectionRange(effective, block.range)
                if !paragraphStylesMatch(current, style), run.length > 0 {
                    storage.addAttribute(.paragraphStyle, value: style, range: run)
                }
                let nextCursor = NSMaxRange(run)
                cursor = nextCursor > cursor ? nextCursor : cursor + 1
            }
        }
        return window.visited.count
    }

    /// Finds only the edited paragraphs and their structural neighbors. The
    /// final lookahead is metadata for styling the last visited block and is
    /// not itself changed or included in the returned visit count.
    private static func localBlockWindow(
        in text: NSAttributedString,
        edited: NSRange
    ) -> (visited: [Block], lookahead: Block?) {
        let source = text.string as NSString
        guard source.length > 0 else { return ([], nil) }

        let location = min(max(edited.location, 0), source.length)
        let requestedEnd = edited.location.addingReportingOverflow(edited.length)
        let unclampedEnd = requestedEnd.overflow ? source.length : requestedEnd.partialValue
        let end = min(max(unclampedEnd, location), source.length)
        let firstProbe = min(location, source.length - 1)
        let lastProbe = edited.length == 0
            ? firstProbe
            : min(max(location, end - 1), source.length - 1)
        let firstParagraph = paragraph(in: source, containing: firstProbe)
        let lastParagraph = paragraph(in: source, containing: lastProbe)

        var visited: [Block] = []
        if let previous = previousBlock(in: text, source: source, before: firstParagraph.start) {
            visited.append(previous)
        }

        var cursor = firstParagraph.start
        while cursor <= lastParagraph.start, cursor < source.length {
            let info = paragraph(in: source, containing: cursor)
            if let current = block(in: text, source: source, start: info.start, contentsEnd: info.contentsEnd) {
                visited.append(current)
            }
            guard info.end > cursor else { break }
            cursor = info.end
        }

        var successorStart = lastParagraph.end
        let successor = nextBlock(in: text, source: source, atOrAfter: &successorStart)
        if let successor { visited.append(successor) }
        let lookahead = nextBlock(in: text, source: source, atOrAfter: &successorStart)
        return (visited, lookahead)
    }

    private static func paragraph(
        in source: NSString,
        containing location: Int
    ) -> (start: Int, end: Int, contentsEnd: Int) {
        var start = 0
        var end = 0
        var contentsEnd = 0
        source.getParagraphStart(
            &start,
            end: &end,
            contentsEnd: &contentsEnd,
            for: NSRange(location: location, length: 0)
        )
        return (start, end, contentsEnd)
    }

    private static func previousBlock(
        in text: NSAttributedString,
        source: NSString,
        before location: Int
    ) -> Block? {
        var cursor = location
        while cursor > 0 {
            let info = paragraph(in: source, containing: cursor - 1)
            if let result = block(in: text, source: source, start: info.start, contentsEnd: info.contentsEnd) {
                return result
            }
            guard info.start < cursor else { break }
            cursor = info.start
        }
        return nil
    }

    private static func nextBlock(
        in text: NSAttributedString,
        source: NSString,
        atOrAfter location: inout Int
    ) -> Block? {
        while location < source.length {
            let info = paragraph(in: source, containing: location)
            location = info.end
            if let result = block(in: text, source: source, start: info.start, contentsEnd: info.contentsEnd) {
                return result
            }
            guard info.end > info.start else { break }
        }
        return nil
    }

    private static func paragraphStylesMatch(_ current: NSParagraphStyle?, _ style: NSParagraphStyle) -> Bool {
        guard let current else { return false }
        return current.paragraphSpacing == style.paragraphSpacing
            && current.headIndent == style.headIndent
            && current.firstLineHeadIndent == style.firstLineHeadIndent
            && current.lineSpacing == style.lineSpacing
    }

    public static func plainText(from text: NSAttributedString) -> String {
        let source = text.string as NSString
        var result = ""
        var previousWasList = false
        for block in blocks(in: text) {
            if !result.isEmpty {
                result += previousWasList && block.marker != nil ? "\n" : "\n\n"
            }
            result += source.substring(with: block.range)
                .replacingOccurrences(of: "\u{2028}", with: "\n")
            previousWasList = block.marker != nil
        }
        return result
    }

    /// No font or size is exported: the receiving composer supplies typography.
    public static func html(from text: NSAttributedString) -> String {
        var result = "<!DOCTYPE html><html><head><meta charset=\"utf-8\"></head><body>"
        let source = text.string as NSString
        var openList: AparteListKind?
        for block in blocks(in: text) {
            let kind = block.marker?.kind
            if openList != kind {
                if let openList { result += openList == .ordered ? "</ol>" : "</ul>" }
                if let kind {
                    if kind == .ordered {
                        result += "<ol start=\"\(block.marker?.number ?? 1)\">"
                    } else {
                        result += "<ul>"
                    }
                }
                openList = kind
            }
            var range = block.range
            if let marker = block.marker {
                range.location += marker.utf16Length
                range.length -= marker.utf16Length
            }
            let tag = kind != nil ? "li" : block.headingLevel > 0 ? "h\(min(block.headingLevel, 6))" : "p"
            let number = kind == .ordered ? block.marker?.number : nil
            let value = number.map { " value=\"\($0)\"" } ?? ""
            result += "<\(tag)\(value)>\(inlineHTML(text, source: source, range: range))</\(tag)>"
        }
        if let openList { result += openList == .ordered ? "</ol>" : "</ul>" }
        return result + "</body></html>"
    }

    private static func inlineHTML(_ text: NSAttributedString, source: NSString, range: NSRange) -> String {
        var result = ""
        text.enumerateAttributes(in: range) { attributes, range, _ in
            var segment = escapeHTML(source.substring(with: range), replacingSoftBreaks: true)
            let traits = NSFontManager.shared.traits(of: attributes[.font] as? NSFont ?? AparteTypography.bodyFont)
            if traits.contains(.boldFontMask) { segment = "<strong>\(segment)</strong>" }
            if traits.contains(.italicFontMask) { segment = "<em>\(segment)</em>" }
            if (attributes[.underlineStyle] as? Int ?? 0) != 0 { segment = "<u>\(segment)</u>" }
            let link = ((attributes[.link] as? URL)?.absoluteString ?? attributes[.link] as? String).flatMap(LinkURLNormalizer.normalize)
            if let link { segment = "<a href=\"\(escapeHTML(link.absoluteString))\">\(segment)</a>" }
            result += segment
        }
        return result
    }

    private static func escapeHTML(_ value: String, replacingSoftBreaks: Bool = false) -> String {
        var escaped = ""
        escaped.reserveCapacity(value.utf8.count)
        for scalar in value.unicodeScalars {
            switch scalar {
            case "&": escaped += "&amp;"
            case "<": escaped += "&lt;"
            case ">": escaped += "&gt;"
            case "\"": escaped += "&quot;"
            case "'": escaped += "&#39;"
            case "\u{2028}" where replacingSoftBreaks: escaped += "<br>"
            default: escaped.unicodeScalars.append(scalar)
            }
        }
        return escaped
    }
}
