import XCTest
import VUI

// ASSERTIONS textFontDesignPublic27Observed

final class TextFontDesignPublicAPITests: XCTestCase {
    private func requireText(_ value: Text) {
        _ = value
    }

    private func requireView<V: View>(_ value: V) {
        _ = value
    }

    func testTextAndViewFontDesignProducersArePublic() {
        requireText(Text(verbatim: "A").fontDesign(.rounded))
        requireText(Text(verbatim: "A").fontDesign(nil))
        requireView(EmptyView().fontDesign(.serif))
        requireView(EmptyView().fontDesign(nil))
    }
}
