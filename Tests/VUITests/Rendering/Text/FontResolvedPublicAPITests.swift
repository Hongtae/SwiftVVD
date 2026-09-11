import Foundation
import XCTest
import VUI

final class FontResolvedPublicAPITests: XCTestCase {
    // ASSERTIONS fontResolvedRetainedContextObserved
    func testExternalConsumerCanResolveAndCompareFontValues() {
        func requireValue<T: Hashable & Sendable>(_: T) {}
        var environment = EnvironmentValues()
        environment.font = .system(size: 31)
        let context: Font.Context = environment.fontResolutionContext
        let resolved: Font.Resolved = Font.system(size: 17).resolve(in: context)
        requireValue(context)
        requireValue(resolved)
        XCTAssertEqual(resolved.pointSize, 17)
        XCTAssertFalse(context.debugDescription.isEmpty)

        environment.font = .system(size: 41)
        let changed = environment.fontResolutionContext
        XCTAssertNotEqual(context, changed)
        let sameFont = Font.system(size: 17).resolve(in: changed)
        let differentFont = Font.system(size: 19).resolve(in: changed)
        XCTAssertEqual(resolved, sameFont)
        XCTAssertEqual(Set([resolved, sameFont, differentFont]).count, 2)
        XCTAssertEqual([resolved: "retained"][sameFont], "retained")
    }
}
