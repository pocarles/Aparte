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
