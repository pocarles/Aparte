import AppKit
import XCTest
@testable import AparteCore

final class MarkdownCodecTests: XCTestCase {
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
