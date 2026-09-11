import AppKit

// AppKit's HTML reader calls this WebResourceLoadDelegate selector for every
// subsidiary request, including redirects. No resource URL is allowed.
final class DenyHTMLResources: NSObject, @unchecked Sendable {
    // Keep the stateless delegate alive even if AppKit finishes a load later.
    static let shared = DenyHTMLResources()
    @objc(webView:resource:willSendRequest:redirectResponse:fromDataSource:)
    func webView(_ sender: AnyObject, resource: AnyObject, willSendRequest request: URLRequest,
                 redirectResponse: URLResponse?, fromDataSource: AnyObject) -> URLRequest? {
        nil
    }
}

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
            if let rawLink = (attributes[.link] as? URL)?.absoluteString ?? attributes[.link] as? String,
               let link = LinkURLNormalizer.normalize(rawLink) {
                output.addAttributes(
                    [.link: link, .foregroundColor: NSColor.linkColor, .underlineStyle: NSUnderlineStyle.single.rawValue],
                    range: range
                )
            }
            if let paragraph = attributes[.paragraphStyle] as? NSParagraphStyle,
               !paragraph.textLists.isEmpty {
                let kind: AparteListKind = paragraph.textLists[0].isOrdered ? .ordered : .unordered
                output.addAttribute(.aparteListKind, value: kind.rawValue, range: range)
            }
        }
        // Cocoa list markers end with a tab; some macOS versions also prepend one.
        // Replace that prefix only when the source paragraph is a native list.
        let source = input.string as NSString
        var replacements: [(NSRange, String)] = []
        var cursor = 0
        var previousList: NSTextList?
        var ordinal = 0
        while cursor < source.length {
            let paragraph = source.paragraphRange(for: NSRange(location: cursor, length: 0))
            if let style = input.attribute(.paragraphStyle, at: cursor, effectiveRange: nil) as? NSParagraphStyle,
               let list = style.textLists.first {
                let kind: AparteListKind = list.isOrdered ? .ordered : .unordered
                ordinal = previousList === list ? (ordinal == Int.max ? Int.max : ordinal + 1) : list.startingItemNumber
                previousList = list
                let line = source.substring(with: paragraph) as NSString
                var prefixLength = 0
                let generated = list.marker(forItemNumber: ordinal)
                for prefix in ["\t\(generated)\t", "\(generated)\t"] where line.hasPrefix(prefix) {
                    prefixLength = prefix.utf16.count
                    break
                }
                let marker = kind == .ordered ? "\(ordinal). " : "• "
                replacements.append((NSRange(location: cursor, length: prefixLength), marker))
                output.addAttribute(.aparteListKind, value: kind.rawValue, range: paragraph)
                output.removeAttribute(.aparteHeadingLevel, range: paragraph)
            } else { previousList = nil }
            cursor = NSMaxRange(paragraph)
        }
        for (range, marker) in replacements.reversed() {
            var attributes = output.attributes(at: range.location, effectiveRange: nil)
            attributes[.font] = AparteTypography.bodyFont
            output.replaceCharacters(in: range, with: NSAttributedString(string: marker, attributes: attributes))
        }
        return ParagraphFormatting.editorText(from: output)
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
               options: [.documentType: NSAttributedString.DocumentType.html,
                         .characterEncoding: String.Encoding.utf8.rawValue,
                         .webResourceLoadDelegate: DenyHTMLResources.shared],
               documentAttributes: nil
           ) {
            return normalized(html)
        }
        if let string = pasteboard.string(forType: .string) {
            return ParagraphFormatting.editorText(from: NSAttributedString(string: string, attributes: AparteTypography.baseAttributes))
        }
        return nil
    }
}
