import Foundation
import XCTest
@testable import AparteCore

final class MarkdownFileExporterTests: XCTestCase {
    func testSuggestedNameUsesTheFirstHeadingWithoutItsMarkup() {
        XCTAssertEqual(MarkdownFileExporter.suggestedBaseName(for: "# Focused writing\n\nBody"), "Focused writing")
    }

    func testSuggestedNameReplacesPathCharactersAndStaysShort() {
        let name = MarkdownFileExporter.suggestedBaseName(for: String(repeating: "a/b:", count: 40))

        XCTAssertTrue(name.hasPrefix("a-b-a-b-"))
        XCTAssertFalse(name.contains("/"))
        XCTAssertFalse(name.contains(":"))
        XCTAssertEqual(name.count, 80)
    }
}
