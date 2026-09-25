import Foundation
import XCTest
import VUI

// ASSERTIONS textAccessibilitySpeechPublic27Observed

final class TextAccessibilitySpeechPublicAPITests: XCTestCase {
    private func requireSendable<T: Sendable>(_ value: T) {
        _ = value
    }

    func testPublicTypesAndAllTextProducerOverloadsCompile() {
        let contentTypes: [AccessibilityTextContentType] = [
            .plain, .console, .fileSystem, .messaging,
            .narrative, .sourceCode, .spreadsheet, .wordProcessing,
        ]
        contentTypes.forEach(requireSendable)

        XCTAssertEqual(AccessibilityHeadingLevel.unspecified.rawValue, 0)
        XCTAssertEqual(AccessibilityHeadingLevel.h1.rawValue, 1)
        XCTAssertEqual(AccessibilityHeadingLevel.h2.rawValue, 2)
        XCTAssertEqual(AccessibilityHeadingLevel.h3.rawValue, 3)
        XCTAssertEqual(AccessibilityHeadingLevel.h4.rawValue, 4)
        XCTAssertEqual(AccessibilityHeadingLevel.h5.rawValue, 5)
        XCTAssertEqual(AccessibilityHeadingLevel.h6.rawValue, 6)

        let generic = "Generic spoken"[...]
        let resource = LocalizedStringResource("spoken")
        let text = Text(verbatim: "Hg")
            .speechAlwaysIncludesPunctuation()
            .speechAlwaysIncludesPunctuation(false)
            .speechSpellsOutCharacters()
            .speechSpellsOutCharacters(false)
            .speechAdjustedPitch(0.75)
            .speechAnnouncementsQueued()
            .speechAnnouncementsQueued(false)
            .accessibilityTextContentType(.sourceCode)
            .accessibilityHeading(.h2)
            .accessibilityLabel(Text(verbatim: "Text spoken"))
            .accessibilityLabel(LocalizedStringKey("spoken"))
            .accessibilityLabel(resource)
            .accessibilityLabel(generic)
        _ = text
    }
}
