import AppKit

public extension NSAttributedString.Key {
    static let aparteHeadingLevel = NSAttributedString.Key("com.pocarles.aparte.headingLevel")
    static let aparteInlineOnly = NSAttributedString.Key("com.pocarles.aparte.inlineOnly")
    static let aparteInlineBold = NSAttributedString.Key("com.pocarles.aparte.inlineBold")
}

public enum AparteListKind: String, Sendable {
    case unordered
    case ordered
}

public enum AparteTypography {
    public static let bodySize: CGFloat = 17

    public static var bodyFont: NSFont {
        .systemFont(ofSize: bodySize, weight: .regular)
    }

    /// Heading weight is structural. Only explicitly known bold survives when
    /// returning to body text; italic remains an inline trait in either block.
    public static func inlineTraits(in attributes: [NSAttributedString.Key: Any]) -> NSFontTraitMask {
        let font = attributes[.font] as? NSFont ?? bodyFont
        var traits = NSFontManager.shared.traits(of: font).intersection([.boldFontMask, .italicFontMask])
        if attributes[.aparteHeadingLevel] != nil, attributes[.aparteInlineBold] as? Bool != true {
            traits.remove(.boldFontMask)
        }
        return traits
    }

    public static func headingSize(level: Int) -> CGFloat {
        let sizes: [CGFloat] = [30, 24, 20, 18, 17, 16]
        let index = min(max(level, 1), sizes.count) - 1
        return sizes[index]
    }

    public static func headingFont(level: Int) -> NSFont {
        .systemFont(ofSize: headingSize(level: level), weight: .semibold)
    }

    /// The single place fonts are built. A heading is already semibold, which is
    /// reported as bold, so inline bold inside one needs a visibly heavier face.
    /// Whole-line bold is not contrast: callers drop it before asking for a font.
    public static func font(headingLevel: Int?, traits: NSFontTraitMask) -> NSFont {
        var font: NSFont
        if let headingLevel {
            font = traits.contains(.boldFontMask)
                ? .systemFont(ofSize: headingSize(level: headingLevel), weight: .heavy)
                : headingFont(level: headingLevel)
        } else {
            font = bodyFont
            if traits.contains(.boldFontMask) {
                font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
            }
        }
        if traits.contains(.italicFontMask) {
            font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
        }
        return font
    }

    public static func applyInlineTraits(
        _ traits: NSFontTraitMask,
        to attributes: inout [NSAttributedString.Key: Any]
    ) {
        let level = attributes[.aparteHeadingLevel] as? Int
        attributes[.font] = font(headingLevel: level, traits: traits)
        if level != nil {
            attributes[.aparteInlineBold] = traits.contains(.boldFontMask)
        } else {
            attributes.removeValue(forKey: .aparteInlineBold)
        }
    }

    /// True when every run in `range` carries inline bold. An empty range does not.
    public static func inlineBoldCovers(_ text: NSAttributedString, range: NSRange) -> Bool {
        guard range.length > 0 else { return false }
        var covers = true
        text.enumerateAttributes(in: range) { attributes, _, stop in
            if !inlineTraits(in: attributes).contains(.boldFontMask) {
                covers = false
                stop.pointee = true
            }
        }
        return covers
    }

    /// Heading weight is structural. Whole-line bold has no contrast against the
    /// heading face, so it is dropped; partial bold stays the heavier face.
    public static func applyHeadingTypography(
        level: Int,
        to text: NSMutableAttributedString,
        range: NSRange
    ) {
        guard range.length > 0 else { return }
        let wholeLineBold = inlineBoldCovers(text, range: range)
        var updates: [(NSRange, NSFontTraitMask, [NSAttributedString.Key: Any])] = []
        text.enumerateAttributes(in: range) { attributes, run, _ in
            var traits = inlineTraits(in: attributes)
            if wholeLineBold { traits.remove(.boldFontMask) }
            updates.append((run, traits, attributes))
        }
        for (run, traits, attributes) in updates {
            var updated = attributes
            updated.removeValue(forKey: .aparteInlineOnly)
            updated[.aparteHeadingLevel] = level
            applyInlineTraits(traits, to: &updated)
            if let font = updated[.font] {
                text.addAttribute(.font, value: font, range: run)
            }
            text.addAttribute(.aparteHeadingLevel, value: level, range: run)
            if let inlineBold = updated[.aparteInlineBold] {
                text.addAttribute(.aparteInlineBold, value: inlineBold, range: run)
            } else {
                text.removeAttribute(.aparteInlineBold, range: run)
            }
            text.removeAttribute(.aparteInlineOnly, range: run)
        }
    }

    /// Gap after a paragraph, and after the last item of a list. Headings use
    /// `headingSpacing`. Item-to-item gaps use `listItemSpacing`. Which one
    /// applies is decided from the document, not stored on the paragraph when
    /// it is typed.
    public static let paragraphSpacing: CGFloat = 18
    public static let listItemSpacing: CGFloat = 5
    public static let headingSpacing: CGFloat = paragraphSpacing * 2

    public static var bodyParagraphStyle: NSParagraphStyle {
        paragraphStyle(spacing: paragraphSpacing, headIndent: 0)
    }

    public static var listParagraphStyle: NSParagraphStyle {
        paragraphStyle(spacing: listItemSpacing, headIndent: 0)
    }

    /// `headIndent` hangs wrapped lines under the item text. The caller measures
    /// the marker prefix; a fixed indent would be wrong for "10. ".
    public static func paragraphStyle(spacing: CGFloat, headIndent: CGFloat) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 5
        style.paragraphSpacing = spacing
        style.firstLineHeadIndent = 0
        style.headIndent = headIndent
        style.lineBreakMode = .byWordWrapping
        return style
    }

    /// Width of `prefix` in the body font, rounded up so the wrap clears the marker.
    public static func markerIndent(for prefix: String) -> CGFloat {
        ceil((prefix as NSString).size(withAttributes: [.font: bodyFont]).width)
    }

    public static var baseAttributes: [NSAttributedString.Key: Any] {
        [
            .font: bodyFont,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: bodyParagraphStyle,
        ]
    }
}
