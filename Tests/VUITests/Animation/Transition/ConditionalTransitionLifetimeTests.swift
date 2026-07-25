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
            return try Update.ensure {
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
                        let displayList = try XCTUnwrap(host.rootDisplayList?.value)
                        host.data.graph.drainActionOutbox()
                        return displayList
                    }
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

    func testAsymmetricMoveRemovalSamplesRetainedBranchPosition() throws {
        let probe = ConditionalTransitionLifetimeProbe()
        let rendererHost = TestViewRendererHost()
        let host = ViewGraph(
            rootViewType: ConditionalAsymmetricTransitionLifetimeRoot.self,
            content: ConditionalAsymmetricTransitionLifetimeRoot(probe: probe),
            rendererHost: rendererHost
        )
        rendererHost.storage = host

        func sampleBounds(at seconds: Double) throws -> CGRect? {
            let time = Time(seconds: seconds)
            rendererHost.currentTimestamp = time
            return try Update.ensure {
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
                        let bounds = try XCTUnwrap(host.rootDisplayList?.value)
                            .debugItemRecords
                            .compactMap(\.bounds)
                            .first
                        host.data.graph.drainActionOutbox()
                        return bounds
                    }
                }
            }
        }

        let initial = try XCTUnwrap(sampleBounds(at: 0))
        let toggle = try XCTUnwrap(probe.toggle)
        withAnimation(.linear(duration: 1)) {
            toggle()
        }

        _ = try sampleBounds(at: 1.0 / 60.0)
        _ = try sampleBounds(at: 2.0 / 60.0)
        let midpoint = try XCTUnwrap(sampleBounds(at: 0.5))
        _ = try sampleBounds(at: 2)
        let completed = try sampleBounds(at: 2 + 1.0 / 60.0)

        XCTAssertGreaterThan(midpoint.minX, initial.minX)
        XCTAssertLessThan(midpoint.minX, initial.maxX)
        XCTAssertNil(completed)
    }

    func testAsymmetricScaleInsertionSamplesPresentationBounds() throws {
        let probe = ConditionalTransitionLifetimeProbe()
        let rendererHost = TestViewRendererHost()
        let host = ViewGraph(
            rootViewType: ConditionalAsymmetricInsertionLifetimeRoot.self,
            content: ConditionalAsymmetricInsertionLifetimeRoot(probe: probe),
            rendererHost: rendererHost
        )
        rendererHost.storage = host

        func sample(at seconds: Double) throws -> (bounds: CGRect?, opacity: Double?) {
            let time = Time(seconds: seconds)
            rendererHost.currentTimestamp = time
            return try Update.ensure {
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
                        let list = try XCTUnwrap(host.rootDisplayList?.value)
                        let bounds = list
                            .debugItemRecords
                            .compactMap(\.bounds)
                            .first
                        host.data.graph.drainActionOutbox()
                        return (bounds, firstOpacity(in: list))
                    }
                }
            }
        }

        XCTAssertNil(try sample(at: 0).bounds)
        let toggle = try XCTUnwrap(probe.toggle)
        withAnimation(.linear(duration: 1)) {
            toggle()
        }

        let initial = try XCTUnwrap(sample(at: 0).bounds)
        _ = try sample(at: 1.0 / 60.0)
        _ = try sample(at: 2.0 / 60.0)
        let midpointSample = try sample(at: 0.5)
        let midpoint = try XCTUnwrap(midpointSample.bounds)
        let midpointOpacity = try XCTUnwrap(midpointSample.opacity)
        let completed = try XCTUnwrap(sample(at: 1).bounds)

        XCTAssertEqual(initial.width, 13, accuracy: 0.25)
        XCTAssertGreaterThan(midpoint.width, initial.width)
        XCTAssertLessThan(midpoint.width, completed.width)
        XCTAssertEqual(completed.width, 20, accuracy: 0.25)
        XCTAssertGreaterThan(midpointOpacity, 0)
        XCTAssertLessThan(midpointOpacity, 1)
    }

    func testDefaultConditionalInsertionSamplesOpacity() throws {
        let probe = ConditionalTransitionLifetimeProbe()
        let rendererHost = TestViewRendererHost()
        let host = ViewGraph(
            rootViewType: ConditionalDefaultInsertionLifetimeRoot.self,
            content: ConditionalDefaultInsertionLifetimeRoot(probe: probe),
            rendererHost: rendererHost
        )
        rendererHost.storage = host

        func sample(at seconds: Double) throws -> Double? {
            let time = Time(seconds: seconds)
            rendererHost.currentTimestamp = time
            return try Update.ensure {
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
                        let list = try XCTUnwrap(host.rootDisplayList?.value)
                        host.data.graph.drainActionOutbox()
                        return firstOpacity(in: list)
                    }
                }
            }
        }

        XCTAssertNil(try sample(at: 0))
        withAnimation(.linear(duration: 1)) {
            probe.toggle?()
        }

        _ = try sample(at: 1.0 / 60.0)
        _ = try sample(at: 2.0 / 60.0)
        let midpoint = try XCTUnwrap(sample(at: 0.5))
        XCTAssertGreaterThan(midpoint, 0)
        XCTAssertLessThan(midpoint, 1)
    }

    func testCompletedAsymmetricRemovalReinsertsThroughScaleTransition() throws {
        let probe = ConditionalTransitionLifetimeProbe()
        let rendererHost = TestViewRendererHost()
        let host = ViewGraph(
            rootViewType: ConditionalAsymmetricTransitionLifetimeRoot.self,
            content: ConditionalAsymmetricTransitionLifetimeRoot(probe: probe),
            rendererHost: rendererHost
        )
        rendererHost.storage = host

        func sampleBounds(at seconds: Double) throws -> CGRect? {
            let time = Time(seconds: seconds)
            rendererHost.currentTimestamp = time
            return try Update.ensure {
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
                        let bounds = host.rootDisplayList?.value
                            .debugItemRecords
                            .compactMap(\.bounds)
                            .first
                        host.data.graph.drainActionOutbox()
                        return bounds
                    }
                }
            }
        }

        _ = try XCTUnwrap(sampleBounds(at: 0))
        let toggle = try XCTUnwrap(probe.toggle)
        withAnimation(.linear(duration: 1)) {
            toggle()
        }

        _ = try sampleBounds(at: 1.0 / 60.0)
        _ = try sampleBounds(at: 0.5)
        _ = try sampleBounds(at: 1)
        _ = try sampleBounds(at: 1 + 1.0 / 60.0)
        XCTAssertNil(try sampleBounds(at: 2))

        withAnimation(.linear(duration: 1)) {
            toggle()
        }

        // ASSERTIONS contentTransitionLateReinsertFreshItemObserved
        let initial = try XCTUnwrap(sampleBounds(at: 2))
        _ = try sampleBounds(at: 2 + 1.0 / 60.0)
        _ = try sampleBounds(at: 2 + 2.0 / 60.0)
        let midpoint = try XCTUnwrap(sampleBounds(at: 2.5))
        let completed = try XCTUnwrap(sampleBounds(at: 3 + 1.0 / 60.0))

        XCTAssertEqual(initial.width, 13, accuracy: 0.25)
        XCTAssertGreaterThan(midpoint.width, initial.width)
        XCTAssertLessThan(midpoint.width, completed.width)
        XCTAssertEqual(completed.width, 20, accuracy: 0.25)
    }
}

private func firstOpacity(in list: DisplayList) -> Double? {
    for item in list.items {
        switch item.value {
        case let .content(content):
            if case let .style(style) = content.value,
               case let .opacity(opacity) = style.style {
                return opacity
            }
        case let .effect(_, contents):
            if let opacity = firstOpacity(in: contents) {
                return opacity
            }
        case let .states(states):
            for (_, contents) in states {
                if let opacity = firstOpacity(in: contents) {
                    return opacity
                }
            }
        case .empty:
            break
        }
    }
    return nil
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

private struct ConditionalAsymmetricTransitionLifetimeRoot: View {
    let probe: ConditionalTransitionLifetimeProbe
    @State private var isVisible = true

    var body: some View {
        probe.toggle = {
            isVisible.toggle()
        }
        return ZStack {
            Color.clear
                .frame(width: 100, height: 80)
            if isVisible {
                ConditionalTransitionLifetimeLeaf(marker: 1)
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.65)
                                .combined(with: .opacity),
                            removal: .move(edge: .trailing)
                                .combined(with: .opacity)
                        )
                    )
            }
        }
    }
}

private struct ConditionalAsymmetricInsertionLifetimeRoot: View {
    let probe: ConditionalTransitionLifetimeProbe
    @State private var isVisible = false

    var body: some View {
        probe.toggle = {
            isVisible.toggle()
        }
        return ZStack {
            Color.clear
                .frame(width: 100, height: 80)
            if isVisible {
                ConditionalTransitionLifetimeLeaf(marker: 1)
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.65)
                                .combined(with: .opacity),
                            removal: .move(edge: .trailing)
                                .combined(with: .opacity)
                        )
                    )
            }
        }
    }
}

private struct ConditionalDefaultInsertionLifetimeRoot: View {
    let probe: ConditionalTransitionLifetimeProbe
    @State private var isVisible = false

    var body: some View {
        probe.toggle = {
            isVisible.toggle()
        }
        return ZStack {
            Color.clear
                .frame(width: 100, height: 80)
            if isVisible {
                ConditionalTransitionLifetimeLeaf(marker: 1)
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
            list.appendCustomItem(
                bounds: CGRect(x: 0, y: 0, width: 20, height: 20),
                isOpaque: false,
                colorMode: .nonLinear,
                rendersAsynchronously: false
            ) { _ in }
            list.appendDebugItem(bounds: CGRect(x: 0, y: 0, width: 20, height: 20)) { _ in }
            return list
        }
        var outputs = _ViewOutputs(layoutComputer: OptionalAttribute(layout))
        outputs.preferences.append(DisplayList.Key.self, node: displayList.identifier)
        return outputs
    }
}
