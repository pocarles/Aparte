import AppKit
import XCTest
@testable import AparteCore

final class MarkdownCodecTests: XCTestCase {
    func testLiteralDelimitersInsideFormattingKeepTextAndLinkDestination() {
        let labels = ["A](example.com)B", "A**B", "<u>", "</u>", "A[B", #"A\*B"#, "A](https://other.example/path_(x))B"]
        for mask in 0..<16 {
            var traits: NSFontTraitMask = []
            if mask & 1 != 0 { traits.insert(.boldFontMask) }
            if mask & 2 != 0 { traits.insert(.italicFontMask) }
            var attributes: [NSAttributedString.Key: Any] = [.font: NSFontManager.shared.convert(AparteTypography.bodyFont, toHaveTrait: traits)]
            if mask & 4 != 0 { attributes[.underlineStyle] = 1 }
            if mask & 8 != 0 { attributes[.link] = URL(string: "https://target.example")! }
            let cases = labels + (mask == 0 ? [] : ["**literal**", "<u>literal</u>", "[literal](https://other.example)"])
            for label in cases {
                var text: NSAttributedString = NSAttributedString(string: label, attributes: attributes)
                for _ in 0..<3 {
                    let markdown = MarkdownCodec.markdown(from: text)
                    text = MarkdownCodec.render(markdown)
                    XCTAssertEqual(text.string, label, "mask \(mask): \(markdown)")
                    guard text.length == label.utf16.count else { continue }
                    text.enumerateAttributes(in: NSRange(location: 0, length: text.length)) { actual, _, _ in
                        let fontTraits = NSFontManager.shared.traits(of: actual[.font] as! NSFont)
                        XCTAssertEqual(fontTraits.contains(.boldFontMask), mask & 1 != 0, markdown)
                        XCTAssertEqual(fontTraits.contains(.italicFontMask), mask & 2 != 0, markdown)
                        XCTAssertEqual(actual[.underlineStyle] as? Int ?? 0, mask & 12 != 0 ? 1 : 0, markdown)
                        XCTAssertEqual((actual[.link] as? URL)?.absoluteString, mask & 8 != 0 ? "https://target.example" : nil, markdown)
                    }
                }
            }
        }
    }

    func testPlainDelimitersBesideGeneratedFormattingCannotCaptureIt() {
        let text = NSMutableAttributedString(string: "A**B ", attributes: AparteTypography.baseAttributes)
        text.append(NSAttributedString(string: "bold", attributes: [.font: NSFontManager.shared.convert(AparteTypography.bodyFont, toHaveTrait: .boldFontMask)]))
        text.append(NSAttributedString(string: " [tail](example.com)", attributes: AparteTypography.baseAttributes))
        let rendered = MarkdownCodec.render(MarkdownCodec.markdown(from: text))
        XCTAssertEqual(rendered.string, text.string)
        XCTAssertEqual(MarkdownCodec.markdown(from: rendered), MarkdownCodec.markdown(from: text))
    }

    func testUnformattedTypedMarkupKeepsExistingInterpretation() {
        let plain = NSAttributedString(string: "**word**", attributes: AparteTypography.baseAttributes)
        XCTAssertEqual(MarkdownCodec.markdown(from: plain), "**word**")
        XCTAssertEqual(MarkdownCodec.render(MarkdownCodec.markdown(from: plain)).string, "word")
    }

    func testEveryInlineFormattingCombinationSurvivesRepeatedRoundTrips() {
        for mask in 0..<16 {
            var attributes = AparteTypography.baseAttributes
            var traits: NSFontTraitMask = []
            if mask & 1 != 0 { traits.insert(.boldFontMask) }
            if mask & 2 != 0 { traits.insert(.italicFontMask) }
            attributes[.font] = NSFontManager.shared.convert(AparteTypography.bodyFont, toHaveTrait: traits)
            if mask & 4 != 0 { attributes[.underlineStyle] = 1 }
            if mask & 8 != 0 { attributes[.link] = URL(string: "https://example.com")! }
            var text: NSAttributedString = NSAttributedString(string: "word", attributes: attributes)
            for _ in 0..<4 {
                text = MarkdownCodec.render(MarkdownCodec.markdown(from: text))
                XCTAssertEqual(text.string, "word", "mask \(mask)")
                let actual = NSFontManager.shared.traits(of: text.attribute(.font, at: 0, effectiveRange: nil) as! NSFont)
                XCTAssertEqual(actual.contains(.boldFontMask), mask & 1 != 0, "mask \(mask)")
                XCTAssertEqual(actual.contains(.italicFontMask), mask & 2 != 0, "mask \(mask)")
                XCTAssertEqual(text.attribute(.underlineStyle, at: 0, effectiveRange: nil) as? Int ?? 0, mask & 12 != 0 ? 1 : 0)
                XCTAssertEqual(text.attribute(.link, at: 0, effectiveRange: nil) != nil, mask & 8 != 0)
            }
        }
    }

    func testNestedFormattingKeepsInnerAndOuterRuns() {
        for markdown in ["**outer *inner* outer**", "*outer **inner** outer*", "<u>outer ***inner*** outer</u>", "[outer **<u>*inner*</u>** outer](https://example.com)"] {
            let text = MarkdownCodec.render(markdown)
            XCTAssertEqual(text.string, "outer inner outer")
            let inner = (text.string as NSString).range(of: "inner")
            let traits = NSFontManager.shared.traits(of: text.attribute(.font, at: inner.location, effectiveRange: nil) as! NSFont)
            XCTAssertTrue(traits.contains(.boldFontMask))
            XCTAssertTrue(traits.contains(.italicFontMask))
            let reopened = MarkdownCodec.render(MarkdownCodec.markdown(from: text))
            XCTAssertEqual(reopened.string, text.string)
            XCTAssertEqual(MarkdownCodec.markdown(from: reopened), MarkdownCodec.markdown(from: text))
        }
    }

    func testAdjacentFormattingRunsKeepTheirOwnTraits() {
        for first in 0..<16 {
            for second in 0..<16 {
                let text = NSMutableAttributedString()
                for (mask, word) in [(first, "one"), (second, "two")] {
                    var traits: NSFontTraitMask = []
                    if mask & 1 != 0 { traits.insert(.boldFontMask) }
                    if mask & 2 != 0 { traits.insert(.italicFontMask) }
                    var attributes: [NSAttributedString.Key: Any] = [.font: NSFontManager.shared.convert(AparteTypography.bodyFont, toHaveTrait: traits)]
                    if mask & 4 != 0 { attributes[.underlineStyle] = 1 }
                    if mask & 8 != 0 { attributes[.link] = URL(string: "https://example.com")! }
                    text.append(NSAttributedString(string: word, attributes: attributes))
                }
                let markdown = MarkdownCodec.markdown(from: text)
                let rendered = MarkdownCodec.render(markdown)
                XCTAssertEqual(rendered.string, "onetwo", "\(first), \(second): \(markdown)")
                guard rendered.length == 6 else { continue }
                for (mask, index) in [(first, 0), (second, 3)] {
                    let traits = NSFontManager.shared.traits(of: rendered.attribute(.font, at: index, effectiveRange: nil) as! NSFont)
                    XCTAssertEqual(traits.contains(.boldFontMask), mask & 1 != 0, markdown)
                    XCTAssertEqual(traits.contains(.italicFontMask), mask & 2 != 0, markdown)
                    XCTAssertEqual(rendered.attribute(.underlineStyle, at: index, effectiveRange: nil) as? Int ?? 0, mask & 12 != 0 ? 1 : 0, markdown)
                    XCTAssertEqual(rendered.attribute(.link, at: index, effectiveRange: nil) != nil, mask & 8 != 0, markdown)
                }
            }
        }
    }

    func testBackslashesDoNotGrowAcrossReopening() {
        let original = #"one\two \\server\share trailing\"#
        var text = NSAttributedString(string: original)
        for _ in 0..<8 {
            text = MarkdownCodec.render(MarkdownCodec.markdown(from: text))
            XCTAssertEqual(text.string, original)
        }
    }

    func testDenseMarkupAndMalformedNearMatchesStayResponsive() {
        let dense = String(repeating: "**bold** *italic* <u>under</u> [web](https://example.com) ", count: 1800)
        let malformed = String(repeating: "[missing]( <u", count: 8000)
        let start = Date()
        XCTAssertEqual(MarkdownCodec.render(dense).string, String(repeating: "bold italic under web ", count: 1800))
        XCTAssertEqual(MarkdownCodec.render(malformed).string, malformed)
        XCTAssertLessThan(Date().timeIntervalSince(start), 10)
    }

    func testMalformedDelimitersRemainLiteral() {
        for text in ["before **unfinished", "before *unfinished", "before <u>unfinished", "before [unfinished](https://example.com", "</u> alone", "****", "<u></u>", "[](https://example.com)"] {
            XCTAssertEqual(MarkdownCodec.render(text).string, text)
        }
    }

    func testNonWebLinksBecomeVisibleTextAtEveryExportBoundary() {
        for destination in ["javascript:alert(1)", "file:///tmp/test", "data:text/plain,test", "not a url"] {
            let rendered = MarkdownCodec.render("[label](\(destination))")
            XCTAssertEqual(rendered.string, "label")
            XCTAssertNil(rendered.attribute(.link, at: 0, effectiveRange: nil))
            let rich = NSAttributedString(string: "label", attributes: [.link: destination])
            XCTAssertEqual(MarkdownCodec.markdown(from: rich), "label")
            XCTAssertFalse(ParagraphFormatting.html(from: rich).contains("href="))
        }
    }

    func testSupportedMarkdownRendersAndReturnsCleanMarkdown() {
        let markdown = """
        # A heading

        A **bold** and *italic* line with <u>underlining</u> and a [link](https://example.com).

        - First item
        1. Second item
        """

        let rendered = MarkdownCodec.render(markdown)
        let roundTrip = MarkdownCodec.markdown(from: rendered)

        XCTAssertEqual(roundTrip, markdown)
        XCTAssertEqual(rendered.string, "A heading\nA bold and italic line with underlining and a link.\n• First item\n1. Second item")
    }

    func testEmptyDocumentRoundTrips() {
        XCTAssertEqual(MarkdownCodec.markdown(from: MarkdownCodec.render("")), "")
    }

    func testTrailingNewlineIsPreserved() {
        let markdown = "one\n\ntwo\n"
        XCTAssertEqual(MarkdownCodec.markdown(from: MarkdownCodec.render(markdown)), markdown)
    }

    func testEmojiAtEndOfDocumentRoundTrips() {
        let markdown = "A thought 💭"
        XCTAssertEqual(MarkdownCodec.markdown(from: MarkdownCodec.render(markdown)), markdown)
    }

    func testMultiScalarEmojiSequencesRoundTrip() {
        let markdown = "France 🇫🇷\n\nHello 👋🏽"
        XCTAssertEqual(MarkdownCodec.markdown(from: MarkdownCodec.render(markdown)), markdown)
    }

    func testEmojiBeforeTrailingNewlineRoundTrips() {
        let markdown = "Done ✅\n"
        XCTAssertEqual(MarkdownCodec.markdown(from: MarkdownCodec.render(markdown)), markdown)
    }

    func testParagraphsUseOneEditorBoundaryAndCanonicalMarkdown() {
        let rendered = MarkdownCodec.render("First\n\n\nSecond\nThird")
        XCTAssertEqual(rendered.string, "First\nSecond\nThird")
        let canonical = "First\n\nSecond\n\nThird"
        XCTAssertEqual(MarkdownCodec.markdown(from: rendered), canonical)
        XCTAssertEqual(MarkdownCodec.markdown(from: MarkdownCodec.render(canonical)), canonical)
        let style = rendered.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertEqual(style?.paragraphSpacing, 30)
    }

    func testNumberedListsKeepTheirStartingNumber() {
        let markdown = "A plan\n\n7. First\n8. Second\n\nDone"
        XCTAssertEqual(MarkdownCodec.markdown(from: MarkdownCodec.render(markdown)), markdown)
    }

    func testListItemsUseFivePointParagraphSpacing() {
        for markdown in ["- First\n- Second", "1. First\n2. Second"] {
            let rendered = MarkdownCodec.render(markdown)
            let secondItem = (rendered.string as NSString).range(of: "Second")
            for location in [0, secondItem.location] {
                let style = rendered.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle
                XCTAssertEqual(style?.paragraphSpacing, 5)
            }
        }
    }
}
