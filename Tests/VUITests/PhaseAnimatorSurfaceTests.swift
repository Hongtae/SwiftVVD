import Foundation
import XCTest
@testable import VUI

private struct PhaseSizedView: View, _PrimitiveView {
    var width: CGFloat

    typealias Body = Never

    static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        guard let graph = AttributeGraph.current else {
            fatalError("\(Self.self)._makeView called outside an active AttributeGraph context.")
        }
        let layout = graph.makeRule {
            let value = view._attribute.value
            return LayoutComputer.fixed(CGSize(width: value.width, height: 19))
        }
        return _ViewOutputs(layoutComputer: OptionalAttribute(layout))
    }
}

private struct PhaseAnimatorRelaySource: View, _PrimitiveView {
    typealias Body = Never

    static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        guard let graph = AttributeGraph.current else {
            fatalError("\(Self.self)._makeView called outside an active AttributeGraph context.")
        }
        let layout = graph.makeRule {
            LayoutComputer.fixed(CGSize(width: 31, height: 23))
        }
        return _ViewOutputs(layoutComputer: OptionalAttribute(layout))
    }
}

private struct PhaseAnimatorTransactionWidthKey: TransactionKey {
    static let defaultValue: CGFloat = 0
}

private struct TransactionSizedPhaseView: View, _PrimitiveView {
    typealias Body = Never

    static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        guard let graph = AttributeGraph.current else {
            fatalError("\(Self.self)._makeView called outside an active AttributeGraph context.")
        }
        let transaction = inputs.base.transaction
        let layout = graph.makeRule {
            let width = transaction.value[PhaseAnimatorTransactionWidthKey.self]
            return LayoutComputer.fixed(CGSize(width: width, height: 29))
        }
        return _ViewOutputs(layoutComputer: OptionalAttribute(layout))
    }
}

final class PhaseAnimatorSurfaceTests: XCTestCase {
    func testStorageLabelsMatchObservedShape() {
        let view = PhaseAnimator([1, 2]) { phase in
            PhaseSizedView(width: CGFloat(phase))
        }

        let labels = Mirror(reflecting: view).children.map(\.label)
        XCTAssertEqual(labels, [
            "phases",
            "content",
            "animation",
            "behavior",
            "_currentIndex",
            "_seed",
        ])
    }

    func testInitialPhaseContentBuildsDirectPhaseAnimatorView() throws {
        try withPhaseAnimatorHost { _, graph in
            let view = PhaseAnimator([7, 11]) { phase in
                PhaseSizedView(width: CGFloat(phase))
            }
            let source = graph.makeInput(value: view)
            let outputs = type(of: view)._makeView(
                view: _GraphValue(_attribute: source),
                inputs: makeViewInputs(graph: graph)
            )

            let layout = try XCTUnwrap(outputs._layoutComputer.attribute?.value)
            XCTAssertEqual(layout.sizeThatFits(.unspecified), CGSize(width: 7, height: 19))
        }
    }

    func testChildValueStorageLabelsMatchObservedProjectionShape() {
        typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer

        let value = Container.Child.Value(
            content: PhaseSizedView(width: 1),
            phaseChangeTransaction: Transaction(),
            phaseChangeTransactionSeed: 3
        )

        let labels = Mirror(reflecting: value).children.map(\.label)
        XCTAssertEqual(labels, [
            "content",
            "phaseChangeTransaction",
            "phaseChangeTransactionSeed",
        ])
    }

    func testAnimationCompletionStorageLabelsMatchObservedShape() {
        typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer

        let completion = Container.AnimationCompletion(seed: 2, didAnimate: true)

        let labels = Mirror(reflecting: completion).children.map(\.label)
        XCTAssertEqual(labels, [
            "seed",
            "didAnimate",
        ])
    }

    func testCompletionListenerStorageLabelsMatchObservedShape() {
        typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer

        let listener = Container.CompletionListener { _ in }

        let labels = Mirror(reflecting: listener).children.map(\.label)
        XCTAssertEqual(labels, [
            "action",
            "count",
            "didAnimate",
            "didFireAction",
        ])
    }

    func testCompletionListenerFallbackSkipsAfterAnimationWasAdded() {
        typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
        var completions: [Bool] = []
        let listener = Container.CompletionListener { didAnimate in
            completions.append(didAnimate)
        }

        listener.animationWasAdded()
        listener.fireNoAnimationFallback()

        XCTAssertEqual(completions, [])

        listener.animationWasRemoved().forEach { $0() }

        XCTAssertEqual(completions, [true])
        XCTAssertEqual(listener.animationWasRemoved().count, 0)
    }

    func testChildStorageLabelsMatchObservedShape() {
        withPhaseAnimatorHost { viewGraph, graph in
            let container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer(
                phases: [0],
                content: { PhaseSizedView(width: CGFloat($0)) },
                animation: { _ in nil },
                behavior: .repeating
            )
            let child = makeChild(
                in: graph,
                viewGraph: viewGraph,
                container: container
            )

            let labels = Mirror(reflecting: child).children.map(\.label)
            XCTAssertEqual(labels, [
                "_view",
                "_transaction",
                "_transactionSeed",
                "_phase",
                "_animationCompletion",
                "_isVisible",
                "currentIndex",
                "completionSeed",
                "resetSeed",
                "endlessLoopState",
                "lastBehavior",
                "phaseChangeTransaction",
                "phaseChangeTransactionSeed",
            ])
        }
    }

    func testInitialTransactionPassesThroughChildTransactionRule() throws {
        try withPhaseAnimatorHost { _, graph in
            let view = PhaseAnimator([0]) { _ in
                TransactionSizedPhaseView()
            }
            var transaction = Transaction()
            transaction[PhaseAnimatorTransactionWidthKey.self] = 43

            let source = graph.makeInput(value: view)
            let outputs = type(of: view)._makeView(
                view: _GraphValue(_attribute: source),
                inputs: makeViewInputs(graph: graph, transaction: transaction)
            )

            let layout = try XCTUnwrap(outputs._layoutComputer.attribute?.value)
            XCTAssertEqual(layout.sizeThatFits(.unspecified), CGSize(width: 43, height: 29))
        }
    }

    func testChildAdvanceFromWrapsWithinPhaseBounds() {
        withPhaseAnimatorHost { viewGraph, graph in
            let container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer(
                phases: [0, 1, 2],
                content: { PhaseSizedView(width: CGFloat($0)) },
                animation: { _ in nil },
                behavior: .repeating
            )
            viewGraph.data.transactionSeed = 5
            var child = makeChild(
                in: graph,
                viewGraph: viewGraph,
                container: container
            )

            child.advance(from: 2)

            XCTAssertEqual(child.currentIndex, 0)
            XCTAssertEqual(child.completionSeed, 1)
            XCTAssertEqual(child.phaseChangeTransactionSeed, 5)
        }
    }

    func testChildAdvanceFromRequiresAtLeastTwoPhases() {
        withPhaseAnimatorHost { viewGraph, graph in
            let container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer(
                phases: [0],
                content: { PhaseSizedView(width: CGFloat($0)) },
                animation: { _ in nil },
                behavior: .repeating
            )
            var child = makeChild(
                in: graph,
                viewGraph: viewGraph,
                container: container
            )

            child.advance(from: 0)

            XCTAssertEqual(child.currentIndex, 0)
            XCTAssertEqual(child.completionSeed, 0)
        }
    }

    func testChildAdvanceToOutOfBoundsFallsBackToAdvanceFrom() {
        withPhaseAnimatorHost { viewGraph, graph in
            let container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer(
                phases: [0, 1, 2],
                content: { PhaseSizedView(width: CGFloat($0)) },
                animation: { _ in nil },
                behavior: .repeating
            )
            var child = makeChild(
                in: graph,
                viewGraph: viewGraph,
                container: container
            )

            child.advance(to: 3)

            XCTAssertEqual(child.currentIndex, 0)
            XCTAssertEqual(child.completionSeed, 1)
        }
    }

    func testChildAdvanceToMatchingActiveLoopTargetClearsLoopState() {
        withPhaseAnimatorHost { viewGraph, graph in
            let container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer(
                phases: [0, 1, 2],
                content: { PhaseSizedView(width: CGFloat($0)) },
                animation: { _ in nil },
                behavior: .repeating
            )
            var child = makeChild(
                in: graph,
                viewGraph: viewGraph,
                container: container
            )
            child.currentIndex = 2
            child.completionSeed = 4
            child.endlessLoopState = .active(1)

            child.advance(to: 1)

            XCTAssertEqual(child.currentIndex, 0)
            XCTAssertEqual(child.completionSeed, 4)
            XCTAssertEqual(child.endlessLoopState, .empty)
        }
    }

    func testChildAdvanceToDifferentActiveLoopTargetContinuesAdvancePath() {
        withPhaseAnimatorHost { viewGraph, graph in
            let container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer(
                phases: [0, 1, 2],
                content: { PhaseSizedView(width: CGFloat($0)) },
                animation: { _ in nil },
                behavior: .repeating
            )
            var child = makeChild(
                in: graph,
                viewGraph: viewGraph,
                container: container
            )
            child.currentIndex = 0
            child.completionSeed = 4
            child.endlessLoopState = .active(2)

            child.advance(to: 1)

            XCTAssertEqual(child.currentIndex, 1)
            XCTAssertEqual(child.completionSeed, 5)
            XCTAssertEqual(child.endlessLoopState, .active(2))
        }
    }

    func testChildAdvanceToAnimatedPhaseRegistersLogicalCompletionListener() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            let container = Container(
                phases: [0, 1],
                content: { PhaseSizedView(width: CGFloat($0)) },
                animation: { _ in .linear(duration: 0.25) },
                behavior: .repeating
            )
            let source = graph.makeInput(value: container)
            let transaction = graph.makeInput(value: Transaction())
            let phase = graph.makeInput(value: Phase())
            let completion = graph.makeInput(
                value: Optional<Container.AnimationCompletion>.none
            )
            let isVisible = graph.makeInput(value: true)
            viewGraph.data.transactionSeed = 11
            var child = Container.Child(
                view: source,
                transaction: transaction,
                transactionSeed: viewGraph.data.transactionSeedAttribute,
                phase: phase,
                animationCompletion: completion,
                isVisible: isVisible
            )

            child.advance(to: 1)

            XCTAssertEqual(child.currentIndex, 1)
            XCTAssertEqual(child.completionSeed, 1)
            XCTAssertEqual(child.phaseChangeTransactionSeed, 11)
            XCTAssertNotNil(child.phaseChangeTransaction.animation)
            XCTAssertTrue(
                child.phaseChangeTransaction.animationLogicalListener is Container.CompletionListener
            )
            XCTAssertNil(completion.value)
            XCTAssertTrue(viewGraph.hasPendingTransactions)

            viewGraph.flushTransactions()

            XCTAssertEqual(completion.value?.seed, 1)
            XCTAssertEqual(completion.value?.didAnimate, false)
        }
    }

    func testChildAnimatedCompletionListenerPublishesAnimatedCompletion() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            let container = Container(
                phases: [0, 1],
                content: { PhaseSizedView(width: CGFloat($0)) },
                animation: { _ in .linear(duration: 0.25) },
                behavior: .repeating
            )
            let source = graph.makeInput(value: container)
            let transaction = graph.makeInput(value: Transaction())
            let phase = graph.makeInput(value: Phase())
            let completion = graph.makeInput(
                value: Optional<Container.AnimationCompletion>.none
            )
            let isVisible = graph.makeInput(value: true)
            var child = Container.Child(
                view: source,
                transaction: transaction,
                transactionSeed: viewGraph.data.transactionSeedAttribute,
                phase: phase,
                animationCompletion: completion,
                isVisible: isVisible
            )

            Update.begin()
            child.advance(to: 1)
            let listener = child.phaseChangeTransaction.animationLogicalListener
                as? Container.CompletionListener
            listener?.animationWasAdded()
            Update.end()

            XCTAssertFalse(viewGraph.hasPendingTransactions)

            let actions = listener?.animationWasRemoved() ?? []
            actions.forEach { $0() }

            XCTAssertTrue(viewGraph.hasPendingTransactions)
            XCTAssertNil(completion.value)

            viewGraph.flushTransactions()

            XCTAssertEqual(completion.value?.seed, 1)
            XCTAssertEqual(completion.value?.didAnimate, true)
        }
    }

    func testChildUpdatePublishesClampedIndexContent() {
        withPhaseAnimatorHost { viewGraph, graph in
            let container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer(
                phases: [0, 1, 2],
                content: { PhaseSizedView(width: CGFloat($0)) },
                animation: { _ in nil },
                behavior: .repeating
            )
            var child = makeChild(
                in: graph,
                viewGraph: viewGraph,
                container: container
            )
            child.currentIndex = 2
            child.endlessLoopState = .active(2)
            let childValue = graph.makeStatefulRule(child)

            XCTAssertEqual(childValue.value.content.width, 0)
        }
    }

    func testChildUpdateDoesNotTreatAbsentCompletionAsFalseCompletion() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            let container = Container(
                phases: [0, 1],
                content: { PhaseSizedView(width: CGFloat($0)) },
                animation: { _ in nil },
                behavior: .repeating
            )
            let source = graph.makeInput(value: container)
            let transaction = graph.makeInput(value: Transaction())
            let phase = graph.makeInput(value: Phase())
            let completion = graph.makeInput(
                value: Optional<Container.AnimationCompletion>.none
            )
            let isVisible = graph.makeInput(value: true)
            let childValue = graph.makeStatefulRule(
                Container.Child(
                    view: source,
                    transaction: transaction,
                    transactionSeed: viewGraph.data.transactionSeedAttribute,
                    phase: phase,
                    animationCompletion: completion,
                    isVisible: isVisible
                )
            )

            XCTAssertEqual(childValue.value.content.width, 0)
            XCTAssertEqual(childValue.value.content.width, 0)
            XCTAssertNil(childValue.value.phaseChangeTransactionSeed)
        }
    }

    func testChildUpdateConsumesNonAnimatedCompletionThroughEndlessLoopBranch() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            let container = Container(
                phases: [0, 1],
                content: { PhaseSizedView(width: CGFloat($0)) },
                animation: { _ in nil },
                behavior: .repeating
            )
            let source = graph.makeInput(value: container)
            let transaction = graph.makeInput(value: Transaction())
            let phase = graph.makeInput(value: Phase())
            let completion = graph.makeInput(
                value: Optional<Container.AnimationCompletion>.none
            )
            let isVisible = graph.makeInput(value: true)
            viewGraph.data.transactionSeed = 23
            let childValue = graph.makeStatefulRule(
                Container.Child(
                    view: source,
                    transaction: transaction,
                    transactionSeed: viewGraph.data.transactionSeedAttribute,
                    phase: phase,
                    animationCompletion: completion,
                    isVisible: isVisible
                )
            )

            XCTAssertEqual(childValue.value.content.width, 0)

            completion.setValue(.some(Container.AnimationCompletion(seed: 0, didAnimate: false)))
            let advanced = childValue.value

            XCTAssertEqual(advanced.content.width, 0)
            XCTAssertEqual(advanced.phaseChangeTransactionSeed, 23)
            XCTAssertNil(advanced.phaseChangeTransaction.animation)
            XCTAssertTrue(viewGraph.hasPendingTransactions)

            viewGraph.flushTransactions()

            XCTAssertEqual(completion.value?.seed, 1)
            XCTAssertEqual(completion.value?.didAnimate, false)
        }
    }

    func testChildUpdateSkipsNonAnimatedEventDrivenCompletionAtZeroIndex() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            let container = Container(
                phases: [0, 1],
                content: { PhaseSizedView(width: CGFloat($0)) },
                animation: { _ in nil },
                behavior: .eventDriven(trigger: AnyEquatable(1))
            )
            let source = graph.makeInput(value: container)
            let transaction = graph.makeInput(value: Transaction())
            let phase = graph.makeInput(value: Phase())
            let completion = graph.makeInput(
                value: Optional<Container.AnimationCompletion>.none
            )
            let isVisible = graph.makeInput(value: true)
            let childValue = graph.makeStatefulRule(
                Container.Child(
                    view: source,
                    transaction: transaction,
                    transactionSeed: viewGraph.data.transactionSeedAttribute,
                    phase: phase,
                    animationCompletion: completion,
                    isVisible: isVisible
                )
            )

            XCTAssertEqual(childValue.value.content.width, 0)

            completion.setValue(.some(Container.AnimationCompletion(seed: 0, didAnimate: false)))
            let unchanged = childValue.value

            XCTAssertEqual(unchanged.content.width, 0)
            XCTAssertNil(unchanged.phaseChangeTransactionSeed)
            XCTAssertFalse(viewGraph.hasPendingTransactions)
        }
    }

    func testChildUpdateConsumesAnimatedCompletionByAdvancingRepeatingPhase() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            let container = Container(
                phases: [0, 1, 2],
                content: { PhaseSizedView(width: CGFloat($0)) },
                animation: { _ in .linear(duration: 0.25) },
                behavior: .repeating
            )
            let source = graph.makeInput(value: container)
            let transaction = graph.makeInput(value: Transaction())
            let phase = graph.makeInput(value: Phase())
            let completion = graph.makeInput(
                value: Optional<Container.AnimationCompletion>.none
            )
            let isVisible = graph.makeInput(value: true)
            viewGraph.data.transactionSeed = 17
            let childValue = graph.makeStatefulRule(
                Container.Child(
                    view: source,
                    transaction: transaction,
                    transactionSeed: viewGraph.data.transactionSeedAttribute,
                    phase: phase,
                    animationCompletion: completion,
                    isVisible: isVisible
                )
            )

            XCTAssertEqual(childValue.value.content.width, 0)

            completion.setValue(.some(Container.AnimationCompletion(seed: 0, didAnimate: true)))
            let advanced = childValue.value

            XCTAssertEqual(advanced.content.width, 1)
            XCTAssertEqual(advanced.phaseChangeTransactionSeed, 17)
            XCTAssertNotNil(advanced.phaseChangeTransaction.animation)
        }
    }

    func testChildUpdateConsumesAnimatedCompletionByAdvancingEventDrivenPhase() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            let container = Container(
                phases: [0, 1, 2],
                content: { PhaseSizedView(width: CGFloat($0)) },
                animation: { _ in .linear(duration: 0.25) },
                behavior: .eventDriven(trigger: AnyEquatable(1))
            )
            let source = graph.makeInput(value: container)
            let transaction = graph.makeInput(value: Transaction())
            let phase = graph.makeInput(value: Phase())
            let completion = graph.makeInput(
                value: Optional<Container.AnimationCompletion>.none
            )
            let isVisible = graph.makeInput(value: true)
            viewGraph.data.transactionSeed = 19
            let childValue = graph.makeStatefulRule(
                Container.Child(
                    view: source,
                    transaction: transaction,
                    transactionSeed: viewGraph.data.transactionSeedAttribute,
                    phase: phase,
                    animationCompletion: completion,
                    isVisible: isVisible
                )
            )

            XCTAssertEqual(childValue.value.content.width, 0)

            completion.setValue(.some(Container.AnimationCompletion(seed: 0, didAnimate: true)))
            let advanced = childValue.value

            XCTAssertEqual(advanced.content.width, 1)
            XCTAssertEqual(advanced.phaseChangeTransactionSeed, 19)
            XCTAssertNotNil(advanced.phaseChangeTransaction.animation)
        }
    }

    func testChildUpdateDoesNotConsumeCompletionWhileInvisible() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            let container = Container(
                phases: [0, 1],
                content: { PhaseSizedView(width: CGFloat($0)) },
                animation: { _ in .linear(duration: 0.25) },
                behavior: .repeating
            )
            let source = graph.makeInput(value: container)
            let transaction = graph.makeInput(value: Transaction())
            let phase = graph.makeInput(value: Phase())
            let completion = graph.makeInput(
                value: Optional<Container.AnimationCompletion>.none
            )
            let isVisible = graph.makeInput(value: false)
            let childValue = graph.makeStatefulRule(
                Container.Child(
                    view: source,
                    transaction: transaction,
                    transactionSeed: viewGraph.data.transactionSeedAttribute,
                    phase: phase,
                    animationCompletion: completion,
                    isVisible: isVisible
                )
            )

            XCTAssertEqual(childValue.value.content.width, 0)

            completion.setValue(.some(Container.AnimationCompletion(seed: 0, didAnimate: true)))
            let unchanged = childValue.value

            XCTAssertEqual(unchanged.content.width, 0)
            XCTAssertNil(unchanged.phaseChangeTransactionSeed)
        }
    }

    func testAppearanceHandlerQueuesVisibleAssignmentThroughAsyncTransaction() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            let isVisible = graph.makeInput(value: false)
            let appear = Container.appearanceHandler(isVisible: isVisible, value: true)

            appear()

            XCTAssertTrue(viewGraph.hasPendingTransactions)
            XCTAssertFalse(isVisible.value)

            viewGraph.flushTransactions()

            XCTAssertTrue(isVisible.value)
            XCTAssertFalse(viewGraph.hasPendingTransactions)
            XCTAssertEqual(viewGraph.data.transactionSeed, 1)
        }
    }

    func testStateTransitioningContainerMakeViewQueuesAppearanceHandler() throws {
        try withPhaseAnimatorHost { viewGraph, graph in
            let view = PhaseAnimator([7]) { phase in
                PhaseSizedView(width: CGFloat(phase))
            }
            let source = graph.makeInput(value: view)
            let outputs = type(of: view)._makeView(
                view: _GraphValue(_attribute: source),
                inputs: makeViewInputs(graph: graph)
            )

            let layout = try XCTUnwrap(outputs._layoutComputer.attribute?.value)
            XCTAssertEqual(layout.sizeThatFits(.unspecified), CGSize(width: 7, height: 19))
            XCTAssertTrue(viewGraph.hasPendingTransactions)
        }
    }

    func testTransactionRuleSelectsPhaseChangeTransactionWhenSeedMatches() {
        let graph = AttributeGraph()
        let ref = AttributeGraphRef(graph: graph)

        ref.withCurrent {
            var baseTransaction = Transaction()
            baseTransaction[PhaseAnimatorTransactionWidthKey.self] = 13
            var phaseTransaction = Transaction()
            phaseTransaction[PhaseAnimatorTransactionWidthKey.self] = 89

            let transaction = graph.makeInput(value: baseTransaction)
            let transactionSeed = graph.makeInput(value: UInt32(7))
            let phaseChangeTransaction = graph.makeInput(value: phaseTransaction)
            let phaseChangeTransactionSeed = graph.makeInput(value: Optional<UInt32>.some(7))
            let selected = graph.makeStatefulRule(
                PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer.TransactionRule(
                    transaction: transaction,
                    transactionSeed: transactionSeed,
                    phaseChangeTransaction: phaseChangeTransaction,
                    phaseChangeTransactionSeed: phaseChangeTransactionSeed
                )
            )

            XCTAssertEqual(selected.value[PhaseAnimatorTransactionWidthKey.self], 89)

            phaseChangeTransactionSeed.setValue(8)

            XCTAssertEqual(selected.value[PhaseAnimatorTransactionWidthKey.self], 13)
        }
    }

    func testTransactionRuleStorageLabelsMatchObservedShape() {
        let graph = AttributeGraph()
        let ref = AttributeGraphRef(graph: graph)

        ref.withCurrent {
            let rule = PhaseAnimator<Int, PhaseSizedView>
                .StateTransitioningContainer
                .TransactionRule(
                    transaction: graph.makeInput(value: Transaction()),
                    transactionSeed: graph.makeInput(value: UInt32.zero),
                    phaseChangeTransaction: graph.makeInput(value: Transaction()),
                    phaseChangeTransactionSeed: graph.makeInput(value: Optional<UInt32>.none)
                )

            let labels = Mirror(reflecting: rule).children.map(\.label)
            XCTAssertEqual(labels, [
                "_transaction",
                "_transactionSeed",
                "_phaseChangeTransaction",
                "_phaseChangeTransactionSeed",
            ])
        }
    }

    func testViewPhaseAnimatorRelaysPlaceholderContent() throws {
        try withPhaseAnimatorHost { _, graph in
            let view = PhaseAnimatorRelaySource().phaseAnimator([0]) { placeholder, _ in
                placeholder
            }
            let source = graph.makeInput(value: view)
            let outputs = type(of: view)._makeView(
                view: _GraphValue(_attribute: source),
                inputs: makeViewInputs(graph: graph)
            )

            let layout = try XCTUnwrap(outputs._layoutComputer.attribute?.value)
            XCTAssertEqual(layout.sizeThatFits(.unspecified), CGSize(width: 31, height: 23))
        }
    }

    private func makeViewInputs(graph: AttributeGraph, transaction: Transaction = Transaction()) -> _ViewInputs {
        let environment = graph.makeInput(value: EnvironmentValues())
        let base = _GraphInputs(
            customInputs: PropertyList(),
            time: graph.makeInput(value: Time(seconds: 0)),
            cachedEnvironment: MutableBox(CachedEnvironment(environment: environment)),
            phase: graph.makeInput(value: Phase()),
            transaction: graph.makeInput(value: transaction),
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

    private func withPhaseAnimatorHost(
        _ body: (ViewGraph, AttributeGraph) throws -> Void
    ) rethrows {
        let rendererHost = TestViewRendererHost()
        let viewGraph = ViewGraph(
            rootViewType: EmptyView.self,
            content: EmptyView(),
            rendererHost: rendererHost,
            requestedOutputs: []
        )
        rendererHost.storage = viewGraph
        try viewGraph.data.withCurrent {
            try body(viewGraph, viewGraph.data.graph)
        }
    }

    private func makeChild(
        in graph: AttributeGraph,
        viewGraph: ViewGraph,
        container: PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
    ) -> PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer.Child {
        let source = graph.makeInput(value: container)
        let transaction = graph.makeInput(value: Transaction())
        let phase = graph.makeInput(value: Phase())
        let completion = graph.makeInput(
            value: Optional<PhaseAnimator<Int, PhaseSizedView>
                .StateTransitioningContainer
                .AnimationCompletion>.none
        )
        let isVisible = graph.makeInput(value: true)
        return PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer.Child(
            view: source,
            transaction: transaction,
            transactionSeed: viewGraph.data.transactionSeedAttribute,
            phase: phase,
            animationCompletion: completion,
            isVisible: isVisible
        )
    }
}
