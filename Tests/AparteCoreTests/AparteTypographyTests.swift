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
}
