import XCTest
import VUI

// ASSERTIONS viewBaselineOffsetPublic27Observed

final class ViewBaselineOffsetPublicAPITests: XCTestCase {
    private func requireView<V: View>(_ value: V) {
        _ = value
    }

    func testViewBaselineOffsetProducerIsPublic() {
        requireView(EmptyView().baselineOffset(3))
        requireView(EmptyView().baselineOffset(0))
        requireView(
            EmptyView().baselineOffset(3).baselineOffset(5)
        )
    }
}
