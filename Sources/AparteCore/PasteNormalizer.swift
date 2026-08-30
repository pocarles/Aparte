import AppKit

public enum PasteNormalizer {
    public static func normalized(_ input: NSAttributedString) -> NSAttributedString {
        let output = NSMutableAttributedString(string: input.string, attributes: AparteTypography.baseAttributes)
        guard input.length > 0 else { return output }

        input.enumerateAttributes(in: NSRange(location: 0, length: input.length)) { attributes, range, _ in
            var font = AparteTypography.bodyFont
            if let sourceFont = attributes[.font] as? NSFont {
                let traits = NSFontManager.shared.traits(of: sourceFont)
                if traits.contains(.boldFontMask) {
                    font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
                }
                if traits.contains(.italicFontMask) {
                    font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
                }
                output.addAttribute(.font, value: font, range: range)

                if sourceFont.pointSize >= 22 {
                    let level = sourceFont.pointSize >= 28 ? 1 : 2
                    output.addAttributes(
                        [.font: AparteTypography.headingFont(level: level), .aparteHeadingLevel: level],
                        range: range
                    )
                }
            }

            if let underline = attributes[.underlineStyle] as? Int, underline != 0 {
                output.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            }
            if let link = attributes[.link] {
                output.addAttributes(
                    [.link: link, .foregroundColor: NSColor.linkColor, .underlineStyle: NSUnderlineStyle.single.rawValue],
                    range: range
                )
            }
            if let paragraph = attributes[.paragraphStyle] as? NSParagraphStyle,
               !paragraph.textLists.isEmpty {
                let marker = paragraph.textLists[0].markerFormat
                let kind: AparteListKind = marker == .decimal ? .ordered : .unordered
                output.addAttribute(.aparteListKind, value: kind.rawValue, range: range)
            }
        }
        return output
    }

    public static func read(from pasteboard: NSPasteboard) -> NSAttributedString? {
        if let data = pasteboard.data(forType: .rtf),
           let richText = try? NSAttributedString(
               data: data,
               options: [.documentType: NSAttributedString.DocumentType.rtf],
               documentAttributes: nil
           ) {
            return normalized(richText)
        }
        if let data = pasteboard.data(forType: .html),
           let html = try? NSAttributedString(
               data: data,
               options: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue],
               documentAttributes: nil
           ) {
            return normalized(html)
        }
        if let string = pasteboard.string(forType: .string) {
            return NSAttributedString(string: string, attributes: AparteTypography.baseAttributes)
        }
        return nil
    }
}
