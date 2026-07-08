import Foundation
import Observation
import XCTest
@testable import VUI

@Observable
private final class ViewObservationTransactionModel {
    var value: CGFloat = 10
}

private struct ViewObservationTransactionKey: TransactionKey {
    static let defaultValue = 0
}

private enum ViewObservationTransactionProbeError: Error {
    case expected
}

private struct ObservationTransactionRoot: View {
    let model: ViewObservationTransactionModel

    var body: ObservationTransactionLeaf {
        ObservationTransactionLeaf(width: model.value)
    }
}

private struct ObservationTransactionLeaf: View, _PrimitiveView {
    var width: CGFloat

    typealias Body = Never

    static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("\(Self.self)._makeView called outside an active _AGGraph context.")
        }

        let layout = graph.makeRule {
            let leaf = view._attribute.value
            return LayoutComputer.fixed(CGSize(width: leaf.width, height: 12))
        }
        return _ViewOutputs(layoutComputer: OptionalAttribute(layout))
    }
}

private struct ObservationAnimatableTransactionRoot: View {
    let model: ViewObservationTransactionModel

    var body: ObservationAnimatableTransactionLeaf {
        ObservationAnimatableTransactionLeaf(width: model.value)
    }
}

private struct ObservationAnimatableTransactionLeaf: View, _PrimitiveView, Animatable {
    var width: CGFloat

    typealias Body = Never

    var animatableData: CGFloat {
        get { width }
        set { width = newValue }
    }

    static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("\(Self.self)._makeView called outside an active _AGGraph context.")
        }

        var animatedView = view
        Self._makeAnimatable(value: &animatedView, inputs: inputs.base)
        let layout = graph.makeRule {
            let leaf = animatedView._attribute.value
            return LayoutComputer.fixed(CGSize(width: leaf.width, height: 12))
        }
        return _ViewOutputs(layoutComputer: OptionalAttribute(layout))
    }
}

private final class StateAnimatableTransactionProbe {
    var toggle: (() -> Void)?
}

private struct StateAnimatableTransactionRoot: View {
    let probe: StateAnimatableTransactionProbe
    @State private var expanded = false

    var body: ObservationAnimatableTransactionLeaf {
        probe.toggle = {
            expanded.toggle()
        }
        return ObservationAnimatableTransactionLeaf(width: expanded ? 24 : 10)
    }
}

private struct AnimationLabDisplayLeaf: View, _PrimitiveView {
    typealias Body = Never

    static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("\(Self.self)._makeView called outside an active _AGGraph context.")
        }

        let layout = graph.makeRule {
            LayoutComputer.fixed(CGSize(width: 20, height: 20))
        }
        let displayList: Attribute<DisplayList> = graph.makeRule {
            var list = DisplayList()
            list.appendDebugItem(bounds: CGRect(x: 0, y: 0, width: 20, height: 20)) { _ in }
            return list
        }
        var outputs = _ViewOutputs(layoutComputer: OptionalAttribute(layout))
        outputs.preferences.append(DisplayList.Key.self, node: displayList.identifier)
        return outputs
    }
}

private struct StateAnimationLabModifierStackRoot: View {
    let probe: StateAnimatableTransactionProbe
    @State private var expanded = false

    var body: some View {
        probe.toggle = {
            expanded.toggle()
        }
        return AnimationLabDisplayLeaf()
            .scaleEffect(expanded ? 1.08 : 0.78)
            .rotationEffect(.degrees(expanded ? 8 : -8))
            .offset(x: expanded ? 42 : -42, y: expanded ? 8 : -8)
            .opacity(expanded ? 0.92 : 0.55)
    }
}

@MainActor
private final class ObservationAsyncWaiter {
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}

final class ViewObservationTransactionTests: XCTestCase {
    func testDefaultBodyObservationInvalidationPropagatesCurrentTransaction() throws {
        let host = GraphHost()
        let model = ViewObservationTransactionModel()

        try host.data.withCurrent {
            try AGSubgraph.withCurrent(host.data.rootSubgraph) {
                let graph = host.data.graph
                let source = graph.makeInput(value: ObservationTransactionRoot(model: model))
                let outputs = ObservationTransactionRoot._makeView(
                    view: _GraphValue(_attribute: source),
                    inputs: makeViewInputs(graph: graph)
                )
                let layoutAttr = try XCTUnwrap(outputs._layoutComputer.attribute)
                XCTAssertEqual(layoutAttr.value.sizeThatFits(.unspecified), CGSize(width: 10, height: 12))
                XCTAssertNil(graph.transaction(for: layoutAttr.identifier))

                var transaction = Transaction()
                transaction[ViewObservationTransactionKey.self] = 7

                withTransaction(transaction) {
                    model.value = 24
                }

                host.data.rootSubgraph.update()

                let propagated = try XCTUnwrap(graph.transaction(for: layoutAttr.identifier))
                XCTAssertEqual(propagated[ViewObservationTransactionKey.self], 7)
                XCTAssertEqual(layoutAttr.value.sizeThatFits(.unspecified), CGSize(width: 24, height: 12))
            }
        }
    }

    func testDefaultBodyObservationAnimatableSourceUsesScopedTransaction() throws {
        let rendererHost = TestViewRendererHost()
        let host = ViewGraph(
            rootViewType: EmptyView.self,
            content: EmptyView(),
            rendererHost: rendererHost,
            requestedOutputs: []
        )
        rendererHost.storage = host
        let model = ViewObservationTransactionModel()

        try host.data.withCurrent {
            try AGSubgraph.withCurrent(host.data.rootSubgraph) {
                let graph = host.data.graph
                let source = graph.makeInput(value: ObservationAnimatableTransactionRoot(model: model))
                let outputs = ObservationAnimatableTransactionRoot._makeView(
                    view: _GraphValue(_attribute: source),
                    inputs: makeViewInputs(graph: graph)
                )
                let layoutAttr = try XCTUnwrap(outputs._layoutComputer.attribute)
                XCTAssertEqual(layoutAttr.value.sizeThatFits(.unspecified), CGSize(width: 10, height: 12))

                withAnimation(.linear(duration: 1.0)) {
                    model.value = 24
                }

                host.data.rootSubgraph.update()

                let sampledWidth = layoutAttr.value.sizeThatFits(.unspecified).width
                XCTAssertLessThan(sampledWidth, 24)
                XCTAssertGreaterThanOrEqual(sampledWidth, 10)
                let propagated = try XCTUnwrap(graph.transaction(for: layoutAttr.identifier))
                XCTAssertNotNil(propagated.animation)
            }
        }
    }

    func testDefaultBodyStateActionAnimatableSourceUsesScopedTransaction() throws {
        let rendererHost = TestViewRendererHost()
        let host = ViewGraph(
            rootViewType: EmptyView.self,
            content: EmptyView(),
            rendererHost: rendererHost,
            requestedOutputs: []
        )
        rendererHost.storage = host
        let probe = StateAnimatableTransactionProbe()

        try host.data.withCurrent {
            try AGSubgraph.withCurrent(host.data.rootSubgraph) {
                let graph = host.data.graph
                let source = graph.makeInput(value: StateAnimatableTransactionRoot(probe: probe))
                let outputs = StateAnimatableTransactionRoot._makeView(
                    view: _GraphValue(_attribute: source),
                    inputs: makeViewInputs(graph: graph)
                )
                let layoutAttr = try XCTUnwrap(outputs._layoutComputer.attribute)
                XCTAssertEqual(layoutAttr.value.sizeThatFits(.unspecified), CGSize(width: 10, height: 12))
                let toggle = try XCTUnwrap(probe.toggle)

                withAnimation(.linear(duration: 1.0)) {
                    toggle()
                }

                host.data.rootSubgraph.update()

                let sampledWidth = layoutAttr.value.sizeThatFits(.unspecified).width
                XCTAssertLessThan(sampledWidth, 24)
                XCTAssertGreaterThanOrEqual(sampledWidth, 10)
                let propagated = try XCTUnwrap(graph.transaction(for: layoutAttr.identifier))
                XCTAssertNotNil(propagated.animation)
            }
        }
    }

    func testDefaultBodyStateActionAnimatesAnimationLabModifierStack() throws {
        let rendererHost = TestViewRendererHost()
        let host = ViewGraph(
            rootViewType: EmptyView.self,
            content: EmptyView(),
            rendererHost: rendererHost,
            requestedOutputs: []
        )
        rendererHost.storage = host
        let probe = StateAnimatableTransactionProbe()

        try host.data.withCurrent {
            try AGSubgraph.withCurrent(host.data.rootSubgraph) {
                let graph = host.data.graph
                let time = graph.makeInput(value: Time(seconds: 0))
                let source = graph.makeInput(value: StateAnimationLabModifierStackRoot(probe: probe))
                let outputs = StateAnimationLabModifierStackRoot._makeView(
                    view: _GraphValue(_attribute: source),
                    inputs: makeViewInputs(
                        graph: graph,
                        time: time,
                        size: graph.makeInput(value: ViewSize(width: 20, height: 20))
                    )
                )
                let displayID = try XCTUnwrap(outputs.preferences.value(for: DisplayList.Key.self))
                let initialBounds = try XCTUnwrap(Attribute<DisplayList>(displayID).value.interpolationBounds)
                let toggle = try XCTUnwrap(probe.toggle)

                withAnimation(.linear(duration: 1.0)) {
                    toggle()
                }
                host.data.rootSubgraph.update()
                _ = Attribute<DisplayList>(displayID).value

                time.setValue(Time(seconds: 0.5))
                host.data.rootSubgraph.update()
                _ = Attribute<DisplayList>(displayID).value

                time.setValue(Time(seconds: 0.6))
                host.data.rootSubgraph.update()
                let midpointBounds = try XCTUnwrap(Attribute<DisplayList>(displayID).value.interpolationBounds)

                time.setValue(Time(seconds: 2.0))
                host.data.rootSubgraph.update()
                let finalBounds = try XCTUnwrap(Attribute<DisplayList>(displayID).value.interpolationBounds)

                XCTAssertNotEqual(initialBounds, finalBounds)
                XCTAssertNotEqual(midpointBounds, finalBounds)
                XCTAssertGreaterThan(midpointBounds.minX, initialBounds.minX)
                XCTAssertLessThan(midpointBounds.minX, finalBounds.minX)
            }
        }
    }

    func testKeyPathThrowingBodyMutationPropagatesScopedTransaction() throws {
        let host = GraphHost()
        let model = ViewObservationTransactionModel()
        let layoutAttr = try makeObservedLayout(host: host, model: model)

        do {
            try withTransaction(\.disablesAnimations, true) {
                model.value = 28
                throw ViewObservationTransactionProbeError.expected
            }
            XCTFail("throwing key-path withTransaction returned normally")
        } catch ViewObservationTransactionProbeError.expected {
        } catch {
            XCTFail("unexpected error: \(error)")
        }

        try host.data.withCurrent {
            try AGSubgraph.withCurrent(host.data.rootSubgraph) {
                host.data.rootSubgraph.update()

                let propagated = try XCTUnwrap(host.data.graph.transaction(for: layoutAttr.identifier))
                XCTAssertTrue(propagated.disablesAnimations)
                XCTAssertFalse(propagated.tracksVelocity)
                XCTAssertEqual(layoutAttr.value.sizeThatFits(.unspecified), CGSize(width: 28, height: 12))
            }
        }
    }

    func testKeyPathThrowingCatchMutationDoesNotInheritThrownTransaction() throws {
        let host = GraphHost()
        let model = ViewObservationTransactionModel()
        let layoutAttr = try makeObservedLayout(host: host, model: model)

        do {
            try withTransaction(\.disablesAnimations, true) {
                throw ViewObservationTransactionProbeError.expected
            }
            XCTFail("throwing key-path withTransaction returned normally")
        } catch ViewObservationTransactionProbeError.expected {
            model.value = 32
        } catch {
            XCTFail("unexpected error: \(error)")
        }

        host.data.withCurrent {
            AGSubgraph.withCurrent(host.data.rootSubgraph) {
                host.data.rootSubgraph.update()

                XCTAssertNil(host.data.graph.transaction(for: layoutAttr.identifier))
                XCTAssertEqual(layoutAttr.value.sizeThatFits(.unspecified), CGSize(width: 32, height: 12))
            }
        }
    }

    func testNestedKeyPathThrowingCatchMutationRestoresOuterTransaction() throws {
        let host = GraphHost()
        let model = ViewObservationTransactionModel()
        let layoutAttr = try makeObservedLayout(host: host, model: model)

        withTransaction(\.tracksVelocity, true) {
            do {
                try withTransaction(\.disablesAnimations, true) {
                    throw ViewObservationTransactionProbeError.expected
                }
                XCTFail("throwing key-path withTransaction returned normally")
            } catch ViewObservationTransactionProbeError.expected {
                model.value = 36
            } catch {
                XCTFail("unexpected error: \(error)")
            }
        }

        try host.data.withCurrent {
            try AGSubgraph.withCurrent(host.data.rootSubgraph) {
                host.data.rootSubgraph.update()

                let propagated = try XCTUnwrap(host.data.graph.transaction(for: layoutAttr.identifier))
                XCTAssertFalse(propagated.disablesAnimations)
                XCTAssertTrue(propagated.tracksVelocity)
                XCTAssertEqual(layoutAttr.value.sizeThatFits(.unspecified), CGSize(width: 36, height: 12))
            }
        }
    }

    @MainActor
    func testDispatchQueueObservableInvalidationScheduledInsideTransactionDoesNotPropagateScopedTransaction() async throws {
        let host = GraphHost()
        let model = ViewObservationTransactionModel()
        let layoutAttr = try makeObservedLayout(host: host, model: model)

        var transaction = Transaction(animation: .linear(duration: 0.20))
        transaction[ViewObservationTransactionKey.self] = 11

        let waiter = ObservationAsyncWaiter()
        withTransaction(transaction) {
            DispatchQueue.main.async {
                model.value = 32
                waiter.resume()
            }
        }
        await waiter.wait()

        host.data.withCurrent {
            AGSubgraph.withCurrent(host.data.rootSubgraph) {
                host.data.rootSubgraph.update()

                XCTAssertNil(host.data.graph.transaction(for: layoutAttr.identifier))
                XCTAssertEqual(layoutAttr.value.sizeThatFits(.unspecified), CGSize(width: 32, height: 12))
            }
        }
    }

    @MainActor
    func testMainActorObservableInvalidationScheduledInsideAnimationDoesNotPropagateScopedTransaction() async throws {
        let host = GraphHost()
        let model = ViewObservationTransactionModel()
        let layoutAttr = try makeObservedLayout(host: host, model: model)

        let waiter = ObservationAsyncWaiter()
        _ = withAnimation(.linear(duration: 0.20)) {
            Task { @MainActor in
                model.value = 48
                waiter.resume()
            }
        }
        await waiter.wait()

        host.data.withCurrent {
            AGSubgraph.withCurrent(host.data.rootSubgraph) {
                host.data.rootSubgraph.update()

                XCTAssertNil(host.data.graph.transaction(for: layoutAttr.identifier))
                XCTAssertEqual(layoutAttr.value.sizeThatFits(.unspecified), CGSize(width: 48, height: 12))
            }
        }
    }

    private func makeObservedLayout(
        host: GraphHost,
        model: ViewObservationTransactionModel
    ) throws -> Attribute<LayoutComputer> {
        try host.data.withCurrent {
            try AGSubgraph.withCurrent(host.data.rootSubgraph) {
                let graph = host.data.graph
                let source = graph.makeInput(value: ObservationTransactionRoot(model: model))
                let outputs = ObservationTransactionRoot._makeView(
                    view: _GraphValue(_attribute: source),
                    inputs: makeViewInputs(graph: graph)
                )
                let layoutAttr = try XCTUnwrap(outputs._layoutComputer.attribute)
                XCTAssertEqual(layoutAttr.value.sizeThatFits(.unspecified), CGSize(width: 10, height: 12))
                XCTAssertNil(graph.transaction(for: layoutAttr.identifier))
                return layoutAttr
            }
        }
    }

    private func makeViewInputs(
        graph: _AGGraph,
        time: Attribute<Time>? = nil,
        size: Attribute<ViewSize>? = nil
    ) -> _ViewInputs {
        let environment = graph.makeInput(value: EnvironmentValues())
        let base = _GraphInputs(
            customInputs: PropertyList(),
            time: time ?? graph.makeInput(value: Time(seconds: 0)),
            cachedEnvironment: MutableBox(CachedEnvironment(environment: environment)),
            phase: graph.makeInput(value: Phase()),
            transaction: graph.makeInput(value: Transaction()),
            changedDebugProperties: 0,
            options: [],
            mergedInputs: []
        )
        return _ViewInputs(
            base: base,
            customInputs: PropertyList(),
            preferences: PreferencesInputs(
                keys: PreferenceKeys(),
                hostKeys: graph.makeInput(value: PreferenceKeys())
            ),
            transform: graph.makeInput(value: ViewTransform()),
            position: graph.makeInput(value: CGPoint.zero),
            containerPosition: graph.makeInput(value: CGPoint.zero),
            size: size ?? graph.makeInput(value: ViewSize(width: 0, height: 0)),
            safeAreaInsets: OptionalAttribute(),
            containerSize: OptionalAttribute(),
            stackOrientation: nil
        )
    }
}
