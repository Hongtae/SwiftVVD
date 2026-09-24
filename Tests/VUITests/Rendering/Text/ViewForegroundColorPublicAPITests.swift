import XCTest
import VUI

// ASSERTIONS viewForegroundColorPublic27Observed

final class ViewForegroundColorPublicAPITests: XCTestCase {
    private func requireView<V: View>(_ value: V) {
        _ = value
    }

    func testViewForegroundColorProducerIsPublic() {
        requireView(EmptyView().foregroundColor(.red))
        requireView(EmptyView().foregroundColor(nil))
        requireView(
            EmptyView()
                .foregroundColor(.red)
                .foregroundColor(.blue)
        )
        requireView(
            EmptyView()
                .foregroundColor(.red)
                .foregroundStyle(.blue)
        )
    }
}
