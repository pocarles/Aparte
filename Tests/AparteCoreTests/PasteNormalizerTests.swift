import AppKit
import XCTest
@testable import AparteCore

final class PasteNormalizerTests: XCTestCase {
    func testGeneratedMarkerSeparatorsDoNotChangePrefixMatching() {
        for marker in ["7.", "•"] {
            for generated in [marker, "\t" + marker, marker + "\t", " \t" + marker + "\t "] {
                for leadingTab in ["", "\t"] {
                    let prefix = leadingTab + marker + "\t"
                    let line = prefix + "One\tinside\t"
                    let length = PasteNormalizer.nativeListPrefixLength(in: line as NSString, generatedMarker: generated, canonicalMarker: marker)
                    XCTAssertEqual(length, prefix.utf16.count)
                    XCTAssertEqual((line as NSString).substring(from: length), "One\tinside\t")
                }
                for line in [marker + "x\tOne", "\t" + marker + "x\tOne", "\tuser\ttabs", marker + " One"] {
                    XCTAssertEqual(PasteNormalizer.nativeListPrefixLength(in: line as NSString, generatedMarker: generated, canonicalMarker: marker), 0)
                }
            }
        }
        XCTAssertEqual(PasteNormalizer.nativeListPrefixLength(in: "\t\tOne", generatedMarker: " \t ", canonicalMarker: ""), 0)
    }

    func testCanonicalMarkerFallbackMatchesOnlyTheResolvedItem() {
        for (generated, canonical) in [("7", "7."), ("○", "•"), ("", "•")] {
            let visibleMarkers = generated.isEmpty ? [canonical] : [generated, canonical]
            for visible in visibleMarkers {
                for leadingTab in ["", "\t"] {
                    let prefix = leadingTab + visible + "\t"
                    let line = prefix + "One\tinside\t"
                    let length = PasteNormalizer.nativeListPrefixLength(in: line as NSString, generatedMarker: generated, canonicalMarker: canonical)
                    XCTAssertEqual(length, prefix.utf16.count)
                    XCTAssertEqual((line as NSString).substring(from: length), "One\tinside\t")
                    let plain = PasteNormalizer.normalized(NSAttributedString(string: line))
                    XCTAssertEqual(plain.string, line)
                }
            }
            for line in ["8.\tOne", "\t8.\tOne", "77.\tOne", "7.x\tOne", "\t7.x\tOne", "7. One", "•x\tOne", "\tuser\ttabs"] {
                XCTAssertEqual(PasteNormalizer.nativeListPrefixLength(in: line as NSString, generatedMarker: generated, canonicalMarker: canonical), 0)
            }
        }
    }

    func testNativeListMarkerShapesNormalizeWithoutRelyingOnRTFImporter() {
        for format: NSTextList.MarkerFormat in [.decimal, .disc] {
            for leadingTab in ["", "\t"] {
                let list = NSTextList(markerFormat: format, options: 0)
                list.startingItemNumber = 7
                let style = NSMutableParagraphStyle()
                style.textLists = [list]
                let source = "\(leadingTab)\(list.marker(forItemNumber: 7))\tOne\tinside\n\(leadingTab)\(list.marker(forItemNumber: 8))\tTwo\ttail"
                let result = PasteNormalizer.normalized(NSAttributedString(string: source, attributes: [.paragraphStyle: style]))
                let ordered = format == .decimal
                let expected = ordered ? "7. One\tinside\n8. Two\ttail" : "• One\tinside\n• Two\ttail"
                XCTAssertEqual(result.string, expected)
                XCTAssertEqual(ParagraphFormatting.plainText(from: result), expected)
                XCTAssertEqual(MarkdownCodec.markdown(from: result), ordered ? expected : "- One\tinside\n- Two\ttail")
                let plain = PasteNormalizer.normalized(NSAttributedString(string: source))
                XCTAssertEqual(plain.string, source)
            }
        }
    }

    func testNativeListOnlyRemovesAnExactGeneratedMarkerPrefix() {
        let list = NSTextList(markerFormat: .decimal, options: 0)
        list.startingItemNumber = 7
        let style = NSMutableParagraphStyle()
        style.textLists = [list]
        for source in ["7.x\tOne\tinside", "\t7.x\tOne\tinside", "8.\tOne\tinside", "\t8.\tOne\tinside", "\tuser\ttabs"] {
            let result = PasteNormalizer.normalized(NSAttributedString(string: source, attributes: [.paragraphStyle: style]))
            XCTAssertEqual(result.string, "7. " + source)
        }
    }

    func testHTMLListPasteKeepsNumbersAndOnlyReplacesGeneratedTabs() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.setString("<ol start=\"7\"><li>One</li><li>Two</li></ol><ul><li>Three</li></ul>", forType: .html)
        let result = try XCTUnwrap(PasteNormalizer.read(from: board))
        XCTAssertEqual(result.string.trimmingCharacters(in: .newlines), "7. One\n8. Two\n• Three")
        XCTAssertEqual(MarkdownCodec.markdown(from: result).trimmingCharacters(in: .newlines), "7. One\n8. Two\n- Three")
    }

    func testRTFListsRetainStartingNumberAndContentTabs() throws {
        let list = NSTextList(markerFormat: .decimal, options: 0)
        list.startingItemNumber = 7
        let style = NSMutableParagraphStyle()
        style.textLists = [list]
        let text = NSAttributedString(string: "\t7.\tOne\tinside\n\t8.\tTwo", attributes: [.paragraphStyle: style])
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let data = try text.data(from: NSRange(location: 0, length: text.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        board.setData(data, forType: .rtf)
        let result = try XCTUnwrap(PasteNormalizer.read(from: board))
        XCTAssertEqual(result.string, "7. One\tinside\n8. Two")
        XCTAssertEqual(ParagraphFormatting.plainText(from: result), result.string)
    }

    func testUserAuthoredTabsAndNonWebLinkLabelsSurviveNormalization() {
        let text = NSAttributedString(string: "\tuser\ttabs", attributes: [.link: "javascript:alert(1)"])
        let result = PasteNormalizer.normalized(text)
        XCTAssertEqual(result.string, text.string)
        XCTAssertNil(result.attribute(.link, at: 0, effectiveRange: nil))
    }

    func testHTMLResourceDelegateDeniesEveryRequestAndRedirect() {
        let delegate = DenyHTMLResources()
        XCTAssertTrue(delegate.responds(to: NSSelectorFromString("webView:resource:willSendRequest:redirectResponse:fromDataSource:")))
        for url in ["https://example.com/image.png", "http://127.0.0.1/style.css", "file:///tmp/image.svg", "data:image/svg+xml,test"] {
            let request = URLRequest(url: URL(string: url)!)
            XCTAssertNil(delegate.webView(NSObject(), resource: NSObject(), willSendRequest: request, redirectResponse: nil, fromDataSource: NSObject()))
            XCTAssertNil(delegate.webView(NSObject(), resource: NSObject(), willSendRequest: request, redirectResponse: URLResponse(), fromDataSource: NSObject()))
        }
    }

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

    func testRichHeadingPasteKeepsItalicButNotStructuralBold() {
        let italicTitle = NSFontManager.shared.convert(NSFont.systemFont(ofSize: 30, weight: .bold), toHaveTrait: .italicFontMask)
        let normalized = PasteNormalizer.normalized(NSAttributedString(string: "Title", attributes: [.font: italicTitle]))
        XCTAssertEqual(normalized.attribute(.aparteHeadingLevel, at: 0, effectiveRange: nil) as? Int, 1)
        XCTAssertEqual(MarkdownCodec.markdown(from: normalized), "# *Title*")
    }

    func testPlainPasteUsesAparteBodyTypography() {
        let normalized = PasteNormalizer.normalized(NSAttributedString(string: "Plain"))
        let font = normalized.attribute(.font, at: 0, effectiveRange: nil) as? NSFont

        XCTAssertEqual(font?.pointSize, AparteTypography.bodySize)
        XCTAssertEqual(font?.familyName, AparteTypography.bodyFont.familyName)
    }

    func testPastedParagraphsUseEditorSpacingWithoutExtraEmptyRows() {
        let source = NSAttributedString(string: "One\n\n\nTwo", attributes: [.underlineStyle: 1])
        let normalized = PasteNormalizer.normalized(source)
        XCTAssertEqual(normalized.string, "One\nTwo")
        XCTAssertEqual(normalized.attribute(.underlineStyle, at: 4, effectiveRange: nil) as? Int, 1)
        XCTAssertEqual(ParagraphFormatting.plainText(from: normalized), "One\n\nTwo")
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
