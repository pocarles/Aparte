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
        let rendered = MarkdownCodec.render("# Title\n\nFirst\n\n- One\n- Two\n\nAfter\n\n10. Ten\n11. Eleven")
        assertSpacingMatchesReload(rendered)
        assertSpacingMatchesReload(MarkdownCodec.render("Intro\n\n# After paragraph\n\nBody"))
        assertSpacingMatchesReload(MarkdownCodec.render("- One\n- Two\n\n# After list\n\nBody"))

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
        type("\nTitle")
        storage.addAttribute(.aparteHeadingLevel, value: 1, range: (storage.string as NSString).range(of: "Title"))
        ParagraphFormatting.applyStructuralSpacing(to: storage)
        assertSpacingMatchesReload(storage)

        let live = NSMutableAttributedString(
            string: "Intro\nHeadingA\n- One\n- Two\nHeadingB\nBody",
            attributes: AparteTypography.baseAttributes
        )
        let liveSource = live.string as NSString
        live.addAttribute(.aparteHeadingLevel, value: 1, range: liveSource.range(of: "HeadingA"))
        live.addAttribute(.aparteHeadingLevel, value: 1, range: liveSource.range(of: "HeadingB"))
        ParagraphFormatting.applyStructuralSpacing(to: live)
        XCTAssertEqual(spacing(live, at: liveSource.range(of: "Intro").location), AparteTypography.headingSpacing)
        XCTAssertEqual(spacing(live, at: liveSource.range(of: "Two").location), AparteTypography.headingSpacing)
        assertSpacingMatchesReload(live)
    }

    func testLevel2HeadingTakesTheSameAirAsLevel1() {
        let rendered = MarkdownCodec.render("Intro\n\n## Title\n\nBody")
        let source = rendered.string as NSString
        XCTAssertEqual((rendered.attribute(.font, at: source.range(of: "Title").location, effectiveRange: nil) as? NSFont)?.pointSize, 24)
        XCTAssertEqual(spacing(rendered, at: source.range(of: "Intro").location), AparteTypography.headingSpacing)
        XCTAssertEqual(spacing(rendered, at: source.range(of: "Title").location), AparteTypography.headingSpacing)
        XCTAssertEqual(spacing(rendered, at: source.range(of: "Body").location), AparteTypography.paragraphSpacing)
        XCTAssertEqual(spacing(rendered, at: source.range(of: "Intro").location), 36)
        XCTAssertEqual(spacing(rendered, at: source.range(of: "Title").location), 36)

        let afterList = MarkdownCodec.render("- One\n- Two\n\n## Title")
        let listed = afterList.string as NSString
        XCTAssertEqual(spacing(afterList, at: listed.range(of: "One").location), AparteTypography.listItemSpacing)
        XCTAssertEqual(spacing(afterList, at: listed.range(of: "Two").location), AparteTypography.headingSpacing)
        XCTAssertEqual(spacing(afterList, at: listed.range(of: "Title").location), AparteTypography.headingSpacing)
    }

    func testHeadingIsFollowedByTwiceTheBodyGap() {
        let rendered = MarkdownCodec.render("# Title\n\nBody")
        let source = rendered.string as NSString
        XCTAssertEqual(spacing(rendered, at: source.range(of: "Title").location), AparteTypography.headingSpacing)
        XCTAssertEqual(spacing(rendered, at: source.range(of: "Body").location), AparteTypography.paragraphSpacing)

        for level in 1...6 {
            let hashes = String(repeating: "#", count: level)
            let last = MarkdownCodec.render("Intro\n\n\(hashes) End")
            let end = (last.string as NSString).range(of: "End")
            XCTAssertEqual(spacing(last, at: 0), AparteTypography.headingSpacing)
            XCTAssertEqual(spacing(last, at: end.location), AparteTypography.headingSpacing)
        }
    }

    func testBlockBeforeAHeadingTakesTheHeadingGap() {
        let afterParagraph = MarkdownCodec.render("Intro\n\n# Title\n\nBody")
        let prose = afterParagraph.string as NSString
        XCTAssertEqual(spacing(afterParagraph, at: prose.range(of: "Intro").location), AparteTypography.headingSpacing)
        XCTAssertEqual(spacing(afterParagraph, at: prose.range(of: "Title").location), AparteTypography.headingSpacing)
        XCTAssertEqual(spacing(afterParagraph, at: prose.range(of: "Body").location), AparteTypography.paragraphSpacing)

        let afterList = MarkdownCodec.render("- One\n- Two\n\n# Title")
        let listed = afterList.string as NSString
        XCTAssertEqual(spacing(afterList, at: listed.range(of: "One").location), AparteTypography.listItemSpacing)
        XCTAssertEqual(spacing(afterList, at: listed.range(of: "Two").location), AparteTypography.headingSpacing)
        XCTAssertEqual(spacing(afterList, at: listed.range(of: "Title").location), AparteTypography.headingSpacing)

        let atStart = MarkdownCodec.render("# Title\n\nBody")
        XCTAssertEqual(spacing(atStart, at: 0), AparteTypography.headingSpacing)
        XCTAssertEqual(spacing(atStart, at: (atStart.string as NSString).range(of: "Body").location), AparteTypography.paragraphSpacing)

        let liveList = NSMutableAttributedString(
            string: "- One\nTitle",
            attributes: AparteTypography.baseAttributes
        )
        liveList.addAttribute(.aparteHeadingLevel, value: 1, range: (liveList.string as NSString).range(of: "Title"))
        ParagraphFormatting.applyStructuralSpacing(to: liveList)
        XCTAssertEqual(spacing(liveList, at: 0), AparteTypography.headingSpacing)
        assertSpacingMatchesReload(liveList)
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

    func testZeroLengthBoundaryEditSkipsBlankRowsAndMatchesFullRestyle() {
        let text = NSMutableAttributedString(
            string: "- One\n\n- Two\n- Three\nBody",
            attributes: AparteTypography.baseAttributes
        )
        ParagraphFormatting.applyStructuralSpacing(to: text)

        // Delete the remaining empty row and report the post-edit insertion
        // point, as NSTextStorage does for a deletion.
        let blankRow = (text.string as NSString).range(of: "\n\n")
        text.deleteCharacters(in: NSRange(location: blankRow.location, length: 1))
        let visited = ParagraphFormatting.applyStructuralSpacing(
            to: text,
            edited: NSRange(location: blankRow.location, length: 0)
        )

        XCTAssertEqual(text.string, "- One\n- Two\n- Three\nBody")
        XCTAssertGreaterThan(visited, 0)
        XCTAssertLessThanOrEqual(visited, 3)
        assertLocalizedSpacingMatchesFullRestyle(text)

        let atStart = NSMutableAttributedString(
            string: "- One\n- Two",
            attributes: AparteTypography.baseAttributes
        )
        ParagraphFormatting.applyStructuralSpacing(to: atStart)
        atStart.deleteCharacters(in: NSRange(location: 0, length: 2))
        XCTAssertGreaterThan(
            ParagraphFormatting.applyStructuralSpacing(
                to: atStart,
                edited: NSRange(location: 0, length: 0)
            ),
            0
        )
        XCTAssertEqual(spacing(atStart, at: 0), AparteTypography.paragraphSpacing)
        assertLocalizedSpacingMatchesFullRestyle(atStart)
    }

    func testLocalizedSpacingMatchesFullRestyleForSplitsMergesAndAttributeEdits() {
        let split = NSMutableAttributedString(
            string: "Intro\n- One and Two\nBody",
            attributes: AparteTypography.baseAttributes
        )
        ParagraphFormatting.applyStructuralSpacing(to: split)
        let splitPoint = (split.string as NSString).range(of: " and").location
        split.replaceCharacters(in: NSRange(location: splitPoint, length: 1), with: "\n- ")
        XCTAssertGreaterThan(
            ParagraphFormatting.applyStructuralSpacing(
                to: split,
                edited: NSRange(location: splitPoint, length: 3)
            ),
            0
        )
        assertLocalizedSpacingMatchesFullRestyle(split)

        let merged = NSMutableAttributedString(
            string: "Intro\n- One\n- Two\nBody",
            attributes: AparteTypography.baseAttributes
        )
        ParagraphFormatting.applyStructuralSpacing(to: merged)
        let mergePoint = (merged.string as NSString).range(of: "\n- Two").location
        merged.replaceCharacters(in: NSRange(location: mergePoint, length: 3), with: " ")
        ParagraphFormatting.applyStructuralSpacing(
            to: merged,
            edited: NSRange(location: mergePoint, length: 0)
        )
        assertLocalizedSpacingMatchesFullRestyle(merged)

        let attributed = NSMutableAttributedString(
            string: "Intro\nTitle\n- One\n- Two\nBest,\u{2028}Ada",
            attributes: AparteTypography.baseAttributes
        )
        ParagraphFormatting.applyStructuralSpacing(to: attributed)
        let title = (attributed.string as NSString).range(of: "Title")
        attributed.addAttribute(.aparteHeadingLevel, value: 2, range: title)
        ParagraphFormatting.applyStructuralSpacing(to: attributed, edited: title)
        assertLocalizedSpacingMatchesFullRestyle(attributed)
    }

    func testBatchedEditorNormalizationMatchesReferenceAcrossChunkBoundaries() {
        let source = NSMutableAttributedString(
            string: "\r\n \n",
            attributes: AparteTypography.baseAttributes
        )
        for index in 0..<620 {
            var attributes = AparteTypography.baseAttributes
            if index.isMultiple(of: 9) {
                attributes[.font] = NSFontManager.shared.convert(
                    AparteTypography.bodyFont,
                    toHaveTrait: .boldFontMask
                )
            }
            let prefix = index.isMultiple(of: 5) ? "- " : ""
            source.append(NSAttributedString(
                string: "\(prefix)Paragraph \(index) 👩🏽‍💻\u{2028}continued",
                attributes: attributes
            ))
            if index.isMultiple(of: 101) {
                let paragraph = (source.string as NSString).paragraphRange(
                    for: NSRange(location: source.length - 1, length: 0)
                )
                source.addAttribute(.aparteHeadingLevel, value: 2, range: paragraph)
            }
            let gap = index.isMultiple(of: 3) ? "\r\n \r\n" : index.isMultiple(of: 2) ? "\n\n" : "\n"
            var gapAttributes = AparteTypography.baseAttributes
            if index.isMultiple(of: 7) {
                gapAttributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            }
            source.append(NSAttributedString(string: gap, attributes: gapAttributes))
        }
        source.append(NSAttributedString(string: " \r\n", attributes: [.font: NSFont.boldSystemFont(ofSize: 17)]))

        let expected = referenceEditorText(from: source)
        let normalized = NSMutableAttributedString(attributedString: source)
        ParagraphFormatting.normalizeEditorTextInPlace(normalized)

        XCTAssertEqual(normalized, expected)
        XCTAssertEqual(ParagraphFormatting.blocks(in: normalized).count, 620)
        XCTAssertTrue(normalized.string.hasSuffix("\n"))
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

    private func assertLocalizedSpacingMatchesFullRestyle(
        _ storage: NSMutableAttributedString,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let fullyRestyled = NSMutableAttributedString(attributedString: storage)
        ParagraphFormatting.applyStructuralSpacing(to: fullyRestyled)
        XCTAssertEqual(fullyRestyled.string, storage.string, file: file, line: line)
        for block in ParagraphFormatting.blocks(in: storage) {
            let local = storage.attribute(.paragraphStyle, at: block.range.location, effectiveRange: nil) as? NSParagraphStyle
            let full = fullyRestyled.attribute(.paragraphStyle, at: block.range.location, effectiveRange: nil) as? NSParagraphStyle
            XCTAssertEqual(local?.paragraphSpacing, full?.paragraphSpacing, file: file, line: line)
            XCTAssertEqual(local?.headIndent, full?.headIndent, file: file, line: line)
            XCTAssertEqual(local?.firstLineHeadIndent, full?.firstLineHeadIndent, file: file, line: line)
            XCTAssertEqual(local?.lineSpacing, full?.lineSpacing, file: file, line: line)
        }
    }

    private func referenceEditorText(from text: NSAttributedString) -> NSAttributedString {
        let output = NSMutableAttributedString()
        let blocks = ParagraphFormatting.blocks(in: text)
        for (index, block) in blocks.enumerated() {
            if output.length > 0 {
                output.append(NSAttributedString(string: "\n", attributes: AparteTypography.baseAttributes))
            }
            let paragraph = NSMutableAttributedString(attributedString: text.attributedSubstring(from: block.range))
            let next = index + 1 < blocks.count ? blocks[index + 1] : nil
            paragraph.addAttribute(
                .paragraphStyle,
                value: ParagraphFormatting.paragraphStyle(for: block, next: next),
                range: NSRange(location: 0, length: paragraph.length)
            )
            output.append(paragraph)
        }
        if output.length > 0, text.string.last?.isNewline == true {
            output.append(NSAttributedString(string: "\n", attributes: AparteTypography.baseAttributes))
        }
        return output
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
        for (markdown, expected, canonical) in [
            ("# *world*", "*wor*", "# *world*"),
            ("# **world**", "wor", "# world"),
            ("# ***world***", "*wor*", "# *world*"),
        ] {
            let heading = MarkdownCodec.render(markdown)
            let fragment = ParagraphFormatting.copyText(from: heading, range: NSRange(location: 0, length: 3))
            XCTAssertEqual(MarkdownCodec.markdown(from: fragment), expected)
            XCTAssertEqual(MarkdownCodec.markdown(from: heading), canonical)
        }
        let ambiguous = NSAttributedString(string: "world", attributes: [.font: AparteTypography.headingFont(level: 1), .aparteHeadingLevel: 1])
        let fragment = ParagraphFormatting.copyText(from: ambiguous, range: NSRange(location: 0, length: 3))
        XCTAssertEqual(MarkdownCodec.markdown(from: fragment), "wor")
        XCTAssertFalse(ParagraphFormatting.html(from: fragment).contains("<strong>"))
    }
}
