import Foundation
import XCTest
import VUI

// ASSERTIONS textCasePublic27Observed

final class TextCasePublicAPITests: XCTestCase {
    private func requireView<V: View>(_ value: V) {
        _ = value
    }

    private func requireConformances<T: Hashable & Sendable>(_: T.Type) {}

    func testPublicEnvironmentValueAndViewProducerAreAvailable() {
        requireConformances(Text.Case.self)
        XCTAssertNotEqual(Text.Case.uppercase, .lowercase)

        var environment = EnvironmentValues()
        XCTAssertNil(environment.textCase)
        environment.textCase = .uppercase
        XCTAssertEqual(environment.textCase, .uppercase)

        var copy = environment
        copy.textCase = .lowercase
        XCTAssertEqual(environment.textCase, .uppercase)
        XCTAssertEqual(copy.textCase, .lowercase)
        copy.textCase = nil
        XCTAssertNil(copy.textCase)

        requireView(EmptyView().textCase(nil))
        requireView(EmptyView().textCase(.uppercase))
        requireView(EmptyView().textCase(.lowercase))
        requireView(
            EmptyView().textCase(.uppercase).textCase(.lowercase)
        )
        requireView(
            EmptyView().textCase(nil).textCase(.uppercase)
        )
    }
}
