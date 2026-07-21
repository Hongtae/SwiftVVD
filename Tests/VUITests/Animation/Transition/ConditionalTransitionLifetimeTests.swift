import XCTest
@testable import VUI

final class ConditionalTransitionLifetimeTests: XCTestCase {
    func testRemovalTransitionRetainsConditionalBranchAttributes() throws {
        let probe = ConditionalTransitionLifetimeProbe()
        let rendererHost = TestViewRendererHost()
        let host = ViewGraph(
            rootViewType: ConditionalTransitionLifetimeRoot.self,
            content: ConditionalTransitionLifetimeRoot(probe: probe),
            rendererHost: rendererHost
        )
        rendererHost.storage = host

        func sample(at seconds: Double) throws -> DisplayList {
            let time = Time(seconds: seconds)
            rendererHost.currentTimestamp = time
            host.updateOutputs(at: time)
            return try host.data.withCurrent {
                try AGSubgraph.withCurrent(host.data.rootSubgraph) {
                    let layout = try XCTUnwrap(host.rootLayoutComputer).value
                    let size = CGSize(width: 200, height: 120)
                    layout.place(
                        at: CGPoint(x: size.width / 2, y: size.height / 2),
                        anchor: .center,
                        proposal: ProposedViewSize(size)
                    )
                    host.data.rootSubgraph.update()
                    return try XCTUnwrap(host.rootDisplayList?.value)
                }
            }
        }

        _ = try sample(at: 0)
        let toggle = try XCTUnwrap(probe.toggle)
        withAnimation(.linear(duration: 1)) {
            toggle()
        }

        let midpoint = try sample(at: 0.5)
        _ = try sample(at: 2)

        func debugItemCount(in list: DisplayList) -> Int {
            list.debugItems.count + list.effects.reduce(0) {
                $0 + debugItemCount(in: $1.contents)
            }
        }
        XCTAssertGreaterThan(debugItemCount(in: midpoint), 0)
    }
}

private final class ConditionalTransitionLifetimeProbe {
    var toggle: (() -> Void)?
}

private struct ConditionalTransitionLifetimeRoot: View {
    let probe: ConditionalTransitionLifetimeProbe
    @State private var isVisible = true

    var body: some View {
        probe.toggle = {
            isVisible.toggle()
        }
        return VStack {
            if isVisible {
                ConditionalTransitionLifetimeLeaf(marker: 1)
                    .transition(.opacity)
            }
        }
    }
}

private struct ConditionalTransitionLifetimeLeaf: View, TestPrimitiveView {
    var marker: Int

    typealias Body = Never

    static func _makeView(
        view: _GraphValue<Self>,
        inputs: _ViewInputs
    ) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("ConditionalTransitionLifetimeLeaf._makeView requires an active graph")
        }
        let layout = graph.makeRule {
            LayoutComputer.fixed(CGSize(width: 20, height: 20))
        }
        let displayList: Attribute<DisplayList> = graph.makeRule {
            _ = view._attribute.value.marker
            var list = DisplayList()
            list.appendDebugItem(bounds: CGRect(x: 0, y: 0, width: 20, height: 20)) { _ in }
            return list
        }
        var outputs = _ViewOutputs(layoutComputer: OptionalAttribute(layout))
        outputs.preferences.append(DisplayList.Key.self, node: displayList.identifier)
        return outputs
    }
}
