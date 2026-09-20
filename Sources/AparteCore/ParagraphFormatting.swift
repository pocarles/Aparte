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
            let range = NSRange(location: cursor, length: contentsEnd - cursor)
            let line = source.substring(with: range)
            // A soft break is content even when nothing follows it, so a block
            // that is only U+2028 survives. Other blank rows stay spacing.
            let hasContent = line.contains("\u{2028}")
                || !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if hasContent {
                let attributes = text.attributes(at: cursor, effectiveRange: nil)
                let inlineOnly = attributes[.aparteInlineOnly] as? Bool == true
                result.append(Block(
                    range: range,
                    marker: inlineOnly ? nil : ListContinuation.marker(in: line),
                    headingLevel: inlineOnly ? 0 : attributes[.aparteHeadingLevel] as? Int ?? 0
                ))
            }
            cursor = end
        }
        return result
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
        let output = NSMutableAttributedString()
        let blocks = blocks(in: text)
        for (index, block) in blocks.enumerated() {
            if output.length > 0 {
                output.append(NSAttributedString(string: "\n", attributes: AparteTypography.baseAttributes))
            }
            let paragraph = NSMutableAttributedString(attributedString: text.attributedSubstring(from: block.range))
            let next = index + 1 < blocks.count ? blocks[index + 1] : nil
            paragraph.addAttribute(.paragraphStyle,
                                   value: paragraphStyle(for: block, next: next),
                                   range: NSRange(location: 0, length: paragraph.length))
            output.append(paragraph)
        }
        if output.length > 0, text.string.last?.isNewline == true {
            output.append(NSAttributedString(string: "\n", attributes: AparteTypography.baseAttributes))
        }
        return output
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
        let blocks = blocks(in: storage)
        guard !blocks.isEmpty else { return 0 }
        let scope = edited ?? NSRange(location: 0, length: storage.length)
        // A block owns the newline that follows it, which `range` excludes.
        func intersects(_ block: Block) -> Bool {
            let owned = NSMaxRange(block.range) + 1
            return scope.location < owned && block.range.location < NSMaxRange(scope)
        }
        guard let first = blocks.firstIndex(where: intersects) else { return 0 }
        let last = blocks.lastIndex(where: intersects) ?? first
        let lower = max(0, first - 1)
        let upper = min(blocks.count - 1, last + 1)

        for index in lower...upper {
            let block = blocks[index]
            let next = index + 1 < blocks.count ? blocks[index + 1] : nil
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
        return upper - lower + 1
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
            result += "<\(tag)\(value)>\(inlineHTML(text, range: range))</\(tag)>"
        }
        if let openList { result += openList == .ordered ? "</ol>" : "</ul>" }
        return result + "</body></html>"
    }

    private static func inlineHTML(_ text: NSAttributedString, range: NSRange) -> String {
        var result = ""
        text.enumerateAttributes(in: range) { attributes, range, _ in
            var segment = escapeHTML((text.string as NSString).substring(with: range))
                .replacingOccurrences(of: "\u{2028}", with: "<br>")
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

    private static func escapeHTML(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
