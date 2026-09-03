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
        let markdown = "one\ntwo\n"
        XCTAssertEqual(MarkdownCodec.markdown(from: MarkdownCodec.render(markdown)), markdown)
    }

    func testEmojiAtEndOfDocumentRoundTrips() {
        let markdown = "A thought 💭"
        XCTAssertEqual(MarkdownCodec.markdown(from: MarkdownCodec.render(markdown)), markdown)
    }

    func testMultiScalarEmojiSequencesRoundTrip() {
        let markdown = "France 🇫🇷\nHello 👋🏽"
        XCTAssertEqual(MarkdownCodec.markdown(from: MarkdownCodec.render(markdown)), markdown)
    }

    func testEmojiBeforeTrailingNewlineRoundTrips() {
        let markdown = "Done ✅\n"
        XCTAssertEqual(MarkdownCodec.markdown(from: MarkdownCodec.render(markdown)), markdown)
    }
}
