import XCTest
import VUI

// ASSERTIONS viewDecorationPublic27Observed

final class ViewDecorationPublicAPITests: XCTestCase {
    private func requireView<V: View>(_ value: V) {
        _ = value
    }

    func testViewDecorationProducersArePublic() {
        requireView(EmptyView().underline())
        requireView(EmptyView().underline(
            false,
            pattern: .dash,
            color: .red
        ))
        requireView(EmptyView().strikethrough())
        requireView(EmptyView().strikethrough(
            false,
            pattern: .dot,
            color: .blue
        ))
        requireView(
            EmptyView()
                .underline(pattern: .dashDot)
                .strikethrough(pattern: .dashDotDot)
        )
    }
}
