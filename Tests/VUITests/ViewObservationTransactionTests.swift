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
            try AGSubgraph.$current.withValue(host.data.rootSubgraph) {
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
            try AGSubgraph.$current.withValue(host.data.rootSubgraph) {
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
            AGSubgraph.$current.withValue(host.data.rootSubgraph) {
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
            try AGSubgraph.$current.withValue(host.data.rootSubgraph) {
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
            AGSubgraph.$current.withValue(host.data.rootSubgraph) {
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
            AGSubgraph.$current.withValue(host.data.rootSubgraph) {
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
            try AGSubgraph.$current.withValue(host.data.rootSubgraph) {
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

    private func makeViewInputs(graph: _AGGraph) -> _ViewInputs {
        let environment = graph.makeInput(value: EnvironmentValues())
        let base = _GraphInputs(
            customInputs: PropertyList(),
            time: graph.makeInput(value: Time(seconds: 0)),
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
            size: graph.makeInput(value: ViewSize(width: 0, height: 0)),
            safeAreaInsets: OptionalAttribute(),
            containerSize: OptionalAttribute(),
            stackOrientation: nil
        )
    }
}
