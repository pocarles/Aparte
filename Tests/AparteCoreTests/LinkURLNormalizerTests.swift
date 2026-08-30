import XCTest
@testable import AparteCore

final class LinkURLNormalizerTests: XCTestCase {
    func testAcceptsCompleteWebAddress() {
        XCTAssertEqual(
            LinkURLNormalizer.normalize("https://example.com/path"),
            URL(string: "https://example.com/path")
        )
    }

    func testAddsHTTPSWhenSchemeIsMissing() {
        XCTAssertEqual(
            LinkURLNormalizer.normalize("example.com"),
            URL(string: "https://example.com")
        )
    }

    func testRejectsIncompleteAndUnsupportedAddresses() {
        XCTAssertNil(LinkURLNormalizer.normalize("https://"))
        XCTAssertNil(LinkURLNormalizer.normalize("mailto:person@example.com"))
        XCTAssertNil(LinkURLNormalizer.normalize("ordinary text"))
        XCTAssertNil(LinkURLNormalizer.normalize("hello"))
        XCTAssertNil(LinkURLNormalizer.normalize("  "))
    }
}
