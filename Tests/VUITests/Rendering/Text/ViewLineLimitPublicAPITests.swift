import XCTest
import VUI

// ASSERTIONS viewLineLimitPublic27Observed

final class ViewLineLimitPublicAPITests: XCTestCase {
    private func requireView<V: View>(_ value: V) {
        _ = value
    }

    func testViewLineLimitRangeProducersArePublic() {
        requireView(EmptyView().lineLimit(2...4))
        requireView(EmptyView().lineLimit(2...))
        requireView(EmptyView().lineLimit(...4))
        requireView(EmptyView().lineLimit(3, reservesSpace: true))
        requireView(EmptyView().lineLimit(3, reservesSpace: false))
        requireView(
            EmptyView()
                .lineLimit(2...4)
                .lineLimit(Optional(1))
        )
        requireView(
            EmptyView()
                .lineLimit(Optional(1))
                .lineLimit(2...4)
        )
    }
}
