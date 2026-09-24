import XCTest
import VUI

// ASSERTIONS textAllowsTightening27Observed

final class TextAllowsTighteningPublicAPITests: XCTestCase {
    private func requireView<V: View>(_ value: V) {
        _ = value
    }

    func testPublicEnvironmentValueAndViewProducerAreAvailable() {
        var environment = EnvironmentValues()
        XCTAssertFalse(environment.allowsTightening)
        environment.allowsTightening = true
        XCTAssertTrue(environment.allowsTightening)

        var copy = environment
        copy.allowsTightening = false
        XCTAssertTrue(environment.allowsTightening)
        XCTAssertFalse(copy.allowsTightening)

        requireView(EmptyView().allowsTightening(true))
        requireView(EmptyView().allowsTightening(false))
        requireView(
            EmptyView().allowsTightening(true).allowsTightening(false)
        )
        requireView(
            EmptyView().allowsTightening(false).allowsTightening(true)
        )
    }
}
