import XCTest
@testable import Alexandria

final class BookSectionsTests: XCTestCase {
    func testPlainTextKeepsParagraphsAndLineBreaks() {
        let html = "<p>All good things must come to an end.</p><p>Roland walks on.<br/>The tower waits.</p>"
        XCTAssertEqual(plainText(fromHTML: html),
                       "All good things must come to an end.\n\nRoland walks on.\nThe tower waits.")
    }

    func testPlainTextDecodesEntitiesAmpersandLast() {
        XCTAssertEqual(plainText(fromHTML: "Tom &amp; Jerry&nbsp;&quot;live&quot; &#39;here&#39;"),
                       "Tom & Jerry \"live\" 'here'")
        // An escaped entity stays literal instead of decoding twice.
        XCTAssertEqual(plainText(fromHTML: "&amp;lt;b&amp;gt;"), "&lt;b&gt;")
    }

    func testPlainTextCollapsesRunsOfBlankLines() {
        XCTAssertEqual(plainText(fromHTML: "<p>One</p><p></p><p></p><p>Two</p>"), "One\n\nTwo")
    }

    func testAudibleLinkPrefersASIN() {
        let direct = ExternalLinks.audible(asin: "B008ALC7JS", title: "The Gunslinger", author: "Stephen King")
        XCTAssertEqual(direct?.path, "/pd/B008ALC7JS")

        let search = ExternalLinks.audible(asin: nil, title: "The Gunslinger", author: "Stephen King")
        XCTAssertEqual(search?.path, "/search")
        XCTAssertEqual(URLComponents(url: search!, resolvingAgainstBaseURL: false)?
            .queryItems?.first?.value, "The Gunslinger Stephen King")
    }

    func testGoodreadsSearchesByISBNWhenKnown() {
        let url = ExternalLinks.goodreads(isbn: "9780452284692", title: "The Gunslinger", author: "Stephen King")
        XCTAssertEqual(URLComponents(url: url!, resolvingAgainstBaseURL: false)?
            .queryItems?.first?.value, "9780452284692")
    }
}
