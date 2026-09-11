import AppKit

/// Shared paragraph boundaries for the editor, Markdown, and the clipboard.
public enum ParagraphFormatting {
    struct Block {
        let range: NSRange
        let marker: ListContinuation.Marker?
        let headingLevel: Int
    }

    static func blocks(in text: NSAttributedString) -> [Block] {
        let source = text.string as NSString
        var result: [Block] = []
        var cursor = 0
        var orderedNumber: Int?
        while cursor < source.length {
            var end = 0
            var contentsEnd = 0
            source.getParagraphStart(nil, end: &end, contentsEnd: &contentsEnd,
                                     for: NSRange(location: cursor, length: 0))
            let range = NSRange(location: cursor, length: contentsEnd - cursor)
            let line = source.substring(with: range)
            if !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let attributes = text.attributes(at: cursor, effectiveRange: nil)
                let kind = (attributes[.aparteListKind] as? String).flatMap(AparteListKind.init(rawValue:))
                let inlineOnly = attributes[.aparteInlineOnly] as? Bool == true
                var marker = inlineOnly ? nil : ListContinuation.marker(in: line, listKind: kind)
                if let item = marker, item.kind == .ordered {
                    let number = item.number ?? orderedNumber.map { $0 == Int.max ? Int.max : $0 + 1 } ?? 1
                    marker = ListContinuation.Marker(kind: .ordered, number: number, prefix: item.prefix)
                    orderedNumber = number
                } else { orderedNumber = nil }
                result.append(Block(
                    range: range,
                    marker: marker,
                    headingLevel: inlineOnly ? 0 : attributes[.aparteHeadingLevel] as? Int ?? 0
                ))
            } else { orderedNumber = nil }
            cursor = end
        }
        return result
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
                        let font = NSFontManager.shared.convert(AparteTypography.bodyFont,
                                                               toHaveTrait: AparteTypography.inlineTraits(in: attributes))
                        output.addAttribute(.font, value: font, range: run)
                    }
                }
                output.removeAttribute(.aparteListKind, range: fragment)
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
        for block in blocks(in: text) {
            if output.length > 0 {
                output.append(NSAttributedString(string: "\n", attributes: AparteTypography.baseAttributes))
            }
            let paragraph = NSMutableAttributedString(attributedString: text.attributedSubstring(from: block.range))
            paragraph.addAttribute(.paragraphStyle,
                                   value: block.marker == nil ? AparteTypography.bodyParagraphStyle : AparteTypography.listParagraphStyle,
                                   range: NSRange(location: 0, length: paragraph.length))
            output.append(paragraph)
        }
        if output.length > 0, text.string.last?.isNewline == true {
            output.append(NSAttributedString(string: "\n", attributes: AparteTypography.baseAttributes))
        }
        return output
    }

    public static func plainText(from text: NSAttributedString) -> String {
        let source = text.string as NSString
        var result = ""
        var previousWasList = false
        for block in blocks(in: text) {
            if !result.isEmpty {
                result += previousWasList && block.marker != nil ? "\n" : "\n\n"
            }
            let line = source.substring(with: block.range)
            if let marker = block.marker, marker.prefix.isEmpty {
                result += marker.kind == .unordered ? "• " : "\(marker.number ?? 1). "
            }
            result += line
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
