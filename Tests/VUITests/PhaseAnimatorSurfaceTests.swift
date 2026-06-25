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
            let storageTypes = Dictionary(uniqueKeysWithValues: Mirror(reflecting: child).children.compactMap {
                child -> (String, String)? in
                guard let label = child.label else { return nil }
                return (label, Self.typeDescription(of: child.value))
            })
            XCTAssertTrue(
                storageTypes["_animationCompletion"]?.contains("WeakAttribute<Swift.Optional<") == true,
                "\(storageTypes)"
            )
            XCTAssertTrue(
                storageTypes["_isVisible"]?.contains("WeakAttribute<Swift.Bool>") == true,
                "\(storageTypes)"
            )
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

    func testChildAdvanceToMatchingMonitoringLoopTargetPausesLoopState() {
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
            child.endlessLoopState = .monitoring(firstNonAnimatedPhaseIndex: 1)

            child.advance(to: 1)

            XCTAssertEqual(child.currentIndex, 0)
            XCTAssertEqual(child.completionSeed, 4)
            XCTAssertEqual(child.endlessLoopState, .paused)
        }
    }

    func testChildAdvanceToDifferentMonitoringLoopTargetContinuesAdvancePath() {
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
            child.endlessLoopState = .monitoring(firstNonAnimatedPhaseIndex: 2)

            child.advance(to: 1)

            XCTAssertEqual(child.currentIndex, 1)
            XCTAssertEqual(child.completionSeed, 5)
            XCTAssertEqual(child.endlessLoopState, .monitoring(firstNonAnimatedPhaseIndex: 2))
        }
    }

    func testChildAdvanceToPausedLoopStateReturnsWithoutMutation() {
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
            child.endlessLoopState = .paused

            child.advance(to: 1)

            XCTAssertEqual(child.currentIndex, 2)
            XCTAssertEqual(child.completionSeed, 4)
            XCTAssertEqual(child.endlessLoopState, .paused)
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
                animationCompletion: completion.asWeak(),
                isVisible: isVisible.asWeak()
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
                animationCompletion: completion.asWeak(),
                isVisible: isVisible.asWeak()
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
            child.endlessLoopState = .monitoring(firstNonAnimatedPhaseIndex: 2)
            let childValue = graph.makeStatefulRule(child)

            XCTAssertEqual(childValue.value.content.width, 0)
        }
    }

    func testChildUpdateClampsOutOfRangeAnimatingIndexToLastPhase() {
        withPhaseAnimatorHost { viewGraph, graph in
            let container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer(
                phases: [0, 1, 2],
                content: { PhaseSizedView(width: CGFloat($0)) },
                animation: { _ in nil },
                behavior: .eventDriven(trigger: AnyEquatable(1))
            )
            var child = makeChild(
                in: graph,
                viewGraph: viewGraph,
                container: container
            )
            child.currentIndex = 99
            child.lastBehavior = container.behavior

            let childValue = graph.makeStatefulRule(child)

            XCTAssertEqual(childValue.value.content.width, 2)
        }
    }

    func testChildUpdateDoesNotTreatAbsentCompletionAsFalseCompletion() {
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
            var child = Container.Child(
                view: source,
                transaction: transaction,
                transactionSeed: viewGraph.data.transactionSeedAttribute,
                phase: phase,
                animationCompletion: completion.asWeak(),
                isVisible: isVisible.asWeak()
            )
            child.lastBehavior = container.behavior
            let childValue = graph.makeStatefulRule(
                child
            )

            XCTAssertEqual(childValue.value.content.width, 0)
            XCTAssertEqual(childValue.value.content.width, 0)
            XCTAssertNil(childValue.value.phaseChangeTransactionSeed)
        }
    }

    func testChildUpdatePublishesBaseTransactionBeforePhaseChangeTransactionExists() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            let container = Container(
                phases: [0, 1],
                content: { PhaseSizedView(width: CGFloat($0)) },
                animation: { _ in nil },
                behavior: .eventDriven(trigger: AnyEquatable(1))
            )
            var baseTransaction = Transaction()
            baseTransaction[PhaseAnimatorTransactionWidthKey.self] = 377
            let source = graph.makeInput(value: container)
            let transaction = graph.makeInput(value: baseTransaction)
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
                animationCompletion: completion.asWeak(),
                isVisible: isVisible.asWeak()
            )
            child.lastBehavior = container.behavior

            let childValue = graph.makeStatefulRule(child)

            XCTAssertEqual(childValue.value.content.width, 0)
            XCTAssertEqual(childValue.value.phaseChangeTransaction[PhaseAnimatorTransactionWidthKey.self], 377)
            XCTAssertNil(childValue.value.phaseChangeTransactionSeed)
        }
    }

    func testChildUpdateSinglePhaseRepeatingDoesNotCreateCompletionTransaction() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            let container = Container(
                phases: [0],
                content: { PhaseSizedView(width: CGFloat($0)) },
                animation: { _ in .linear(duration: 0.1) },
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
                animationCompletion: completion.asWeak(),
                isVisible: isVisible.asWeak()
            )
            child.lastBehavior = container.behavior
            let childValue = graph.makeStatefulRule(
                child
            )

            XCTAssertEqual(childValue.value.content.width, 0)
            XCTAssertNil(childValue.value.phaseChangeTransactionSeed)
            XCTAssertNil(completion.value)
            XCTAssertFalse(viewGraph.hasPendingTransactions)
        }
    }

    func testChildUpdateRepeatingVisibleUpdateRunsBeforeNonAnimatedCompletion() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            let container = Container(
                phases: [0, 1, 2],
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
            var child = Container.Child(
                view: source,
                transaction: transaction,
                transactionSeed: viewGraph.data.transactionSeedAttribute,
                phase: phase,
                animationCompletion: completion.asWeak(),
                isVisible: isVisible.asWeak()
            )
            child.lastBehavior = container.behavior
            let childValue = graph.makeStatefulRule(
                child
            )

            let started = childValue.value

            XCTAssertEqual(started.content.width, 1)
            XCTAssertEqual(started.phaseChangeTransactionSeed, 23)
            XCTAssertNil(started.phaseChangeTransaction.animation)

            completion.setValue(.some(Container.AnimationCompletion(seed: 1, didAnimate: false)))
            let advanced = childValue.value

            XCTAssertEqual(advanced.content.width, 2)
            XCTAssertEqual(advanced.phaseChangeTransactionSeed, 23)
            XCTAssertNil(advanced.phaseChangeTransaction.animation)
            XCTAssertTrue(viewGraph.hasPendingTransactions)

            viewGraph.flushTransactions()

            XCTAssertEqual(completion.value?.seed, 2)
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
                    animationCompletion: completion.asWeak(),
                    isVisible: isVisible.asWeak()
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

    func testChildUpdateRepeatingVisibleUpdateRunsBeforeAnimatedCompletion() {
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
            var child = Container.Child(
                view: source,
                transaction: transaction,
                transactionSeed: viewGraph.data.transactionSeedAttribute,
                phase: phase,
                animationCompletion: completion.asWeak(),
                isVisible: isVisible.asWeak()
            )
            child.lastBehavior = container.behavior
            let childValue = graph.makeStatefulRule(
                child
            )

            let started = childValue.value

            XCTAssertEqual(started.content.width, 1)
            XCTAssertEqual(started.phaseChangeTransactionSeed, 17)
            XCTAssertNotNil(started.phaseChangeTransaction.animation)

            completion.setValue(.some(Container.AnimationCompletion(seed: 1, didAnimate: true)))
            let advanced = childValue.value

            XCTAssertEqual(advanced.content.width, 2)
            XCTAssertEqual(advanced.phaseChangeTransactionSeed, 17)
            XCTAssertNotNil(advanced.phaseChangeTransaction.animation)
        }
    }

    func testChildUpdateSkipsAnimatedEventDrivenCompletionAtZeroIndex() {
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
                    animationCompletion: completion.asWeak(),
                    isVisible: isVisible.asWeak()
                )
            )

            XCTAssertEqual(childValue.value.content.width, 0)

            completion.setValue(.some(Container.AnimationCompletion(seed: 0, didAnimate: true)))
            let unchanged = childValue.value

            XCTAssertEqual(unchanged.content.width, 0)
            XCTAssertNil(unchanged.phaseChangeTransactionSeed)
        }
    }

    func testChildUpdateStartsVisibleRepeatingSequence() {
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
            viewGraph.data.transactionSeed = 31
            let childValue = graph.makeStatefulRule(
                Container.Child(
                    view: source,
                    transaction: transaction,
                    transactionSeed: viewGraph.data.transactionSeedAttribute,
                    phase: phase,
                    animationCompletion: completion.asWeak(),
                    isVisible: isVisible.asWeak()
                )
            )

            let initialVisibleValue = childValue.value

            XCTAssertEqual(initialVisibleValue.content.width, 1)
            XCTAssertEqual(initialVisibleValue.phaseChangeTransactionSeed, 31)
            XCTAssertNotNil(initialVisibleValue.phaseChangeTransaction.animation)
        }
    }

    func testChildUpdateStartsEventDrivenSequenceWhenTriggerChanges() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            let source = graph.makeInput(
                value: Container(
                    phases: [0, 1, 2],
                    content: { PhaseSizedView(width: CGFloat($0)) },
                    animation: { _ in .linear(duration: 0.25) },
                    behavior: .eventDriven(trigger: AnyEquatable(1))
                )
            )
            let transaction = graph.makeInput(value: Transaction())
            let phase = graph.makeInput(value: Phase())
            let completion = graph.makeInput(
                value: Optional<Container.AnimationCompletion>.none
            )
            let isVisible = graph.makeInput(value: true)
            viewGraph.data.transactionSeed = 37
            let childValue = graph.makeStatefulRule(
                Container.Child(
                    view: source,
                    transaction: transaction,
                    transactionSeed: viewGraph.data.transactionSeedAttribute,
                    phase: phase,
                    animationCompletion: completion.asWeak(),
                    isVisible: isVisible.asWeak()
                )
            )

            XCTAssertEqual(childValue.value.content.width, 0)
            XCTAssertNil(childValue.value.phaseChangeTransactionSeed)

            source.setValue(
                Container(
                    phases: [0, 1, 2],
                    content: { PhaseSizedView(width: CGFloat($0)) },
                    animation: { _ in .linear(duration: 0.25) },
                    behavior: .eventDriven(trigger: AnyEquatable(2))
                )
            )
            let triggeredValue = childValue.value

            XCTAssertEqual(triggeredValue.content.width, 1)
            XCTAssertEqual(triggeredValue.phaseChangeTransactionSeed, 37)
            XCTAssertNotNil(triggeredValue.phaseChangeTransaction.animation)
        }
    }

    func testChildUpdateSwitchingFromRepeatingToEventDrivenAdvancesToFirstPhase() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            let source = graph.makeInput(
                value: Container(
                    phases: [0, 1, 2],
                    content: { PhaseSizedView(width: CGFloat($0)) },
                    animation: { _ in nil },
                    behavior: .eventDriven(trigger: AnyEquatable(1))
                )
            )
            let transaction = graph.makeInput(value: Transaction())
            let phase = graph.makeInput(value: Phase())
            let completion = graph.makeInput(
                value: Optional<Container.AnimationCompletion>.none
            )
            let isVisible = graph.makeInput(value: true)
            viewGraph.data.transactionSeed = 47
            var child = Container.Child(
                view: source,
                transaction: transaction,
                transactionSeed: viewGraph.data.transactionSeedAttribute,
                phase: phase,
                animationCompletion: completion.asWeak(),
                isVisible: isVisible.asWeak()
            )
            child.currentIndex = 2
            child.lastBehavior = .repeating
            let childValue = graph.makeStatefulRule(child)

            let triggeredValue = childValue.value

            XCTAssertEqual(triggeredValue.content.width, 0)
            XCTAssertEqual(triggeredValue.phaseChangeTransactionSeed, 47)
            XCTAssertNil(triggeredValue.phaseChangeTransaction.animation)
        }
    }

    func testChildUpdateSwitchingFromEventDrivenToRepeatingAdvancesFromCurrentIndex() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            let source = graph.makeInput(
                value: Container(
                    phases: [0, 1, 2],
                    content: { PhaseSizedView(width: CGFloat($0)) },
                    animation: { _ in nil },
                    behavior: .repeating
                )
            )
            let transaction = graph.makeInput(value: Transaction())
            let phase = graph.makeInput(value: Phase())
            let completion = graph.makeInput(
                value: Optional<Container.AnimationCompletion>.none
            )
            let isVisible = graph.makeInput(value: true)
            viewGraph.data.transactionSeed = 53
            var child = Container.Child(
                view: source,
                transaction: transaction,
                transactionSeed: viewGraph.data.transactionSeedAttribute,
                phase: phase,
                animationCompletion: completion.asWeak(),
                isVisible: isVisible.asWeak()
            )
            child.currentIndex = 1
            child.lastBehavior = .eventDriven(trigger: AnyEquatable(1))
            let childValue = graph.makeStatefulRule(child)

            let triggeredValue = childValue.value

            XCTAssertEqual(triggeredValue.content.width, 2)
            XCTAssertEqual(triggeredValue.phaseChangeTransactionSeed, 53)
            XCTAssertNil(triggeredValue.phaseChangeTransaction.animation)
        }
    }

    func testChildUpdateEventDrivenTriggerChangeRestartsFromZeroSource() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            let source = graph.makeInput(
                value: Container(
                    phases: [0, 1, 2],
                    content: { PhaseSizedView(width: CGFloat($0)) },
                    animation: { _ in nil },
                    behavior: .eventDriven(trigger: AnyEquatable(2))
                )
            )
            let transaction = graph.makeInput(value: Transaction())
            let phase = graph.makeInput(value: Phase())
            let completion = graph.makeInput(
                value: Optional<Container.AnimationCompletion>.none
            )
            let isVisible = graph.makeInput(value: true)
            viewGraph.data.transactionSeed = 59
            var child = Container.Child(
                view: source,
                transaction: transaction,
                transactionSeed: viewGraph.data.transactionSeedAttribute,
                phase: phase,
                animationCompletion: completion.asWeak(),
                isVisible: isVisible.asWeak()
            )
            child.currentIndex = 2
            child.lastBehavior = .eventDriven(trigger: AnyEquatable(1))
            let childValue = graph.makeStatefulRule(child)

            let triggeredValue = childValue.value

            XCTAssertEqual(triggeredValue.content.width, 1)
            XCTAssertEqual(triggeredValue.phaseChangeTransactionSeed, 59)
            XCTAssertNil(triggeredValue.phaseChangeTransaction.animation)
        }
    }

    func testChildUpdateAnimatedEventDrivenCompletionWrapsToZero() {
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
                value: Optional<Container.AnimationCompletion>.some(
                    Container.AnimationCompletion(seed: 7, didAnimate: true)
                )
            )
            let isVisible = graph.makeInput(value: true)
            viewGraph.data.transactionSeed = 41
            var child = Container.Child(
                view: source,
                transaction: transaction,
                transactionSeed: viewGraph.data.transactionSeedAttribute,
                phase: phase,
                animationCompletion: completion.asWeak(),
                isVisible: isVisible.asWeak()
            )
            child.currentIndex = 2
            child.completionSeed = 7
            child.lastBehavior = container.behavior
            let childValue = graph.makeStatefulRule(child)

            let wrappedValue = childValue.value

            XCTAssertEqual(wrappedValue.content.width, 0)
            XCTAssertEqual(wrappedValue.phaseChangeTransactionSeed, 41)
            XCTAssertNotNil(wrappedValue.phaseChangeTransaction.animation)
        }
    }

    func testChildUpdateEventDrivenTriggerChangeStartsAfterCompletedCycle() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            let oldBehavior = PhaseAnimator<Int, PhaseSizedView>
                .Behavior
                .eventDriven(trigger: AnyEquatable(1))
            let source = graph.makeInput(
                value: Container(
                    phases: [0, 1, 2],
                    content: { PhaseSizedView(width: CGFloat($0)) },
                    animation: { _ in .linear(duration: 0.25) },
                    behavior: oldBehavior
                )
            )
            let transaction = graph.makeInput(value: Transaction())
            let phase = graph.makeInput(value: Phase())
            let completion = graph.makeInput(
                value: Optional<Container.AnimationCompletion>.some(
                    Container.AnimationCompletion(seed: 5, didAnimate: true)
                )
            )
            let isVisible = graph.makeInput(value: true)
            viewGraph.data.transactionSeed = 43
            var child = Container.Child(
                view: source,
                transaction: transaction,
                transactionSeed: viewGraph.data.transactionSeedAttribute,
                phase: phase,
                animationCompletion: completion.asWeak(),
                isVisible: isVisible.asWeak()
            )
            child.currentIndex = 0
            child.completionSeed = 5
            child.lastBehavior = oldBehavior
            let childValue = graph.makeStatefulRule(child)

            source.setValue(
                Container(
                    phases: [0, 1, 2],
                    content: { PhaseSizedView(width: CGFloat($0)) },
                    animation: { _ in .linear(duration: 0.25) },
                    behavior: .eventDriven(trigger: AnyEquatable(2))
                )
            )
            let triggeredValue = childValue.value

            XCTAssertEqual(triggeredValue.content.width, 1)
            XCTAssertEqual(triggeredValue.phaseChangeTransactionSeed, 43)
            XCTAssertNotNil(triggeredValue.phaseChangeTransaction.animation)
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
                    animationCompletion: completion.asWeak(),
                    isVisible: isVisible.asWeak()
                )
            )

            XCTAssertEqual(childValue.value.content.width, 0)

            completion.setValue(.some(Container.AnimationCompletion(seed: 0, didAnimate: true)))
            let unchanged = childValue.value

            XCTAssertEqual(unchanged.content.width, 0)
            XCTAssertNil(unchanged.phaseChangeTransactionSeed)
        }
    }

    func testChildUpdateWithInvalidVisibilityWeakAttributePublishesCurrentPhaseOnly() {
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
                value: Optional<Container.AnimationCompletion>.some(
                    Container.AnimationCompletion(seed: 3, didAnimate: true)
                )
            )
            let isVisible = graph.makeInput(value: true)
            let weakVisibility = isVisible.asWeak()
            graph.removeNode(isVisible.identifier)

            var child = Container.Child(
                view: source,
                transaction: transaction,
                transactionSeed: viewGraph.data.transactionSeedAttribute,
                phase: phase,
                animationCompletion: completion.asWeak(),
                isVisible: weakVisibility
            )
            child.currentIndex = 1
            child.completionSeed = 3
            child.lastBehavior = container.behavior
            let childValue = graph.makeStatefulRule(child)

            let value = childValue.value

            XCTAssertEqual(value.content.width, 1)
            XCTAssertNil(value.phaseChangeTransactionSeed)
            XCTAssertNil(value.phaseChangeTransaction.animation)
            XCTAssertFalse(viewGraph.hasPendingTransactions)
        }
    }

    func testChildUpdateWithInvalidCompletionWeakAttributeDoesNotConsumeCompletion() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            let behavior = PhaseAnimator<Int, PhaseSizedView>.Behavior.eventDriven(
                trigger: AnyEquatable(7)
            )
            let container = Container(
                phases: [0, 1, 2],
                content: { PhaseSizedView(width: CGFloat($0)) },
                animation: { _ in .linear(duration: 0.25) },
                behavior: behavior
            )
            let source = graph.makeInput(value: container)
            let transaction = graph.makeInput(value: Transaction())
            let phase = graph.makeInput(value: Phase())
            let completion = graph.makeInput(
                value: Optional<Container.AnimationCompletion>.some(
                    Container.AnimationCompletion(seed: 3, didAnimate: true)
                )
            )
            let weakCompletion = completion.asWeak()
            graph.removeNode(completion.identifier)
            let isVisible = graph.makeInput(value: true)

            var child = Container.Child(
                view: source,
                transaction: transaction,
                transactionSeed: viewGraph.data.transactionSeedAttribute,
                phase: phase,
                animationCompletion: weakCompletion,
                isVisible: isVisible.asWeak()
            )
            child.currentIndex = 1
            child.completionSeed = 3
            child.lastBehavior = behavior
            let childValue = graph.makeStatefulRule(child)

            let value = childValue.value

            XCTAssertEqual(value.content.width, 1)
            XCTAssertNil(value.phaseChangeTransactionSeed)
            XCTAssertNil(value.phaseChangeTransaction.animation)
            XCTAssertFalse(viewGraph.hasPendingTransactions)
        }
    }

    func testChildUpdateGraphPhaseResetKeepsPhaseChangeTransactionSeed() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            let container = Container(
                phases: [0, 1, 2],
                content: { PhaseSizedView(width: CGFloat($0)) },
                animation: { _ in nil },
                behavior: .eventDriven(trigger: AnyEquatable(1))
            )
            var graphPhase = Phase()
            graphPhase.resetSeed = 1
            let source = graph.makeInput(value: container)
            let transaction = graph.makeInput(value: Transaction())
            let phase = graph.makeInput(value: graphPhase)
            let completion = graph.makeInput(
                value: Optional<Container.AnimationCompletion>.none
            )
            let isVisible = graph.makeInput(value: true)
            var child = Container.Child(
                view: source,
                transaction: transaction,
                transactionSeed: viewGraph.data.transactionSeedAttribute,
                phase: phase,
                animationCompletion: completion.asWeak(),
                isVisible: isVisible.asWeak()
            )
            child.currentIndex = 2
            child.completionSeed = 9
            child.endlessLoopState = .monitoring(firstNonAnimatedPhaseIndex: 2)
            child.lastBehavior = .eventDriven(trigger: AnyEquatable(1))
            child.phaseChangeTransactionSeed = 77
            let childValue = graph.makeStatefulRule(child)

            let resetValue = childValue.value

            XCTAssertEqual(resetValue.content.width, 0)
            XCTAssertEqual(resetValue.phaseChangeTransactionSeed, 77)
        }
    }

    func testChildUpdateInvisibleResetReturnsInitialPhaseWithoutClearingPhaseTransactionSeed() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            let container = Container(
                phases: [0, 1, 2],
                content: { PhaseSizedView(width: CGFloat($0)) },
                animation: { _ in nil },
                behavior: .repeating
            )
            let source = graph.makeInput(value: container)
            let transaction = graph.makeInput(value: Transaction())
            let phase = graph.makeInput(value: Phase())
            let completion = graph.makeInput(
                value: Optional<Container.AnimationCompletion>.some(
                    Container.AnimationCompletion(seed: 4, didAnimate: true)
                )
            )
            let isVisible = graph.makeInput(value: false)
            var child = Container.Child(
                view: source,
                transaction: transaction,
                transactionSeed: viewGraph.data.transactionSeedAttribute,
                phase: phase,
                animationCompletion: completion.asWeak(),
                isVisible: isVisible.asWeak()
            )
            child.currentIndex = 1
            child.completionSeed = 4
            child.endlessLoopState = .animating
            child.lastBehavior = container.behavior
            child.phaseChangeTransactionSeed = 83
            let childValue = graph.makeStatefulRule(child)

            let resetValue = childValue.value

            XCTAssertEqual(resetValue.content.width, 0)
            XCTAssertEqual(resetValue.phaseChangeTransactionSeed, 83)
            XCTAssertFalse(viewGraph.hasPendingTransactions)
        }
    }

    func testAppearanceHandlerQueuesVisibleAssignmentThroughAsyncTransaction() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            let isVisible = graph.makeInput(value: false)
            let appear = Container.appearanceHandler(isVisible: isVisible.asWeak(), value: true)

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

    func testTransactionRuleFallsBackWhenPhaseChangeSeedIsNil() {
        let graph = AttributeGraph()
        let ref = AttributeGraphRef(graph: graph)

        ref.withCurrent {
            var baseTransaction = Transaction()
            baseTransaction[PhaseAnimatorTransactionWidthKey.self] = 21
            var phaseTransaction = Transaction()
            phaseTransaction[PhaseAnimatorTransactionWidthKey.self] = 144

            let selected = graph.makeStatefulRule(
                PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer.TransactionRule(
                    transaction: graph.makeInput(value: baseTransaction),
                    transactionSeed: graph.makeInput(value: UInt32(9)),
                    phaseChangeTransaction: graph.makeInput(value: phaseTransaction),
                    phaseChangeTransactionSeed: graph.makeInput(value: Optional<UInt32>.none)
                )
            )

            XCTAssertEqual(selected.value[PhaseAnimatorTransactionWidthKey.self], 21)
        }
    }

    func testTransactionRuleRechecksCurrentTransactionSeed() {
        let graph = AttributeGraph()
        let ref = AttributeGraphRef(graph: graph)

        ref.withCurrent {
            var baseTransaction = Transaction()
            baseTransaction[PhaseAnimatorTransactionWidthKey.self] = 34
            var phaseTransaction = Transaction()
            phaseTransaction[PhaseAnimatorTransactionWidthKey.self] = 233

            let transactionSeed = graph.makeInput(value: UInt32(2))
            let phaseChangeTransactionSeed = graph.makeInput(value: Optional<UInt32>.some(3))
            let selected = graph.makeStatefulRule(
                PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer.TransactionRule(
                    transaction: graph.makeInput(value: baseTransaction),
                    transactionSeed: transactionSeed,
                    phaseChangeTransaction: graph.makeInput(value: phaseTransaction),
                    phaseChangeTransactionSeed: phaseChangeTransactionSeed
                )
            )

            XCTAssertEqual(selected.value[PhaseAnimatorTransactionWidthKey.self], 34)

            transactionSeed.setValue(3)

            XCTAssertEqual(selected.value[PhaseAnimatorTransactionWidthKey.self], 233)
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
            animationCompletion: completion.asWeak(),
            isVisible: isVisible.asWeak()
        )
    }

    private static func typeDescription(of value: Any) -> String {
        String(reflecting: Mirror(reflecting: value).subjectType)
    }
}
