import XCTest
import VUI

// ASSERTIONS viewFontWeightPublic27Observed

final class ViewFontWeightPublicAPITests: XCTestCase {
    private func requireView<V: View>(_ value: V) {
        _ = value
    }

    func testViewFontWeightProducerIsPublicAndAcceptsOptionalWeight() {
        requireView(EmptyView().fontWeight(.light))
        requireView(EmptyView().fontWeight(.heavy))
        requireView(EmptyView().fontWeight(nil))
        requireView(EmptyView().fontWeight(.light).fontWeight(nil))
    }
}
