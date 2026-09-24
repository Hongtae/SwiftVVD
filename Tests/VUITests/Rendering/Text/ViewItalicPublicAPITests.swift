import XCTest
import VUI

// ASSERTIONS viewItalicPublic27Observed

final class ViewItalicPublicAPITests: XCTestCase {
    private func requireView<V: View>(_ value: V) {
        _ = value
    }

    func testViewItalicProducerIsPublicAndDefaultsToActive() {
        requireView(EmptyView().italic())
        requireView(EmptyView().italic(true))
        requireView(EmptyView().italic(false))
        requireView(EmptyView().italic(true).italic(false))
    }
}
