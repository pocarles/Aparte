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

    func testStructuralSpacingAgreesWithTheDocument() {
        let rendered = MarkdownCodec.render("First\n\n- One\n- Two\n\nAfter\n\n10. Ten\n11. Eleven")
        assertSpacingMatchesReload(rendered)

        let storage = NSMutableAttributedString(string: "Hello", attributes: AparteTypography.baseAttributes)
        func type(_ text: String) {
            storage.append(NSAttributedString(string: text, attributes: AparteTypography.baseAttributes))
            ParagraphFormatting.applyStructuralSpacing(to: storage)
        }
        type("\n- one")
        type("\n- two")
        type("\nAfter")
        type("\n10. Ten")
        type(" more")
        assertSpacingMatchesReload(storage)
    }

    func testHandTypedMarkerIsSpacedAsAListItem() {
        let text = NSMutableAttributedString(string: "Intro\n- foo\n- bar\nOutro", attributes: AparteTypography.baseAttributes)
        ParagraphFormatting.applyStructuralSpacing(to: text)
        let source = text.string as NSString
        let foo = source.range(of: "- foo")
        let bar = source.range(of: "- bar")
        let outro = source.range(of: "Outro")
        XCTAssertEqual(spacing(text, at: foo.location), AparteTypography.listItemSpacing)
        XCTAssertEqual(spacing(text, at: bar.location), AparteTypography.paragraphSpacing)
        XCTAssertEqual(spacing(text, at: outro.location), AparteTypography.paragraphSpacing)
        XCTAssertGreaterThan(headIndent(text, at: foo.location), 0)
    }

    func testLastListItemUsesBodySpacingAndAHangingIndent() {
        let rendered = MarkdownCodec.render("- One\n- Two\n\nAfter")
        let source = rendered.string as NSString
        let one = source.range(of: "One")
        let two = source.range(of: "Two")
        XCTAssertEqual(spacing(rendered, at: one.location), AparteTypography.listItemSpacing)
        XCTAssertEqual(spacing(rendered, at: two.location), AparteTypography.paragraphSpacing)
        XCTAssertEqual(spacing(rendered, at: source.range(of: "After").location), AparteTypography.paragraphSpacing)

        let bullet = AparteTypography.markerIndent(for: "• ")
        let wide = AparteTypography.markerIndent(for: "10. ")
        XCTAssertEqual(headIndent(rendered, at: one.location), bullet)
        XCTAssertGreaterThan(wide, bullet)

        let numbered = MarkdownCodec.render("10. Ten")
        XCTAssertEqual(headIndent(numbered, at: 0), wide)
        XCTAssertEqual((numbered.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.firstLineHeadIndent, 0)
    }

    func testDifferentListKindsUseTheBodyGap() {
        let text = NSMutableAttributedString(string: "- Bullet\n1. Numbered", attributes: AparteTypography.baseAttributes)
        ParagraphFormatting.applyStructuralSpacing(to: text)
        XCTAssertEqual(spacing(text, at: 0), AparteTypography.paragraphSpacing)
        XCTAssertEqual(spacing(text, at: (text.string as NSString).range(of: "1.").location), AparteTypography.paragraphSpacing)
        let html = ParagraphFormatting.html(from: text)
        XCTAssertTrue(html.contains("</ul><ol"))
    }

    func testHandTypedWidePrefixIndentsByItsOwnWidth() {
        let line = "-    wrapped item"
        let marker = ListContinuation.marker(in: line)
        XCTAssertEqual(marker?.prefix, "-    ")
        let text = NSMutableAttributedString(string: line, attributes: AparteTypography.baseAttributes)
        ParagraphFormatting.applyStructuralSpacing(to: text)
        XCTAssertEqual(headIndent(text, at: 0), AparteTypography.markerIndent(for: "-    "))
        XCTAssertGreaterThan(headIndent(text, at: 0), AparteTypography.markerIndent(for: "- "))
    }

    func testDeletingTheParagraphBetweenListItemsJoinsTheirGap() {
        // "gap" is a real block, so the two items are not neighbors until it
        // goes. The edit touches only that block; the items sit on either side
        // of it in the block list.
        let text = NSMutableAttributedString(
            string: "- One\ngap\n- Two\nAfter",
            attributes: AparteTypography.baseAttributes
        )
        ParagraphFormatting.applyStructuralSpacing(to: text)
        let source = text.string as NSString
        let one = source.range(of: "- One").location
        XCTAssertEqual(spacing(text, at: one), AparteTypography.paragraphSpacing)

        let gap = source.range(of: "gap")
        let removed = NSRange(location: gap.location - 1, length: gap.length + 1)
        text.replaceCharacters(in: removed, with: "")
        ParagraphFormatting.applyStructuralSpacing(to: text, edited: NSRange(location: gap.location - 1, length: 0))

        XCTAssertEqual(text.string, "- One\n- Two\nAfter")
        XCTAssertEqual(spacing(text, at: 0), AparteTypography.listItemSpacing)
        XCTAssertEqual(spacing(text, at: (text.string as NSString).range(of: "- Two").location), AparteTypography.paragraphSpacing)
        assertSpacingMatchesReload(text)
    }

    func testMiddleEditRestylesOnlyNearbyBlocks() {
        let paragraphs = (0..<40).map { "Paragraph \($0) stands alone." }
        let text = NSMutableAttributedString(
            string: paragraphs.joined(separator: "\n"),
            attributes: AparteTypography.baseAttributes
        )
        ParagraphFormatting.applyStructuralSpacing(to: text)
        let source = text.string as NSString
        let target = source.range(of: "Paragraph 20")
        text.replaceCharacters(in: NSRange(location: target.location, length: 0), with: "- ")
        let visited = ParagraphFormatting.applyStructuralSpacing(
            to: text,
            edited: NSRange(location: target.location, length: 2)
        )
        XCTAssertLessThanOrEqual(visited, 3)
        XCTAssertGreaterThan(visited, 0)
        assertSpacingMatchesReload(text)
        let far = source.range(of: "Paragraph 2 ")
        XCTAssertEqual(spacing(text, at: far.location), AparteTypography.paragraphSpacing)
    }

    func testSoftBreakStaysInsideItsBlock() {
        let text = NSMutableAttributedString(string: "Best,\u{2028}Ada", attributes: AparteTypography.baseAttributes)
        XCTAssertEqual(ParagraphFormatting.plainText(from: text), "Best,\nAda")
        XCTAssertTrue(ParagraphFormatting.html(from: text).contains("Best,<br>Ada"))
        XCTAssertFalse(ParagraphFormatting.html(from: text).contains("</p><p>"))

        let markdown = MarkdownCodec.markdown(from: text)
        XCTAssertEqual(markdown, "Best,  \nAda")
        let roundTrip = MarkdownCodec.render(markdown)
        XCTAssertTrue(roundTrip.string.contains("\u{2028}"))
        XCTAssertEqual(ParagraphFormatting.plainText(from: roundTrip), "Best,\nAda")
        XCTAssertEqual(MarkdownCodec.markdown(from: roundTrip), markdown)
    }

    private func assertSpacingMatchesReload(_ storage: NSAttributedString) {
        let reloaded = ParagraphFormatting.editorText(from: storage)
        XCTAssertEqual(reloaded.string, storage.string)
        let source = storage.string as NSString
        var cursor = 0
        while cursor < source.length {
            let paragraph = source.paragraphRange(for: NSRange(location: cursor, length: 0))
            if paragraph.length > 0 {
                XCTAssertEqual(spacing(storage, at: paragraph.location), spacing(reloaded, at: paragraph.location),
                               "spacing diverges at \(paragraph.location)")
            }
            let next = NSMaxRange(paragraph)
            cursor = next > cursor ? next : cursor + 1
        }
    }

    private func spacing(_ text: NSAttributedString, at location: Int) -> CGFloat {
        (text.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle)?.paragraphSpacing ?? -1
    }

    private func headIndent(_ text: NSAttributedString, at location: Int) -> CGFloat {
        (text.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle)?.headIndent ?? -1
    }

    func testDeletedMarkerLeavesPlainBodyText() {
        let text = NSAttributedString(string: "Item", attributes: [.paragraphStyle: AparteTypography.listParagraphStyle])
        XCTAssertEqual(ParagraphFormatting.plainText(from: text), "Item")
        XCTAssertEqual(MarkdownCodec.markdown(from: text), "Item")
        XCTAssertTrue(ParagraphFormatting.html(from: text).contains("<p>Item</p>"))
    }

    func testEmptyClipboardContent() {
        let source = NSAttributedString(string: "\n\n")
        XCTAssertEqual(ParagraphFormatting.plainText(from: source), "")
        XCTAssertFalse(ParagraphFormatting.html(from: source).contains("<p>"))
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
