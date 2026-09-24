import XCTest
import VUI

// ASSERTIONS viewKerningPublic27Observed

final class ViewKerningPublicAPITests: XCTestCase {
    private func requireView<V: View>(_ value: V) {
        _ = value
    }

    func testViewKerningProducerIsPublic() {
        requireView(EmptyView().kerning(3))
        requireView(EmptyView().kerning(0))
        requireView(EmptyView().kerning(-4))
        requireView(EmptyView().kerning(3).kerning(5))
    }
}
