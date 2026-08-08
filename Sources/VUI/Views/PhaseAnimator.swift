//
//  File: PhaseAnimator.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

public struct PhaseAnimator<Phase, Content>: View where Phase: Equatable, Content: View {
    var phases: [Phase]
    var content: (Phase) -> Content
    var animation: (Phase) -> Animation?
    var behavior: Behavior

    @State private var currentIndex: Int
    @State private var seed: Int

    public init(
        _ phases: some Sequence<Phase>,
        trigger: some Equatable,
        @ViewBuilder content: @escaping (Phase) -> Content,
        animation: @escaping (Phase) -> Animation? = { _ in .default }
    ) {
        self.phases = Array(phases)
        self.content = content
        self.animation = animation
        self.behavior = .eventDriven(trigger: AnyEquatable(trigger))
        self._currentIndex = State(wrappedValue: 0)
        self._seed = State(wrappedValue: 0)
    }

    public init(
        _ phases: some Sequence<Phase>,
        @ViewBuilder content: @escaping (Phase) -> Content,
        animation: @escaping (Phase) -> Animation? = { _ in .default }
    ) {
        self.phases = Array(phases)
        self.content = content
        self.animation = animation
        self.behavior = .repeating
        self._currentIndex = State(wrappedValue: 0)
        self._seed = State(wrappedValue: 0)
    }

    public var body: some View {
        if phases.isEmpty {
            EmptyPhasesView().onAppear {
                Log.warning("PhaseAnimator requires at least one phase value")
            }
        } else {
            StateTransitioningContainer(
                phases: phases,
                content: content,
                animation: animation,
                behavior: behavior
            )
        }
    }
}

extension PhaseAnimator {
    enum Behavior: Equatable {
        case repeating
        case eventDriven(trigger: AnyEquatable)
    }

    struct EmptyPhasesView: View {
        typealias Body = Never

        static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
            _ViewOutputs()
        }

        static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
            _ViewListOutputs(views: .staticList(.merged([])),
                             nextImplicitID: 0,
                             staticCount: 0)
        }
    }

    struct StateTransitioningContainer: View {
        var phases: [Phase]
        var content: (Phase) -> Content
        var animation: (Phase) -> Animation?
        var behavior: Behavior

        typealias Body = Never

        static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
            guard let graph = _AGGraph.current else {
                fatalError("\(Self.self)._makeView called outside an active _AGGraph context.")
            }
            let attrs = makeChildAttributes(view: view, baseInputs: inputs.base)
            var inputs = inputs
            inputs.base.transaction = attrs.transaction
            let appearanceModifier = graph.makeInput(
                value: _AppearanceActionModifier(
                    appear: appearanceHandler(isVisible: attrs.isVisible.asWeak(), value: true),
                    disappear: appearanceHandler(isVisible: attrs.isVisible.asWeak(), value: false)
                )
            )
            return _AppearanceActionModifier._makeView(
                modifier: _GraphValue(_attribute: appearanceModifier),
                inputs: inputs
            ) { _, inputs in
                Content._makeView(view: _GraphValue(_attribute: attrs.content), inputs: inputs)
            }
        }

        static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
            let attrs = makeChildAttributes(view: view, baseInputs: inputs.base)
            var inputs = inputs
            inputs.base.transaction = attrs.transaction
            guard let graph = _AGGraph.current else {
                fatalError("\(Self.self)._makeViewList called outside an active _AGGraph context.")
            }
            let appearanceModifier = graph.makeInput(
                value: _AppearanceActionModifier(
                    appear: appearanceHandler(isVisible: attrs.isVisible.asWeak(), value: true),
                    disappear: appearanceHandler(isVisible: attrs.isVisible.asWeak(), value: false)
                )
            )
            return _AppearanceActionModifier._makeViewList(
                modifier: _GraphValue(_attribute: appearanceModifier),
                inputs: inputs
            ) { _, inputs in
                Content._makeViewList(
                    view: _GraphValue(_attribute: attrs.content),
                    inputs: inputs
                )
            }
        }

        private static func makeChildAttributes(
            view: _GraphValue<Self>,
            baseInputs: _GraphInputs
        ) -> (content: Attribute<Content>, transaction: Attribute<Transaction>, isVisible: Attribute<Bool>) {
            guard let graph = _AGGraph.current else {
                fatalError("\(Self.self) child attributes requested outside an active _AGGraph context.")
            }

            let animationCompletionAttr = graph.makeInput(
                value: Optional<AnimationCompletion>.none
            )
            let isVisibleAttr = graph.makeInput(value: false)
            let transactionSeedAttr = transactionSeedAttribute(in: graph)
            let childAttr: Attribute<Child.Value> = graph.makeStatefulRule(
                Child(
                    view: view._attribute,
                    transaction: baseInputs.transaction,
                    transactionSeed: transactionSeedAttr,
                    phase: baseInputs.phase,
                    animationCompletion: animationCompletionAttr.asWeak(),
                    isVisible: isVisibleAttr.asWeak()
                )
            )
            let contentAttr: Attribute<Content> = graph.makeRule {
                childAttr.value.content
            }
            let phaseChangeTransactionAttr: Attribute<Transaction> = graph.makeRule {
                childAttr.value.phaseChangeTransaction
            }
            let phaseChangeTransactionSeedAttr: Attribute<UInt32?> = graph.makeRule {
                childAttr.value.phaseChangeTransactionSeed
            }
            let transactionAttr: Attribute<Transaction> = graph.makeStatefulRule(
                TransactionRule(
                    transaction: baseInputs.transaction,
                    transactionSeed: transactionSeedAttr,
                    phaseChangeTransaction: phaseChangeTransactionAttr,
                    phaseChangeTransactionSeed: phaseChangeTransactionSeedAttr
                )
            )
            return (contentAttr, transactionAttr, isVisibleAttr)
        }

        private static func transactionSeedAttribute(in graph: _AGGraph) -> Attribute<UInt32> {
            if let ref = _AGGraphContext.current,
               let host = ref.context as? GraphHost {
                return host.data._transactionSeed
            }
            return graph.makeInput(value: UInt32.zero)
        }

        static func appearanceHandler(isVisible: WeakAttribute<Bool>, value: Bool) -> () -> Void {
            let host = GraphHost.currentHost
            return {
                host.asyncTransaction(
                    Transaction.current,
                    id: Transaction.id,
                    mutation: AssignmentGraphMutation(isVisible, newValue: value),
                    style: .deferred,
                    mayDeferUpdate: false
                )
            }
        }

        static func _viewListCount(inputs: _ViewListCountInputs) -> Int? {
            Content._viewListCount(inputs: inputs)
        }

        final class CompletionListener: AnimationListener, @unchecked Sendable {
            private let action: (Bool) -> Void
            private var count = 0
            private var didAnimate = false
            private var didFireAction = false

            init(action: @escaping (Bool) -> Void) {
                self.action = action
            }

            override func animationWasAdded() {
                count += 1
                didAnimate = true
            }

            override func animationWasRemoved() {
                count -= 1
                guard count == 0 else { return }
                fireActions(didAnimate: didAnimate)
            }

            func fireNoAnimationFallback() {
                guard !didAnimate else {
                    return
                }
                action(false)
                didFireAction = true
            }

            private func fireActions(didAnimate: Bool) {
                guard !didFireAction else { return }
                action(didAnimate)
                didFireAction = true
            }
        }
    }
}

extension PhaseAnimator.StateTransitioningContainer {
    struct AnimationCompletion {
        var seed: Int
        var didAnimate: Bool
    }

    struct Child: StatefulRule {
        struct Value {
            var content: Content
            var phaseChangeTransaction: Transaction
            var phaseChangeTransactionSeed: UInt32?
        }

        enum EndlessLoopState: Equatable {
            case monitoring(firstNonAnimatedPhaseIndex: Int)
            case animating
            case paused
        }

        var _view: Attribute<PhaseAnimator<Phase, Content>.StateTransitioningContainer>
        var _transaction: Attribute<Transaction>
        var _transactionSeed: Attribute<UInt32>
        var _phase: Attribute<_GraphInputs.Phase>
        var _animationCompletion: WeakAttribute<AnimationCompletion?>
        var _isVisible: WeakAttribute<Bool>
        var currentIndex = 0
        var completionSeed = 0
        var resetSeed = UInt32(0)
        var endlessLoopState = EndlessLoopState.animating
        var lastBehavior: PhaseAnimator<Phase, Content>.Behavior?
        var phaseChangeTransaction = Transaction()
        var phaseChangeTransactionSeed: UInt32?

        init(
            view: Attribute<PhaseAnimator<Phase, Content>.StateTransitioningContainer>,
            transaction: Attribute<Transaction>,
            transactionSeed: Attribute<UInt32>,
            phase: Attribute<_GraphInputs.Phase>,
            animationCompletion: WeakAttribute<AnimationCompletion?>,
            isVisible: WeakAttribute<Bool>
        ) {
            self._view = view
            self._transaction = transaction
            self._transactionSeed = transactionSeed
            self._phase = phase
            self._animationCompletion = animationCompletion
            self._isVisible = isVisible
        }

        mutating func updateValue() {
            let graphPhase = _phase.value
            if resetSeed != graphPhase.resetSeed {
                resetSeed = graphPhase.resetSeed
                resetAnimationState()
            }

            let viewChanged = _AGGraph.currentStatefulInputChanged(_view.identifier)
            let container = _view.value

            let isVisible: Bool?
            let visibilityChanged: Bool
            let graph = _AGGraph.current
            if let graph,
               _isVisible.isValid(in: graph) {
                let visibleAttribute = _isVisible.toStrong()
                visibilityChanged = _AGGraph.currentStatefulInputChanged(visibleAttribute.identifier)
                isVisible = visibleAttribute.value
            } else {
                visibilityChanged = false
                isVisible = nil
            }

            if isVisible == false {
                resetAnimationState()
            }

            if isVisible != nil {
                if isVisible == true {
                    scheduleVisibleRepeatingStartIfNeeded(
                        behavior: container.behavior,
                        viewChanged: viewChanged,
                        visibilityChanged: visibilityChanged,
                        previousBehavior: lastBehavior
                    )
                }
                if viewChanged {
                    resetEndlessLoopAfterViewChange(behavior: container.behavior)
                }
                if let lastBehavior,
                   lastBehavior != container.behavior {
                    scheduleBehaviorMismatch(from: lastBehavior, to: container.behavior)
                }
                lastBehavior = container.behavior

                let animationCompletion: AnimationCompletion?
                if let graph,
                   _animationCompletion.isValid(in: graph) {
                    animationCompletion = _animationCompletion.toStrong().value
                } else {
                    animationCompletion = nil
                }

                if let animationCompletion,
                   animationCompletion.seed == completionSeed {
                    if animationCompletion.didAnimate {
                        endlessLoopState = .animating
                        switch container.behavior {
                        case .repeating:
                            advance(from: currentIndex)
                        case .eventDriven:
                            if currentIndex != 0 {
                                advance(from: currentIndex)
                            }
                        }
                    } else {
                        consumeNonAnimatedCompletion(behavior: container.behavior)
                    }
                }
            }

            let currentPhase = container.phases[clampedIndex]
            _AGGraph.setStatefulOutput(
                Value(
                    content: container.content(currentPhase),
                    phaseChangeTransaction: phaseChangeTransaction,
                    phaseChangeTransactionSeed: phaseChangeTransactionSeed
                )
            )
        }

        var clampedIndex: Int {
            guard endlessLoopState != .paused else { return 0 }
            let container = _view.value
            let lastPhaseIndex = container.phases.count - 1
            return min(currentIndex, lastPhaseIndex)
        }

        mutating func resetAnimationState() {
            currentIndex = 0
            completionSeed &+= 1
            endlessLoopState = .animating
            lastBehavior = nil
        }

        mutating func resetEndlessLoopAfterViewChange(behavior: PhaseAnimator<Phase, Content>.Behavior) {
            let shouldRestartRepeating: Bool
            if case .paused = endlessLoopState {
                shouldRestartRepeating = true
            } else {
                shouldRestartRepeating = false
            }
            endlessLoopState = .animating

            guard shouldRestartRepeating else { return }
            guard case .repeating = behavior else { return }
            advance(from: currentIndex)
        }

        mutating func consumeNonAnimatedCompletion(behavior: PhaseAnimator<Phase, Content>.Behavior) {
            switch behavior {
            case .repeating:
                break
            case .eventDriven:
                guard currentIndex != 0 else { return }
            }

            let sourceIndex = currentIndex
            if case .animating = endlessLoopState {
                endlessLoopState = .monitoring(firstNonAnimatedPhaseIndex: sourceIndex)
            }
            advance(from: sourceIndex)
        }

        mutating func scheduleVisibleRepeatingStartIfNeeded(
            behavior: PhaseAnimator<Phase, Content>.Behavior,
            viewChanged: Bool,
            visibilityChanged: Bool,
            previousBehavior: PhaseAnimator<Phase, Content>.Behavior?
        ) {
            if case .repeating = behavior {
                if previousBehavior == behavior,
                   viewChanged || (!visibilityChanged && completionSeed != 0) {
                    return
                }
                advance(from: currentIndex)
            }
        }

        mutating func scheduleBehaviorMismatch(
            from previousBehavior: PhaseAnimator<Phase, Content>.Behavior,
            to behavior: PhaseAnimator<Phase, Content>.Behavior
        ) {
            switch (previousBehavior, behavior) {
            case (.repeating, .eventDriven):
                advance(to: 0)
            case (.eventDriven, .repeating):
                advance(from: currentIndex)
            case let (.eventDriven(previous), .eventDriven(current)):
                guard previous != current else { return }
                advance(from: 0)
            case (.repeating, .repeating):
                return
            }
        }

        mutating func advance(from sourceIndex: Int) {
            let container = _view.value
            guard container.phases.count >= 2 else { return }
            var nextIndex = sourceIndex + 1
            if nextIndex >= container.phases.count {
                nextIndex = 0
            }
            advance(to: nextIndex)
        }

        mutating func advance(to targetIndex: Int) {
            switch endlessLoopState {
            case .paused:
                return
            case let .monitoring(firstNonAnimatedPhaseIndex) where firstNonAnimatedPhaseIndex == targetIndex:
                endlessLoopState = .paused
                currentIndex = 0
                return
            case .monitoring, .animating:
                break
            }

            let container = _view.value
            guard targetIndex < container.phases.count else {
                advance(from: targetIndex)
                return
            }

            let phase = container.phases[targetIndex]
            currentIndex = targetIndex
            completionSeed &+= 1

            var transaction = _transaction.value
            let animation = container.animation(phase)
            if let animation {
                let host = GraphHost.currentHost
                let completion = _animationCompletion
                let seed = completionSeed
                let listener = PhaseAnimator<Phase, Content>
                    .StateTransitioningContainer
                    .CompletionListener { didAnimate in
                        Update.begin()
                        defer { Update.end() }

                        let value = Optional.some(AnimationCompletion(
                            seed: seed,
                            didAnimate: didAnimate
                        ))
                        host.asyncTransaction(
                            Transaction(),
                            id: Transaction.id,
                            mutation: CustomGraphMutation {
                                guard let graph = _AGGraph.current,
                                      completion.isValid(in: graph) else {
                                    return
                                }
                                completion.toStrong().setValue(value)
                            },
                            style: .deferred,
                            mayDeferUpdate: true
                        )
                    }
                transaction.animation = animation
                transaction.addAnimationLogicalListener(listener)
                Update.enqueueAction {
                    listener.fireNoAnimationFallback()
                }
            } else {
                transaction.animation = nil
                GraphHost.currentHost.continueTransaction(
                    setting: _animationCompletion,
                    to: Optional.some(AnimationCompletion(seed: completionSeed, didAnimate: false))
                )
            }

            phaseChangeTransaction = transaction
            phaseChangeTransactionSeed = _transactionSeed.value
        }
    }

    struct TransactionRule: StatefulRule {
        typealias Value = Transaction

        var _transaction: Attribute<Transaction>
        var _transactionSeed: Attribute<UInt32>
        var _phaseChangeTransaction: Attribute<Transaction>
        var _phaseChangeTransactionSeed: Attribute<UInt32?>

        init(
            transaction: Attribute<Transaction>,
            transactionSeed: Attribute<UInt32>,
            phaseChangeTransaction: Attribute<Transaction>,
            phaseChangeTransactionSeed: Attribute<UInt32?>
        ) {
            self._transaction = transaction
            self._transactionSeed = transactionSeed
            self._phaseChangeTransaction = phaseChangeTransaction
            self._phaseChangeTransactionSeed = phaseChangeTransactionSeed
        }

        mutating func updateValue() {
            let transaction = _transaction.value
            let phaseChangeTransaction = _phaseChangeTransaction.value
            let transactionSeed = _transactionSeed.value
            let phaseChangeTransactionSeed = _phaseChangeTransactionSeed.value
            let selected: Transaction
            if let phaseChangeTransactionSeed,
               phaseChangeTransactionSeed == transactionSeed {
                selected = phaseChangeTransaction
            } else {
                selected = transaction
            }
            _AGGraph.setStatefulOutput(selected)
        }
    }
}

extension PhaseAnimator.EmptyPhasesView: PrimitiveView {
}

extension PhaseAnimator.StateTransitioningContainer: PrimitiveView, UnaryView {
}

@available(*, unavailable)
extension PhaseAnimator: Sendable {
}

extension View {
    public func phaseAnimator<Phase>(
        _ phases: some Sequence<Phase>,
        trigger: some Equatable,
        @ViewBuilder content: @escaping (PlaceholderContentView<Self>, Phase) -> some View,
        animation: @escaping (Phase) -> Animation? = { _ in .default }
    ) -> some View where Phase: Equatable {
        let result = PhaseAnimator(phases, trigger: trigger, content: { phase in
            content(PlaceholderContentView<Self>(), phase)
        }, animation: animation)
        return modifier(phaseAnimatorModifier(result))
    }

    public func phaseAnimator<Phase>(
        _ phases: some Sequence<Phase>,
        @ViewBuilder content: @escaping (PlaceholderContentView<Self>, Phase) -> some View,
        animation: @escaping (Phase) -> Animation? = { _ in .default }
    ) -> some View where Phase: Equatable {
        let result = PhaseAnimator(phases, content: { phase in
            content(PlaceholderContentView<Self>(), phase)
        }, animation: animation)
        return modifier(phaseAnimatorModifier(result))
    }

    private func phaseAnimatorModifier<Result>(_ result: Result) -> CustomModifier<Self, Result>
        where Result: View {
        CustomModifier(result: result)
    }
}

struct AnyEquatable: Equatable {
    let value: Any
    private let equals: (Any) -> Bool

    init<Value>(_ value: Value) where Value: Equatable {
        self.value = value
        self.equals = { other in
            guard let other = other as? Value else { return false }
            return value == other
        }
    }

    static func == (lhs: AnyEquatable, rhs: AnyEquatable) -> Bool {
        lhs.equals(rhs.value)
    }
}
