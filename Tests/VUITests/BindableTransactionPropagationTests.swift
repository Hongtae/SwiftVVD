import Observation
import XCTest
@testable import VUI

@Observable
private final class BindableTransactionModel {
    var localValue = 0.0
    var ambientValue = 0.0
    var ambientNilValue = 0.0
}

private struct BindableTransactionSnapshot: Equatable {
    var isEmpty: Bool
    var hasAnimation: Bool
    var disablesAnimations: Bool
}

private struct BindableTransactionGraphKey: TransactionKey {
    static let defaultValue = 0
}

private struct BindableLocalTransactionRoot: View {
    let model: BindableTransactionModel

    var body: BindableTransactionLeaf {
        BindableTransactionLeaf(width: CGFloat(model.localValue))
    }
}

private struct BindableAmbientTransactionRoot: View {
    let model: BindableTransactionModel

    var body: BindableTransactionLeaf {
        BindableTransactionLeaf(width: CGFloat(model.ambientValue))
    }
}

private struct BindableTransactionLeaf: View, _PrimitiveView {
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

private final class BindableTransactionSnapshotRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [BindableTransactionSnapshot] = []

    var snapshots: [BindableTransactionSnapshot] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func record(_ snapshot: BindableTransactionSnapshot) {
        lock.lock()
        storage.append(snapshot)
        lock.unlock()
    }
}

final class BindableTransactionPropagationTests: XCTestCase {
    func testLocalTransactionInstallsActiveScopeForObservableInvalidation() {
        let model = BindableTransactionModel()
        let bindable = Bindable(model)
        let recorder = BindableTransactionSnapshotRecorder()
        var events: [String] = []

        withObservationTracking {
            _ = model.localValue
        } onChange: {
            recorder.record(Self.snapshot(Transaction.current))
        }

        var local = Transaction(animation: .linear(duration: 0.20))
        local.disablesAnimations = true
        local.addAnimationCompletion(criteria: .removed) {
            events.append("local completion")
        }

        bindable.localValue.transaction(local).wrappedValue = 1
        events.append("returned")

        XCTAssertEqual(model.localValue, 1)
        XCTAssertEqual(
            recorder.snapshots,
            [.init(isEmpty: false, hasAnimation: true, disablesAnimations: true)]
        )

        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        XCTAssertEqual(events, ["returned"])

        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.25))
        XCTAssertEqual(events, ["returned", "local completion"])
    }

    func testAmbientTransactionOwnsBindableMutationWhenLocalTransactionIsPresent() {
        let model = BindableTransactionModel()
        let bindable = Bindable(model)
        let recorder = BindableTransactionSnapshotRecorder()
        var events: [String] = []

        withObservationTracking {
            _ = model.ambientValue
        } onChange: {
            recorder.record(Self.snapshot(Transaction.current))
        }

        var local = Transaction(animation: nil)
        local.disablesAnimations = true
        local.addAnimationCompletion(criteria: .removed) {
            events.append("local completion")
        }

        var ambient = Transaction(animation: .linear(duration: 0.20))
        ambient.addAnimationCompletion(criteria: .removed) {
            events.append("ambient completion")
        }

        withTransaction(ambient) {
            bindable.ambientValue.transaction(local).wrappedValue = 1
            events.append("body")
        }
        events.append("returned")

        XCTAssertEqual(model.ambientValue, 1)
        XCTAssertEqual(
            recorder.snapshots,
            [.init(isEmpty: false, hasAnimation: true, disablesAnimations: false)]
        )

        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        XCTAssertEqual(events, ["body", "returned", "local completion"])

        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.25))
        XCTAssertEqual(events, ["body", "returned", "local completion", "ambient completion"])
    }

    func testAmbientNilTransactionOverridesBindableLocalAnimation() {
        let model = BindableTransactionModel()
        let bindable = Bindable(model)
        let recorder = BindableTransactionSnapshotRecorder()
        var events: [String] = []

        withObservationTracking {
            _ = model.ambientNilValue
        } onChange: {
            recorder.record(Self.snapshot(Transaction.current))
        }

        var local = Transaction(animation: .linear(duration: 0.20))
        local.disablesAnimations = true
        local.addAnimationCompletion(criteria: .removed) {
            events.append("local completion")
        }

        var ambient = Transaction(animation: nil)
        ambient.addAnimationCompletion(criteria: .removed) {
            events.append("ambient completion")
        }

        withTransaction(ambient) {
            bindable.ambientNilValue.transaction(local).wrappedValue = 1
            events.append("body")
        }
        events.append("returned")

        XCTAssertEqual(model.ambientNilValue, 1)
        XCTAssertEqual(
            recorder.snapshots,
            [.init(isEmpty: false, hasAnimation: false, disablesAnimations: false)]
        )

        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        XCTAssertEqual(
            events,
            [
                "body",
                "returned",
                "local completion",
                "ambient completion",
            ]
        )
    }

    func testLocalBindableTransactionPropagatesToGraphInvalidation() throws {
        let model = BindableTransactionModel()
        let bindable = Bindable(model)

        var local = Transaction(animation: .linear(duration: 0.20))
        local[BindableTransactionGraphKey.self] = 17

        let host = GraphHost()
        try host.data.withCurrent {
            try AGSubgraph.withCurrent(host.data.rootSubgraph) {
                let graph = host.data.graph
                let source = graph.makeInput(value: BindableLocalTransactionRoot(model: model))
                let outputs = BindableLocalTransactionRoot._makeView(
                    view: _GraphValue(_attribute: source),
                    inputs: makeViewInputs(graph: graph)
                )
                let layoutAttr = try XCTUnwrap(outputs._layoutComputer.attribute)
                XCTAssertEqual(
                    layoutAttr.value.sizeThatFits(.unspecified),
                    CGSize(width: 0, height: 12)
                )
                XCTAssertNil(graph.transaction(for: layoutAttr.identifier))

                bindable.localValue.transaction(local).wrappedValue = 24
                host.data.rootSubgraph.update()

                let propagated = try XCTUnwrap(graph.transaction(for: layoutAttr.identifier))
                XCTAssertEqual(propagated[BindableTransactionGraphKey.self], 17)
                XCTAssertNotNil(propagated.animation)
                XCTAssertEqual(propagated.disablesAnimations, false)
                XCTAssertEqual(
                    layoutAttr.value.sizeThatFits(.unspecified),
                    CGSize(width: 24, height: 12)
                )
            }
        }
    }

    func testAmbientTransactionPropagatesToGraphInvalidationWhenBindableLocalIsPresent() throws {
        let model = BindableTransactionModel()
        let bindable = Bindable(model)

        var local = Transaction(animation: nil)
        local.disablesAnimations = true
        local[BindableTransactionGraphKey.self] = 17

        var ambient = Transaction(animation: .linear(duration: 0.20))
        ambient[BindableTransactionGraphKey.self] = 29

        let host = GraphHost()
        try host.data.withCurrent {
            try AGSubgraph.withCurrent(host.data.rootSubgraph) {
                let graph = host.data.graph
                let source = graph.makeInput(value: BindableAmbientTransactionRoot(model: model))
                let outputs = BindableAmbientTransactionRoot._makeView(
                    view: _GraphValue(_attribute: source),
                    inputs: makeViewInputs(graph: graph)
                )
                let layoutAttr = try XCTUnwrap(outputs._layoutComputer.attribute)
                XCTAssertEqual(
                    layoutAttr.value.sizeThatFits(.unspecified),
                    CGSize(width: 0, height: 12)
                )
                XCTAssertNil(graph.transaction(for: layoutAttr.identifier))

                withTransaction(ambient) {
                    bindable.ambientValue.transaction(local).wrappedValue = 24
                }
                host.data.rootSubgraph.update()

                let propagated = try XCTUnwrap(graph.transaction(for: layoutAttr.identifier))
                XCTAssertEqual(propagated[BindableTransactionGraphKey.self], 29)
                XCTAssertNotNil(propagated.animation)
                XCTAssertEqual(propagated.disablesAnimations, false)
                XCTAssertEqual(
                    layoutAttr.value.sizeThatFits(.unspecified),
                    CGSize(width: 24, height: 12)
                )
            }
        }
    }

    private static func snapshot(_ transaction: Transaction) -> BindableTransactionSnapshot {
        BindableTransactionSnapshot(
            isEmpty: transaction.isEmpty,
            hasAnimation: transaction.animation != nil,
            disablesAnimations: transaction.disablesAnimations
        )
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
