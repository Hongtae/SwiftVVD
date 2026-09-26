import Foundation
import XCTest
@testable import VUI

final class StateMacroTests: XCTestCase {
    func testPrivateExpressionBackedStateDefersInitializationUntilMount() {
        stateMacroInitializationCounter.reset()

        let first = ExpressionBackedStateView()
        let second = ExpressionBackedStateView()
        let third = ExpressionBackedStateView()
        withExtendedLifetime((first, second, third)) {}

        XCTAssertEqual(stateMacroInitializationCounter.value, 0)
    }

    func testInitialValueArgumentDefersInitializationUntilMount() {
        stateMacroArgumentCounter.reset()

        let first = ArgumentBackedStateView()
        let second = ArgumentBackedStateView()
        withExtendedLifetime((first, second)) {}

        XCTAssertEqual(stateMacroArgumentCounter.value, 0)
    }

    func testExplicitInitializerKeepsPerConstructionCandidateEvaluation() {
        explicitStateInitializationCounter.reset()

        let first = ExplicitlyInitializedStateView()
        let second = ExplicitlyInitializedStateView()
        let third = ExplicitlyInitializedStateView()
        withExtendedLifetime((first, second, third)) {}

        XCTAssertEqual(explicitStateInitializationCounter.value, 3)
    }

    func testClassAndNonPrivateSourceCompatibilityFormsCompile() {
        let owner = ClassStateSyntaxProbe()
        let view = NonPrivateStateSyntaxProbe()

        XCTAssertEqual(owner.read(), 1)
        XCTAssertEqual(view.value, 1)
        XCTAssertEqual(view.$value.wrappedValue, 1)
    }

    func testStateDeclarationShapeDiagnosticsMatchSampledCompiler() throws {
        #if os(macOS)
        let letOutput = try runMacroDiagnosticProbe(
            named: "state-let",
            source: """
            import VUI

            struct LetStateProbe {
                @State private let value = 1
            }
            """
        )
        XCTAssertTrue(
            letOutput.contains("error: '@State' can only be applied to a 'var' declaration"),
            letOutput
        )
        XCTAssertTrue(letOutput.contains("note: Replace 'let' with 'var'"), letOutput)

        let multiOutput = try runMacroDiagnosticProbe(
            named: "state-multi-binding",
            source: """
            import VUI

            struct MultiStateProbe {
                @State private var first = 1, second = 2
            }
            """
        )
        XCTAssertTrue(
            multiOutput.contains("error: '@State' can only be applied to a 'var' declaration with a simple name"),
            multiOutput
        )

        let computedOutput = try runMacroDiagnosticProbe(
            named: "state-computed",
            source: """
            import VUI

            struct ComputedStateProbe {
                @State private var value: Int { 1 }
            }
            """
        )
        XCTAssertTrue(
            computedOutput.contains("error: variable already has a getter"),
            computedOutput
        )
        #endif
    }

    func testLazyStateUnmountedStorageRetainsThunkSemantics() {
        var calls = 0
        let lazy = LazyState<Int>(initialValue: {
            calls += 1
            return 40 + calls
        })

        guard case .thunk = lazy._storage else {
            return XCTFail("expected thunk storage")
        }
        XCTAssertNil(lazy._location)
        XCTAssertEqual(lazy.wrappedValue, 41)
        XCTAssertEqual(lazy.wrappedValue, 42)
        lazy.wrappedValue = 99
        XCTAssertEqual(lazy.wrappedValue, 43)

        let eager = LazyState<Int>(_initialValue: 7)
        guard case .value(let value) = eager._storage else {
            return XCTFail("expected eager value storage")
        }
        XCTAssertEqual(value, 7)
        XCTAssertNil(eager._location)
        XCTAssertEqual(eager.wrappedValue, 7)
        XCTAssertEqual(State<Int>._propertyStorageSize, 16)
        XCTAssertEqual(LazyState<Int>._propertyStorageSize, 16)
    }

    func testMountedLazyStateRetainsValueAndProjectedBindingAcrossReconstruction()
        throws {
        mountedStateInitializationCounter.reset()
        let capture = MountedStateCapture()
        let host = GraphHost()

        try host.data.withCurrent {
            try AGSubgraph.withCurrent(host.data.rootSubgraph) {
                let graph = host.data.graph
                let source = graph.makeInput(
                    value: MountedStateRoot(revision: 0, capture: capture)
                )
                let outputs = MountedStateRoot._makeView(
                    view: _GraphValue(_attribute: source),
                    inputs: makeStateMacroViewInputs(graph: graph)
                )
                let layout = try XCTUnwrap(outputs._layoutComputer.attribute)

                XCTAssertEqual(
                    layout.value.sizeThatFits(.unspecified),
                    CGSize(width: 100, height: 10)
                )
                XCTAssertEqual(mountedStateInitializationCounter.value, 1)
                XCTAssertEqual(capture.modelIDs, [1])
                XCTAssertEqual(capture.localValues, [0])

                source.setValue(MountedStateRoot(revision: 1, capture: capture))
                host.data.rootSubgraph.update()
                XCTAssertEqual(
                    layout.value.sizeThatFits(.unspecified),
                    CGSize(width: 101, height: 10)
                )
                XCTAssertEqual(mountedStateInitializationCounter.value, 1)
                XCTAssertEqual(capture.modelIDs.last, 1)

                let binding = try XCTUnwrap(capture.binding)
                binding.wrappedValue += 1
                host.flushTransactions()
                host.data.rootSubgraph.update()
                XCTAssertEqual(
                    layout.value.sizeThatFits(.unspecified),
                    CGSize(width: 111, height: 10)
                )
                XCTAssertEqual(capture.localValues.last, 1)

                source.setValue(MountedStateRoot(revision: 2, capture: capture))
                host.data.rootSubgraph.update()
                XCTAssertEqual(
                    layout.value.sizeThatFits(.unspecified),
                    CGSize(width: 112, height: 10)
                )
                XCTAssertEqual(mountedStateInitializationCounter.value, 1)
                XCTAssertEqual(capture.modelIDs.last, 1)
                XCTAssertEqual(capture.localValues.last, 1)
            }
        }
    }

    func testExplicitIDReplacementStartsNewLazyStateLifetime() throws {
        identityStateInitializationCounter.reset()
        let capture = IdentityStateCapture()
        let host = GraphHost()

        try host.data.withCurrent {
            try AGSubgraph.withCurrent(host.data.rootSubgraph) {
                let graph = host.data.graph
                let source = graph.makeInput(
                    value: IdentityStateRoot(
                        identity: 0,
                        revision: 0,
                        capture: capture
                    )
                )
                let outputs = IdentityStateRoot._makeView(
                    view: _GraphValue(_attribute: source),
                    inputs: makeStateMacroViewInputs(graph: graph)
                )
                let layout = try XCTUnwrap(outputs._layoutComputer.attribute)
                _ = layout.value

                XCTAssertEqual(identityStateInitializationCounter.value, 1)
                XCTAssertEqual(capture.modelIDs.last, 1)

                source.setValue(IdentityStateRoot(
                    identity: 0,
                    revision: 1,
                    capture: capture
                ))
                host.data.rootSubgraph.update()
                _ = layout.value
                XCTAssertEqual(identityStateInitializationCounter.value, 1)
                XCTAssertEqual(capture.modelIDs.last, 1)

                capture.binding?.wrappedValue = 3
                host.flushTransactions()
                host.data.rootSubgraph.update()
                _ = layout.value
                XCTAssertEqual(capture.localValues.last, 3)

                source.setValue(IdentityStateRoot(
                    identity: 1,
                    revision: 2,
                    capture: capture
                ))
                host.data.rootSubgraph.update()
                _ = layout.value

                XCTAssertEqual(identityStateInitializationCounter.value, 2)
                XCTAssertEqual(capture.modelIDs.last, 2)
                XCTAssertEqual(capture.localValues.last, 0)
            }
        }
    }
}

private let stateMacroInitializationCounter = StateMacroInitializationCounter()

private final class StateMacroInitializationCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.withLock { count }
    }

    func reset() {
        lock.withLock { count = 0 }
    }

    func increment() {
        lock.withLock { count += 1 }
    }

    func next() -> Int {
        lock.withLock {
            count += 1
            return count
        }
    }
}

private final class ExpressionBackedStateModel {
    init() {
        stateMacroInitializationCounter.increment()
    }
}

private struct ExpressionBackedStateView: View {
    @State private var model = ExpressionBackedStateModel()

    var body: some View {
        EmptyView()
    }
}

private let stateMacroArgumentCounter = StateMacroInitializationCounter()

private final class ArgumentBackedStateModel {
    init() {
        stateMacroArgumentCounter.increment()
    }
}

private struct ArgumentBackedStateView: View {
    @State(initialValue: ArgumentBackedStateModel())
    private var model: ArgumentBackedStateModel

    var body: some View {
        EmptyView()
    }
}

private final class ClassStateSyntaxProbe {
    @State private var value = 1

    func read() -> Int {
        value
    }
}

private struct NonPrivateStateSyntaxProbe: View {
    @State var value = 1

    var body: some View {
        EmptyView()
    }
}

private let explicitStateInitializationCounter = StateMacroInitializationCounter()

private final class ExplicitlyInitializedStateModel {
    init() {
        explicitStateInitializationCounter.increment()
    }
}

private struct ExplicitlyInitializedStateView: View {
    @State private var model: ExplicitlyInitializedStateModel

    init() {
        self.model = ExplicitlyInitializedStateModel()
    }

    var body: some View {
        EmptyView()
    }
}

private final class MountedStateCapture {
    var modelIDs: [Int] = []
    var localValues: [Int] = []
    var binding: Binding<Int>?
}

private let mountedStateInitializationCounter = StateMacroInitializationCounter()

private final class MountedStateModel {
    let id = mountedStateInitializationCounter.next()
}

private struct MountedStateRoot: View {
    var revision: Int
    let capture: MountedStateCapture
    @State private var model = MountedStateModel()
    @State private var local = 0

    var body: MountedStateLeaf {
        capture.modelIDs.append(model.id)
        capture.localValues.append(local)
        capture.binding = $local
        return MountedStateLeaf(
            modelID: model.id,
            local: local,
            revision: revision
        )
    }
}

private struct MountedStateLeaf: View, TestPrimitiveView {
    let modelID: Int
    let local: Int
    let revision: Int

    typealias Body = Never

    static func _makeView(
        view: _GraphValue<Self>,
        inputs: _ViewInputs
    ) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("MountedStateLeaf requires an active graph.")
        }
        let layout = graph.makeRule {
            let value = view._attribute.value
            return LayoutComputer.fixed(CGSize(
                width: CGFloat(value.modelID * 100 + value.local * 10 + value.revision),
                height: 10
            ))
        }
        return _ViewOutputs(layoutComputer: OptionalAttribute(layout))
    }
}

private final class IdentityStateCapture {
    var modelIDs: [Int] = []
    var localValues: [Int] = []
    var binding: Binding<Int>?
}

private let identityStateInitializationCounter = StateMacroInitializationCounter()

private final class IdentityStateModel {
    let id = identityStateInitializationCounter.next()
}

private struct IdentityStateRoot: View {
    let identity: Int
    let revision: Int
    let capture: IdentityStateCapture

    var body: some View {
        IdentityStateChild(revision: revision, capture: capture)
            .id(identity)
    }
}

private struct IdentityStateChild: View {
    let revision: Int
    let capture: IdentityStateCapture
    @State private var model = IdentityStateModel()
    @State private var local = 0

    var body: MountedStateLeaf {
        capture.modelIDs.append(model.id)
        capture.localValues.append(local)
        capture.binding = $local
        return MountedStateLeaf(
            modelID: model.id,
            local: local,
            revision: revision
        )
    }
}

private func makeStateMacroViewInputs(graph: _AGGraph) -> _ViewInputs {
    let environment = graph.makeInput(value: EnvironmentValues())
    let base = _GraphInputs(
        time: graph.makeInput(value: Time(seconds: 0)),
        phase: graph.makeInput(value: _GraphInputs.Phase()),
        environment: environment,
        transaction: graph.makeInput(value: Transaction())
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
        size: graph.makeInput(value: ViewSize(.zero)),
        safeAreaInsets: OptionalAttribute(),
        containerSize: OptionalAttribute(),
        stackOrientation: nil
    )
}
