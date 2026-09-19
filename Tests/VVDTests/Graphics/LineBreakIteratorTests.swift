import XCTest
import VVD

final class LineBreakIteratorTests: XCTestCase {
    // ASSERTIONS textLineBoundaryBackend27Observed
    func testBoundariesKeepFullUTF16ContextAndRepeatedCursorQueries() {
        let cases: [(String, [Int?])] = [
            ("A A A A 漢字", [0, 0, 2, 2, 4, 4, 6, 6, 8, 9]),
            ("A A A A 日本語", [0, 0, 2, 2, 4, 4, 6, 6, 8, 9, 10]),
            ("漢字漢字", [0, 1, 2, 3]),
            ("日本語日本語", [0, 1, 2, 3, 4, 5]),
            ("漢字。漢字", [0, 1, 1, 3, 4]),
            ("（漢字）漢字", [0, 0, 2, 2, 4, 5]),
            ("漢字 漢字", [0, 1, 1, 3, 4]),
            ("A漢字B", [0, 1, 2, 3]),
            ("한국어한글", [0, 0, 0, 0, 0]),
            ("한국어 한글", [0, 0, 0, 0, 4, 4]),
            ("가나", [0, 0, 0, 0]),
            ("A\u{a0}B C", [0, 0, 0, 0, 4]),
            ("A A A A don't", [0, 0, 2, 2, 4, 4, 6, 6, 8, 8, 8, 8, 8]),
            ("A A A A don’t", [0, 0, 2, 2, 4, 4, 6, 6, 8, 8, 8, 8, 8]),
            ("A A A A BB-BB", [0, 0, 2, 2, 4, 4, 6, 6, 8, 8, 8, 11, 11]),
            ("e\u{301}lan", [0, 0, 0, 0, 0]),
            ("👩‍👩‍👧‍👦 a", [nil, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 12]),
            ("𐐀𐐁漢字", [nil, 0, 0, 0, 4, 5]),
        ]
        for language in ["en-KR", "en", "ko", "ja", "zh", "th", ""] {
            for (string, expected) in cases {
                let iterator = LineBreakIterator(string, locale: language, keepsHangulWords: true)
                XCTAssertEqual(iterator.count, expected.count)
                XCTAssertNil(iterator.preceding(0))
                let indices = Array(1...expected.count)
                // Change traversal direction to exercise the retained cursor.
                for index in indices + indices.reversed() + indices {
                    XCTAssertEqual(iterator.preceding(index), expected[index - 1],
                                   "\(string) locale=\(language) index=\(index)")
                }
            }
        }
    }

    // ASSERTIONS textLineBoundaryBackend27Observed
    func testHangulPolicyIsFixedForEachOwnedBuffer() {
        var source = "한국어한글"
        let joined = LineBreakIterator(source, locale: "ko", keepsHangulWords: true)
        let separated = LineBreakIterator(source, locale: "ko", keepsHangulWords: false)
        source = "replacement"
        XCTAssertEqual(source, "replacement")
        for index in 1...5 {
            XCTAssertEqual(joined.preceding(index), 0)
            XCTAssertEqual(separated.preceding(index), index - 1)
        }
        let empty = LineBreakIterator("", locale: "en", keepsHangulWords: true)
        XCTAssertEqual(empty.count, 0)
        XCTAssertNil(empty.preceding(0))
    }
}
