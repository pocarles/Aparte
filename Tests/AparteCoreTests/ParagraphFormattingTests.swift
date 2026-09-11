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
        XCTAssertTrue(html.contains("href=\"https://example.com/?q=%22a%22&amp;next=%3Cb%3E\""))
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

    func testAttributeOnlyOrderedItemsShareResolvedNumbers() {
        let text = NSAttributedString(string: "7. One\nTwo\nThree", attributes: [.aparteListKind: AparteListKind.ordered.rawValue])
        XCTAssertEqual(ParagraphFormatting.plainText(from: text), "7. One\n8. Two\n9. Three")
        XCTAssertEqual(MarkdownCodec.markdown(from: text), "7. One\n8. Two\n9. Three")
        XCTAssertTrue(ParagraphFormatting.html(from: text).contains("<ol start=\"7\"><li value=\"7\">One</li><li value=\"8\">Two</li><li value=\"9\">Three</li></ol>"))
    }

    func testCopyFragmentsLoseBlockMeaningButWholeParagraphsKeepIt() {
        for markdown in ["- world", "7. world", "# world"] {
            let text = MarkdownCodec.render(markdown)
            let word = (text.string as NSString).range(of: "wor")
            let fragment = ParagraphFormatting.copyText(from: text, range: word)
            XCTAssertEqual(ParagraphFormatting.plainText(from: fragment), "wor")
            XCTAssertFalse(MarkdownCodec.markdown(from: fragment).hasPrefix("# "))
            XCTAssertFalse(MarkdownCodec.markdown(from: fragment).hasPrefix("- "))
            let html = ParagraphFormatting.html(from: fragment)
            XCTAssertFalse(html.contains("<li") || html.contains("<h1>"))
            if markdown.hasPrefix("#") {
                XCTAssertEqual(MarkdownCodec.markdown(from: fragment), "wor")
                XCTAssertFalse(html.contains("<strong>"))
            }
            let whole = ParagraphFormatting.copyText(from: text, range: NSRange(location: 0, length: text.length))
            XCTAssertEqual(MarkdownCodec.markdown(from: whole), markdown)
        }
        let text = MarkdownCodec.render("- world")
        let prefix = ParagraphFormatting.copyText(from: text, range: NSRange(location: 0, length: 5))
        XCTAssertEqual(ParagraphFormatting.plainText(from: prefix), "• wor")
        XCTAssertFalse(ParagraphFormatting.html(from: prefix).contains("<li>"))
    }

    func testPartialHeadingsRetainOnlyExplicitInlineTraits() {
        for (markdown, expected) in [("# *world*", "*wor*"), ("# **world**", "**wor**"), ("# ***world***", "***wor***")] {
            let heading = MarkdownCodec.render(markdown)
            let fragment = ParagraphFormatting.copyText(from: heading, range: NSRange(location: 0, length: 3))
            XCTAssertEqual(MarkdownCodec.markdown(from: fragment), expected)
            XCTAssertEqual(MarkdownCodec.markdown(from: heading), markdown)
        }
        let ambiguous = NSAttributedString(string: "world", attributes: [.font: AparteTypography.headingFont(level: 1), .aparteHeadingLevel: 1])
        let fragment = ParagraphFormatting.copyText(from: ambiguous, range: NSRange(location: 0, length: 3))
        XCTAssertEqual(MarkdownCodec.markdown(from: fragment), "wor")
        XCTAssertFalse(ParagraphFormatting.html(from: fragment).contains("<strong>"))
    }
}
