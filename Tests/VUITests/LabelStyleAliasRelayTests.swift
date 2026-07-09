import XCTest
@testable import VUI

private struct LabelStyleAliasRelayRoot: View {
    var body: some View {
        VStack(spacing: 8) {
            Button("Test Button") {}

            Label {
                Text("Test Label")
            } icon: {
                Text("ICON")
            }

            Text("Test Text")
        }
        .padding(16)
    }
}

final class LabelStyleAliasRelayTests: XCTestCase {
    func testDefaultLabelStyleConfigurationLabelRelaysOriginalSources() throws {
        let rendererHost = TestViewRendererHost()
        let viewGraph = ViewGraph(
            rootViewType: LabelStyleAliasRelayRoot.self,
            content: LabelStyleAliasRelayRoot(),
            rendererHost: rendererHost
        )
        rendererHost.storage = viewGraph

        viewGraph.updateOutputs(at: Time(seconds: 0))

        try viewGraph.data.withCurrent {
            try AGSubgraph.withCurrent(viewGraph.data.rootSubgraph) {
                let layout = try XCTUnwrap(viewGraph.rootLayoutComputer).value
                let size = layout.sizeThatFits(.unspecified)
                XCTAssertGreaterThan(size.width, 0)
                XCTAssertGreaterThan(size.height, 0)
            }
        }
    }
}
