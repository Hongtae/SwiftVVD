import XCTest
import VUI

// ASSERTIONS viewBoldPublic27Observed

final class ViewBoldPublicAPITests: XCTestCase {
    private func requireView<V: View>(_ value: V) {
        _ = value
    }

    func testViewBoldProducerIsPublicAndDefaultsActive() {
        requireView(EmptyView().bold())
        requireView(EmptyView().bold(true))
        requireView(EmptyView().bold(false))
        requireView(EmptyView().bold(true).bold(false))
    }
}
