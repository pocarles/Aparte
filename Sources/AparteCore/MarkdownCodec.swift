import AppKit

public enum MarkdownCodec {
    private struct Block {
        let content: String
        let headingLevel: Int
        let list: AparteListKind?
        let listNumber: Int
        let markerStemLength: Int
    }

    private struct Line {
        let raw: String
        let block: Block
    }

    private struct InlineToken {
        let range: NSRange
        let kind: Int
        var partner: Int?
        var link: URL?
    }

    public static func render(_ markdown: String) -> NSAttributedString {
        let baseAttributes = AparteTypography.baseAttributes
        let output = NSMutableAttributedString()
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false).map { rawLine in
            let raw = String(rawLine)
            return Line(raw: raw, block: parseBlock(raw))
        }

        for index in lines.indices {
            let raw = lines[index].raw
            let block = lines[index].block
            // CommonMark ends an ATX heading at its newline, so trailing spaces
            // there are not a hard break. Otherwise a break joins this line to
            // the next unless that line starts its own block. A list item's
            // continuation has no marker of its own.
            let next = index + 1 < lines.count ? lines[index + 1].block : nil
            let continues = next.map { !$0.content.isEmpty && $0.headingLevel == 0 && $0.list == nil } ?? false
            let hardBreak = block.headingLevel == 0 && continues && raw.hasSuffix("  ")
            var content = block.content
            var list = block.list
            var listNumber = block.listNumber
            if hardBreak, content.hasSuffix("  ") {
                content.removeLast(2)
            } else if hardBreak, list != nil {
                // The spaces may be the list marker's required separator rather
                // than content. If stripping them removes that separator, the
                // original parser treated the remainder as plain text.
                let stripped = String(raw.dropLast(2))
                if stripped.count <= block.markerStemLength {
                    content = stripped
                    list = nil
                    listNumber = 1
                }
            }
            let rendered = renderInline(content, baseAttributes: baseAttributes)

            if block.headingLevel > 0 {
                AparteTypography.applyHeadingTypography(
                    level: block.headingLevel,
                    to: rendered,
                    range: NSRange(location: 0, length: rendered.length)
                )
            }

            if let list {
                let marker = list == .unordered ? "• " : "\(listNumber). "
                rendered.insert(NSAttributedString(string: marker, attributes: baseAttributes), at: 0)
            }

            output.append(rendered)
            if index < lines.count - 1 {
                let separator = hardBreak ? "\u{2028}" : "\n"
                output.append(NSAttributedString(string: separator, attributes: baseAttributes))
            }
        }

        if output.length == 0 {
            output.append(NSAttributedString(string: "", attributes: baseAttributes))
        }
        ParagraphFormatting.normalizeEditorTextInPlace(output)
        return output
    }

    public static func markdown(from attributedString: NSAttributedString) -> String {
        guard attributedString.length > 0 else { return "" }
        let source = attributedString.string as NSString
        var result = ""
        var previousWasList = false

        for block in ParagraphFormatting.blocks(in: attributedString) {
            let headingLevel = block.headingLevel
            var visibleRange = block.range
            var prefix = headingLevel > 0 ? String(repeating: "#", count: headingLevel) + " " : ""
            if let marker = block.marker {
                prefix = marker.kind == .unordered ? "- " : "\(marker.number ?? 1). "
                visibleRange.location += marker.utf16Length
                visibleRange.length -= marker.utf16Length
            }

            // A soft break with nothing after it carries no meaning. Dropping
            // it here keeps the round-trip from writing stray trailing spaces.
            let content = trimmingTrailingSoftBreak(attributedString, range: visibleRange)
            // Each side of a soft break is its own inline run. A delimiter that
            // straddled the break would be parsed on separate physical lines
            // and come back as literal asterisks.
            let segments = content.filter { $0.length > 0 }
            // Nothing but soft breaks: the block carries no text to write.
            guard !segments.isEmpty else { continue }
            let inline = segments
                .map { serializeInline(attributedString, range: $0, ignoreBold: headingLevel > 0) }
                .joined(separator: "  \n")
            if !result.isEmpty {
                result += previousWasList && block.marker != nil ? "\n" : "\n\n"
            }
            result += prefix + inline
            previousWasList = block.marker != nil
        }

        if !result.isEmpty, source.hasSuffix("\n") {
            result += "\n"
        }
        return result
    }

    private static func parseBlock(_ line: String) -> Block {
        if let match = line.firstMatch(of: /^(#{1,6})\s+(.*)$/) {
            return Block(content: String(match.2), headingLevel: match.1.count, list: nil, listNumber: 1, markerStemLength: 0)
        }
        if let match = line.firstMatch(of: /^[-*+]\s+(.*)$/) {
            return Block(content: String(match.1), headingLevel: 0, list: .unordered, listNumber: 1, markerStemLength: 1)
        }
        if let match = line.firstMatch(of: /^(\d+)\.\s+(.*)$/) {
            return Block(
                content: String(match.2),
                headingLevel: 0,
                list: .ordered,
                listNumber: Int(match.1) ?? 1,
                markerStemLength: match.1.count + 1
            )
        }
        return Block(content: line, headingLevel: 0, list: nil, listNumber: 1, markerStemLength: 0)
    }

    private static func renderInline(
        _ source: String,
        baseAttributes: [NSAttributedString.Key: Any]
    ) -> NSMutableAttributedString {
        // Most pad lines are ordinary prose. Avoid building UTF-16, token,
        // opener, and parenthesis collections when no supported delimiter can
        // affect the result.
        let hasDelimiter = source.utf8.contains { unit in
            unit == 92 || unit == 42 || unit == 60 || unit == 91 || unit == 93
        }
        guard hasDelimiter else {
            return NSMutableAttributedString(string: source, attributes: baseAttributes)
        }

        // Pair delimiters once, then emit runs once. Unpaired delimiters remain
        // literal, without rescanning the rest of a long malformed paragraph.
        let units = Array(source.utf16)
        let string = source as NSString
        var tokens: [InlineToken] = []
        var openers = [[Int]](repeating: [], count: 5)
        var parentheses: [Int: Int] = [:]
        var openings: [Int] = []
        for index in units.indices {
            if units[index] == 40 { openings.append(index) }
            if units[index] == 41, let start = openings.popLast() { parentheses[start] = index }
        }
        func add(_ start: Int, _ length: Int, _ kind: Int, closing: Bool = false, link: URL? = nil) {
            let index = tokens.count
            tokens.append(InlineToken(range: NSRange(location: start, length: length), kind: kind))
            if closing, let opener = openers[kind].popLast(), NSMaxRange(tokens[opener].range) < start {
                tokens[opener].partner = index
                tokens[opener].link = link
                tokens[index].partner = opener
            } else if !closing { openers[kind].append(index) }
        }
        var cursor = 0
        while cursor < units.count {
            if units[cursor] == 92, cursor + 1 < units.count, [92, 42, 91, 93, 60, 62].contains(units[cursor + 1]) {
                tokens.append(InlineToken(range: NSRange(location: cursor, length: 2), kind: 0))
                cursor += 2
            } else if units[cursor] == 42 {
                var end = cursor
                while end < units.count, units[end] == 42 { end += 1 }
                while cursor < end {
                    let remaining = end - cursor
                    let closesBold = !openers[1].isEmpty && remaining >= 2
                    let closesItalic = !openers[2].isEmpty && remaining % 2 == 1
                    let closing = closesBold || closesItalic
                    let length = closing ? (closesBold ? 2 : 1) : (remaining >= 2 ? 2 : 1)
                    add(cursor, length, length == 2 ? 1 : 2, closing: closing)
                    cursor += length
                }
            } else if cursor + 3 <= units.count, units[cursor..<cursor + 3].elementsEqual([60, 117, 62]) {
                add(cursor, 3, 3)
                cursor += 3
            } else if cursor + 4 <= units.count, units[cursor..<cursor + 4].elementsEqual([60, 47, 117, 62]) {
                add(cursor, 4, 3, closing: true)
                cursor += 4
            } else if units[cursor] == 91 {
                add(cursor, 1, 4)
                cursor += 1
            } else if units[cursor] == 93, cursor + 1 < units.count, units[cursor + 1] == 40,
                      let end = parentheses[cursor + 1], !openers[4].isEmpty {
                let destination = string.substring(with: NSRange(location: cursor + 2, length: end - cursor - 2))
                add(cursor, end - cursor + 1, 4, closing: true, link: LinkURLNormalizer.normalize(destination))
                cursor = end + 1
            } else { cursor += 1 }
        }

        let output = NSMutableAttributedString()
        var active = [Int](repeating: 0, count: 5)
        var links: [URL?] = []
        let bodyFont = baseAttributes[.font] as? NSFont ?? AparteTypography.bodyFont
        var fonts = [NSFont?](repeating: nil, count: 4)
        func append(_ text: String) {
            guard !text.isEmpty else { return }
            var attributes = baseAttributes
            let fontIndex = (active[1] > 0 ? 1 : 0) | (active[2] > 0 ? 2 : 0)
            if fonts[fontIndex] == nil {
                var traits: NSFontTraitMask = []
                if fontIndex & 1 != 0 { traits.insert(.boldFontMask) }
                if fontIndex & 2 != 0 { traits.insert(.italicFontMask) }
                fonts[fontIndex] = NSFontManager.shared.convert(bodyFont, toHaveTrait: traits)
            }
            attributes[.font] = fonts[fontIndex]
            if active[3] > 0 { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
            if let link = links.last ?? nil {
                attributes[.link] = link
                attributes[.foregroundColor] = NSColor.linkColor
                attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            }
            output.append(NSAttributedString(string: text, attributes: attributes))
        }
        cursor = 0
        for (index, token) in tokens.enumerated() {
            append(string.substring(with: NSRange(location: cursor, length: token.range.location - cursor)))
            if token.kind == 0 { append(string.substring(with: NSRange(location: token.range.location + 1, length: 1))) }
            else if let partner = token.partner {
                let opening = partner > index
                active[token.kind] += opening ? 1 : -1
                if token.kind == 4 {
                    if opening { links.append(token.link) } else { links.removeLast() }
                }
            } else { append(string.substring(with: token.range)) }
            cursor = NSMaxRange(token.range)
        }
        append(string.substring(from: cursor))
        return output
    }

    /// Drops U+2028 characters that end the block, then splits what remains.
    private static func trimmingTrailingSoftBreak(
        _ text: NSAttributedString,
        range: NSRange
    ) -> [NSRange] {
        let source = text.string as NSString
        var end = NSMaxRange(range)
        while end > range.location, source.character(at: end - 1) == 0x2028 {
            end -= 1
        }
        var segments: [NSRange] = []
        var start = range.location
        var cursor = range.location
        while cursor < end {
            if source.character(at: cursor) == 0x2028 {
                segments.append(NSRange(location: start, length: cursor - start))
                start = cursor + 1
            }
            cursor += 1
        }
        segments.append(NSRange(location: start, length: end - start))
        return segments
    }

    private static func serializeInline(
        _ attributedString: NSAttributedString,
        range: NSRange,
        ignoreBold: Bool
    ) -> String {
        guard range.length > 0 else { return "" }
        var result = ""
        var open: [(start: String, end: String)] = []
        // Plain typed Markdown keeps its existing interpretation. Once a
        // paragraph contains generated formatting, escape its text so literal
        // delimiters cannot open, close, or retarget that formatting.
        var protectMarkup = ignoreBold
        if !protectMarkup {
            attributedString.enumerateAttributes(in: range) { attributes, _, stop in
                let link = ((attributes[.link] as? URL)?.absoluteString ?? attributes[.link] as? String).flatMap(LinkURLNormalizer.normalize)
                if !AparteTypography.inlineTraits(in: attributes).isEmpty
                    || (attributes[.underlineStyle] as? Int ?? 0) != 0 || link != nil {
                    protectMarkup = true
                    stop.pointee = true
                }
            }
        }
        let source = attributedString.string as NSString
        attributedString.enumerateAttributes(in: range) { attributes, runRange, _ in
            let text = source.substring(with: runRange)
            let font = attributes[.font] as? NSFont ?? AparteTypography.bodyFont
            let traits = NSFontManager.shared.traits(of: font)
            let isBold = (!ignoreBold || attributes[.aparteInlineBold] as? Bool == true) && traits.contains(.boldFontMask)
            let isItalic = traits.contains(.italicFontMask)
            let isUnderlined = (attributes[.underlineStyle] as? Int ?? 0) != 0
            let link = ((attributes[.link] as? URL)?.absoluteString ?? attributes[.link] as? String).flatMap(LinkURLNormalizer.normalize)

            var desired: [(start: String, end: String)] = []
            if let link {
                let destination = link.absoluteString.replacingOccurrences(of: "(", with: "%28").replacingOccurrences(of: ")", with: "%29")
                desired.append(("[", "](\(destination))"))
            }
            if isUnderlined && link == nil { desired.append(("<u>", "</u>")) }
            if isItalic { desired.append(("*", "*")) }
            if isBold { desired.append(("**", "**")) }
            var common = 0
            while common < min(open.count, desired.count),
                  open[common].start == desired[common].start, open[common].end == desired[common].end {
                common += 1
            }
            for delimiter in open[common...].reversed() { result += delimiter.end }
            for delimiter in desired[common...] { result += delimiter.start }
            result += escapePlainText(text, protectMarkup: protectMarkup)
            open = desired
        }
        for delimiter in open.reversed() { result += delimiter.end }
        return result
    }

    private static func escapePlainText(_ text: String, protectMarkup: Bool) -> String {
        var result = ""
        for character in text {
            if character == "\\" || protectMarkup && "*[]<>".contains(character) { result.append("\\") }
            result.append(character)
        }
        return result
    }

}
