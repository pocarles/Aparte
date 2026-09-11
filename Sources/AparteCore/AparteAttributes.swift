import AppKit

public extension NSAttributedString.Key {
    static let aparteHeadingLevel = NSAttributedString.Key("com.pocarles.aparte.headingLevel")
    static let aparteListKind = NSAttributedString.Key("com.pocarles.aparte.listKind")
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

    public static func headingFont(level: Int) -> NSFont {
        let sizes: [CGFloat] = [30, 24, 20, 18, 17, 16]
        let index = min(max(level, 1), sizes.count) - 1
        return .systemFont(ofSize: sizes[index], weight: .semibold)
    }

    public static var bodyParagraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 5
        style.paragraphSpacing = 30
        style.lineBreakMode = .byWordWrapping
        return style
    }

    public static var listParagraphStyle: NSParagraphStyle {
        let style = bodyParagraphStyle.mutableCopy() as! NSMutableParagraphStyle
        style.paragraphSpacing = 5
        return style
    }

    public static var baseAttributes: [NSAttributedString.Key: Any] {
        [
            .font: bodyFont,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: bodyParagraphStyle,
        ]
    }
}
