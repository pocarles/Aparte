import AppKit

public enum MarkdownCodec {
    private struct InlineToken {
        let range: Range<String.Index>
        let visible: String
        let attributes: [NSAttributedString.Key: Any]
    }

    public static func render(_ markdown: String) -> NSAttributedString {
        let output = NSMutableAttributedString()
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false)

        for (index, rawLine) in lines.enumerated() {
            let line = String(rawLine)
            let block = parseBlock(line)
            let rendered = renderInline(block.content)

            if block.headingLevel > 0 {
                rendered.addAttributes(
                    [
                        .font: AparteTypography.headingFont(level: block.headingLevel),
                        .aparteHeadingLevel: block.headingLevel,
                    ],
                    range: NSRange(location: 0, length: rendered.length)
                )
            }

            if let listKind = block.listKind {
                let marker = listKind == .unordered ? "• " : "\(block.listNumber). "
                rendered.insert(NSAttributedString(string: marker, attributes: AparteTypography.baseAttributes), at: 0)
                rendered.addAttribute(
                    .aparteListKind,
                    value: listKind.rawValue,
                    range: NSRange(location: 0, length: rendered.length)
                )
            }

            output.append(rendered)
            if index < lines.count - 1 {
                output.append(NSAttributedString(string: "\n", attributes: AparteTypography.baseAttributes))
            }
        }

        if output.length == 0 {
            output.append(NSAttributedString(string: "", attributes: AparteTypography.baseAttributes))
        }
        return output
    }

    public static func markdown(from attributedString: NSAttributedString) -> String {
        guard attributedString.length > 0 else { return "" }
        let source = attributedString.string as NSString
        var lines: [String] = []

        source.enumerateSubstrings(
            in: NSRange(location: 0, length: source.length),
            options: [.byParagraphs, .substringNotRequired]
        ) { _, paragraphRange, _, _ in
            var contentRange = paragraphRange
            while contentRange.length > 0 {
                let last = NSMaxRange(contentRange) - 1
                if CharacterSet.newlines.contains(UnicodeScalar(source.character(at: last))!) {
                    contentRange.length -= 1
                } else {
                    break
                }
            }

            let headingLevel = integerAttribute(.aparteHeadingLevel, in: attributedString, range: contentRange)
            let listKind = stringAttribute(.aparteListKind, in: attributedString, range: contentRange)
            var visibleRange = contentRange
            var prefix = headingLevel > 0 ? String(repeating: "#", count: headingLevel) + " " : ""

            if listKind == AparteListKind.unordered.rawValue {
                prefix = "- "
                visibleRange = droppingListMarker(in: source, range: contentRange)
            } else if listKind == AparteListKind.ordered.rawValue {
                prefix = "1. "
                visibleRange = droppingListMarker(in: source, range: contentRange)
            }

            let inline = serializeInline(
                attributedString,
                range: visibleRange,
                ignoreBold: headingLevel > 0
            )
            lines.append(prefix + inline)
        }

        if source.hasSuffix("\n") {
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private static func parseBlock(_ line: String) -> (
        content: String,
        headingLevel: Int,
        listKind: AparteListKind?,
        listNumber: Int
    ) {
        if let match = line.firstMatch(of: /^(#{1,6})\s+(.*)$/) {
            return (String(match.2), match.1.count, nil, 1)
        }
        if let match = line.firstMatch(of: /^[-*+]\s+(.*)$/) {
            return (String(match.1), 0, .unordered, 1)
        }
        if let match = line.firstMatch(of: /^(\d+)\.\s+(.*)$/) {
            return (String(match.2), 0, .ordered, Int(match.1) ?? 1)
        }
        return (line, 0, nil, 1)
    }

    private static func renderInline(_ source: String) -> NSMutableAttributedString {
        let output = NSMutableAttributedString()
        var cursor = source.startIndex

        while cursor < source.endIndex {
            let remainder = source[cursor...]
            guard let token = nextToken(in: remainder) else {
                output.append(NSAttributedString(string: String(remainder), attributes: AparteTypography.baseAttributes))
                break
            }

            if cursor < token.range.lowerBound {
                output.append(NSAttributedString(
                    string: String(source[cursor..<token.range.lowerBound]),
                    attributes: AparteTypography.baseAttributes
                ))
            }

            var attributes = AparteTypography.baseAttributes
            token.attributes.forEach { attributes[$0.key] = $0.value }
            output.append(NSAttributedString(string: token.visible, attributes: attributes))
            cursor = token.range.upperBound
        }
        return output
    }

    private static func nextToken(in source: Substring) -> InlineToken? {
        var tokens: [InlineToken] = []
        let string = String(source)

        if let match = string.firstMatch(of: /\*\*([^\n]+?)\*\*/) {
            let range = match.range
            let font = NSFontManager.shared.convert(AparteTypography.bodyFont, toHaveTrait: .boldFontMask)
            tokens.append(InlineToken(range: range, visible: String(match.1), attributes: [.font: font]))
        }
        if let match = string.firstMatch(of: /\*([^*\n]+?)\*/) {
            let range = match.range
            let font = NSFontManager.shared.convert(AparteTypography.bodyFont, toHaveTrait: .italicFontMask)
            tokens.append(InlineToken(range: range, visible: String(match.1), attributes: [.font: font]))
        }
        if let match = string.firstMatch(of: /<u>([^\n]+?)<\/u>/) {
            tokens.append(InlineToken(
                range: match.range,
                visible: String(match.1),
                attributes: [.underlineStyle: NSUnderlineStyle.single.rawValue]
            ))
        }
        if let match = string.firstMatch(of: /\[([^\]\n]+)\]\(([^)\n]+)\)/),
           let url = URL(string: String(match.2)) {
            tokens.append(InlineToken(
                range: match.range,
                visible: String(match.1),
                attributes: [.link: url, .foregroundColor: NSColor.linkColor, .underlineStyle: NSUnderlineStyle.single.rawValue]
            ))
        }

        guard let first = tokens.min(by: { $0.range.lowerBound < $1.range.lowerBound }) else { return nil }
        let lowerOffset = string.distance(from: string.startIndex, to: first.range.lowerBound)
        let upperOffset = string.distance(from: string.startIndex, to: first.range.upperBound)
        let lower = source.index(source.startIndex, offsetBy: lowerOffset)
        let upper = source.index(source.startIndex, offsetBy: upperOffset)
        return InlineToken(range: lower..<upper, visible: first.visible, attributes: first.attributes)
    }

    private static func serializeInline(
        _ attributedString: NSAttributedString,
        range: NSRange,
        ignoreBold: Bool
    ) -> String {
        guard range.length > 0 else { return "" }
        var result = ""
        attributedString.enumerateAttributes(in: range) { attributes, runRange, _ in
            let text = (attributedString.string as NSString).substring(with: runRange)
            let font = attributes[.font] as? NSFont ?? AparteTypography.bodyFont
            let traits = NSFontManager.shared.traits(of: font)
            let isBold = !ignoreBold && traits.contains(.boldFontMask)
            let isItalic = traits.contains(.italicFontMask)
            let isUnderlined = (attributes[.underlineStyle] as? Int ?? 0) != 0
            let link = (attributes[.link] as? URL) ?? (attributes[.link] as? String).flatMap(URL.init(string:))

            var segment = escapePlainText(text)
            if isBold { segment = "**\(segment)**" }
            if isItalic { segment = "*\(segment)*" }
            if isUnderlined && link == nil { segment = "<u>\(segment)</u>" }
            if let link { segment = "[\(segment)](\(link.absoluteString))" }
            result += segment
        }
        return result
    }

    private static func escapePlainText(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
    }

    private static func integerAttribute(
        _ key: NSAttributedString.Key,
        in attributedString: NSAttributedString,
        range: NSRange
    ) -> Int {
        guard range.length > 0 else { return 0 }
        return attributedString.attribute(key, at: range.location, effectiveRange: nil) as? Int ?? 0
    }

    private static func stringAttribute(
        _ key: NSAttributedString.Key,
        in attributedString: NSAttributedString,
        range: NSRange
    ) -> String? {
        guard range.length > 0 else { return nil }
        return attributedString.attribute(key, at: range.location, effectiveRange: nil) as? String
    }

    private static func droppingListMarker(in source: NSString, range: NSRange) -> NSRange {
        guard range.length > 0 else { return range }
        let line = source.substring(with: range)
        if line.hasPrefix("• ") {
            return NSRange(location: range.location + 2, length: max(0, range.length - 2))
        }
        if let match = line.firstMatch(of: /^\d+\.\s/) {
            let count = line.distance(from: match.range.lowerBound, to: match.range.upperBound)
            return NSRange(location: range.location + count, length: max(0, range.length - count))
        }
        return range
    }
}
