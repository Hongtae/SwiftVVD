import XCTest
@testable import VUI

final class ParagraphWordBoundaryTests: XCTestCase {
    // ASSERTIONS textParagraphWordBoundary27Observed
    func testDefaultWordBoundariesKeepCombiningMarksAndDictionarySegments() {
        let cases: [(String, Bool)] = [
            ("A", true), ("word", true), ("don't", true), ("don’t", true),
            ("BB-BB", false), ("e\u{0301}lan", true), ("café", true),
            ("漢字", true), ("日本語", true), ("本語", false),
            ("a_b", true), ("a__", true), ("a.b", true), ("a/b", false),
            ("12.3", true), ("가", true), ("𐐀𐐁", false),
            ("ภาษาไทย", false), ("ไทย", true), ("שלום", true),
            ("Привет", true), ("مرحبا", true), ("l’heure", true),
            ("l'heure", true), ("123,456", true), ("a:b", false),
            ("a@b", false), ("a\u{200d}b", true), ("a\u{200c}b", true),
            ("\u{0301}a", false), ("a\u{00ad}b", true), ("कर्म", true),
            ("한국어", true), ("中文", true), ("abc漢字", false), ("漢字abc", false),
        ]
        for (word, expected) in cases {
            for tail in ["", " ", "...", "\u{fffc}", "\n", "!", " a"] {
                XCTAssertEqual(ParagraphWordBoundary.isSingleWord(word + tail),
                    expected && tail != " a", (word + tail).debugDescription)
            }
        }
        for text in ["", " ", ".word", "\tword", "\u{fffc}", "🇰🇷"] {
            XCTAssertFalse(ParagraphWordBoundary.isSingleWord(text), text.debugDescription)
        }
    }
}
