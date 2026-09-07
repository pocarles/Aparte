import XCTest
@testable import AparteCore

final class ListContinuationTests: XCTestCase {
    func testRecognizesNativeMarkersAndUnicodeContent() throws {
        let unordered = ListContinuation.marker(in: "• Café 💭", listKind: .unordered)
        XCTAssertEqual(unordered?.kind, .unordered)
        XCTAssertEqual(unordered?.prefix, "• ")
        XCTAssertEqual(unordered?.utf16Length, 2)
        XCTAssertFalse(ListContinuation.isEmptyItem(in: "• Café 💭", marker: try XCTUnwrap(unordered)))

        let ordered = ListContinuation.marker(in: "12. 東京", listKind: .ordered)
        XCTAssertEqual(ordered?.number, 12)
        XCTAssertEqual(ListContinuation.nextMarker(after: try XCTUnwrap(ordered)), "13. ")
    }

    func testStoredListKindAllowsMarkerlessNativeItem() throws {
        let marker = try XCTUnwrap(ListContinuation.marker(in: "内容", listKind: .unordered))
        XCTAssertEqual(marker.prefix, "")
        XCTAssertFalse(ListContinuation.isEmptyItem(in: "内容", marker: marker))

        let empty = try XCTUnwrap(ListContinuation.marker(in: "   ", listKind: .ordered))
        XCTAssertTrue(ListContinuation.isEmptyItem(in: "   ", marker: empty))
        XCTAssertEqual(ListContinuation.nextMarker(after: empty), "1. ")
    }

    func testTypedMarkersContinueWithoutTreatingArbitraryTextAsAList() throws {
        let unordered = try XCTUnwrap(ListContinuation.marker(in: "- item"))
        XCTAssertEqual(ListContinuation.nextMarker(after: unordered), "- ")

        let ordered = try XCTUnwrap(ListContinuation.marker(in: "7. item"))
        XCTAssertEqual(ListContinuation.nextMarker(after: ordered), "8. ")

        XCTAssertNil(ListContinuation.marker(in: "A paragraph with 1. text"))
        XCTAssertNil(ListContinuation.marker(in: "1.item"))
        XCTAssertNil(ListContinuation.marker(in: "999999999999999999999999999999. item"))
    }

    func testEmptyMarkerOnlyItemIsEmpty() throws {
        let marker = try XCTUnwrap(ListContinuation.marker(in: "• "))
        XCTAssertTrue(ListContinuation.isEmptyItem(in: "• \t", marker: marker))
    }
}
