import AppKit
import XCTest
@testable import AparteCore

final class PasteNormalizerTests: XCTestCase {
    func testRichPasteKeepsMeaningAndDropsForeignStyling() {
        let source = NSMutableAttributedString(string: "Title and link")
        source.addAttributes(
            [
                .font: NSFont(name: "Courier", size: 30)!,
                .foregroundColor: NSColor.red,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
            ],
            range: NSRange(location: 0, length: 5)
        )
        source.addAttributes(
            [.link: URL(string: "https://example.com")!, .font: NSFont.systemFont(ofSize: 42)],
            range: NSRange(location: 10, length: 4)
        )

        let normalized = PasteNormalizer.normalized(source)

        XCTAssertEqual(normalized.string, source.string)
        XCTAssertNotEqual(normalized.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor, .red)
        XCTAssertEqual(normalized.attribute(.aparteHeadingLevel, at: 0, effectiveRange: nil) as? Int, 1)
        XCTAssertEqual(normalized.attribute(.underlineStyle, at: 0, effectiveRange: nil) as? Int, NSUnderlineStyle.single.rawValue)
        XCTAssertEqual(normalized.attribute(.link, at: 10, effectiveRange: nil) as? URL, URL(string: "https://example.com"))
    }

    func testPlainPasteUsesAparteBodyTypography() {
        let normalized = PasteNormalizer.normalized(NSAttributedString(string: "Plain"))
        let font = normalized.attribute(.font, at: 0, effectiveRange: nil) as? NSFont

        XCTAssertEqual(font?.pointSize, AparteTypography.bodySize)
        XCTAssertEqual(font?.familyName, AparteTypography.bodyFont.familyName)
    }

    func testRTFPasteboardInputPreservesBoldMeaning() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let boldFont = NSFontManager.shared.convert(AparteTypography.bodyFont, toHaveTrait: .boldFontMask)
        let source = NSAttributedString(string: "Bold", attributes: [.font: boldFont])
        let data = try source.data(
            from: NSRange(location: 0, length: source.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
        pasteboard.declareTypes([.rtf], owner: nil)
        pasteboard.setData(data, forType: .rtf)

        let result = try XCTUnwrap(PasteNormalizer.read(from: pasteboard))
        let font = try XCTUnwrap(result.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)

        XCTAssertTrue(NSFontManager.shared.traits(of: font).contains(.boldFontMask))
        XCTAssertEqual(font.pointSize, AparteTypography.bodySize)
    }
}
