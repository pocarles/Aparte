import AppKit

public extension NSAttributedString.Key {
    static let aparteHeadingLevel = NSAttributedString.Key("com.pocarles.aparte.headingLevel")
    static let aparteListKind = NSAttributedString.Key("com.pocarles.aparte.listKind")
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

    public static func headingFont(level: Int) -> NSFont {
        let sizes: [CGFloat] = [30, 24, 20, 18, 17, 16]
        let index = min(max(level, 1), sizes.count) - 1
        return .systemFont(ofSize: sizes[index], weight: .semibold)
    }

    public static var bodyParagraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 5
        style.paragraphSpacing = 8
        style.lineBreakMode = .byWordWrapping
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

