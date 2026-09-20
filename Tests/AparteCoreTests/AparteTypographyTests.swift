import AppKit
import XCTest
@testable import AparteCore

final class AparteTypographyTests: XCTestCase {
    func testBodyFontCarriesRequestedInlineTraits() {
        let bold = AparteTypography.font(headingLevel: nil, traits: .boldFontMask)
        XCTAssertTrue(NSFontManager.shared.traits(of: bold).contains(.boldFontMask))
        XCTAssertEqual(bold.pointSize, AparteTypography.bodySize)

        let italic = AparteTypography.font(headingLevel: nil, traits: .italicFontMask)
        XCTAssertTrue(NSFontManager.shared.traits(of: italic).contains(.italicFontMask))
    }

    func testHeadingWithoutTraitsIsTheStructuralHeadingFont() {
        for level in 1...6 {
            XCTAssertEqual(AparteTypography.font(headingLevel: level, traits: []), AparteTypography.headingFont(level: level))
        }
    }

    func testBoldHeadingIsHeavierThanTheStructuralSemibold() {
        let heading = AparteTypography.headingFont(level: 1)
        let bold = AparteTypography.font(headingLevel: 1, traits: .boldFontMask)

        XCTAssertTrue(NSFontManager.shared.traits(of: bold).contains(.boldFontMask))
        XCTAssertGreaterThan(NSFontManager.shared.weight(of: bold), NSFontManager.shared.weight(of: heading))
        XCTAssertEqual(bold.pointSize, heading.pointSize)

        let italicHeading = AparteTypography.font(headingLevel: 1, traits: .italicFontMask)
        XCTAssertTrue(NSFontManager.shared.traits(of: italicHeading).contains(.italicFontMask))
    }

    func testParagraphSpacingIsStructural() {
        XCTAssertEqual(AparteTypography.paragraphSpacing, 18)
        XCTAssertEqual(AparteTypography.listItemSpacing, 5)
        XCTAssertEqual(AparteTypography.headingSpacing, AparteTypography.paragraphSpacing * 2)
        XCTAssertEqual(AparteTypography.headingSpacing, 36)
        XCTAssertEqual(AparteTypography.bodyParagraphStyle.paragraphSpacing, 18)
        XCTAssertEqual(AparteTypography.bodyParagraphStyle.lineSpacing, 5)
        XCTAssertEqual(AparteTypography.listParagraphStyle.paragraphSpacing, 5)

        let narrow = AparteTypography.markerIndent(for: "- ")
        let wide = AparteTypography.markerIndent(for: "10. ")
        XCTAssertGreaterThan(narrow, 0)
        XCTAssertGreaterThan(wide, narrow)
    }

    func testInlineTraitsRoundTripThroughAttributes() {
        var attributes: [NSAttributedString.Key: Any] = [.aparteHeadingLevel: 1]
        AparteTypography.applyInlineTraits([.boldFontMask], to: &attributes)
        XCTAssertEqual(attributes[.aparteInlineBold] as? Bool, true)
        XCTAssertEqual(AparteTypography.inlineTraits(in: attributes), [.boldFontMask])

        var body: [NSAttributedString.Key: Any] = [:]
        AparteTypography.applyInlineTraits([.boldFontMask, .italicFontMask], to: &body)
        XCTAssertNil(body[.aparteInlineBold])
        XCTAssertEqual(AparteTypography.inlineTraits(in: body), [.boldFontMask, .italicFontMask])
    }

    func testFullyBoldHeadingMatchesPlainHeadingAtEveryLevel() {
        for level in 1...6 {
            let hashes = String(repeating: "#", count: level)
            let fromPlainMarkdown = MarkdownCodec.render("\(hashes) Title")
            let fromBoldMarkdown = MarkdownCodec.render("\(hashes) **Title**")

            let fromPlainLine = NSMutableAttributedString(string: "Title", attributes: AparteTypography.baseAttributes)
            AparteTypography.applyHeadingTypography(
                level: level,
                to: fromPlainLine,
                range: NSRange(location: 0, length: fromPlainLine.length)
            )
            let fromBoldLine = NSMutableAttributedString(
                string: "Title",
                attributes: [.font: AparteTypography.font(headingLevel: nil, traits: .boldFontMask)]
            )
            AparteTypography.applyHeadingTypography(
                level: level,
                to: fromBoldLine,
                range: NSRange(location: 0, length: fromBoldLine.length)
            )

            let expected = AparteTypography.headingFont(level: level)
            for (label, text) in [
                ("plain markdown", fromPlainMarkdown),
                ("bold markdown", fromBoldMarkdown),
                ("plain line", fromPlainLine),
                ("bold line", fromBoldLine),
            ] {
                let font = text.attribute(.font, at: 0, effectiveRange: nil) as! NSFont
                XCTAssertEqual(font, expected, "level \(level) \(label)")
                XCTAssertEqual(font.pointSize, expected.pointSize, "level \(level) \(label) size")
                XCTAssertEqual(
                    NSFontManager.shared.weight(of: font),
                    NSFontManager.shared.weight(of: expected),
                    "level \(level) \(label) weight"
                )
                XCTAssertEqual(text.attribute(.aparteInlineBold, at: 0, effectiveRange: nil) as? Bool, false)
            }
        }
    }

    func testPartialBoldInsideHeadingIsHeavierThanTheHeadingFace() {
        for level in 1...6 {
            let hashes = String(repeating: "#", count: level)
            let rendered = MarkdownCodec.render("\(hashes) Hello **world**")
            let source = rendered.string as NSString
            let heading = rendered.attribute(.font, at: source.range(of: "Hello").location, effectiveRange: nil) as! NSFont
            let bold = rendered.attribute(.font, at: source.range(of: "world").location, effectiveRange: nil) as! NSFont
            XCTAssertEqual(heading, AparteTypography.headingFont(level: level))
            XCTAssertGreaterThan(NSFontManager.shared.weight(of: bold), NSFontManager.shared.weight(of: heading))
            XCTAssertEqual(bold.pointSize, heading.pointSize)
            XCTAssertEqual(rendered.attribute(.aparteInlineBold, at: source.range(of: "world").location, effectiveRange: nil) as? Bool, true)
            XCTAssertEqual(rendered.attribute(.aparteInlineBold, at: source.range(of: "Hello").location, effectiveRange: nil) as? Bool, false)

            let mixed = NSMutableAttributedString(string: "Hello world", attributes: AparteTypography.baseAttributes)
            let world = NSRange(location: 6, length: 5)
            mixed.addAttribute(.font, value: AparteTypography.font(headingLevel: nil, traits: .boldFontMask), range: world)
            AparteTypography.applyHeadingTypography(
                level: level,
                to: mixed,
                range: NSRange(location: 0, length: mixed.length)
            )
            let mixedHeading = mixed.attribute(.font, at: 0, effectiveRange: nil) as! NSFont
            let mixedBold = mixed.attribute(.font, at: 6, effectiveRange: nil) as! NSFont
            XCTAssertEqual(mixedHeading, AparteTypography.headingFont(level: level))
            XCTAssertGreaterThan(NSFontManager.shared.weight(of: mixedBold), NSFontManager.shared.weight(of: mixedHeading))
            XCTAssertEqual(mixed.attribute(.aparteInlineBold, at: 6, effectiveRange: nil) as? Bool, true)
        }
    }

    func testWholeHeadingBoldCollapsesBackToTheHeadingFace() {
        let text = NSMutableAttributedString(string: "Title", attributes: AparteTypography.baseAttributes)
        let range = NSRange(location: 0, length: text.length)
        AparteTypography.applyHeadingTypography(level: 1, to: text, range: range)
        var attributes = text.attributes(at: 0, effectiveRange: nil)
        AparteTypography.applyInlineTraits([.boldFontMask], to: &attributes)
        text.addAttributes(attributes, range: range)
        XCTAssertEqual(text.attribute(.aparteInlineBold, at: 0, effectiveRange: nil) as? Bool, true)
        XCTAssertGreaterThan(
            NSFontManager.shared.weight(of: text.attribute(.font, at: 0, effectiveRange: nil) as! NSFont),
            NSFontManager.shared.weight(of: AparteTypography.headingFont(level: 1))
        )

        AparteTypography.applyHeadingTypography(level: 1, to: text, range: range)
        let font = text.attribute(.font, at: 0, effectiveRange: nil) as! NSFont
        XCTAssertEqual(font, AparteTypography.headingFont(level: 1))
        XCTAssertEqual(text.attribute(.aparteInlineBold, at: 0, effectiveRange: nil) as? Bool, false)
    }
}
