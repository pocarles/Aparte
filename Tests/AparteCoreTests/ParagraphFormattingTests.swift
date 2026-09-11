import AppKit
import XCTest
@testable import AparteCore

final class ParagraphFormattingTests: XCTestCase {
    func testPlainCopySeparatesProseAndKeepsListsCompact() {
        let source = NSAttributedString(string: "Hello,\nFirst paragraph.\n\n\nSecond paragraph.\n\n- One\n- Two\n\nThanks!")
        let expected = "Hello,\n\nFirst paragraph.\n\nSecond paragraph.\n\n- One\n- Two\n\nThanks!"
        XCTAssertEqual(ParagraphFormatting.plainText(from: source), expected)
        XCTAssertEqual(ParagraphFormatting.plainText(from: NSAttributedString(string: expected)), expected)
    }

    func testWhitespaceAndCRLFDoNotCreateRunawayGaps() {
        let source = NSAttributedString(string: "\r\nOne 👋🏽\r\n \r\n\r\nTwo\r\n")
        XCTAssertEqual(ParagraphFormatting.plainText(from: source), "One 👋🏽\n\nTwo")
        XCTAssertEqual(ParagraphFormatting.editorText(from: source).string, "One 👋🏽\nTwo\n")
    }

    func testHTMLPreservesSemanticsWithoutEditorTypography() {
        let source = MarkdownCodec.render("# Heading\n\n**Bold** and *italic* with <u>underline</u> and [site](https://example.com/?a=1&b=2).\n\n- One\n- Two\n7. Seven\n8. Eight")
        let html = ParagraphFormatting.html(from: source)
        XCTAssertTrue(html.contains("<h1>"))
        XCTAssertTrue(html.contains("<strong>Bold</strong>"))
        XCTAssertTrue(html.contains("<em>italic</em>"))
        XCTAssertTrue(html.contains("<u>underline</u>"))
        XCTAssertTrue(html.contains("href=\"https://example.com/?a=1&amp;b=2\""))
        XCTAssertTrue(html.contains("<ul><li>One</li><li>Two</li></ul>"))
        XCTAssertTrue(html.contains("<ol start=\"7\"><li value=\"7\">Seven</li><li value=\"8\">Eight</li></ol>"))
        for forbidden in ["font-family", "font-size", "Helvetica", "style=", "<font"] {
            XCTAssertFalse(html.contains(forbidden), forbidden)
        }
    }

    func testHTMLTextAndLinkAttributesAreEscaped() {
        let source = NSMutableAttributedString(string: "<draft> & \"quotes\" 'text'")
        source.addAttribute(.link, value: "https://example.com/?q=\"a\"&next=<b>",
                            range: NSRange(location: 0, length: source.length))
        let html = ParagraphFormatting.html(from: source)
        XCTAssertTrue(html.contains("&lt;draft&gt; &amp; &quot;quotes&quot; &#39;text&#39;"))
        XCTAssertTrue(html.contains("href=\"https://example.com/?q=&quot;a&quot;&amp;next=&lt;b&gt;\""))
        XCTAssertFalse(html.contains("<draft>"))
    }

    func testNativeListWithoutVisibleMarkerGetsReadablePlainText() {
        let source = NSAttributedString(string: "One\nTwo", attributes: [.aparteListKind: AparteListKind.unordered.rawValue])
        XCTAssertEqual(ParagraphFormatting.plainText(from: source), "• One\n• Two")
        XCTAssertTrue(ParagraphFormatting.html(from: source).contains("<ul><li>One</li><li>Two</li></ul>"))
    }

    func testEmptyClipboardContent() {
        let source = NSAttributedString(string: "\n\n")
        XCTAssertEqual(ParagraphFormatting.plainText(from: source), "")
        XCTAssertFalse(ParagraphFormatting.html(from: source).contains("<p>"))
    }
}
