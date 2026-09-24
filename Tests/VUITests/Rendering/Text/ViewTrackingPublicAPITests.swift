import XCTest
import VUI

// ASSERTIONS viewTrackingPublic27Observed

final class ViewTrackingPublicAPITests: XCTestCase {
    private func requireView<V: View>(_ value: V) {
        _ = value
    }

    func testViewTrackingProducerIsPublic() {
        requireView(EmptyView().tracking(3))
        requireView(EmptyView().tracking(0))
        requireView(EmptyView().tracking(-4))
        requireView(EmptyView().tracking(3).tracking(5))
    }
}
