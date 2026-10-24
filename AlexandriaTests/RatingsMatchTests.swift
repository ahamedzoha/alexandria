import XCTest
@testable import Alexandria

/// Fixtures are trimmed from real Audible catalog / Open Library responses
/// (October 2026). The search for "The Dark Tower" returns every volume of the
/// series plus Spanish editions — the matcher has to pick the right one.
final class RatingsMatchTests: XCTestCase {
    private func product(_ asin: String, _ title: String, language: String = "english",
                         narrator: String, series: String = "The Dark Tower", sequence: String,
                         ratings: Int) -> String {
        """
        { "asin": "\(asin)", "title": "\(title)", "language": "\(language)",
          "authors": [{ "name": "Stephen King" }], "narrators": [{ "name": "\(narrator)" }],
          "series": [{ "title": "\(series)", "sequence": "\(sequence)" }],
          "rating": { "num_reviews": 31,
            "overall_distribution": { "average_rating": 4.1, "num_ratings": \(ratings) },
            "performance_distribution": { "average_rating": 4.3, "num_ratings": \(ratings) },
            "story_distribution": { "average_rating": 3.9, "num_ratings": \(ratings) } } }
        """
    }

    private func darkTowerSearch() throws -> [AudibleProduct] {
        let json = """
        { "products": [
          \(product("B0BXBL51K5", "La Torre Oscura (La Torre Oscura 7)", language: "spanish",
                    narrator: "Julio Caycedo", series: "La Torre Oscura", sequence: "7", ratings: 29)),
          \(product("B008ALC7JS", "The Dark Tower I: The Gunslinger", narrator: "George Guidall", sequence: "1", ratings: 433)),
          \(product("B0089ZO82Y", "The Dark Tower VII: The Dark Tower", narrator: "George Guidall", sequence: "7", ratings: 268)),
          \(product("B008AX6HGK", "The Dark Tower II: The Drawing of the Three", narrator: "Frank Muller", sequence: "2", ratings: 305))
        ] }
        """
        return try RatingsClient.decoder.decode(AudibleProductsPage.self, from: Data(json.utf8)).products ?? []
    }

    func testPicksTheRightVolumeOutOfTheSeries() throws {
        let query = RatingsQuery(title: "The Dark Tower", authors: ["Stephen King"], narrators: ["George Guidall"],
                                 series: "The Dark Tower", sequence: "7", language: "English")
        XCTAssertEqual(RatingsMatch.bestAudible(try darkTowerSearch(), for: query)?.asin, "B0089ZO82Y")
    }

    func testMatchesWhenTheStoreTitleCarriesTheSeriesPrefix() throws {
        let query = RatingsQuery(title: "The Gunslinger", authors: ["Stephen King"], narrators: ["George Guidall"],
                                 series: "The Dark Tower", sequence: "1", language: "English")
        XCTAssertEqual(RatingsMatch.bestAudible(try darkTowerSearch(), for: query)?.asin, "B008ALC7JS")
    }

    func testRejectsOtherLanguageEditions() throws {
        let query = RatingsQuery(title: "La Torre Oscura", authors: ["Stephen King"], language: "English")
        XCTAssertNil(RatingsMatch.bestAudible(try darkTowerSearch(), for: query))
    }

    func testRejectsADifferentAuthor() throws {
        let query = RatingsQuery(title: "The Dark Tower", authors: ["C. S. Lewis"])
        XCTAssertNil(RatingsMatch.bestAudible(try darkTowerSearch(), for: query))
    }

    func testTitleOnlyPrefixDoesNotMatchAnotherVolume() throws {
        // "The Dark Tower" must not latch onto "The Dark Tower I: The Gunslinger"
        // just because the title starts the same way.
        let gunslingerOnly = try darkTowerSearch().filter { $0.asin == "B008ALC7JS" }
        let query = RatingsQuery(title: "The Dark Tower", authors: ["Stephen King"])
        XCTAssertNil(RatingsMatch.bestAudible(gunslingerOnly, for: query))
    }

    func testSummaryReadsTheSplitRatings() throws {
        let best = try XCTUnwrap(darkTowerSearch().first { $0.asin == "B0089ZO82Y" })
        let summary = try XCTUnwrap(RatingsClient.summary(best, domain: "audible.com"))
        XCTAssertEqual(summary.overall, RatingScore(average: 4.1, count: 268))
        XCTAssertEqual(summary.story?.average, 3.9)
        XCTAssertEqual(summary.narration?.average, 4.3)
        XCTAssertEqual(summary.productURL?.absoluteString, "https://www.audible.com/pd/B0089ZO82Y")
    }

    func testUnratedProductHasNoSummary() throws {
        // An unknown ASIN comes back 200 with zeroed ratings.
        let json = """
        { "asin": "B000000000", "rating": { "num_reviews": 0,
          "overall_distribution": { "average_rating": 0.0, "num_ratings": 0 } } }
        """
        let unrated = try RatingsClient.decoder.decode(AudibleProduct.self, from: Data(json.utf8))
        XCTAssertNil(RatingsClient.summary(unrated, domain: "audible.com"))
    }

    func testOpenLibraryMatchNeedsTitleAuthorAndRatings() throws {
        let json = """
        { "docs": [
          { "key": "/works/OL1W", "title": "The Gunslinger", "author_name": ["Somebody Else"], "ratings_average": 3.0, "ratings_count": 9 },
          { "key": "/works/OL2W", "title": "The Gunslinger", "author_name": ["Stephen King"], "ratings_count": 0 },
          { "key": "/works/OL81628W", "title": "The Gunslinger", "author_name": ["Stephen King"], "ratings_average": 4.03, "ratings_count": 71 }
        ] }
        """
        let docs = try RatingsClient.decoder.decode(OpenLibrarySearch.self, from: Data(json.utf8)).docs ?? []
        let query = RatingsQuery(title: "The Gunslinger", authors: ["Stephen King"])
        XCTAssertEqual(RatingsMatch.bestOpenLibrary(docs, for: query)?.key, "/works/OL81628W")
    }

    func testAuthorInitialsMatchAcrossPunctuation() {
        XCTAssertTrue(RatingsMatch.namesOverlap(["J.K. Rowling"], ["JK Rowling"]))
        XCTAssertTrue(RatingsMatch.namesOverlap(["J. K. Rowling"], ["J.K. Rowling"]))
        XCTAssertFalse(RatingsMatch.namesOverlap(["Stephen King"], ["Owen King"]))
    }

    func testQueryFallsBackWhenDetailIsMissing() {
        let query = RatingsQuery(meta: nil, fallbackTitle: "Anna Karenina",
                                 fallbackAuthor: "Leo Tolstoy", fallbackNarrator: "Maggie Gyllenhaal")
        XCTAssertEqual(query.title, "Anna Karenina")
        XCTAssertEqual(query.authors, ["Leo Tolstoy"])
        XCTAssertEqual(query.narrators, ["Maggie Gyllenhaal"])
        XCTAssertNil(query.asin)
    }

    func testStoreFollowsRegionWithUSFallback() {
        XCTAssertEqual(AudibleStore.forRegion("GB").domain, "audible.co.uk")
        XCTAssertEqual(AudibleStore.forRegion("AT"), .germany)
        XCTAssertEqual(AudibleStore.forRegion("BD"), .us)
        XCTAssertEqual(AudibleStore.forRegion(nil), .us)
    }
}

/// Review fixtures trimmed from Audible's /reviews responses.
final class AudibleReviewTests: XCTestCase {
    private func decode(_ json: String) throws -> AudibleReview {
        try RatingsClient.decoder.decode(AudibleReview.self, from: Data(json.utf8))
    }

    func testFreeformBodyKeepsEscapedLineBreaks() throws {
        let review = try decode("""
        { "id": "1", "format": "Freeform", "title": "A Surrealistic Western",
          "body": "I really want to be in on the joke.&lt;br/>&lt;br/>The Gunslinger is a story &amp; more.",
          "submission_date": "2012-06-19T21:06:37Z", "ratings": { "overall_rating": 3 } }
        """)
        XCTAssertEqual(review.parts, [.init(prompt: nil, text: "I really want to be in on the joke.\n\nThe Gunslinger is a story & more.")])
        XCTAssertNotNil(review.date)
    }

    func testGuidedReviewKeepsOnlyAnsweredPrompts() throws {
        let review = try decode("""
        { "id": "2", "format": "Guided", "body": "[{\\"ignored\\": true}]",
          "guided_responses": [
            { "question": "Would you listen to it again?", "answer": "No, not again." },
            { "question": "What did you like best about this story?", "answer": "  " },
            { "question": "Any additional comments?", "answer": "I'll finish the series." } ] }
        """)
        XCTAssertEqual(review.parts, [
            .init(prompt: "Would you listen to it again?", text: "No, not again."),
            .init(prompt: nil, text: "I'll finish the series."),
        ])
    }

    func testReviewerNameAndTitleDecodeEntities() throws {
        let review = try decode(#"{ "id": "4", "author_name": "Jim &quot;The Impatient&quot;", "title": "Tom &amp; Jerry" }"#)
        XCTAssertEqual(review.displayAuthor, "Jim \"The Impatient\"")
        XCTAssertEqual(review.displayTitle, "Tom & Jerry")
    }

    func testReviewWithNothingToReadHasNoParts() throws {
        let review = try decode(#"{ "id": "3", "format": "Guided", "guided_responses": [{ "question": "Q?", "answer": "" }] }"#)
        XCTAssertTrue(review.parts.isEmpty)
    }
}
