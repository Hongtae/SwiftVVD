import Foundation
@testable import VUI

final class AnimatableAttributeHarness {
    private let rendererHost = TestViewRendererHost()
    private let viewGraph: ViewGraph
    private var animatableSubgraph: AGSubgraph!
    private var source: Attribute<_OpacityEffect>!
    private var time: Attribute<Time>!
    private var phase: Attribute<Phase>!
    private var transaction: Attribute<Transaction>!
    private var animated: Attribute<_OpacityEffect>!

    init(initialValue: _OpacityEffect) {
        let viewGraph = ViewGraph(
            rootViewType: EmptyView.self,
            content: EmptyView(),
            rendererHost: rendererHost,
            requestedOutputs: []
        )
        rendererHost.storage = viewGraph
        self.viewGraph = viewGraph

        viewGraph.data.withCurrent {
            let graph = viewGraph.data.graph
            source = graph.makeInput(value: initialValue)
            time = graph.makeInput(value: Time(seconds: 0))
            phase = graph.makeInput(value: Phase())
            transaction = graph.makeInput(value: Transaction())
            let environment = graph.makeInput(value: EnvironmentValues())
            let inputs = _GraphInputs(
                time: time,
                phase: phase,
                environment: environment,
                transaction: transaction
            )
            let subgraph = AGSubgraph()
            animatableSubgraph = subgraph
            AGSubgraph.withCurrent(subgraph) {
                var graphValue = _GraphValue<_OpacityEffect>(_attribute: source)
                _OpacityEffect._makeAnimatable(value: &graphValue, inputs: inputs)
                animated = graphValue._attribute
            }
        }
    }

    func currentValue() -> _OpacityEffect {
        viewGraph.data.withCurrent {
            animated.value
        }
    }

    func valueNeedsEvaluation() -> Bool {
        viewGraph.data.withCurrent {
            animated.valueState.rawValue & 1 != 0
        }
    }

    func setSource(_ value: _OpacityEffect, animation: Animation?) {
        setSource(value, transaction: Transaction(animation: animation))
    }

    func setSource(_ value: _OpacityEffect, transaction: Transaction) {
        viewGraph.data.withCurrent {
            self.transaction.setValue(transaction)
            source.setValue(value, transaction: transaction)
        }
    }

    func setSourceUsingCurrentTransaction(_ value: _OpacityEffect) {
        viewGraph.data.withCurrent {
            let transaction = Transaction.current
            self.transaction.setValue(transaction)
            source.setValue(value, transaction: transaction)
        }
    }

    func setSourceThroughBinding(_ value: _OpacityEffect, transaction: Transaction) {
        viewGraph.data.withCurrent {
            let binding = Binding<_OpacityEffect>(
                get: { self.source.value },
                set: { newValue, transaction in
                    self.transaction.setValue(transaction)
                    self.source.setValue(newValue, transaction: transaction)
                }
            )
            binding.transaction(transaction).wrappedValue = value
        }
    }

    func setSourceThroughDynamicMemberBinding(_ opacity: Double, transaction: Transaction) {
        viewGraph.data.withCurrent {
            let binding = Binding<_OpacityEffect>(
                get: { self.source.value },
                set: { newValue, transaction in
                    self.transaction.setValue(transaction)
                    self.source.setValue(newValue, transaction: transaction)
                }
            )
            binding.opacity.transaction(transaction).wrappedValue = opacity
        }
    }

    func setSourceThroughCollectionElementBinding(_ value: _OpacityEffect, transaction: Transaction) {
        viewGraph.data.withCurrent {
            let binding = Binding<[_OpacityEffect]>(
                get: { [self.source.value] },
                set: { newValue, transaction in
                    self.transaction.setValue(transaction)
                    self.source.setValue(newValue[0], transaction: transaction)
                }
            )
            binding[0].transaction(transaction).wrappedValue = value
        }
    }

    func setSourceThroughCollectionMemberBinding(_ opacity: Double, transaction: Transaction) {
        viewGraph.data.withCurrent {
            let binding = Binding<[_OpacityEffect]>(
                get: { [self.source.value] },
                set: { newValue, transaction in
                    self.transaction.setValue(transaction)
                    self.source.setValue(newValue[0], transaction: transaction)
                }
            )
            binding[0].opacity.transaction(transaction).wrappedValue = opacity
        }
    }

    func setTime(_ seconds: Double) {
        viewGraph.data.withCurrent {
            time.setValue(Time(seconds: seconds))
        }
    }

    func bumpPhaseResetSeed() {
        viewGraph.data.withCurrent {
            var value = phase.value
            value.resetSeed &+= 1
            phase.setValue(value)
        }
    }

    func invalidateAnimatableSubgraph() {
        viewGraph.data.withCurrent {
            animatableSubgraph.invalidate()
            animatableSubgraph.removeFromParent()
        }
    }

    func nextUpdateInterval() -> Double {
        viewGraph.nextUpdateInterval
    }

    func nextUpdateReasons() -> Set<UInt32> {
        viewGraph.nextUpdateReasons
    }

    func resetNextUpdate() {
        viewGraph.nextUpdate = (ViewGraph.NextUpdate(), ViewGraph.NextUpdate())
    }

    func finalizeTransactionBody() {
        Transaction.dispatchPendingListeners().forEach { $0() }
        flushCompletionActions()
    }

    func flushCompletionActions() {
        while !viewGraph.data.graph.actionOutbox.isEmpty {
            let actions = viewGraph.data.graph.actionOutbox
            viewGraph.data.graph.actionOutbox.removeAll()
            actions.forEach { $0() }
        }
    }
}

final class GenericAnimatableAttributeHarness<Value: Animatable> {
    private let rendererHost = TestViewRendererHost()
    private let viewGraph: ViewGraph
    private var animatableSubgraph: AGSubgraph!
    private var source: Attribute<Value>!
    private var time: Attribute<Time>!
    private var phase: Attribute<Phase>!
    private var transaction: Attribute<Transaction>!
    private var animated: Attribute<Value>!

    init(initialValue: Value) {
        let viewGraph = ViewGraph(
            rootViewType: EmptyView.self,
            content: EmptyView(),
            rendererHost: rendererHost,
            requestedOutputs: []
        )
        rendererHost.storage = viewGraph
        self.viewGraph = viewGraph

        viewGraph.data.withCurrent {
            let graph = viewGraph.data.graph
            source = graph.makeInput(value: initialValue)
            time = graph.makeInput(value: Time(seconds: 0))
            phase = graph.makeInput(value: Phase())
            transaction = graph.makeInput(value: Transaction())
            let environment = graph.makeInput(value: EnvironmentValues())
            let inputs = _GraphInputs(
                time: time,
                phase: phase,
                environment: environment,
                transaction: transaction
            )
            let subgraph = AGSubgraph()
            animatableSubgraph = subgraph
            AGSubgraph.withCurrent(subgraph) {
                var graphValue = _GraphValue<Value>(_attribute: source)
                Value._makeAnimatable(value: &graphValue, inputs: inputs)
                animated = graphValue._attribute
            }
        }
    }

    func currentValue() -> Value {
        viewGraph.data.withCurrent {
            animated.value
        }
    }

    func valueNeedsEvaluation() -> Bool {
        viewGraph.data.withCurrent {
            animated.valueState.rawValue & 1 != 0
        }
    }

    func setSource(_ value: Value, transaction: Transaction) {
        viewGraph.data.withCurrent {
            self.transaction.setValue(transaction)
            source.setValue(value, transaction: transaction)
        }
    }

    func setTime(_ seconds: Double) {
        viewGraph.data.withCurrent {
            time.setValue(Time(seconds: seconds))
        }
    }

    func nextUpdateInterval() -> Double {
        viewGraph.nextUpdateInterval
    }

    func nextUpdateReasons() -> Set<UInt32> {
        viewGraph.nextUpdateReasons
    }

    func resetNextUpdate() {
        viewGraph.nextUpdate = (ViewGraph.NextUpdate(), ViewGraph.NextUpdate())
    }

    func finalizeTransactionBody() {
        Transaction.dispatchPendingListeners().forEach { $0() }
        flushCompletionActions()
    }

    func flushCompletionActions() {
        while !viewGraph.data.graph.actionOutbox.isEmpty {
            let actions = viewGraph.data.graph.actionOutbox
            viewGraph.data.graph.actionOutbox.removeAll()
            actions.forEach { $0() }
        }
    }
}

final class DualAnimatableAttributeHarness {
    private let rendererHost = TestViewRendererHost()
    private let viewGraph: ViewGraph
    private var firstSource: Attribute<_OpacityEffect>!
    private var secondSource: Attribute<_OpacityEffect>!
    private var firstTime: Attribute<Time>!
    private var secondTime: Attribute<Time>!
    private var firstTransaction: Attribute<Transaction>!
    private var secondTransaction: Attribute<Transaction>!
    private var firstAnimated: Attribute<_OpacityEffect>!
    private var secondAnimated: Attribute<_OpacityEffect>!

    init(firstInitialValue: _OpacityEffect, secondInitialValue: _OpacityEffect) {
        let viewGraph = ViewGraph(
            rootViewType: EmptyView.self,
            content: EmptyView(),
            rendererHost: rendererHost,
            requestedOutputs: []
        )
        rendererHost.storage = viewGraph
        self.viewGraph = viewGraph

        viewGraph.data.withCurrent {
            let graph = viewGraph.data.graph
            firstSource = graph.makeInput(value: firstInitialValue)
            secondSource = graph.makeInput(value: secondInitialValue)
            firstTime = graph.makeInput(value: Time(seconds: 0))
            secondTime = graph.makeInput(value: Time(seconds: 0))
            func makeInputs(
                time: Attribute<Time>,
                transaction: inout Attribute<Transaction>!
            ) -> _GraphInputs {
                let phase = graph.makeInput(value: Phase())
                transaction = graph.makeInput(value: Transaction())
                let environment = graph.makeInput(value: EnvironmentValues())
                return _GraphInputs(
                    time: time,
                    phase: phase,
                    environment: environment,
                    transaction: transaction
                )
            }
            var firstGraphValue = _GraphValue<_OpacityEffect>(_attribute: firstSource)
            _OpacityEffect._makeAnimatable(
                value: &firstGraphValue,
                inputs: makeInputs(time: firstTime, transaction: &firstTransaction)
            )
            firstAnimated = firstGraphValue._attribute
            var secondGraphValue = _GraphValue<_OpacityEffect>(_attribute: secondSource)
            _OpacityEffect._makeAnimatable(
                value: &secondGraphValue,
                inputs: makeInputs(time: secondTime, transaction: &secondTransaction)
            )
            secondAnimated = secondGraphValue._attribute
        }
    }

    func currentFirstValue() -> _OpacityEffect {
        viewGraph.data.withCurrent {
            firstAnimated.value
        }
    }

    func currentSecondValue() -> _OpacityEffect {
        viewGraph.data.withCurrent {
            secondAnimated.value
        }
    }

    func setFirst(_ value: _OpacityEffect, transaction: Transaction) {
        viewGraph.data.withCurrent {
            firstTransaction.setValue(transaction)
            firstSource.setValue(value, transaction: transaction)
        }
    }

    func setSecond(_ value: _OpacityEffect, transaction: Transaction) {
        viewGraph.data.withCurrent {
            secondTransaction.setValue(transaction)
            secondSource.setValue(value, transaction: transaction)
        }
    }

    func setTime(_ seconds: Double) {
        viewGraph.data.withCurrent {
            firstTime.setValue(Time(seconds: seconds))
            secondTime.setValue(Time(seconds: seconds))
        }
    }

    func setFirstTime(_ seconds: Double) {
        viewGraph.data.withCurrent {
            firstTime.setValue(Time(seconds: seconds))
        }
    }

    func setSecondTime(_ seconds: Double) {
        viewGraph.data.withCurrent {
            secondTime.setValue(Time(seconds: seconds))
        }
    }

    func nextUpdateInterval() -> Double {
        viewGraph.nextUpdateInterval
    }

    func nextUpdateReasons() -> Set<UInt32> {
        viewGraph.nextUpdateReasons
    }

    func resetNextUpdate() {
        viewGraph.nextUpdate = (ViewGraph.NextUpdate(), ViewGraph.NextUpdate())
    }

    func finalizeTransactionBody() {
        Transaction.dispatchPendingListeners().forEach { $0() }
        flushCompletionActions()
    }

    func flushCompletionActions() {
        while !viewGraph.data.graph.actionOutbox.isEmpty {
            let actions = viewGraph.data.graph.actionOutbox
            viewGraph.data.graph.actionOutbox.removeAll()
            actions.forEach { $0() }
        }
    }
}

final class AnimatableFrameAttributeHarness {
    private let rendererHost = TestViewRendererHost()
    private let viewGraph: ViewGraph
    private var animatableSubgraph: AGSubgraph!
    private var rawPosition: Attribute<CGPoint>!
    private var rawSize: Attribute<ViewSize>!
    private var time: Attribute<Time>!
    private var phase: Attribute<Phase>!
    private var transaction: Attribute<Transaction>!
    private var animatedPosition: Attribute<CGPoint>!
    private var animatedSize: Attribute<ViewSize>!
    private var animatedFrame: Attribute<ViewFrame>!
    private var cachedFrame: CachedEnvironment.AnimatedFrame!

    init(
        initialPosition: CGPoint,
        initialSize: ViewSize,
        initialTransaction: Transaction = Transaction(),
        supportsVFD: Bool = false,
        animationsDisabled: Bool = false
    ) {
        let viewGraph = ViewGraph(
            rootViewType: EmptyView.self,
            content: EmptyView(),
            rendererHost: rendererHost,
            requestedOutputs: []
        )
        rendererHost.storage = viewGraph
        self.viewGraph = viewGraph

        viewGraph.data.withCurrent {
            let graph = viewGraph.data.graph
            rawPosition = graph.makeInput(value: initialPosition)
            rawSize = graph.makeInput(value: initialSize)
            time = graph.makeInput(value: Time(seconds: 0))
            phase = graph.makeInput(value: Phase())
            transaction = graph.makeInput(value: initialTransaction)
            let environment = graph.makeInput(value: EnvironmentValues())
            var inputs = _GraphInputs(
                time: time,
                phase: phase,
                environment: environment,
                transaction: transaction
            )
            if supportsVFD {
                inputs.options.insert(.supportsVariableFrameDuration)
            }
            if animationsDisabled {
                inputs.options.insert(.animationsDisabled)
            }
            let subgraph = AGSubgraph()
            animatableSubgraph = subgraph
            AGSubgraph.withCurrent(subgraph) {
                let attributes = makeAnimatableFrameAttributes(
                    in: &inputs,
                    position: rawPosition,
                    size: rawSize
                )
                animatedPosition = attributes.position
                animatedSize = attributes.size
                animatedFrame = attributes.frame
                cachedFrame = inputs.cachedEnvironment.value.animatedFrame
            }
        }
    }

    var rawPositionID: AGAttribute { rawPosition.identifier }
    var rawSizeID: AGAttribute { rawSize.identifier }
    var timeID: AGAttribute { time.identifier }
    var phaseID: AGAttribute { phase.identifier }
    var transactionID: AGAttribute { transaction.identifier }
    var frameID: AGAttribute { animatedFrame.identifier }
    var animatedPositionID: AGAttribute { animatedPosition.identifier }
    var animatedSizeID: AGAttribute { animatedSize.identifier }

    func cachedAnimatedFrame() -> CachedEnvironment.AnimatedFrame {
        cachedFrame
    }

    func currentFrame() -> ViewFrame {
        viewGraph.data.withCurrent {
            animatedFrame.value
        }
    }

    func frameNeedsEvaluation() -> Bool {
        viewGraph.data.withCurrent {
            animatedFrame.valueState.rawValue & 1 != 0
        }
    }

    func currentPosition() -> CGPoint {
        viewGraph.data.withCurrent {
            animatedPosition.value
        }
    }

    func currentSize() -> ViewSize {
        viewGraph.data.withCurrent {
            animatedSize.value
        }
    }

    func setFrame(
        position: CGPoint,
        size: ViewSize,
        transaction: Transaction,
        geometryTransaction: Transaction? = nil
    ) {
        viewGraph.data.withCurrent {
            self.transaction.setValue(geometryTransaction ?? transaction)
            rawPosition.setValue(position, transaction: transaction)
            rawSize.setValue(size, transaction: transaction)
        }
    }

    func setTime(_ seconds: Double) {
        viewGraph.data.withCurrent {
            time.setValue(Time(seconds: seconds))
        }
    }

    func bumpPhaseResetSeed() {
        viewGraph.data.withCurrent {
            var value = phase.value
            value.resetSeed &+= 1
            phase.setValue(value)
        }
    }

    func invalidateAnimatableSubgraph() {
        viewGraph.data.withCurrent {
            animatableSubgraph.invalidate()
            animatableSubgraph.removeFromParent()
        }
    }

    func nextUpdateInterval() -> Double {
        viewGraph.nextUpdateInterval
    }

    func nextUpdateReasons() -> Set<UInt32> {
        viewGraph.nextUpdateReasons
    }

    func resetNextUpdate() {
        viewGraph.nextUpdate = (ViewGraph.NextUpdate(), ViewGraph.NextUpdate())
    }

    func flushCompletionActions() {
        while !viewGraph.data.graph.actionOutbox.isEmpty {
            let actions = viewGraph.data.graph.actionOutbox
            viewGraph.data.graph.actionOutbox.removeAll()
            actions.forEach { $0() }
        }
    }
}

final class TestViewRendererHost: ViewRendererHost {
    var storage: ViewGraph!
    var currentTimestamp: Time = Time(seconds: 0)
    var valuesNeedingUpdate: ViewGraphRootValues = []
    var renderingPhase: ViewRenderingPhase = ViewRenderingPhase()
    var externalUpdateCount: Int = 0

    var viewGraph: ViewGraph { storage }
    var responderNode: ResponderNode? { nil }
    var gestureGraph: GestureGraph? { nil }

    func requestUpdate(after: Double) {}

    func `as`<T>(_ type: T.Type) -> T? {
        self as? T
    }

    func updateRootView() {}
    func updateEnvironment() {}
    func updateSize() {}
    func updateSafeArea() {}
    func updateContainerSize() {}
}
