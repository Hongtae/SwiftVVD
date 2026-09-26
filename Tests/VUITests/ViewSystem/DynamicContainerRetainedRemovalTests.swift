import XCTest
@testable import VUI

private final class DynamicContainerViewGraphFixture {
    let rendererHost: TestViewRendererHost
    let viewGraph: ViewGraph

    init() {
        let rendererHost = TestViewRendererHost()
        let viewGraph = ViewGraph(
            rootViewType: EmptyView.self,
            content: EmptyView(),
            rendererHost: rendererHost
        )
        rendererHost.storage = viewGraph
        self.rendererHost = rendererHost
        self.viewGraph = viewGraph
    }
}

private struct RetainingDynamicLayoutAdaptor: DynamicContainerAdaptor {
    typealias Item = DynamicViewListItem
    typealias Items = any ViewList
    typealias ItemLayout = DynamicLayoutViewAdaptor.ItemLayout

    static var maxUnusedItems: Int { 1 }

    var base: DynamicLayoutViewAdaptor

    init(_items: Attribute<any ViewList>) {
        base = DynamicLayoutViewAdaptor(_items: _items)
    }

    mutating func updatedItems() -> (any ViewList)? {
        base.updatedItems()
    }

    func foreachItem(
        items: any ViewList,
        _ body: (DynamicViewListItem) -> Void
    ) {
        base.foreachItem(items: items, body)
    }

    static func containsItem(
        _ items: any ViewList,
        _ item: DynamicViewListItem
    ) -> Bool {
        DynamicLayoutViewAdaptor.containsItem(items, item)
    }

    func makeItemLayout(
        item: DynamicViewListItem,
        uniqueId: UInt32,
        inputs: _ViewInputs,
        containerInfo: Attribute<DynamicContainer.Info>,
        containerInputs: (inout _ViewInputs) -> Void
    ) -> (_ViewOutputs, DynamicLayoutViewAdaptor.ItemLayout) {
        base.makeItemLayout(
            item: item,
            uniqueId: uniqueId,
            inputs: inputs,
            containerInfo: containerInfo,
            containerInputs: containerInputs
        )
    }

    func removeItemLayout(
        uniqueId: UInt32,
        itemLayout: DynamicLayoutViewAdaptor.ItemLayout
    ) {
        base.removeItemLayout(
            uniqueId: uniqueId,
            itemLayout: itemLayout
        )
    }
}

private extension DynamicContainerInfo
    where A == DynamicLayoutViewAdaptor {
    init(
        viewListAttr: Attribute<any ViewList>,
        inputs: _ViewInputs,
        parentSubgraph: AGSubgraph? = AGSubgraph.current,
        lastUniqueId: UInt32 = 0,
        lastRemoved: UInt32 = 0
    ) {
        self.init(
            adaptor: DynamicLayoutViewAdaptor(_items: viewListAttr),
            inputs: inputs,
            outputs: _ViewOutputs(),
            parentSubgraph: parentSubgraph,
            info: DynamicContainer.Info(),
            lastUniqueId: lastUniqueId,
            lastRemoved: lastRemoved,
            lastResetSeed: .max,
            needsPhaseUpdate: false
        )
    }
}

private extension DynamicContainerInfo
    where A == RetainingDynamicLayoutAdaptor {
    init(
        retainingViewListAttr: Attribute<any ViewList>,
        inputs: _ViewInputs,
        parentSubgraph: AGSubgraph? = AGSubgraph.current,
        lastUniqueId: UInt32 = 0,
        lastRemoved: UInt32 = 0
    ) {
        self.init(
            adaptor: RetainingDynamicLayoutAdaptor(
                _items: retainingViewListAttr
            ),
            inputs: inputs,
            outputs: _ViewOutputs(),
            parentSubgraph: parentSubgraph,
            info: DynamicContainer.Info(),
            lastUniqueId: lastUniqueId,
            lastRemoved: lastRemoved,
            lastResetSeed: .max,
            needsPhaseUpdate: false
        )
    }
}

private extension DynamicContainer.ItemInfo {
    var dynamicViewListID: _ViewList_ID.Canonical {
        if let item = self as? DynamicContainer._ItemInfo<DynamicLayoutViewAdaptor> {
            return item.item.id.canonicalID
        }
        if let item = self as? DynamicContainer._ItemInfo<RetainingDynamicLayoutAdaptor> {
            return item.item.id.canonicalID
        }
        preconditionFailure("Unexpected dynamic-layout test adaptor.")
    }
}

final class DynamicContainerRetainedRemovalTests: XCTestCase {
    func testAsymmetricTransitionKeepsBothApplySubtreesAcrossEveryPhase() {
        // ASSERTIONS dynamicLayoutTransitionRuleObserved
        // ASSERTIONS anyTransitionIdentityBodyMetadataObserved
        // ASSERTIONS transitionHelperStartsIdentityObserved
        let insertion = CombiningTransition(
            transition1: ScaleTransition(0.65),
            transition2: OpacityTransition()
        )
        let removal = CombiningTransition(
            transition1: MoveTransition(edge: .trailing),
            transition2: OpacityTransition()
        )
        let transition = AsymmetricTransition(
            insertion: insertion,
            removal: removal
        )

        let rows: [(TransitionPhase, [TransitionPhase])] = [
            (.willAppear, [.willAppear, .identity]),
            (.identity, [.identity, .identity]),
            (.didDisappear, [.identity, .didDisappear]),
        ]
        for (phase, expectedNestedPhases) in rows {
            let body = transition.body(
                content: PlaceholderContentView<
                    AsymmetricTransition<
                        CombiningTransition<ScaleTransition, OpacityTransition>,
                        CombiningTransition<MoveTransition, OpacityTransition>
                    >
                >(),
                phase: phase
            )
            let bodyType = String(reflecting: type(of: body))
            XCTAssertTrue(
                bodyType.contains("ApplyTransitionModifier<VUI.CombiningTransition<VUI.ScaleTransition, VUI.OpacityTransition>>"),
                bodyType
            )
            XCTAssertTrue(
                bodyType.contains("ApplyTransitionModifier<VUI.CombiningTransition<VUI.MoveTransition, VUI.OpacityTransition>>"),
                bodyType
            )
            XCTAssertEqual(
                transitionPhases(in: body),
                expectedNestedPhases,
                "phase \(phase)"
            )
        }
    }

    func testErasedAsymmetricCombinedTransitionMaterializesPhaseDrivenItem() throws {
        let graphFixture = DynamicContainerViewGraphFixture()
        let graphHost = graphFixture.viewGraph
        let graph = graphHost.data.graph
        let ref = _AGGraphContext(graph: graph)

        try ref.withCurrent {
            let inputs = makeGraphInputs(graph: graph, transaction: Transaction())
            let transition = AnyTransition.asymmetric(
                insertion: .scale(scale: 0.65).combined(with: .opacity),
                removal: .move(edge: .trailing).combined(with: .opacity)
            )
            let source = graph.makeInput(
                value: makeTransitionList(
                    inputs: inputs,
                    rows: ["row"],
                    transition: transition,
                    makeOutputs: Self.makeFixedLayoutOutputs
                )
            )
            let info = graph.makeStatefulRule(
                DynamicContainerInfo(
                    viewListAttr: source,
                    inputs: makeViewInputs(graph: graph, base: inputs)
                )
            ).value

            let item = try XCTUnwrap(info.activeItems.first)
            XCTAssertTrue(
                item.for(DynamicLayoutViewAdaptor.self).item.needsTransitions
            )
            let boxType = String(reflecting: transition._transitionType)
            XCTAssertTrue(boxType.contains("TransitionBox<"), boxType)
            XCTAssertTrue(boxType.contains("AsymmetricTransition<"), boxType)
            XCTAssertTrue(boxType.contains("CombiningTransition<"), boxType)
        }
    }

    func testDynamicContainerMaterializationUsesCapturedParentWithoutRuleOwnership() throws {
        // ASSERTIONS dynamicContainerMaterializationParentObserved
        // ASSERTIONS dynamicContainerAdaptorOwnershipObserved
        let graphFixture = DynamicContainerViewGraphFixture()
        let graphHost = graphFixture.viewGraph
        let graph = graphHost.data.graph
        let ref = _AGGraphContext(graph: graph)

        try ref.withCurrent {
            let parentSubgraph = AGSubgraph()
            let inputs = makeGraphInputs(graph: graph, transaction: Transaction())
            let source = graph.makeInput(value: makeTransitionList(inputs: inputs))
            let info = graph.makeStatefulRule(
                DynamicContainerInfo(
                    viewListAttr: source,
                    inputs: makeViewInputs(graph: graph, base: inputs),
                    parentSubgraph: parentSubgraph
                )
            )

            XCTAssertNil(info.subgraphOrNil)
            let item = try XCTUnwrap(info.value.activeItems.first)
            XCTAssertTrue(item.subgraph.parent === parentSubgraph)
        }
    }

    func testDynamicContainerRetainsTransitionRemovalUntilListenerInvalidatesRule() throws {
        let graphFixture = DynamicContainerViewGraphFixture()
        let graphHost = graphFixture.viewGraph
        let graph = graphHost.data.graph
        let ref = _AGGraphContext(graph: graph)
        var source: Attribute<any ViewList>!
        var infoAttr: Attribute<DynamicContainer.Info>!
        var removalEvents: [String] = []

        ref.withCurrent {
            let inputs = makeGraphInputs(graph: graph, transaction: Transaction())
            source = graph.makeInput(value: makeTransitionList(inputs: inputs))
            infoAttr = graph.makeStatefulRule(
                DynamicContainerInfo(
                    viewListAttr: source,
                    inputs: makeViewInputs(graph: graph, base: inputs)
                )
            )

            let initial = infoAttr.value
            XCTAssertEqual(initial.activeItems.count, 1)
            XCTAssertEqual(initial.removedCount, 0)
            XCTAssertEqual(initial.unusedCount, 0)
            XCTAssertEqual(initial.items.first?.phase, .identity)
            XCTAssertGreaterThan(initial.items.first?.subgraph.nodes.count ?? 0, 0)
        }

        let retainedItem = try Update.ensure {
            try ref.withCurrent {
                var removal = Transaction(animation: .linear(duration: 0.02))
                removal.addAnimationCompletion(criteria: .removed) {
                    removalEvents.append("removal removed")
                }
                removal.addAnimationCompletion(criteria: .logicallyComplete) {
                    removalEvents.append("removal logical")
                }
                source.setValue(EmptyViewList(), transaction: removal)

                let retained = infoAttr.value
                XCTAssertEqual(retained.activeItems.count, 0)
                XCTAssertEqual(retained.removedCount, 1)
                XCTAssertEqual(retained.unusedCount, 0)
                let item = try XCTUnwrap(retained.items.first)
                XCTAssertEqual(item.phase, .didDisappear)
                XCTAssertNotNil(item.listener)
                XCTAssertFalse(try XCTUnwrap(item.listener).isComplete)
                XCTAssertGreaterThan(item.subgraph.nodes.count, 0)
                XCTAssertEqual(removalEvents, [])
                return item
            }
        }

        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        XCTAssertEqual(removalEvents, ["removal removed", "removal logical"])
        XCTAssertTrue(try XCTUnwrap(retainedItem.listener).isComplete)
        graphHost.flushTransactions()

        ref.withCurrent {
            let finalized = infoAttr.value
            XCTAssertEqual(finalized.activeItems.count, 0)
            XCTAssertEqual(finalized.removedCount, 0)
            XCTAssertEqual(finalized.unusedCount, 0)
            XCTAssertTrue(finalized.items.isEmpty)
            XCTAssertEqual(retainedItem.subgraph.nodes.count, 0)
        }
    }

    func testDynamicContainerCountersWrapAndReserveZeroRemovalOrder() throws {
        // ASSERTIONS wrappingIncrementAndBasePlusOffsetObserved
        // ASSERTIONS nonzeroRemovalOrderingObserved
        let graphFixture = DynamicContainerViewGraphFixture()
        let graphHost = graphFixture.viewGraph
        let graph = graphHost.data.graph
        let ref = _AGGraphContext(graph: graph)
        var source: Attribute<any ViewList>!
        var infoAttr: Attribute<DynamicContainer.Info>!

        ref.withCurrent {
            let inputs = makeGraphInputs(
                graph: graph,
                transaction: Transaction()
            )
            source = graph.makeInput(
                value: makeTransitionList(inputs: inputs)
            )
            infoAttr = graph.makeStatefulRule(
                DynamicContainerInfo(
                    viewListAttr: source,
                    inputs: makeViewInputs(graph: graph, base: inputs),
                    lastUniqueId: .max,
                    lastRemoved: .max
                )
            )

            let initial = infoAttr.value
            XCTAssertEqual(initial.activeItems.count, 1)
            XCTAssertEqual(initial.items.first?.uniqueId, 0)
        }

        try Update.ensure {
            try ref.withCurrent {
                source.setValue(
                    EmptyViewList(),
                    transaction: Transaction(
                        animation: .linear(duration: 0.02)
                    )
                )

                let retained = infoAttr.value
                XCTAssertEqual(retained.removedCount, 1)
                let item = try XCTUnwrap(retained.items.first)
                XCTAssertEqual(item.phase, .didDisappear)
                XCTAssertEqual(item.removalOrder, 1)
            }
        }

        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        graphHost.flushTransactions()
        ref.withCurrent {
            XCTAssertTrue(infoAttr.value.items.isEmpty)
        }
    }

    func testRetainedTransitionRemovalQueuesDisappearAfterListenerInvalidatesRule() throws {
        let graphFixture = DynamicContainerViewGraphFixture()
        let graphHost = graphFixture.viewGraph
        let graph = graphHost.data.graph
        let ref = _AGGraphContext(graph: graph)
        var source: Attribute<any ViewList>!
        var infoAttr: Attribute<DynamicContainer.Info>!
        var removalEvents: [String] = []
        var lifecycleEvents: [String] = []

        ref.withCurrent {
            let inputs = makeGraphInputs(graph: graph, transaction: Transaction())
            source = graph.makeInput(
                value: makeTransitionList(
                    inputs: inputs,
                    rows: ["row"],
                    makeOutputs: { inputs in
                        Self.makeLifecycleLayoutOutputs(
                            inputs,
                            appear: { lifecycleEvents.append("row appear") },
                            disappear: { lifecycleEvents.append("row disappear") }
                        )
                    }
                )
            )
            infoAttr = graph.makeStatefulRule(
                DynamicContainerInfo(
                    viewListAttr: source,
                    inputs: makeViewInputs(graph: graph, base: inputs)
                )
            )

            let initial = infoAttr.value
            XCTAssertEqual(initial.activeItems.count, 1)
            XCTAssertEqual(initial.items.first?.phase, .identity)
            XCTAssertEqual(lifecycleEvents, ["row appear"])
        }

        let retainedItem = try ref.withCurrent {
            var removal = Transaction(animation: .linear(duration: 0.02))
            removal.addAnimationCompletion(criteria: .removed) {
                removalEvents.append("removal removed")
            }
            removal.addAnimationCompletion(criteria: .logicallyComplete) {
                removalEvents.append("removal logical")
            }
            source.setValue(EmptyViewList(), transaction: removal)

            let retained = infoAttr.value
            XCTAssertEqual(retained.activeItems.count, 0)
            XCTAssertEqual(retained.removedCount, 1)
            let item = try XCTUnwrap(retained.items.first)
            XCTAssertEqual(item.phase, .didDisappear)
            XCTAssertNotNil(item.listener)
            XCTAssertEqual(removalEvents, [])
            XCTAssertEqual(lifecycleEvents, ["row appear"])
            return item
        }

        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        XCTAssertEqual(removalEvents, ["removal removed", "removal logical"])
        XCTAssertEqual(lifecycleEvents, ["row appear"])
        XCTAssertTrue(try XCTUnwrap(retainedItem.listener).isComplete)
        graphHost.flushTransactions()

        ref.withCurrent {
            let finalized = infoAttr.value
            XCTAssertEqual(finalized.removedCount, 0)
            XCTAssertTrue(finalized.items.isEmpty)
            XCTAssertEqual(retainedItem.subgraph.nodes.count, 0)
            XCTAssertEqual(lifecycleEvents, ["row appear", "row disappear"])
        }
    }

    func testRetainedTransitionRemovalSetsDidDisappearPhaseBeforeCompletion() throws {
        // ASSERTIONS dynamicLayoutTransitionRuleObserved
        let graphFixture = DynamicContainerViewGraphFixture()
        let graphHost = graphFixture.viewGraph
        let graph = graphHost.data.graph
        let ref = _AGGraphContext(graph: graph)
        let recorder = DynamicContainerTransitionPhaseRecorder()
        var source: Attribute<any ViewList>!
        var infoAttr: Attribute<DynamicContainer.Info>!
        var viewPhase: Attribute<_GraphInputs.Phase>!
        var removalEvents: [String] = []

        ref.withCurrent {
            let inputs = makeGraphInputs(graph: graph, transaction: Transaction())
            source = graph.makeInput(
                value: makeTransitionList(
                    inputs: inputs,
                    rows: ["row"],
                    transition: AnyTransition(
                        DynamicContainerPhaseRecordingTransition(recorder: recorder)
                    ),
                    makeOutputs: { inputs in
                        viewPhase = inputs.base.phase
                        return Self.makeFixedLayoutOutputs(inputs)
                    }
                )
            )
            infoAttr = graph.makeStatefulRule(
                DynamicContainerInfo(
                    viewListAttr: source,
                    inputs: makeViewInputs(graph: graph, base: inputs)
                )
            )

            let initial = infoAttr.value
            XCTAssertEqual(initial.activeItems.count, 1)
            XCTAssertEqual(initial.items.first?.phase, .identity)
            if let layout = initial.items.first?.outputs._layoutComputer.attribute?.value {
                _ = layout.sizeThatFits(.unspecified)
            }
            XCTAssertEqual(recorder.events, ["identity"])
            XCTAssertFalse(viewPhase.value.isBeingRemoved)
        }

        let retainedItem = try Update.ensure {
            try ref.withCurrent {
                var removal = Transaction(animation: .linear(duration: 0.02))
                removal.addAnimationCompletion(criteria: .removed) {
                    removalEvents.append("removal removed")
                }
                removal.addAnimationCompletion(criteria: .logicallyComplete) {
                    removalEvents.append("removal logical")
                }
                source.setValue(EmptyViewList(), transaction: removal)

                let retained = infoAttr.value
                XCTAssertEqual(retained.activeItems.count, 0)
                XCTAssertEqual(retained.removedCount, 1)
                let item = try XCTUnwrap(retained.items.first)
                XCTAssertEqual(item.phase, .didDisappear)
                XCTAssertNotNil(item.listener)
                XCTAssertFalse(try XCTUnwrap(item.listener).isComplete)
                XCTAssertGreaterThan(item.subgraph.nodes.count, 0)
                if let layout = item.outputs._layoutComputer.attribute?.value {
                    _ = layout.sizeThatFits(.unspecified)
                }
                XCTAssertEqual(removalEvents, [])
                XCTAssertEqual(recorder.events, ["identity", "didDisappear"])
                XCTAssertTrue(viewPhase.value.isBeingRemoved)
                return item
            }
        }

        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        XCTAssertEqual(removalEvents, ["removal removed", "removal logical"])
        XCTAssertTrue(try XCTUnwrap(retainedItem.listener).isComplete)
        XCTAssertEqual(recorder.events, ["identity", "didDisappear"])
        graphHost.flushTransactions()

        ref.withCurrent {
            let finalized = infoAttr.value
            XCTAssertEqual(finalized.removedCount, 0)
            XCTAssertTrue(finalized.items.isEmpty)
            XCTAssertEqual(retainedItem.subgraph.nodes.count, 0)
            XCTAssertEqual(recorder.events, ["identity", "didDisappear"])
        }
    }

    func testSameIdentityReinsertCancelsRetainedTransitionRemovalWithoutLifecycleReinsert() throws {
        let graphFixture = DynamicContainerViewGraphFixture()
        let graphHost = graphFixture.viewGraph
        let graph = graphHost.data.graph
        let ref = _AGGraphContext(graph: graph)
        var source: Attribute<any ViewList>!
        var infoAttr: Attribute<DynamicContainer.Info>!
        var graphInputs: _GraphInputs!
        var lifecycleEvents: [String] = []

        ref.withCurrent {
            graphInputs = makeGraphInputs(graph: graph, transaction: Transaction())
            source = graph.makeInput(
                value: makeTransitionList(
                    inputs: graphInputs,
                    rows: ["row"],
                    makeOutputs: { inputs in
                        Self.makeLifecycleLayoutOutputs(
                            inputs,
                            appear: { lifecycleEvents.append("row appear") },
                            disappear: { lifecycleEvents.append("row disappear") }
                        )
                    }
                )
            )
            infoAttr = graph.makeStatefulRule(
                DynamicContainerInfo(
                    viewListAttr: source,
                    inputs: makeViewInputs(graph: graph, base: graphInputs)
                )
            )

            let initial = infoAttr.value
            XCTAssertEqual(initial.activeItems.count, 1)
            XCTAssertEqual(initial.removedCount, 0)
            XCTAssertEqual(initial.items.first?.phase, .identity)
            XCTAssertEqual(lifecycleEvents, ["row appear"])
        }

        var retainedItem: DynamicContainer.ItemInfo!
        var retainedListener: DynamicAnimationListener!
        try Update.ensure {
            try ref.withCurrent {
                source.setValue(
                    EmptyViewList(),
                    transaction: Transaction(animation: .linear(duration: 0.03))
                )

                let info = infoAttr.value
                XCTAssertEqual(info.activeItems.count, 0)
                XCTAssertEqual(info.removedCount, 1)
                retainedItem = try XCTUnwrap(info.items.first)
                retainedListener = try XCTUnwrap(retainedItem.listener)
                XCTAssertEqual(retainedItem.phase, .didDisappear)
                XCTAssertFalse(retainedListener.isComplete)
                XCTAssertEqual(lifecycleEvents, ["row appear"])
            }

            try ref.withCurrent {
                source.setValue(
                    makeTransitionList(
                        inputs: graphInputs,
                        rows: ["row"],
                        makeOutputs: { inputs in
                            Self.makeLifecycleLayoutOutputs(
                                inputs,
                                appear: { lifecycleEvents.append("row appear") },
                                disappear: { lifecycleEvents.append("row disappear") }
                            )
                        }
                    ),
                    transaction: Transaction(animation: nil)
                )

                let info = infoAttr.value
                XCTAssertEqual(info.activeItems.count, 1)
                XCTAssertEqual(info.removedCount, 0)
                XCTAssertEqual(info.unusedCount, 0)
                let reinserted = try XCTUnwrap(info.items.first)
                XCTAssertTrue(reinserted === retainedItem)
                XCTAssertEqual(reinserted.phase, .identity)
                XCTAssertNil(reinserted.listener)
                XCTAssertGreaterThan(reinserted.subgraph.nodes.count, 0)
                XCTAssertEqual(lifecycleEvents, ["row appear"])
            }
        }

        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        XCTAssertTrue(retainedListener.isComplete)
        XCTAssertFalse(
            graphHost.hasPendingTransactions,
            "A listener detached by reinsertion must not invalidate the container when its old animations drain."
        )

        try ref.withCurrent {
            let info = infoAttr.value
            XCTAssertEqual(info.activeItems.count, 1)
            XCTAssertEqual(info.removedCount, 0)
            XCTAssertEqual(info.unusedCount, 0)
            let active = try XCTUnwrap(info.items.first)
            XCTAssertTrue(active === retainedItem)
            XCTAssertGreaterThan(active.subgraph.nodes.count, 0)
            XCTAssertEqual(lifecycleEvents, ["row appear"])
        }
    }

    func testPublicForEachRetainsTransitionRemovalUntilListenerInvalidatesRule() throws {
        try assertPublicForEachRetainsTransitionRemovalUntilListenerInvalidatesRule { row, recorder in
            DynamicContainerLifecycleRow(row: row, recorder: recorder)
                .transition(.opacity)
        }
    }

    func testPublicForEachRetainedRemovalDrainsForkedAnimatableCompletionsBeforeDisappear() throws {
        try assertPublicRootRetainedRemovalDrainsForkedAnimatableCompletionsBeforeDisappear {
            rows, target, recorder, capture in
            ForEach(rows, id: \.self) { row in
                DynamicContainerForkRetargetRow(
                    row: row,
                    effect: _OpacityEffect(opacity: row == "row" ? target : 0),
                    recorder: recorder,
                    capture: capture
                )
                .transition(.opacity)
            }
        }
    }

    func testPublicGroupForEachRetainsTransitionRemovalUntilListenerInvalidatesRule() throws {
        try assertPublicRootRetainsTransitionRemovalUntilListenerInvalidatesRule { rows, recorder in
            Group(_content:
                ForEach(rows, id: \.self) { row in
                    DynamicContainerLifecycleRow(row: row, recorder: recorder)
                        .transition(.opacity)
                }
            )
        }
    }

    func testPublicGroupForEachRetainedRemovalDrainsForkedAnimatableCompletionsBeforeDisappear() throws {
        try assertPublicRootRetainedRemovalDrainsForkedAnimatableCompletionsBeforeDisappear {
            rows, target, recorder, capture in
            Group(_content:
                ForEach(rows, id: \.self) { row in
                    DynamicContainerForkRetargetRow(
                        row: row,
                        effect: _OpacityEffect(opacity: row == "row" ? target : 0),
                        recorder: recorder,
                        capture: capture
                    )
                    .transition(.opacity)
                }
            )
        }
    }

    func testPublicAnyViewErasedRowRetainsTransitionRemovalUntilListenerInvalidatesRule() throws {
        try assertPublicForEachRetainsTransitionRemovalUntilListenerInvalidatesRule { row, recorder in
            AnyView(DynamicContainerLifecycleRow(row: row, recorder: recorder))
                .transition(.opacity)
        }
    }

    func testPublicAnyViewErasedRowRetainedRemovalDrainsForkedAnimatableCompletionsBeforeDisappear() throws {
        try assertPublicRootRetainedRemovalDrainsForkedAnimatableCompletionsBeforeDisappear {
            rows, target, recorder, capture in
            ForEach(rows, id: \.self) { row in
                AnyView(
                    DynamicContainerForkRetargetRow(
                        row: row,
                        effect: _OpacityEffect(opacity: row == "row" ? target : 0),
                        recorder: recorder,
                        capture: capture
                    )
                )
                .transition(.opacity)
            }
        }
    }

    func testPublicAnyLayoutVStackForEachRetainsTransitionRemovalUntilListenerInvalidatesRule() throws {
        try assertPublicLayoutRootRetainsTransitionRemovalUntilListenerInvalidatesRule { rows, recorder in
            AnyLayout(VStackLayout(spacing: 8)) {
                ForEach(rows, id: \.self) { row in
                    DynamicContainerLifecycleRow(row: row, recorder: recorder)
                        .transition(.opacity)
                }
            }
        }
    }

    func testPublicAnyLayoutVStackForEachRetainedRemovalDrainsForkedAnimatableCompletionsBeforeDisappear() throws {
        try assertPublicLayoutRootRetainedRemovalDrainsForkedAnimatableCompletionsBeforeDisappear {
            rows, target, recorder, capture in
            AnyLayout(VStackLayout(spacing: 8)) {
                ForEach(rows, id: \.self) { row in
                    DynamicContainerForkRetargetRow(
                        row: row,
                        effect: _OpacityEffect(opacity: row == "row" ? target : 0),
                        recorder: recorder,
                        capture: capture
                    )
                    .transition(.opacity)
                }
            }
        }
    }

    func testPublicStandaloneSectionForEachRetainedRemovalDrainsForkedAnimatableCompletionsBeforeDisappear() throws {
        try assertPublicLayoutRootRetainedRemovalDrainsForkedAnimatableCompletionsBeforeDisappear {
            rows, target, recorder, capture in
            Section {
                ForEach(rows, id: \.self) { row in
                    DynamicContainerForkRetargetRow(
                        row: row,
                        effect: _OpacityEffect(opacity: row == "row" ? target : 0),
                        recorder: recorder,
                        capture: capture
                    )
                    .transition(.opacity)
                }
            } header: {
                Text("Header")
            }
        }
    }

    // ASSERTIONS formSectionForkRetainedRemoval27Observed
    func testPublicFormSectionForEachRetainedRemovalDrainsForkedAnimatableCompletionsBeforeDisappear() throws {
        try assertPublicLayoutRootRetainedRemovalDrainsForkedAnimatableCompletionsBeforeDisappear {
            rows, target, recorder, capture in
            Form {
                Section {
                    ForEach(rows, id: \.self) { row in
                        DynamicContainerForkRetargetRow(
                            row: row,
                            effect: _OpacityEffect(
                                opacity: row == "row" ? target : 0
                            ),
                            recorder: recorder,
                            capture: capture
                        )
                        .transition(.opacity)
                    }
                } header: {
                    Text("Header")
                }
            }
        }
    }

    // ASSERTIONS disclosureGroupForkRetainedRemovalObserved
    func testPublicDisclosureGroupForEachRetainedRemovalDrainsForkedAnimatableCompletionsBeforeDisappear() throws {
        try assertPublicLayoutRootRetainedRemovalDrainsForkedAnimatableCompletionsBeforeDisappear {
            rows, target, recorder, capture in
            DisclosureGroup(isExpanded: .constant(true)) {
                ForEach(rows, id: \.self) { row in
                    DynamicContainerForkRetargetRow(
                        row: row,
                        effect: _OpacityEffect(
                            opacity: row == "row" ? target : 0
                        ),
                        recorder: recorder,
                        capture: capture
                    )
                    .transition(.opacity)
                }
            } label: {
                Text("Details")
            }
        }
    }

    func testPublicCustomLayoutForEachRetainedRemovalDrainsForkedAnimatableCompletionsBeforeDisappear() throws {
        try assertPublicLayoutRootRetainedRemovalDrainsForkedAnimatableCompletionsBeforeDisappear {
            rows, target, recorder, capture in
            DynamicContainerProbeVStackLayout(spacing: 8) {
                ForEach(rows, id: \.self) { row in
                    DynamicContainerForkRetargetRow(
                        row: row,
                        effect: _OpacityEffect(opacity: row == "row" ? target : 0),
                        recorder: recorder,
                        capture: capture
                    )
                    .transition(.opacity)
                }
            }
        }
    }

    func testPublicScrollViewVStackForEachRetainsTransitionRemovalUntilListenerInvalidatesRule() throws {
        try assertPublicLayoutRootRetainsTransitionRemovalUntilListenerInvalidatesRule { rows, recorder in
            ScrollView {
                VStack {
                    ForEach(rows, id: \.self) { row in
                        DynamicContainerLifecycleRow(row: row, recorder: recorder)
                            .transition(.opacity)
                    }
                }
                .frame(height: 100)
            }
        }
    }

    func testPublicScrollViewVStackForEachRetainedRemovalDrainsForkedAnimatableCompletionsBeforeDisappear() throws {
        try assertPublicLayoutRootRetainedRemovalDrainsForkedAnimatableCompletionsBeforeDisappear {
            rows, target, recorder, capture in
            ScrollView {
                VStack {
                    ForEach(rows, id: \.self) { row in
                        DynamicContainerForkRetargetRow(
                            row: row,
                            effect: _OpacityEffect(opacity: row == "row" ? target : 0),
                            recorder: recorder,
                            capture: capture
                        )
                        .transition(.opacity)
                    }
                }
                .frame(height: 100)
            }
        }
    }

    func testPublicLazyVStackForEachRetainedRemovalDrainsDisappearBeforeForkedAnimatableCompletions() throws {
        // ASSERTIONS lazyInitialPhaseSettlementObserved
        try assertPublicLayoutRootRetainedRemovalDrainsForkedAnimatableCompletionsBeforeDisappear(
            disappearBeforeRetainedCompletions: true
        ) { rows, target, recorder, capture in
            ScrollView {
                LazyVStack {
                    ForEach(rows, id: \.self) { row in
                        DynamicContainerForkRetargetRow(
                            row: row,
                            effect: _OpacityEffect(opacity: row == "row" ? target : 0),
                            recorder: recorder,
                            capture: capture
                        )
                        .transition(.opacity)
                    }
                }
            }
        }
    }

    func testPublicLazyHStackForEachRetainedRemovalDrainsDisappearBeforeForkedAnimatableCompletions() throws {
        // ASSERTIONS lazyInitialPhaseSettlementObserved
        try assertPublicLayoutRootRetainedRemovalDrainsForkedAnimatableCompletionsBeforeDisappear(
            disappearBeforeRetainedCompletions: true
        ) { rows, target, recorder, capture in
            ScrollView(.horizontal) {
                LazyHStack {
                    ForEach(rows, id: \.self) { row in
                        DynamicContainerForkRetargetRow(
                            row: row,
                            effect: _OpacityEffect(opacity: row == "row" ? target : 0),
                            recorder: recorder,
                            capture: capture
                        )
                        .transition(.opacity)
                    }
                }
            }
        }
    }

    func testPublicLazyVGridForEachRetainedRemovalDrainsDisappearBeforeForkedAnimatableCompletions() throws {
        // ASSERTIONS lazyInitialPhaseSettlementObserved
        try assertPublicLayoutRootRetainedRemovalDrainsForkedAnimatableCompletionsBeforeDisappear(
            disappearBeforeRetainedCompletions: true
        ) { rows, target, recorder, capture in
            ScrollView {
                LazyVGrid(columns: [GridItem(.fixed(44))]) {
                    ForEach(rows, id: \.self) { row in
                        DynamicContainerForkRetargetRow(
                            row: row,
                            effect: _OpacityEffect(opacity: row == "row" ? target : 0),
                            recorder: recorder,
                            capture: capture
                        )
                        .transition(.opacity)
                    }
                }
            }
        }
    }

    func testPublicLazyHGridForEachRetainedRemovalDrainsDisappearBeforeForkedAnimatableCompletions() throws {
        // ASSERTIONS lazyInitialPhaseSettlementObserved
        try assertPublicLayoutRootRetainedRemovalDrainsForkedAnimatableCompletionsBeforeDisappear(
            disappearBeforeRetainedCompletions: true
        ) { rows, target, recorder, capture in
            ScrollView(.horizontal) {
                LazyHGrid(rows: [GridItem(.fixed(44))]) {
                    ForEach(rows, id: \.self) { row in
                        DynamicContainerForkRetargetRow(
                            row: row,
                            effect: _OpacityEffect(opacity: row == "row" ? target : 0),
                            recorder: recorder,
                            capture: capture
                        )
                        .transition(.opacity)
                    }
                }
            }
        }
    }

    func testPublicVStackForEachRetainsTransitionRemovalUntilListenerInvalidatesRule() throws {
        try assertPublicLayoutRootRetainsTransitionRemovalUntilListenerInvalidatesRule { rows, recorder in
            VStack {
                ForEach(rows, id: \.self) { row in
                    DynamicContainerLifecycleRow(row: row, recorder: recorder)
                        .transition(.opacity)
                }
            }
        }
    }

    func testPublicVStackForEachRetainedRemovalDrainsForkedAnimatableCompletionsBeforeDisappear() throws {
        try assertPublicLayoutRootRetainedRemovalDrainsForkedAnimatableCompletionsBeforeDisappear {
            rows, target, recorder, capture in
            VStack {
                ForEach(rows, id: \.self) { row in
                    DynamicContainerForkRetargetRow(
                        row: row,
                        effect: _OpacityEffect(opacity: row == "row" ? target : 0),
                        recorder: recorder,
                        capture: capture
                    )
                    .transition(.opacity)
                }
            }
        }
    }

    func testPublicHStackForEachRetainedRemovalDrainsForkedAnimatableCompletionsBeforeDisappear() throws {
        try assertPublicLayoutRootRetainedRemovalDrainsForkedAnimatableCompletionsBeforeDisappear {
            rows, target, recorder, capture in
            HStack {
                ForEach(rows, id: \.self) { row in
                    DynamicContainerForkRetargetRow(
                        row: row,
                        effect: _OpacityEffect(opacity: row == "row" ? target : 0),
                        recorder: recorder,
                        capture: capture
                    )
                    .transition(.opacity)
                }
            }
        }
    }

    func testPublicMixedVStackForEachRetainsTransitionRemovalUntilListenerInvalidatesRule() throws {
        try assertPublicLayoutRootRetainsTransitionRemovalUntilListenerInvalidatesRule { rows, recorder in
            VStack {
                Text("Header")
                ForEach(rows, id: \.self) { row in
                    DynamicContainerLifecycleRow(row: row, recorder: recorder)
                        .transition(.opacity)
                }
                Text("Footer")
            }
        }
    }

    func testPublicMixedVStackForEachRetainedRemovalDrainsForkedAnimatableCompletionsBeforeDisappear() throws {
        try assertPublicLayoutRootRetainedRemovalDrainsForkedAnimatableCompletionsBeforeDisappear {
            rows, target, recorder, capture in
            VStack {
                Text("Header")
                ForEach(rows, id: \.self) { row in
                    DynamicContainerForkRetargetRow(
                        row: row,
                        effect: _OpacityEffect(opacity: row == "row" ? target : 0),
                        recorder: recorder,
                        capture: capture
                    )
                    .transition(.opacity)
                }
                Text("Footer")
            }
        }
    }

    func testPublicTupleViewForEachRetainsTransitionRemovalUntilListenerInvalidatesRule() throws {
        try assertPublicLayoutRootRetainsTransitionRemovalUntilListenerInvalidatesRule { rows, recorder in
            TupleView((
                Text("Header"),
                ForEach(rows, id: \.self) { row in
                    DynamicContainerLifecycleRow(row: row, recorder: recorder)
                        .transition(.opacity)
                },
                Text("Footer")
            ))
        }
    }

    func testPublicTupleViewForEachRetainedRemovalDrainsForkedAnimatableCompletionsBeforeDisappear() throws {
        try assertPublicLayoutRootRetainedRemovalDrainsForkedAnimatableCompletionsBeforeDisappear {
            rows, target, recorder, capture in
            TupleView((
                Text("Header"),
                ForEach(rows, id: \.self) { row in
                    DynamicContainerForkRetargetRow(
                        row: row,
                        effect: _OpacityEffect(opacity: row == "row" ? target : 0),
                        recorder: recorder,
                        capture: capture
                    )
                    .transition(.opacity)
                },
                Text("Footer")
            ))
        }
    }

    func testPublicConditionalForEachRetainsTransitionRemovalUntilListenerInvalidatesRule() throws {
        try assertPublicLayoutRootRetainsTransitionRemovalUntilListenerInvalidatesRule { rows, recorder in
            DynamicContainerConditionalForEachRoot(rows: rows, recorder: recorder)
        }
    }

    func testPublicConditionalForEachRetainedRemovalDrainsForkedAnimatableCompletionsBeforeDisappear() throws {
        try assertPublicLayoutRootRetainedRemovalDrainsForkedAnimatableCompletionsBeforeDisappear {
            rows, target, recorder, capture in
            VStack {
                if rows != ["never"] {
                    ForEach(rows, id: \.self) { row in
                        DynamicContainerForkRetargetRow(
                            row: row,
                            effect: _OpacityEffect(opacity: row == "row" ? target : 0),
                            recorder: recorder,
                            capture: capture
                        )
                        .transition(.opacity)
                    }
                } else {
                    EmptyView()
                }
            }
        }
    }

    func testPublicConditionalForEachSwitchToEmptyDrainsForkedAnimatableCompletionsBeforeDisappear() throws {
        try assertPublicLayoutRootRetainedRemovalDrainsForkedAnimatableCompletionsBeforeDisappear {
            rows, target, recorder, capture in
            VStack {
                if !rows.isEmpty {
                    ForEach(rows, id: \.self) { row in
                        DynamicContainerForkRetargetRow(
                            row: row,
                            effect: _OpacityEffect(opacity: row == "row" ? target : 0),
                            recorder: recorder,
                            capture: capture
                        )
                        .transition(.opacity)
                    }
                } else {
                    EmptyView()
                }
            }
        }
    }

    func testPublicConditionalStaticBranchRetainsTransitionRemovalUntilListenerInvalidatesRule() throws {
        try assertPublicLayoutRootRetainsTransitionRemovalUntilListenerInvalidatesRule { rows, recorder in
            VStack {
                if let row = rows.first {
                    DynamicContainerLifecycleRow(row: row, recorder: recorder)
                        .transition(.opacity)
                } else {
                    Text("empty")
                }
            }
        }
    }

    func testPublicConditionalStaticBranchInsertionAppliesWillAppearThenIdentity() throws {
        let rendererHost = TestViewRendererHost()
        let viewGraph = ViewGraph(
            rootViewType: EmptyView.self,
            content: EmptyView(),
            rendererHost: rendererHost
        )
        rendererHost.storage = viewGraph
        let graph = viewGraph.data.graph
        let lifecycleRecorder = DynamicContainerLifecycleRecorder()
        let phaseRecorder = DynamicContainerTransitionPhaseRecorder()
        var source: Attribute<DynamicContainerConditionalTransitionRoot>!
        var layoutAttr: Attribute<LayoutComputer>!

        func root(showChild: Bool) -> DynamicContainerConditionalTransitionRoot {
            DynamicContainerConditionalTransitionRoot(
                showChild: showChild,
                lifecycleRecorder: lifecycleRecorder,
                phaseRecorder: phaseRecorder
            )
        }

        func sampleLayout() {
            _ = layoutAttr.value.sizeThatFits(.unspecified)
        }

        try viewGraph.data.withCurrent {
            let inputs = makeGraphInputs(graph: graph, transaction: Transaction())
            source = graph.makeInput(value: root(showChild: false))
            let outputs = DynamicContainerConditionalTransitionRoot._makeView(
                view: _GraphValue(_attribute: source),
                inputs: makeViewInputs(graph: graph, base: inputs)
            )
            layoutAttr = try XCTUnwrap(outputs._layoutComputer.attribute)
            sampleLayout()
            XCTAssertEqual(phaseRecorder.events, [])
            XCTAssertEqual(lifecycleRecorder.events, [])
        }

        viewGraph.data.withCurrent {
            var insertion = Transaction(animation: .linear(duration: 0.02))
            insertion.animationFrameInterval = 1.0 / 120.0
            source.setValue(root(showChild: true), transaction: insertion)
            sampleLayout()
            graph.inbox.drain()
        }
        viewGraph.flushTransactions()
        viewGraph.data.withCurrent {
            sampleLayout()

            XCTAssertEqual(phaseRecorder.events, ["willAppear", "identity"])
            XCTAssertEqual(lifecycleRecorder.events, ["row appear"])
        }
    }

    func testPublicConditionalStaticBranchInsertionPromotesTransactionBeforeIdentity() throws {
        let rendererHost = TestViewRendererHost()
        let viewGraph = ViewGraph(
            rootViewType: EmptyView.self,
            content: EmptyView(),
            rendererHost: rendererHost
        )
        rendererHost.storage = viewGraph
        let graph = viewGraph.data.graph
        let capture = DynamicContainerTransitionValueCapture()
        var graphInputs: _GraphInputs!
        var source: Attribute<DynamicContainerAsymmetricInsertionValueTransitionRoot>!
        var layoutAttr: Attribute<LayoutComputer>!
        var displayOutput: Attribute<DisplayList>!

        func root(showChild: Bool) -> DynamicContainerAsymmetricInsertionValueTransitionRoot {
            DynamicContainerAsymmetricInsertionValueTransitionRoot(
                showChild: showChild,
                capture: capture
            )
        }

        func sampleOutputs() {
            _ = layoutAttr.value.sizeThatFits(.unspecified)
            _ = displayOutput.value
        }

        try viewGraph.data.withCurrent {
            graphInputs = makeGraphInputs(graph: graph, transaction: Transaction())
            source = graph.makeInput(value: root(showChild: false))
            var keys = PreferenceKeys()
            keys.add(DisplayList.Key.self)
            let outputs = DynamicContainerAsymmetricInsertionValueTransitionRoot._makeView(
                view: _GraphValue(_attribute: source),
                inputs: makeViewInputs(
                    graph: graph,
                    base: graphInputs,
                    preferenceKeys: keys
                )
            )
            layoutAttr = try XCTUnwrap(outputs._layoutComputer.attribute)
            displayOutput = Attribute<DisplayList>(
                try XCTUnwrap(outputs.preferences.value(for: DisplayList.Key.self))
            )
            sampleOutputs()
            XCTAssertNil(capture.source)
        }

        try viewGraph.data.withCurrent {
            var insertion = Transaction(animation: .linear(duration: 1))
            insertion.animationFrameInterval = 1.0 / 120.0
            viewGraph.runTransaction(
                insertion,
                do: {
                    graphInputs.transaction.setValue(insertion)
                    source.setValue(root(showChild: true), transaction: insertion)
                    sampleOutputs()
                },
                id: nil
            )
            sampleOutputs()

            let identitySource = try XCTUnwrap(capture.source)
            XCTAssertEqual(identitySource.value.value, 1, accuracy: 0.000_001)
            XCTAssertNotNil(
                graph.transaction(for: identitySource.identifier)?.effectiveAnimation
            )
            let animated = try XCTUnwrap(capture.animated)
            XCTAssertEqual(animated.value.value, 0, accuracy: 0.000_001)

            graphInputs.time.setValue(Time(seconds: 1.0 / 60.0))
            sampleOutputs()
            _ = animated.value
            graphInputs.time.setValue(Time(seconds: 2.0 / 60.0))
            sampleOutputs()
            _ = animated.value
            graphInputs.time.setValue(Time(seconds: 0.5))
            sampleOutputs()
            XCTAssertEqual(animated.value.value, 0.5, accuracy: 0.06)
            // ASSERTIONS contentTransitionInsertionPhasePromotionRuntimeObserved
            // ASSERTIONS contentTransitionInsertionSameTransactionContinuationObserved
            // ASSERTIONS dynamicContainerInsertionPhasePromotionObserved
            // ASSERTIONS dynamicContainerInsertionContinuationDisassemblyObserved
        }
    }

    func testPublicConditionalReplacementAppliesDefaultTransitionToUnmodifiedBranch() throws {
        typealias Root = _ConditionalContent<Text, Text>
        let rendererHost = TestViewRendererHost()
        let viewGraph = ViewGraph(
            rootViewType: EmptyView.self,
            content: EmptyView(),
            rendererHost: rendererHost
        )
        rendererHost.storage = viewGraph
        let graph = viewGraph.data.graph
        var source: Attribute<Root>!
        var infoAttr: Attribute<DynamicContainer.Info>!

        func root(showChild: Bool) -> Root {
            if showChild {
                return ViewBuilder.buildEither(first: Text("child"))
            } else {
                return ViewBuilder.buildEither(second: Text("empty"))
            }
        }

        viewGraph.data.withCurrent {
            AGSubgraph.withCurrent(viewGraph.data.rootSubgraph) {
                let inputs = makeGraphInputs(graph: graph, transaction: Transaction())
                let viewInputs = makeViewInputs(graph: graph, base: inputs)
                source = graph.makeInput(value: root(showChild: true))
                let outputs = Root._makeViewList(
                    view: _GraphValue(_attribute: source),
                    inputs: _ViewListInputs(from: viewInputs)
                )
                guard case .dynamicList(let viewListAttr, _) = outputs.views else {
                    XCTFail("conditional replacement should produce a dynamic list")
                    return
                }
                infoAttr = graph.makeStatefulRule(
                    DynamicContainerInfo(
                        viewListAttr: viewListAttr,
                        inputs: viewInputs
                    )
                )

                let initial = infoAttr.value
                XCTAssertEqual(initial.activeItems.count, 1)
                XCTAssertEqual(initial.activeItems.first?.phase, .identity)
            }
        }

        try viewGraph.data.withCurrent {
            let replacement = Transaction(animation: .linear(duration: 1))
            source.setValue(root(showChild: false), transaction: replacement)

            let updated = infoAttr.value
            XCTAssertEqual(updated.activeItems.count, 1)
            XCTAssertEqual(updated.removedCount, 1)
            let inserted = try XCTUnwrap(updated.activeItems.first)
            XCTAssertTrue(inserted.needsTransitions)
            XCTAssertEqual(inserted.phase, .willAppear)
            let removed = try XCTUnwrap(updated.activeAndRemovedItems.last)
            XCTAssertEqual(inserted.precedingViewCount, 0)
            XCTAssertEqual(
                removed.precedingViewCount,
                inserted.viewCount
            )
        }
    }

    func testPublicConditionalActiveBranchPublishesNestedDynamicListChanges() throws {
        typealias Rows = ForEach<[String], String, Text>
        typealias Root = _ConditionalContent<Rows, EmptyView>
        let graphFixture = DynamicContainerViewGraphFixture()
        let graphHost = graphFixture.viewGraph
        let graph = graphHost.data.graph
        let ref = _AGGraphContext(graph: graph)
        var source: Attribute<Root>!
        var list: Attribute<any ViewList>!
        var info: Attribute<DynamicContainer.Info>!

        func root(_ rows: [String]) -> Root {
            ViewBuilder.buildEither(
                first: ForEach(rows, id: \.self) { Text($0) }
            )
        }

        ref.withCurrent {
            let inputs = makeGraphInputs(graph: graph, transaction: Transaction())
            let viewInputs = makeViewInputs(graph: graph, base: inputs)
            source = graph.makeInput(value: root(["row"]))
            let outputs = Root._makeViewList(
                view: _GraphValue(_attribute: source),
                inputs: _ViewListInputs(from: viewInputs)
            )
            guard case .dynamicList(let attribute, _) = outputs.views else {
                return XCTFail("conditional should publish a dynamic list")
            }
            list = attribute
            info = graph.makeStatefulRule(
                DynamicContainerInfo(viewListAttr: attribute, inputs: viewInputs)
            )
            XCTAssertEqual(list.value.count(style: _ViewList_IteratorStyle()), 1)
            XCTAssertEqual(info.value.activeItems.count, 1)

            source.setValue(root([]))

            XCTAssertEqual(list.value.count(style: _ViewList_IteratorStyle()), 0)
            XCTAssertEqual(info.value.activeItems.count, 0)
        }
    }

    func testDynamicContainerInfoDoesNotTrackInheritedTransaction() throws {
        typealias Rows = ForEach<[String], String, Text>
        typealias Root = _ConditionalContent<Rows, EmptyView>
        let graphFixture = DynamicContainerViewGraphFixture()
        let graphHost = graphFixture.viewGraph
        let graph = graphHost.data.graph
        let ref = _AGGraphContext(graph: graph)

        try ref.withCurrent {
            let graphInputs = makeGraphInputs(
                graph: graph,
                transaction: Transaction(animation: .linear(duration: 1))
            )
            let viewInputs = makeViewInputs(graph: graph, base: graphInputs)
            let source = graph.makeInput(
                value: ViewBuilder.buildEither(
                    first: ForEach(["row"], id: \.self) { Text($0) }
                ) as Root
            )
            let outputs = Root._makeViewList(
                view: _GraphValue(_attribute: source),
                inputs: _ViewListInputs(from: viewInputs)
            )
            let viewList = try XCTUnwrap({
                if case .dynamicList(let attribute, _) = outputs.views {
                    return attribute
                }
                return nil
            }())
            let info = graph.makeStatefulRule(
                DynamicContainerInfo(
                    viewListAttr: viewList,
                    inputs: viewInputs
                )
            )

            _ = info.value

            let node = try XCTUnwrap(
                graph.slots[Int(info.identifier.rawValue)].node
            )
            let inputIdentifiers = Set(node.pointee.inputs.map(\.attribute))
            XCTAssertTrue(
                inputIdentifiers.contains(viewList.identifier.rawValue)
            )
            XCTAssertTrue(
                inputIdentifiers.contains(
                    viewInputs.base.phase.identifier.rawValue
                )
            )
            XCTAssertFalse(
                inputIdentifiers.contains(
                    viewInputs.base.transaction.identifier.rawValue
                )
            )
        }
    }

    func testPublicConditionalReinsertionReusesRetainedBranchItem() throws {
        typealias Root = _ConditionalContent<Text, Text>
        let rendererHost = TestViewRendererHost()
        let viewGraph = ViewGraph(
            rootViewType: EmptyView.self,
            content: EmptyView(),
            rendererHost: rendererHost
        )
        rendererHost.storage = viewGraph
        let graph = viewGraph.data.graph
        var source: Attribute<Root>!
        var infoAttr: Attribute<DynamicContainer.Info>!

        func root(showChild: Bool) -> Root {
            if showChild {
                return ViewBuilder.buildEither(first: Text("child"))
            } else {
                return ViewBuilder.buildEither(second: Text("empty"))
            }
        }

        let initialItem = try viewGraph.data.withCurrent {
            try AGSubgraph.withCurrent(viewGraph.data.rootSubgraph) {
                let inputs = makeGraphInputs(graph: graph, transaction: Transaction())
                let viewInputs = makeViewInputs(graph: graph, base: inputs)
                source = graph.makeInput(value: root(showChild: true))
                let outputs = Root._makeViewList(
                    view: _GraphValue(_attribute: source),
                    inputs: _ViewListInputs(from: viewInputs)
                )
                let viewListAttr = try XCTUnwrap({
                    if case .dynamicList(let attribute, _) = outputs.views {
                        return attribute
                    }
                    return nil
                }(), "conditional replacement should produce a dynamic list")
                infoAttr = graph.makeStatefulRule(
                    DynamicContainerInfo(
                        viewListAttr: viewListAttr,
                        inputs: viewInputs
                    )
                )

                let initial = infoAttr.value
                XCTAssertEqual(initial.activeItems.count, 1)
                let item = try XCTUnwrap(initial.activeItems.first)
                // ASSERTIONS dynamicLayoutStateOwnershipObserved
                XCTAssertEqual(item.uniqueId, 1)
                return item
            }
        }

        viewGraph.data.withCurrent {
            let replacement = Transaction(animation: .linear(duration: 5))
            source.setValue(root(showChild: false), transaction: replacement)

            let removedTrueBranch = infoAttr.value
            XCTAssertEqual(removedTrueBranch.activeItems.count, 1)
            XCTAssertEqual(removedTrueBranch.removedCount, 1)
            XCTAssertEqual(removedTrueBranch.activeItems.first?.uniqueId, 2)
            XCTAssertTrue(removedTrueBranch.items.last === initialItem)

            source.setValue(root(showChild: true), transaction: replacement)

            // ASSERTIONS contentTransitionMidflightReinsertUnremoveObserved
            let reinserted = infoAttr.value
            XCTAssertEqual(reinserted.activeItems.count, 1)
            XCTAssertEqual(reinserted.removedCount, 1)
            XCTAssertTrue(reinserted.activeItems.first === initialItem)
            XCTAssertEqual(reinserted.activeItems.first?.uniqueId, 1)
            XCTAssertEqual(
                Set(reinserted.items.map(\.uniqueId)).count,
                reinserted.items.count,
                "reinsertion must not leave an older item with the same conditional branch identity"
            )
        }
    }

    func testPublicConditionalStaticBranchRemovalInterpolatesTransitionValue() throws {
        let rendererHost = TestViewRendererHost()
        let viewGraph = ViewGraph(
            rootViewType: EmptyView.self,
            content: EmptyView(),
            rendererHost: rendererHost
        )
        rendererHost.storage = viewGraph
        let graph = viewGraph.data.graph
        let capture = DynamicContainerTransitionValueCapture()
        var graphInputs: _GraphInputs!
        var source: Attribute<DynamicContainerConditionalValueTransitionRoot>!
        var layoutAttr: Attribute<LayoutComputer>!
        var displayOutput: Attribute<DisplayList>!
        var initialSourceID: AGAttribute!
        var initialAnimatedID: AGAttribute!

        func root(showChild: Bool) -> DynamicContainerConditionalValueTransitionRoot {
            DynamicContainerConditionalValueTransitionRoot(
                showChild: showChild,
                capture: capture
            )
        }

        func sampleLayout() {
            _ = layoutAttr.value.sizeThatFits(.unspecified)
        }

        try viewGraph.data.withCurrent {
            graphInputs = makeGraphInputs(graph: graph, transaction: Transaction())
            source = graph.makeInput(value: root(showChild: true))
            var keys = PreferenceKeys()
            keys.add(DisplayList.Key.self)
            let outputs = DynamicContainerConditionalValueTransitionRoot._makeView(
                view: _GraphValue(_attribute: source),
                inputs: makeViewInputs(
                    graph: graph,
                    base: graphInputs,
                    preferenceKeys: keys
                )
            )
            layoutAttr = try XCTUnwrap(outputs._layoutComputer.attribute)
            displayOutput = Attribute<DisplayList>(
                try XCTUnwrap(outputs.preferences.value(for: DisplayList.Key.self))
            )
            sampleLayout()
            _ = displayOutput.value
            let initialSource = try XCTUnwrap(capture.source)
            let initialAnimated = try XCTUnwrap(capture.animated)
            initialSourceID = initialSource.identifier
            initialAnimatedID = initialAnimated.identifier
            XCTAssertEqual(initialSource.value.value, 1, accuracy: 0.000_001)
            XCTAssertEqual(initialAnimated.value.value, 1, accuracy: 0.000_001)
        }

        try viewGraph.data.withCurrent {
            var removal = Transaction(animation: .linear(duration: 1))
            removal.animationFrameInterval = 1.0 / 120.0
            graphInputs.transaction.setValue(removal)
            source.setValue(root(showChild: false), transaction: removal)
            sampleLayout()
            _ = displayOutput.value
            let retainedSource = try XCTUnwrap(capture.source)
            XCTAssertEqual(retainedSource.identifier, initialSourceID)
            XCTAssertEqual(retainedSource.value.value, 0, accuracy: 0.000_001)
            XCTAssertNotNil(
                graph.transaction(for: retainedSource.identifier)?.effectiveAnimation
            )
            let retainedValue = try XCTUnwrap(capture.animated)
            XCTAssertEqual(retainedValue.identifier, initialAnimatedID)
            XCTAssertEqual(retainedValue.value.value, 1, accuracy: 0.000_001)

            graphInputs.time.setValue(Time(seconds: 1.0 / 60.0))
            _ = displayOutput.value
            _ = retainedValue.value
            graphInputs.time.setValue(Time(seconds: 2.0 / 60.0))
            _ = displayOutput.value
            _ = retainedValue.value
            graphInputs.time.setValue(Time(seconds: 0.5))
            sampleLayout()
            _ = displayOutput.value
            XCTAssertEqual(retainedSource.value.value, 0, accuracy: 0.000_001)
            XCTAssertEqual(retainedValue.value.value, 0.53, accuracy: 0.06)
        }
    }

    func testPublicZStackOptionalAsymmetricRemovalInterpolatesRemovalBranch() throws {
        let rendererHost = TestViewRendererHost()
        let viewGraph = ViewGraph(
            rootViewType: EmptyView.self,
            content: EmptyView(),
            rendererHost: rendererHost
        )
        rendererHost.storage = viewGraph
        let graph = viewGraph.data.graph
        let capture = DynamicContainerTransitionValueCapture()
        var graphInputs: _GraphInputs!
        var source: Attribute<DynamicContainerZStackAsymmetricTransitionRoot>!
        var layoutAttr: Attribute<LayoutComputer>!
        var displayOutput: Attribute<DisplayList>!
        var initialAnimatedID: AGAttribute!

        func root(showChild: Bool) -> DynamicContainerZStackAsymmetricTransitionRoot {
            DynamicContainerZStackAsymmetricTransitionRoot(
                showChild: showChild,
                capture: capture
            )
        }

        func sampleOutputs() {
            _ = layoutAttr.value.sizeThatFits(.unspecified)
            _ = displayOutput.value
        }

        try viewGraph.data.withCurrent {
            graphInputs = makeGraphInputs(graph: graph, transaction: Transaction())
            source = graph.makeInput(value: root(showChild: true))
            var keys = PreferenceKeys()
            keys.add(DisplayList.Key.self)
            let outputs = DynamicContainerZStackAsymmetricTransitionRoot._makeView(
                view: _GraphValue(_attribute: source),
                inputs: makeViewInputs(
                    graph: graph,
                    base: graphInputs,
                    preferenceKeys: keys
                )
            )
            layoutAttr = try XCTUnwrap(outputs._layoutComputer.attribute)
            displayOutput = Attribute<DisplayList>(
                try XCTUnwrap(outputs.preferences.value(for: DisplayList.Key.self))
            )
            sampleOutputs()
            let initialSource = try XCTUnwrap(capture.source)
            let initialAnimated = try XCTUnwrap(capture.animated)
            initialAnimatedID = initialAnimated.identifier
            XCTAssertEqual(initialSource.value.value, 1, accuracy: 0.000_001)
            XCTAssertEqual(initialAnimated.value.value, 1, accuracy: 0.000_001)
        }

        try Update.ensure {
            try viewGraph.data.withCurrent {
                var removal = Transaction(animation: .linear(duration: 1))
                removal.animationFrameInterval = 1.0 / 120.0
                graphInputs.transaction.setValue(removal)
                source.setValue(root(showChild: false), transaction: removal)
                sampleOutputs()
                let retainedSource = try XCTUnwrap(capture.source)
                let retainedValue = try XCTUnwrap(capture.animated)
                XCTAssertEqual(retainedSource.value.value, 0, accuracy: 0.000_001)
                XCTAssertEqual(retainedValue.identifier, initialAnimatedID)
                XCTAssertEqual(retainedValue.value.value, 1, accuracy: 0.000_001)

                graphInputs.time.setValue(Time(seconds: 1.0 / 60.0))
                sampleOutputs()
                _ = retainedValue.value
                graphInputs.time.setValue(Time(seconds: 2.0 / 60.0))
                sampleOutputs()
                _ = retainedValue.value
                graphInputs.time.setValue(Time(seconds: 0.5))
                sampleOutputs()
                XCTAssertEqual(retainedValue.value.value, 0.53, accuracy: 0.06)
            }
        }
    }

    func testPublicOptionalForEachRetainsTransitionRemovalUntilListenerInvalidatesRule() throws {
        try assertPublicLayoutRootRetainsTransitionRemovalUntilListenerInvalidatesRule { rows, recorder in
            DynamicContainerOptionalForEachRoot(rows: rows, recorder: recorder)
        }
    }

    func testPublicOptionalForEachRetainedRemovalDrainsForkedAnimatableCompletionsBeforeDisappear() throws {
        try assertPublicLayoutRootRetainedRemovalDrainsForkedAnimatableCompletionsBeforeDisappear {
            rows, target, recorder, capture in
            DynamicContainerOptionalForkRetargetRoot(
                rows: rows,
                target: target,
                recorder: recorder,
                capture: capture
            )
        }
    }

    func testPublicOptionalForEachSwitchToNilDrainsForkedAnimatableCompletionsBeforeDisappear() throws {
        try assertPublicLayoutRootRetainedRemovalDrainsForkedAnimatableCompletionsBeforeDisappear {
            rows, target, recorder, capture in
            DynamicContainerOptionalForkRetargetRoot(
                rows: ["row"],
                target: target,
                recorder: recorder,
                capture: capture,
                showRows: !rows.isEmpty
            )
        }
    }

    func testPublicHStackForEachRetainsTransitionRemovalUntilListenerInvalidatesRule() throws {
        try assertPublicLayoutRootRetainsTransitionRemovalUntilListenerInvalidatesRule { rows, recorder in
            HStack {
                ForEach(rows, id: \.self) { row in
                    DynamicContainerLifecycleRow(row: row, recorder: recorder)
                        .transition(.opacity)
                }
            }
        }
    }

    func testPublicZStackForEachRetainsTransitionRemovalUntilListenerInvalidatesRule() throws {
        try assertPublicLayoutRootRetainsTransitionRemovalUntilListenerInvalidatesRule { rows, recorder in
            ZStack {
                ForEach(rows, id: \.self) { row in
                    DynamicContainerLifecycleRow(row: row, recorder: recorder)
                        .transition(.opacity)
                }
            }
        }
    }

    func testPublicZStackForEachRetainedRemovalDrainsForkedAnimatableCompletionsBeforeDisappear() throws {
        try assertPublicLayoutRootRetainedRemovalDrainsForkedAnimatableCompletionsBeforeDisappear {
            rows, target, recorder, capture in
            ZStack {
                ForEach(rows, id: \.self) { row in
                    DynamicContainerForkRetargetRow(
                        row: row,
                        effect: _OpacityEffect(opacity: row == "row" ? target : 0),
                        recorder: recorder,
                        capture: capture
                    )
                    .transition(.opacity)
                }
            }
        }
    }

    func testPublicViewThatFitsSelectedVStackForEachRetainsTransitionRemovalUntilListenerInvalidatesRule() throws {
        try assertPublicLayoutRootRetainsTransitionRemovalUntilListenerInvalidatesRule { rows, recorder in
            ViewThatFits(in: [.horizontal, .vertical]) {
                VStack {
                    ForEach(rows, id: \.self) { row in
                        DynamicContainerLifecycleRow(row: row, recorder: recorder)
                            .transition(.opacity)
                    }
                }
            }
        }
    }

    func testPublicViewThatFitsSelectedVStackForEachRetainedRemovalDrainsForkedAnimatableCompletionsBeforeDisappear() throws {
        try assertPublicLayoutRootRetainedRemovalDrainsForkedAnimatableCompletionsBeforeDisappear {
            rows, target, recorder, capture in
            ViewThatFits(in: [.horizontal, .vertical]) {
                VStack {
                    ForEach(rows, id: \.self) { row in
                        DynamicContainerForkRetargetRow(
                            row: row,
                            effect: _OpacityEffect(opacity: row == "row" ? target : 0),
                            recorder: recorder,
                            capture: capture
                        )
                        .transition(.opacity)
                    }
                }
            }
        }
    }

    func testPublicViewThatFitsFallbackSwitchQueuesSelectedDisappearAndFallbackAppear() throws {
        let graphFixture = DynamicContainerViewGraphFixture()
        let graphHost = graphFixture.viewGraph
        let graph = graphHost.data.graph
        let ref = _AGGraphContext(graph: graph)
        let recorder = DynamicContainerLifecycleRecorder()
        var source: Attribute<DynamicContainerViewThatFitsFallbackRoot>!
        var layoutAttr: Attribute<LayoutComputer>!
        var selectionAttr: Attribute<Int>!

        ref.withCurrent {
            AGSubgraph.withCurrent(graphHost.data.rootSubgraph) {
                let inputs = makeGraphInputs(graph: graph, transaction: Transaction())
                var keys = PreferenceKeys()
                keys.add(DynamicContainerViewThatFitsSelectionKey.self)
                let viewInputs = makeViewInputs(
                    graph: graph,
                    base: inputs,
                    preferenceKeys: keys
                )
                viewInputs.size.setValue(
                    ViewSize(
                        width: 20,
                        height: 20,
                        proposal: _ProposedSize(width: 20, height: 20)
                    )
                )
                source = graph.makeInput(
                    value: DynamicContainerViewThatFitsFallbackRoot(
                        primaryWidth: 10,
                        recorder: recorder
                    )
                )
                let outputs = DynamicContainerViewThatFitsFallbackRoot._makeView(
                    view: _GraphValue(_attribute: source),
                    inputs: viewInputs
                )
                guard let initialLayoutAttr = outputs._layoutComputer.attribute else {
                    XCTFail("ViewThatFits fallback root should produce a layout computer")
                    return
                }
                layoutAttr = initialLayoutAttr
                selectionAttr = Attribute<Int>(
                    try! XCTUnwrap(
                        outputs.preferences.value(
                            for: DynamicContainerViewThatFitsSelectionKey.self
                        )
                    )
                )

                _ = selectionAttr.value
                let layout = layoutAttr.value
                XCTAssertEqual(
                    layout.sizeThatFits(_ProposedSize(width: 20, height: 20)),
                    CGSize(width: 10, height: 10)
                )
                layout.place(
                    at: .zero,
                    anchor: .topLeading,
                    proposal: ProposedViewSize(width: 20, height: 20)
                )
                XCTAssertEqual(recorder.events, ["primary appear"])
            }
        }

        ref.withCurrent {
            source.setValue(
                DynamicContainerViewThatFitsFallbackRoot(
                    primaryWidth: 40,
                    recorder: recorder
                ),
                transaction: Transaction(animation: .linear(duration: 0.02))
            )

            _ = selectionAttr.value
            let layout = layoutAttr.value
            XCTAssertEqual(
                layout.sizeThatFits(_ProposedSize(width: 20, height: 20)),
                CGSize(width: 10, height: 10)
            )
            layout.place(
                at: .zero,
                anchor: .topLeading,
                proposal: ProposedViewSize(width: 20, height: 20)
            )
            XCTAssertEqual(
                recorder.events,
                ["primary appear", "primary disappear", "fallback appear"]
            )
        }
    }

    func testPublicStandaloneSectionForEachRetainsTransitionRemovalUntilListenerInvalidatesRule() throws {
        try assertPublicLayoutRootRetainsTransitionRemovalUntilListenerInvalidatesRule { rows, recorder in
            Section {
                ForEach(rows, id: \.self) { row in
                    DynamicContainerLifecycleRow(row: row, recorder: recorder)
                        .transition(.opacity)
                }
            } header: {
                Text("Header")
            }
        }
    }

    // ASSERTIONS disclosureGroupRetainedListenerOrderObserved
    func testPublicDisclosureGroupForEachRetainsTransitionRemovalUntilListenerInvalidatesRule() throws {
        try assertPublicLayoutRootRetainsTransitionRemovalUntilListenerInvalidatesRule {
            rows, recorder in
            DisclosureGroup(isExpanded: .constant(true)) {
                ForEach(rows, id: \.self) { row in
                    DynamicContainerLifecycleRow(
                        row: row,
                        recorder: recorder
                    )
                    .transition(.opacity)
                }
            } label: {
                Text("Details")
            }
        }
    }

    func testPublicCustomLayoutForEachRetainsTransitionRemovalUntilListenerInvalidatesRule() throws {
        try assertPublicLayoutRootRetainsTransitionRemovalUntilListenerInvalidatesRule { rows, recorder in
            DynamicContainerProbeVStackLayout(spacing: 8) {
                ForEach(rows, id: \.self) { row in
                    DynamicContainerLifecycleRow(row: row, recorder: recorder)
                        .transition(.opacity)
                }
            }
        }
    }

    func testPublicCustomLayoutMoveLayoutRetainedRemovalCollapsesSiblingLayoutSlot() throws {
        let rendererHost = TestViewRendererHost()
        let viewGraph = ViewGraph(
            rootViewType: EmptyView.self,
            content: EmptyView(),
            rendererHost: rendererHost
        )
        rendererHost.storage = viewGraph
        let graph = viewGraph.data.graph
        let recorder = DynamicContainerLifecycleRecorder()
        var source: Attribute<DynamicContainerMoveLayoutCustomLayoutRoot>!
        var layoutAttr: Attribute<LayoutComputer>!
        var removalEvents: [String] = []

        func childGeometries() -> [ViewGeometry] {
            layoutAttr.value.childGeometries(
                at: ViewSize(
                    CGSize(width: 190, height: 42),
                    proposal: _ProposedSize(width: 190, height: 42)
                ),
                origin: .zero
            )
        }

        viewGraph.data.withCurrent {
            AGSubgraph.withCurrent(viewGraph.data.rootSubgraph) {
                let inputs = makeGraphInputs(graph: graph, transaction: Transaction())
                let viewInputs = makeViewInputs(graph: graph, base: inputs)
                source = graph.makeInput(
                    value: DynamicContainerMoveLayoutCustomLayoutRoot(
                        rows: ["removed", "sibling"],
                        recorder: recorder
                    )
                )
                let outputs = DynamicContainerMoveLayoutCustomLayoutRoot._makeView(
                    view: _GraphValue(_attribute: source),
                    inputs: viewInputs
                )
                guard let initialLayoutAttr = outputs._layoutComputer.attribute else {
                    XCTFail("custom Layout root should produce a layout computer")
                    return
                }
                layoutAttr = initialLayoutAttr

                let initial = childGeometries()
                XCTAssertEqual(initial.count, 2)
                XCTAssertEqual(initial[0].origin.x, 0, accuracy: 0.000_001)
                XCTAssertEqual(initial[1].origin.x, 80, accuracy: 0.000_001)
                XCTAssertEqual(recorder.events, ["removed appear", "sibling appear"])
            }
        }

        viewGraph.data.withCurrent {
            var removal = Transaction(animation: .linear(duration: 0.02))
            removal.addAnimationCompletion(criteria: .removed) {
                removalEvents.append("removal removed")
            }
            source.setValue(
                DynamicContainerMoveLayoutCustomLayoutRoot(rows: ["sibling"], recorder: recorder),
                transaction: removal
            )

            let retained = childGeometries()
            XCTAssertEqual(retained.count, 1)
            XCTAssertEqual(retained[0].origin.x, 0, accuracy: 0.000_001)
            XCTAssertEqual(retained[0].dimensions.size.width, 80, accuracy: 0.000_001)
            XCTAssertEqual(removalEvents, [])
            XCTAssertEqual(recorder.events, ["removed appear", "sibling appear"])
        }

        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        XCTAssertEqual(removalEvents, ["removal removed"])
        XCTAssertEqual(recorder.events, ["removed appear", "sibling appear"])
        viewGraph.flushTransactions()

        viewGraph.data.withCurrent {
            graph.inbox.drain()
            _ = layoutAttr.value
            XCTAssertEqual(
                recorder.events,
                ["removed appear", "sibling appear", "removed disappear"]
            )
        }
    }

    private func assertPublicForEachRetainsTransitionRemovalUntilListenerInvalidatesRule<Content: View>(
        @ViewBuilder content: @escaping (String, DynamicContainerLifecycleRecorder) -> Content
    ) throws {
        try assertPublicRootRetainsTransitionRemovalUntilListenerInvalidatesRule { rows, recorder in
            ForEach(rows, id: \.self) { row in
                content(row, recorder)
            }
        }
    }

    private func assertPublicRootRetainsTransitionRemovalUntilListenerInvalidatesRule<Root: View>(
        @ViewBuilder makeRoot: @escaping ([String], DynamicContainerLifecycleRecorder) -> Root
    ) throws {
        let graphFixture = DynamicContainerViewGraphFixture()
        let graphHost = graphFixture.viewGraph
        let graph = graphHost.data.graph
        let ref = _AGGraphContext(graph: graph)
        let recorder = DynamicContainerLifecycleRecorder()
        var source: Attribute<Root>!
        var infoAttr: Attribute<DynamicContainer.Info>!
        var removalEvents: [String] = []

        ref.withCurrent {
            AGSubgraph.withCurrent(graphHost.data.rootSubgraph) {
                let inputs = makeGraphInputs(graph: graph, transaction: Transaction())
                let viewInputs = makeViewInputs(graph: graph, base: inputs)
                source = graph.makeInput(value: makeRoot(["row"], recorder))
                let outputs = Root._makeViewList(
                    view: _GraphValue(_attribute: source),
                    inputs: _ViewListInputs(from: viewInputs)
                )
                guard case .dynamicList(let viewListAttr, _) = outputs.views else {
                    XCTFail("\(Root.self) with transition ForEach should produce a dynamic list")
                    return
                }
                infoAttr = graph.makeStatefulRule(
                    DynamicContainerInfo(
                        viewListAttr: viewListAttr,
                        inputs: viewInputs
                    )
                )

                let initial = infoAttr.value
                XCTAssertEqual(initial.activeItems.count, 1)
                XCTAssertEqual(initial.removedCount, 0)
                XCTAssertEqual(initial.items.first?.phase, .identity)
                XCTAssertEqual(recorder.events, ["row appear"])
            }
        }

        let retainedItem = try ref.withCurrent {
            var removal = Transaction(animation: .linear(duration: 0.02))
            removal.addAnimationCompletion(criteria: .removed) {
                removalEvents.append("removal removed")
            }
            removal.addAnimationCompletion(criteria: .logicallyComplete) {
                removalEvents.append("removal logical")
            }
            source.setValue(makeRoot([], recorder), transaction: removal)

            let retained = infoAttr.value
            XCTAssertEqual(retained.activeItems.count, 0)
            XCTAssertEqual(retained.removedCount, 1)
            XCTAssertEqual(retained.unusedCount, 0)
            let item = try XCTUnwrap(retained.items.first)
            XCTAssertEqual(item.phase, .didDisappear)
            XCTAssertNotNil(item.listener)
            XCTAssertGreaterThan(item.subgraph.nodes.count, 0)
            XCTAssertEqual(removalEvents, [])
            XCTAssertEqual(recorder.events, ["row appear"])
            return item
        }

        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        XCTAssertEqual(removalEvents, ["removal removed", "removal logical"])
        XCTAssertEqual(recorder.events, ["row appear"])
        let listener = try XCTUnwrap(retainedItem.listener)
        XCTAssertTrue(listener.isComplete)
        graphHost.flushTransactions()

        ref.withCurrent {
            graph.inbox.drain()
            let finalized = infoAttr.value
            XCTAssertEqual(finalized.activeItems.count, 0)
            XCTAssertEqual(finalized.removedCount, 0)
            XCTAssertEqual(finalized.unusedCount, 0)
            XCTAssertTrue(finalized.items.isEmpty)
            XCTAssertEqual(retainedItem.subgraph.nodes.count, 0)
            XCTAssertEqual(recorder.events, ["row appear", "row disappear"])
        }
    }

    private func assertPublicLayoutRootRetainsTransitionRemovalUntilListenerInvalidatesRule<Root: View>(
        @ViewBuilder makeRoot: @escaping ([String], DynamicContainerLifecycleRecorder) -> Root
    ) throws {
        let rendererHost = TestViewRendererHost()
        let viewGraph = ViewGraph(
            rootViewType: EmptyView.self,
            content: EmptyView(),
            rendererHost: rendererHost
        )
        rendererHost.storage = viewGraph
        let graph = viewGraph.data.graph
        let recorder = DynamicContainerLifecycleRecorder()
        var source: Attribute<Root>!
        var layoutAttr: Attribute<LayoutComputer>!
        var removalEvents: [String] = []

        func sampleLayout() {
            let layout = layoutAttr.value
            let size = layout.sizeThatFits(.unspecified)
            layout.place(at: .zero, proposal: ProposedViewSize(size))
        }

        viewGraph.data.withCurrent {
            AGSubgraph.withCurrent(viewGraph.data.rootSubgraph) {
                let inputs = makeGraphInputs(graph: graph, transaction: Transaction())
                let viewInputs = makeViewInputs(graph: graph, base: inputs)
                // Lifecycle assertions require a visible, placed scroll content
                // subtree, not just a cached zero-sized layout computer.
                viewInputs.size.setValue(ViewSize(width: 100, height: 100))
                source = graph.makeInput(value: makeRoot(["row"], recorder))
                let outputs = Root._makeView(
                    view: _GraphValue(_attribute: source),
                    inputs: viewInputs
                )
                guard let initialLayoutAttr = outputs._layoutComputer.attribute else {
                    XCTFail("\(Root.self) should produce a layout computer")
                    return
                }
                layoutAttr = initialLayoutAttr

                sampleLayout()
            }
        }
        viewGraph.runTransaction(Transaction(), do: sampleLayout, id: nil)
        viewGraph.flushTransactions()
        XCTAssertEqual(recorder.events, ["row appear"])

        viewGraph.data.withCurrent {
            var removal = Transaction(animation: .linear(duration: 0.02))
            removal.addAnimationCompletion(criteria: .removed) {
                removalEvents.append("removal removed")
            }
            removal.addAnimationCompletion(criteria: .logicallyComplete) {
                removalEvents.append("removal logical")
            }
            source.setValue(makeRoot([], recorder), transaction: removal)

            viewGraph.runTransaction(removal, do: sampleLayout, id: nil)
            XCTAssertEqual(removalEvents, [])
            XCTAssertEqual(recorder.events, ["row appear"])
        }

        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        XCTAssertEqual(removalEvents, ["removal removed", "removal logical"])
        XCTAssertEqual(recorder.events, ["row appear"])
        viewGraph.flushTransactions()

        viewGraph.data.withCurrent {
            graph.inbox.drain()
            viewGraph.runTransaction(nil, do: sampleLayout, id: nil)
            XCTAssertEqual(recorder.events, ["row appear", "row disappear"])
        }
    }

    private func assertPublicLayoutRootRetainedRemovalDrainsForkedAnimatableCompletionsBeforeDisappear<Root: View>(
        disappearBeforeRetainedCompletions: Bool = false,
        @ViewBuilder makeRoot: @escaping (
            [String],
            Double,
            AnimationCompletionRecorder,
            DynamicContainerForkRetargetCapture
        ) -> Root
    ) throws {
        let rendererHost = TestViewRendererHost()
        let viewGraph = ViewGraph(
            rootViewType: EmptyView.self,
            content: EmptyView(),
            rendererHost: rendererHost
        )
        rendererHost.storage = viewGraph
        let graph = viewGraph.data.graph
        let recorder = AnimationCompletionRecorder()
        let sampleRecorder = CustomRetargetSampleRecorder()
        let capture = DynamicContainerForkRetargetCapture()
        var graphInputs: _GraphInputs!
        var source: Attribute<Root>!
        var layoutAttr: Attribute<LayoutComputer>!
        var displayOutput: Attribute<DisplayList>!
        var scrollablesOutput: Attribute<ScrollablePreferenceKey.Value>!
        var animatedValue: Attribute<_OpacityEffect>!
        var hasVisibleLazyItem = false

        func sampleLayout() {
            let layout = layoutAttr.value
            let size = layout.sizeThatFits(.unspecified)
            layout.place(
                at: .zero,
                proposal: ProposedViewSize(size)
            )
            _ = displayOutput.value
            for scrollable in scrollablesOutput.value {
                if let collection = scrollable as? any ScrollableCollection {
                    (collection as? DynamicContainerLazyPlacementSampler)?
                        .resampleCollectedPlacements()
                    hasVisibleLazyItem = hasVisibleLazyItem ||
                        !collection.visibleCollectionViewIDs.isEmpty
                }
                _ = scrollable.mapFirstChild(
                    ofType: (any ScrollableCollection).self
                ) { collection in
                    (collection as? DynamicContainerLazyPlacementSampler)?
                        .resampleCollectedPlacements()
                    hasVisibleLazyItem = hasVisibleLazyItem ||
                        !collection.visibleCollectionViewIDs.isEmpty
                }
            }
        }

        try viewGraph.data.withCurrent {
            try AGSubgraph.withCurrent(viewGraph.data.rootSubgraph) {
                graphInputs = makeGraphInputs(graph: graph, transaction: Transaction())
                var keys = PreferenceKeys()
                keys.add(DisplayList.Key.self)
                keys.add(ScrollablePreferenceKey.self)
                let viewInputs = makeViewInputs(
                    graph: graph,
                    base: graphInputs,
                    preferenceKeys: keys
                )
                // The native ordering marker covers a visible lazy item. A
                // zero-sized fixture can materialize it without committing a
                // placement, so no initial phase mutation would exist to flush.
                viewInputs.size.setValue(ViewSize(width: 100, height: 100))
                source = graph.makeInput(value: makeRoot(["row"], 0, recorder, capture))
                let outputs = Root._makeView(
                    view: _GraphValue(_attribute: source),
                    inputs: viewInputs
                )
                layoutAttr = try XCTUnwrap(outputs._layoutComputer.attribute)
                displayOutput = Attribute<DisplayList>(
                    try XCTUnwrap(
                        outputs.preferences.value(for: DisplayList.Key.self)
                    )
                )
                scrollablesOutput = Attribute<ScrollablePreferenceKey.Value>(
                    try XCTUnwrap(
                        outputs.preferences.value(for: ScrollablePreferenceKey.self)
                    )
                )

                sampleLayout()
                animatedValue = try XCTUnwrap(capture.animated)
                XCTAssertEqual(animatedValue.value.opacity, 0, accuracy: 0.000_001)
                XCTAssertEqual(recorder.events, [])
            }
        }
        // ASSERTIONS appearanceEffectAttributeFlagsObserved
        // ASSERTIONS appearanceMergedCallbacksObserved
        // ASSERTIONS retainedForkMergedAppearanceTeardownObserved
        viewGraph.runTransaction(Transaction(), do: sampleLayout, id: nil)
        // The host settles the scheduled lazy item-phase mutation before the
        // first user transaction can retarget the visible row.
        viewGraph.flushTransactions()
        if disappearBeforeRetainedCompletions {
            XCTAssertTrue(hasVisibleLazyItem)
        }
        XCTAssertEqual(recorder.events, ["row appear"])

        func transaction(label: String) -> Transaction {
            completionTransaction(
                animation: Animation(
                    RetargetBoundaryRecordingAnimation(
                        label: label,
                        logicalAt: 20,
                        nilAt: 20,
                        recorder: sampleRecorder
                    )
                ),
                label: label,
                recorder: recorder
            )
        }

        func retarget(_ label: String, target: Double, firstSample: Double, secondSample: Double) {
            let transaction = transaction(label: label)
            let update = {
                graphInputs.transaction.setValue(transaction)
                source.setValue(
                    makeRoot(["row"], target, recorder, capture),
                    transaction: transaction
                )
                sampleLayout()
                _ = animatedValue.value
                if !disappearBeforeRetainedCompletions {
                    Transaction.dispatchPendingListeners()
                }
                graphInputs.time.setValue(Time(seconds: firstSample))
                sampleLayout()
                _ = animatedValue.value
                graphInputs.time.setValue(Time(seconds: secondSample))
                sampleLayout()
                _ = animatedValue.value
                Self.flushGraphActions(graph)
            }
            if disappearBeforeRetainedCompletions {
                viewGraph.runTransaction(transaction, do: update, id: nil)
                Transaction.dispatchPendingListeners()
            } else {
                viewGraph.data.withCurrent(update)
            }
        }

        retarget("old", target: 1, firstSample: 0.5, secondSample: 0.6)
        retarget("middle", target: 2, firstSample: 0.8, secondSample: 0.9)
        retarget("active", target: 3, firstSample: 1.2, secondSample: 1.3)
        XCTAssertEqual(recorder.events, ["row appear"])

        var removal = completionTransaction(
            animation: .linear(duration: 0.02),
            label: "removal",
            recorder: recorder
        )
        removal.animationFrameInterval = 1.0 / 120.0
        let remove = {
            graphInputs.transaction.setValue(removal)
            source.setValue(makeRoot([], 3, recorder, capture), transaction: removal)
            sampleLayout()
            _ = animatedValue.value
            if !disappearBeforeRetainedCompletions {
                Transaction.dispatchPendingListeners()
            }
            XCTAssertEqual(recorder.events, ["row appear"])
        }
        if disappearBeforeRetainedCompletions {
            viewGraph.runTransaction(removal, do: remove, id: nil)
            Transaction.dispatchPendingListeners()
        } else {
            Update.ensure {
                viewGraph.data.withCurrent {
                    remove()
                }
            }
        }

        if disappearBeforeRetainedCompletions {
            Update.ensure {
                viewGraph.data.withCurrent {
                    // ASSERTIONS animatorStatePhaseTransitionObserved
                    // Drive the scheduled 120 Hz frames through the probed
                    // pending -> first -> second -> running cadence.
                    for frame in 1...6 {
                        graphInputs.time.setValue(
                            Time(seconds: 1.3 + Double(frame) / 120.0)
                        )
                        viewGraph.data.rootSubgraph.update(flags: 1)
                        sampleLayout()
                        _ = animatedValue.value
                    }
                }
            }
        } else {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        }
        Self.flushGraphActions(graph)
        XCTAssertEqual(
            recorder.events,
            [
                "row appear",
                "removal removed",
                "removal logical",
            ]
        )
        if !disappearBeforeRetainedCompletions {
            viewGraph.flushTransactions()
        }

        Update.ensure {
            viewGraph.data.withCurrent {
                graph.inbox.drain()
                if disappearBeforeRetainedCompletions {
                    viewGraph.flushTransactions()
                    layoutAttr.invalidateValue()
                }
                sampleLayout()
                Self.flushGraphActions(graph)
            }
        }
        if disappearBeforeRetainedCompletions {
            XCTAssertEqual(
                recorder.events,
                [
                    "row appear",
                    "removal removed",
                    "removal logical",
                    "row disappear",
                ]
            )
            Update.ensure {
                viewGraph.data.withCurrent {
                    for sampleTime in [20.1, 20.7, 21.1, 21.2] {
                        graphInputs.time.setValue(Time(seconds: sampleTime))
                        graph.inbox.drain()
                        sampleLayout()
                        _ = animatedValue.value
                        Self.flushGraphActions(graph)
                    }
                }
            }
            XCTAssertEqual(
                recorder.events,
                [
                    "row appear",
                    "removal removed",
                    "removal logical",
                    "row disappear",
                    "old removed",
                    "middle removed",
                    "active removed",
                    "active logical",
                    "old logical",
                    "middle logical",
                ]
            )
        } else {
            XCTAssertEqual(
                recorder.events,
                [
                    "row appear",
                    "removal removed",
                    "removal logical",
                    "old removed",
                    "middle removed",
                    "active removed",
                    "active logical",
                    "old logical",
                    "middle logical",
                    "row disappear",
                ]
            )
        }
    }

    private func assertPublicRootRetainedRemovalDrainsForkedAnimatableCompletionsBeforeDisappear<Root: View>(
        @ViewBuilder makeRoot: @escaping (
            [String],
            Double,
            AnimationCompletionRecorder,
            DynamicContainerForkRetargetCapture
        ) -> Root
    ) throws {
        let rendererHost = TestViewRendererHost()
        let viewGraph = ViewGraph(
            rootViewType: EmptyView.self,
            content: EmptyView(),
            rendererHost: rendererHost
        )
        rendererHost.storage = viewGraph
        let graph = viewGraph.data.graph
        let recorder = AnimationCompletionRecorder()
        let sampleRecorder = CustomRetargetSampleRecorder()
        let capture = DynamicContainerForkRetargetCapture()
        var graphInputs: _GraphInputs!
        var source: Attribute<Root>!
        var infoAttr: Attribute<DynamicContainer.Info>!
        var animatedValue: Attribute<_OpacityEffect>!

        func sampleInfo() {
            _ = infoAttr.value
        }

        try viewGraph.data.withCurrent {
            try AGSubgraph.withCurrent(viewGraph.data.rootSubgraph) {
                graphInputs = makeGraphInputs(graph: graph, transaction: Transaction())
                let viewInputs = makeViewInputs(graph: graph, base: graphInputs)
                source = graph.makeInput(value: makeRoot(["row"], 0, recorder, capture))
                let outputs = Root._makeViewList(
                    view: _GraphValue(_attribute: source),
                    inputs: _ViewListInputs(from: viewInputs)
                )
                guard case .dynamicList(let viewListAttr, _) = outputs.views else {
                    XCTFail("\(Root.self) with transition ForEach should produce a dynamic list")
                    return
                }
                infoAttr = graph.makeStatefulRule(
                    DynamicContainerInfo(
                        viewListAttr: viewListAttr,
                        inputs: viewInputs
                    )
                )

                sampleInfo()
                animatedValue = try XCTUnwrap(capture.animated)
                XCTAssertEqual(animatedValue.value.opacity, 0, accuracy: 0.000_001)
                XCTAssertEqual(recorder.events, [])
            }
        }
        // ASSERTIONS appearanceEffectAttributeFlagsObserved
        // ASSERTIONS appearanceMergedCallbacksObserved
        // ASSERTIONS retainedForkMergedAppearanceTeardownObserved
        viewGraph.runTransaction(Transaction(), do: sampleInfo, id: nil)
        XCTAssertEqual(recorder.events, ["row appear"])
        viewGraph.data.withCurrent {
            XCTAssertTrue(infoAttr.value.items.first?.needsTransitions ?? false)
        }

        func transaction(label: String) -> Transaction {
            completionTransaction(
                animation: Animation(
                    RetargetBoundaryRecordingAnimation(
                        label: label,
                        logicalAt: 20,
                        nilAt: 20,
                        recorder: sampleRecorder
                    )
                ),
                label: label,
                recorder: recorder
            )
        }

        func retarget(_ label: String, target: Double, firstSample: Double, secondSample: Double) {
            viewGraph.data.withCurrent {
                let transaction = transaction(label: label)
                graphInputs.transaction.setValue(transaction)
                source.setValue(
                    makeRoot(["row"], target, recorder, capture),
                    transaction: transaction
                )
                sampleInfo()
                _ = animatedValue.value
                Transaction.dispatchPendingListeners()
                graphInputs.time.setValue(Time(seconds: firstSample))
                sampleInfo()
                _ = animatedValue.value
                graphInputs.time.setValue(Time(seconds: secondSample))
                sampleInfo()
                _ = animatedValue.value
                Self.flushGraphActions(graph)
            }
        }

        retarget("old", target: 1, firstSample: 0.5, secondSample: 0.6)
        retarget("middle", target: 2, firstSample: 0.8, secondSample: 0.9)
        retarget("active", target: 3, firstSample: 1.2, secondSample: 1.3)
        XCTAssertEqual(recorder.events, ["row appear"])

        Update.ensure {
            viewGraph.data.withCurrent {
                var removal = completionTransaction(
                    animation: .linear(duration: 0.02),
                    label: "removal",
                    recorder: recorder
                )
                removal.animationFrameInterval = 1.0 / 120.0
                graphInputs.transaction.setValue(removal)
                source.setValue(makeRoot([], 3, recorder, capture), transaction: removal)
                sampleInfo()
                _ = animatedValue.value
                Transaction.dispatchPendingListeners()
                XCTAssertEqual(recorder.events, ["row appear"])
            }
        }

        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        Self.flushGraphActions(graph)
        XCTAssertEqual(
            recorder.events,
            [
                "row appear",
                "removal removed",
                "removal logical",
            ]
        )
        viewGraph.flushTransactions()

        Update.ensure {
            viewGraph.data.withCurrent {
                graph.inbox.drain()
                sampleInfo()
                Self.flushGraphActions(graph)
            }
        }
        XCTAssertEqual(
            recorder.events,
            [
                "row appear",
                "removal removed",
                "removal logical",
                "old removed",
                "middle removed",
                "active removed",
                "active logical",
                "old logical",
                "middle logical",
                "row disappear",
            ]
        )
    }

    func testDynamicContainerRetainsMultipleTransitionRemovalsUntilAllListenersInvalidateRule() throws {
        let graphFixture = DynamicContainerViewGraphFixture()
        let graphHost = graphFixture.viewGraph
        let graph = graphHost.data.graph
        let ref = _AGGraphContext(graph: graph)
        var source: Attribute<any ViewList>!
        var infoAttr: Attribute<DynamicContainer.Info>!
        var removalEvents: [String] = []

        ref.withCurrent {
            let inputs = makeGraphInputs(graph: graph, transaction: Transaction())
            source = graph.makeInput(
                value: makeTransitionList(inputs: inputs, rows: ["first", "second"])
            )
            infoAttr = graph.makeStatefulRule(
                DynamicContainerInfo(
                    viewListAttr: source,
                    inputs: makeViewInputs(graph: graph, base: inputs)
                )
            )

            let initial = infoAttr.value
            XCTAssertEqual(initial.activeItems.count, 2)
            XCTAssertEqual(initial.removedCount, 0)
            XCTAssertEqual(initial.unusedCount, 0)
            XCTAssertEqual(initial.items.map(\.phase), [.identity, .identity])
        }

        let retainedItems = try Update.ensure {
            try ref.withCurrent {
                var removal = Transaction(animation: .linear(duration: 0.02))
                removal.addAnimationCompletion(criteria: .removed) {
                    removalEvents.append("removal removed")
                }
                removal.addAnimationCompletion(criteria: .logicallyComplete) {
                    removalEvents.append("removal logical")
                }
                source.setValue(EmptyViewList(), transaction: removal)

                let retained = infoAttr.value
                XCTAssertEqual(retained.activeItems.count, 0)
                XCTAssertEqual(retained.removedCount, 2)
                XCTAssertEqual(retained.unusedCount, 0)
                XCTAssertEqual(retained.items.map(\.phase), [.didDisappear, .didDisappear])
                XCTAssertEqual(
                    retained.items.map {
                        $0.dynamicViewListID.explicitID as? String
                    },
                    ["first", "second"]
                )
                for item in retained.items {
                    XCTAssertNotNil(item.listener)
                    XCTAssertFalse(try XCTUnwrap(item.listener).isComplete)
                    XCTAssertGreaterThan(item.subgraph.nodes.count, 0)
                }
                XCTAssertEqual(removalEvents, [])
                return retained.items
            }
        }

        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        XCTAssertEqual(removalEvents, ["removal removed", "removal logical"])
        for item in retainedItems {
            XCTAssertTrue(try XCTUnwrap(item.listener).isComplete)
        }
        graphHost.flushTransactions()

        ref.withCurrent {
            graph.inbox.drain()
            let finalized = infoAttr.value
            XCTAssertEqual(finalized.activeItems.count, 0)
            XCTAssertEqual(finalized.removedCount, 0)
            XCTAssertEqual(finalized.unusedCount, 0)
            XCTAssertTrue(finalized.items.isEmpty)
            for item in retainedItems {
                XCTAssertEqual(item.subgraph.nodes.count, 0)
            }
        }
    }

    func testTransitionlessRemovalBecomesUnusedWithoutListener() throws {
        let graphFixture = DynamicContainerViewGraphFixture()
        let graphHost = graphFixture.viewGraph
        let graph = graphHost.data.graph
        let ref = _AGGraphContext(graph: graph)
        var source: Attribute<any ViewList>!
        var infoAttr: Attribute<DynamicContainer.Info>!

        ref.withCurrent {
            let inputs = makeGraphInputs(graph: graph, transaction: Transaction())
            source = graph.makeInput(
                value: makeTransitionList(
                    inputs: inputs,
                    transition: .identity
                )
            )
            infoAttr = graph.makeStatefulRule(
                DynamicContainerInfo(
                    retainingViewListAttr: source,
                    inputs: makeViewInputs(graph: graph, base: inputs)
                )
            )

            let initial = infoAttr.value
            XCTAssertEqual(initial.activeItems.count, 1)
            XCTAssertEqual(initial.items.first?.phase, .identity)
            XCTAssertFalse(initial.items.first?.needsTransitions == true)
        }

        let unusedItem = try ref.withCurrent {
            source.setValue(EmptyViewList(), transaction: Transaction(animation: nil))

            let retained = infoAttr.value
            XCTAssertEqual(retained.activeItems.count, 0)
            XCTAssertEqual(retained.removedCount, 0)
            XCTAssertEqual(retained.unusedCount, 1)
            let item = try XCTUnwrap(retained.items.first)
            XCTAssertNil(item.phase)
            XCTAssertNil(item.listener)
            XCTAssertGreaterThan(item.subgraph.nodes.count, 0)
            return item
        }

        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        ref.withCurrent {
            graph.inbox.drain()
            let retained = infoAttr.value
            XCTAssertEqual(retained.removedCount, 0)
            XCTAssertEqual(retained.unusedCount, 1)
            XCTAssertNil(retained.items.first?.listener)
            XCTAssertGreaterThan(unusedItem.subgraph.nodes.count, 0)
        }
    }

    func testInitialAndTransitionlessRemovalDoNotRequireGraphHost() {
        // ASSERTIONS dynamicContainerRemovalHostLazinessObserved
        let graph = _AGGraph()

        _AGGraph.withCurrent(graph) {
            let inputs = makeGraphInputs(graph: graph, transaction: Transaction())
            let source = graph.makeInput(
                value: makeTransitionList(
                    inputs: inputs,
                    transition: .identity
                )
            )
            let infoAttr = graph.makeStatefulRule(
                DynamicContainerInfo(
                    retainingViewListAttr: source,
                    inputs: makeViewInputs(graph: graph, base: inputs)
                )
            )

            let initial = infoAttr.value
            XCTAssertEqual(initial.activeItems.count, 1)
            XCTAssertEqual(initial.removedCount, 0)
            XCTAssertEqual(initial.unusedCount, 0)

            source.setValue(EmptyViewList(), transaction: Transaction(animation: nil))

            let inactive = infoAttr.value
            XCTAssertEqual(inactive.activeItems.count, 0)
            XCTAssertEqual(inactive.removedCount, 0)
            XCTAssertEqual(inactive.unusedCount, 1)
            XCTAssertNil(inactive.items.first?.listener)
        }
    }

    func testRetainedUnusedReinsertRunsDisappearAndAppearLifecycle() throws {
        let host = GraphHost()
        let graph = host.data.graph
        var source: Attribute<any ViewList>!
        var infoAttr: Attribute<DynamicContainer.Info>!
        var graphInputs: _GraphInputs!
        var lifecycleEvents: [String] = []

        host.data.withCurrent {
            graphInputs = makeGraphInputs(graph: graph, transaction: Transaction())
            source = graph.makeInput(
                value: makeTransitionList(
                    inputs: graphInputs,
                    rows: ["row"],
                    transition: .identity,
                    makeOutputs: { inputs in
                        Self.makeLifecycleLayoutOutputs(
                            inputs,
                            appear: { lifecycleEvents.append("row appear") },
                            disappear: { lifecycleEvents.append("row disappear") }
                        )
                    }
                )
            )
            infoAttr = graph.makeStatefulRule(
                DynamicContainerInfo(
                    retainingViewListAttr: source,
                    inputs: makeViewInputs(
                        graph: graph,
                        base: graphInputs
                    )
                )
            )

            let initial = infoAttr.value
            XCTAssertEqual(initial.activeItems.count, 1)
            XCTAssertEqual(initial.removedCount, 0)
            XCTAssertEqual(initial.unusedCount, 0)
            XCTAssertEqual(initial.items.first?.phase, .identity)
            XCTAssertEqual(lifecycleEvents, ["row appear"])
        }

        let unusedItem = try host.data.withCurrent {
            source.setValue(EmptyViewList(), transaction: Transaction(animation: nil))

            let retained = infoAttr.value
            XCTAssertEqual(retained.activeItems.count, 0)
            XCTAssertEqual(retained.removedCount, 0)
            XCTAssertEqual(retained.unusedCount, 1)
            let item = try XCTUnwrap(retained.items.first)
            XCTAssertNil(item.phase)
            XCTAssertNil(item.listener)
            XCTAssertGreaterThan(item.subgraph.nodes.count, 0)
            XCTAssertEqual(lifecycleEvents, ["row appear", "row disappear"])
            return item
        }

        try host.data.withCurrent {
            source.setValue(
                makeTransitionList(
                    inputs: graphInputs,
                    rows: ["row"],
                    transition: .identity,
                    makeOutputs: { inputs in
                        Self.makeLifecycleLayoutOutputs(
                            inputs,
                            appear: { lifecycleEvents.append("row appear") },
                            disappear: { lifecycleEvents.append("row disappear") }
                        )
                    }
                ),
                transaction: Transaction(animation: nil)
            )

            let reinsertedInfo = infoAttr.value
            XCTAssertEqual(reinsertedInfo.activeItems.count, 1)
            XCTAssertEqual(reinsertedInfo.removedCount, 0)
            XCTAssertEqual(reinsertedInfo.unusedCount, 0)
            let reinserted = try XCTUnwrap(reinsertedInfo.items.first)
            XCTAssertTrue(reinserted === unusedItem)
            XCTAssertEqual(reinserted.phase, .identity)
            // ASSERTIONS dynamicContainerUnusedReinsertionPhaseObserved
            XCTAssertNil(reinserted.listener)
            XCTAssertEqual(lifecycleEvents, ["row appear", "row disappear", "row appear"])

            reinserted.subgraph.update(flags: 1)
            XCTAssertEqual(lifecycleEvents, ["row appear", "row disappear", "row appear"])
        }
    }

    func testRetainedUnusedReinsertNotifiesGraphDelegateThroughDidReinsert() throws {
        let delegate = DynamicContainerGraphDelegateRecorder()
        let host = DynamicContainerDelegateGraphHost(delegate: delegate)
        let graph = host.data.graph
        var source: Attribute<any ViewList>!
        var infoAttr: Attribute<DynamicContainer.Info>!
        var graphInputs: _GraphInputs!
        var lifecycleEvents: [String] = []

        host.data.withCurrent {
            graphInputs = makeGraphInputs(graph: graph, transaction: Transaction())
            source = graph.makeInput(
                value: makeTransitionList(
                    inputs: graphInputs,
                    rows: ["row"],
                    transition: .identity,
                    makeOutputs: { inputs in
                        Self.makeLifecycleLayoutOutputs(
                            inputs,
                            appear: { lifecycleEvents.append("row appear") },
                            disappear: { lifecycleEvents.append("row disappear") }
                        )
                    }
                )
            )
            infoAttr = graph.makeStatefulRule(
                DynamicContainerInfo(
                    retainingViewListAttr: source,
                    inputs: makeViewInputs(
                        graph: graph,
                        base: graphInputs
                    )
                )
            )

            let initial = infoAttr.value
            XCTAssertEqual(initial.activeItems.count, 1)
            XCTAssertEqual(initial.items.first?.phase, .identity)
            XCTAssertEqual(lifecycleEvents, ["row appear"])
            XCTAssertEqual(delegate.events, [])
        }

        let unusedItem = try host.data.withCurrent {
            source.setValue(EmptyViewList(), transaction: Transaction(animation: nil))

            let retained = infoAttr.value
            XCTAssertEqual(retained.activeItems.count, 0)
            XCTAssertEqual(retained.removedCount, 0)
            XCTAssertEqual(retained.unusedCount, 1)
            let item = try XCTUnwrap(retained.items.first)
            XCTAssertNil(item.phase)
            XCTAssertEqual(lifecycleEvents, ["row appear", "row disappear"])
            XCTAssertEqual(delegate.events, [])
            return item
        }

        try host.data.withCurrent {
            source.setValue(
                makeTransitionList(
                    inputs: graphInputs,
                    rows: ["row"],
                    transition: .identity,
                    makeOutputs: { inputs in
                        Self.makeLifecycleLayoutOutputs(
                            inputs,
                            appear: { lifecycleEvents.append("row appear") },
                            disappear: { lifecycleEvents.append("row disappear") }
                        )
                    }
                ),
                transaction: Transaction(animation: nil)
            )

            let reinsertedInfo = infoAttr.value
            XCTAssertEqual(reinsertedInfo.activeItems.count, 1)
            XCTAssertEqual(reinsertedInfo.removedCount, 0)
            XCTAssertEqual(reinsertedInfo.unusedCount, 0)
            let reinserted = try XCTUnwrap(reinsertedInfo.items.first)
            XCTAssertTrue(reinserted === unusedItem)
            XCTAssertEqual(reinserted.phase, .identity)
            XCTAssertEqual(lifecycleEvents, ["row appear", "row disappear", "row appear"])
            XCTAssertEqual(delegate.events, ["change"])

            reinserted.subgraph.update(flags: 1)
            XCTAssertEqual(lifecycleEvents, ["row appear", "row disappear", "row appear"])
            XCTAssertEqual(delegate.events, ["change"])
        }

        XCTAssertFalse(host.hasPendingTransactions)
    }

    func testUnusedRetentionPrunesOlderPhaseThreeItemsBeyondLimit() throws {
        let graphFixture = DynamicContainerViewGraphFixture()
        let graphHost = graphFixture.viewGraph
        let graph = graphHost.data.graph
        let ref = _AGGraphContext(graph: graph)
        var source: Attribute<any ViewList>!
        var infoAttr: Attribute<DynamicContainer.Info>!
        var graphInputs: _GraphInputs!

        ref.withCurrent {
            graphInputs = makeGraphInputs(graph: graph, transaction: Transaction())
            source = graph.makeInput(
                value: makeTransitionList(
                    inputs: graphInputs,
                    rows: ["first", "second"],
                    transition: .identity
                )
            )
            infoAttr = graph.makeStatefulRule(
                DynamicContainerInfo(
                    retainingViewListAttr: source,
                    inputs: makeViewInputs(graph: graph, base: graphInputs)
                )
            )

            let initial = infoAttr.value
            XCTAssertEqual(initial.activeItems.count, 2)
            XCTAssertEqual(initial.removedCount, 0)
            XCTAssertEqual(initial.unusedCount, 0)
            XCTAssertEqual(
                initial.items.map {
                    $0.dynamicViewListID.explicitID as? String
                },
                ["first", "second"]
            )
        }

        let firstUnused = try ref.withCurrent {
            source.setValue(
                makeTransitionList(
                    inputs: graphInputs,
                    rows: ["second"],
                    transition: .identity
                ),
                transaction: Transaction(animation: nil)
            )

            let retained = infoAttr.value
            XCTAssertEqual(retained.activeItems.count, 1)
            XCTAssertEqual(retained.removedCount, 0)
            XCTAssertEqual(retained.unusedCount, 1)
            XCTAssertEqual(
                retained.items.map {
                    $0.dynamicViewListID.explicitID as? String
                },
                ["second", "first"]
            )
            XCTAssertEqual(retained.items.map(\.phase), [.identity, nil])
            let unused = try XCTUnwrap(retained.items.last)
            XCTAssertNil(unused.listener)
            XCTAssertGreaterThan(unused.subgraph.nodes.count, 0)
            return unused
        }

        try ref.withCurrent {
            source.setValue(EmptyViewList(), transaction: Transaction(animation: nil))

            let retained = infoAttr.value
            XCTAssertEqual(retained.activeItems.count, 0)
            XCTAssertEqual(retained.removedCount, 0)
            XCTAssertEqual(retained.unusedCount, 1)
            let newestUnused = try XCTUnwrap(retained.items.first)
            XCTAssertEqual(
                newestUnused.dynamicViewListID.explicitID as? String,
                "second"
            )
            XCTAssertNil(newestUnused.phase)
            XCTAssertNil(newestUnused.listener)
            XCTAssertGreaterThan(newestUnused.subgraph.nodes.count, 0)
            XCTAssertEqual(firstUnused.subgraph.nodes.count, 0)
        }
    }

    func testTransitionRemovalUsesBaselineListenerWithoutRegisteredAnimation() throws {
        let graphFixture = DynamicContainerViewGraphFixture()
        let graphHost = graphFixture.viewGraph
        let graph = graphHost.data.graph
        let ref = _AGGraphContext(graph: graph)
        var source: Attribute<any ViewList>!
        var infoAttr: Attribute<DynamicContainer.Info>!
        var initialItem: DynamicContainer.ItemInfo!

        ref.withCurrent {
            let inputs = makeGraphInputs(graph: graph, transaction: Transaction())
            source = graph.makeInput(value: makeTransitionList(inputs: inputs))
            infoAttr = graph.makeStatefulRule(
                DynamicContainerInfo(
                    viewListAttr: source,
                    inputs: makeViewInputs(graph: graph, base: inputs)
                )
            )

            let initial = infoAttr.value
            XCTAssertEqual(initial.activeItems.count, 1)
            initialItem = initial.items.first
            XCTAssertGreaterThan(initialItem.subgraph.nodes.count, 0)
        }

        let retainedItem = try ref.withCurrent {
            source.setValue(EmptyViewList(), transaction: Transaction(animation: nil))

            let retained = infoAttr.value
            XCTAssertEqual(retained.activeItems.count, 0)
            XCTAssertEqual(retained.removedCount, 1)
            XCTAssertEqual(retained.unusedCount, 0)
            let item = try XCTUnwrap(retained.items.first)
            XCTAssertTrue(item === initialItem)
            XCTAssertNotNil(item.listener)
            XCTAssertTrue(try XCTUnwrap(item.listener).isComplete)
            XCTAssertGreaterThan(item.subgraph.nodes.count, 0)
            return item
        }

        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        XCTAssertTrue(try XCTUnwrap(retainedItem.listener).isComplete)
        graphHost.flushTransactions()

        ref.withCurrent {
            graph.inbox.drain()
            let finalized = infoAttr.value
            XCTAssertEqual(finalized.activeItems.count, 0)
            XCTAssertEqual(finalized.removedCount, 0)
            XCTAssertEqual(finalized.unusedCount, 0)
            XCTAssertTrue(finalized.items.isEmpty)
            XCTAssertEqual(initialItem.subgraph.nodes.count, 0)
        }
    }

    func testRetainedRemovalKeepsDisplayListPreferenceButFiltersOrdinaryPreferences() throws {
        // ASSERTIONS dynamicContainerPreferenceCombinerObserved
        // ASSERTIONS displayListIncludesRemovedValuesObserved
        let rendererHost = TestViewRendererHost()
        let viewGraph = ViewGraph(
            rootViewType: EmptyView.self,
            content: EmptyView(),
            rendererHost: rendererHost
        )
        rendererHost.storage = viewGraph
        let graph = viewGraph.data.graph
        var source: Attribute<any ViewList>!
        var displayOutput: Attribute<DisplayList>!
        var ordinaryOutput: Attribute<String>!
        var graphInputs: _GraphInputs!

        try viewGraph.data.withCurrent {
            graphInputs = makeGraphInputs(graph: graph, transaction: Transaction())
            source = graph.makeInput(
                value: makePreferenceList(inputs: graphInputs, rows: ["first", "second"])
            )
            let layout = graph.makeInput(value: ZStackLayout())
            var keys = PreferenceKeys()
            keys.add(DisplayList.Key.self)
            keys.add(RetainedRemovalOrdinaryPreferenceKey.self)
            let outputs = ZStackLayout._makeLayoutView(
                root: _GraphValue(_attribute: layout),
                inputs: makeViewInputs(
                    graph: graph,
                    base: graphInputs,
                    preferenceKeys: keys
                )
            ) { _, _ in
                _ViewListOutputs(
                    views: .dynamicList(source, nil),
                    nextImplicitID: 0,
                    staticCount: nil
                )
            }

            displayOutput = Attribute<DisplayList>(
                try XCTUnwrap(outputs.preferences.value(for: DisplayList.Key.self))
            )
            ordinaryOutput = Attribute<String>(
                try XCTUnwrap(outputs.preferences.value(for: RetainedRemovalOrdinaryPreferenceKey.self))
            )

            XCTAssertEqual(displayOutput.value.debugItems.count, 3)
            XCTAssertEqual(ordinaryOutput.value, "first,second,")
        }

        viewGraph.data.withCurrent {
            source.setValue(
                makePreferenceList(inputs: graphInputs, rows: ["second"]),
                transaction: Transaction(animation: .linear(duration: 0.02))
            )

            XCTAssertEqual(displayOutput.value.debugItems.count, 3)
            XCTAssertEqual(ordinaryOutput.value, "second,")
        }
    }

    func testRetainedRemovalDisplayMapUsesActivePrefixAndRetainedInclusiveSegments() throws {
        let graphFixture = DynamicContainerViewGraphFixture()
        let graphHost = graphFixture.viewGraph
        let graph = graphHost.data.graph
        let ref = _AGGraphContext(graph: graph)
        ref.withCurrent {
            var info = DynamicContainer.Info()
            let activeLow = makeDisplayMapItem(id: "active-low", zIndex: 0, phase: .identity)
            let activeHigh = makeDisplayMapItem(id: "active-high", zIndex: 8, phase: .identity)
            let activeMiddle = makeDisplayMapItem(id: "active-middle", zIndex: 4, phase: .identity)
            let removed = makeDisplayMapItem(id: "removed", zIndex: 3, phase: .didDisappear)

            info.replaceItems(
                active: [activeLow, activeHigh, activeMiddle],
                removed: [removed]
            )

            XCTAssertEqual(info.removedCount, 1)
            XCTAssertEqual(info.unusedCount, 0)
            XCTAssertEqual(info.displayMap, [0, 2, 1, 0, 3, 2, 1])
            XCTAssertEqual(
                info.displayItems.map(\.uniqueId),
                [activeLow, removed, activeMiddle, activeHigh].map(\.uniqueId)
            )
        }
    }

    // ASSERTIONS dynamicLayoutRetainedViewIndexObserved
    func testRetainedItemsReceiveViewIndexesAfterTheActivePrefix() throws {
        let graphFixture = DynamicContainerViewGraphFixture()
        let graphHost = graphFixture.viewGraph
        let graph = graphHost.data.graph
        let ref = _AGGraphContext(graph: graph)
        ref.withCurrent {
            var info = DynamicContainer.Info()
            let activeA = makeDisplayMapItem(
                id: "active-a",
                viewCount: 2,
                zIndex: 0,
                phase: .identity
            )
            let activeB = makeDisplayMapItem(
                id: "active-b",
                viewCount: 1,
                zIndex: 0,
                phase: .identity
            )
            let removed = makeDisplayMapItem(
                id: "removed",
                viewCount: 3,
                zIndex: 0,
                phase: .didDisappear
            )
            let unused = makeDisplayMapItem(
                id: "unused",
                viewCount: 2,
                zIndex: 0,
                phase: nil
            )

            info.replaceItems(
                active: [activeA, activeB],
                removed: [removed],
                unused: [unused]
            )

            XCTAssertEqual(activeA.precedingViewCount, 0)
            XCTAssertEqual(activeB.precedingViewCount, 2)
            XCTAssertEqual(removed.precedingViewCount, 3)
            XCTAssertEqual(unused.precedingViewCount, 6)
        }
    }

    func testRetainedRemovalDisplaysRemovedItemsBelowActiveReplacements() throws {
        let graphFixture = DynamicContainerViewGraphFixture()
        let graphHost = graphFixture.viewGraph
        let graph = graphHost.data.graph
        let ref = _AGGraphContext(graph: graph)
        ref.withCurrent {
            var info = DynamicContainer.Info()
            let activeA = makeDisplayMapItem(id: "active-a", zIndex: 0, phase: .identity)
            let activeB = makeDisplayMapItem(id: "active-b", zIndex: 0, phase: .identity)
            let removedA = makeDisplayMapItem(id: "removed-a", zIndex: 0, phase: .didDisappear)
            let removedB = makeDisplayMapItem(id: "removed-b", zIndex: 0, phase: .didDisappear)

            info.replaceItems(
                active: [activeA, activeB],
                removed: [removedA, removedB]
            )

            XCTAssertNil(info.displayMap)
            XCTAssertEqual(
                info.displayItems.map(\.uniqueId),
                [removedA, removedB, activeA, activeB].map(\.uniqueId)
            )
        }
    }

    func testRetainedUnusedDisplayMapIgnoresUnusedDepthOnlyItems() throws {
        let graphFixture = DynamicContainerViewGraphFixture()
        let graphHost = graphFixture.viewGraph
        let graph = graphHost.data.graph
        let ref = _AGGraphContext(graph: graph)
        ref.withCurrent {
            var info = DynamicContainer.Info()
            let activeZero = makeDisplayMapItem(id: "active-zero", zIndex: 0, phase: .identity)
            let unusedHigh = makeDisplayMapItem(id: "unused-high", zIndex: 8, phase: nil)

            info.replaceItems(
                active: [activeZero],
                unused: [unusedHigh]
            )

            XCTAssertEqual(info.activeItems.count, 1)
            XCTAssertEqual(info.removedCount, 0)
            XCTAssertEqual(info.unusedCount, 1)
            XCTAssertNil(info.displayMap)
        }
    }

    func testRetainedRemovalDisplayMapOrdersRemovedItemsBeforeSameDepthActiveItems() throws {
        let graphFixture = DynamicContainerViewGraphFixture()
        let graphHost = graphFixture.viewGraph
        let graph = graphHost.data.graph
        let ref = _AGGraphContext(graph: graph)
        ref.withCurrent {
            var info = DynamicContainer.Info()
            let activeZero = makeDisplayMapItem(id: "active-zero", zIndex: 0, phase: .identity)
            let activeSameA = makeDisplayMapItem(id: "active-same-a", zIndex: 5, phase: .identity)
            let activeSameB = makeDisplayMapItem(id: "active-same-b", zIndex: 5, phase: .identity)
            let removedSame = makeDisplayMapItem(id: "removed-same", zIndex: 5, phase: .didDisappear)

            info.replaceItems(
                active: [activeZero, activeSameA, activeSameB],
                removed: [removedSame]
            )

            XCTAssertEqual(info.displayMap, [0, 1, 2, 0, 3, 1, 2])
            XCTAssertEqual(
                info.displayItems.map(\.uniqueId),
                [activeZero, removedSame, activeSameA, activeSameB].map(\.uniqueId)
            )
        }
    }

    func testRetainedRemovalDisplayMapKeepsDepthOrderingAcrossRemovedAndActiveItems() throws {
        let graphFixture = DynamicContainerViewGraphFixture()
        let graphHost = graphFixture.viewGraph
        let graph = graphHost.data.graph
        let ref = _AGGraphContext(graph: graph)
        ref.withCurrent {
            var info = DynamicContainer.Info()
            let activeZero = makeDisplayMapItem(id: "active-zero", zIndex: 0, phase: .identity)
            let activeMiddle = makeDisplayMapItem(id: "active-middle", zIndex: 4, phase: .identity)
            let activeHigh = makeDisplayMapItem(id: "active-high", zIndex: 8, phase: .identity)
            let removedLow = makeDisplayMapItem(id: "removed-low", zIndex: 3, phase: .didDisappear)
            let removedHigh = makeDisplayMapItem(id: "removed-high", zIndex: 7, phase: .didDisappear)

            info.replaceItems(
                active: [activeZero, activeMiddle, activeHigh],
                removed: [removedHigh, removedLow]
            )

            XCTAssertEqual(info.removedCount, 2)
            XCTAssertEqual(info.displayMap, [0, 1, 2, 0, 4, 1, 3, 2])
        }
    }

    func testDynamicContainerResetSeedAndOptionDisableInsertionTransitions() throws {
        enum Mode {
            case enabled
            case resetSeedChanged
            case animationsDisabled
        }

        func insertedPhase(_ mode: Mode) throws -> TransitionPhase? {
            let rendererHost = TestViewRendererHost()
            let viewGraph = ViewGraph(
                rootViewType: EmptyView.self,
                content: EmptyView(),
                rendererHost: rendererHost
            )
            rendererHost.storage = viewGraph
            let graph = viewGraph.data.graph

            return try viewGraph.data.withCurrent {
                try AGSubgraph.withCurrent(viewGraph.data.rootSubgraph) {
                    var graphInputs = makeGraphInputs(
                        graph: graph,
                        transaction: Transaction()
                    )
                    if case .animationsDisabled = mode {
                        graphInputs.options.insert(.animationsDisabled)
                    }
                    let viewInputs = makeViewInputs(graph: graph, base: graphInputs)
                    let source = graph.makeInput(
                        value: makeTransitionList(
                            inputs: graphInputs,
                            rows: [],
                            transition: .scale(scale: 0.65)
                        )
                    )
                    let info = graph.makeStatefulRule(
                        DynamicContainerInfo(
                            viewListAttr: source,
                            inputs: viewInputs
                        )
                    )
                    XCTAssertTrue(info.value.activeItems.isEmpty)

                    if case .resetSeedChanged = mode {
                        var phase = graphInputs.phase.value
                        phase.resetSeed &+= 1
                        graphInputs.phase.setValue(phase)
                    }
                    let insertion = Transaction(animation: .linear(duration: 1))
                    source.setValue(
                        makeTransitionList(
                            inputs: graphInputs,
                            rows: ["row"],
                            transition: .scale(scale: 0.65)
                        ),
                        transaction: insertion
                    )
                    return try XCTUnwrap(info.value.activeItems.first).phase
                }
            }
        }

        XCTAssertEqual(try insertedPhase(.enabled), .willAppear)
        XCTAssertEqual(try insertedPhase(.resetSeedChanged), .identity)
        XCTAssertEqual(try insertedPhase(.animationsDisabled), .identity)
        // ASSERTIONS dynamicContainerInsertionContinuationDisassemblyObserved
    }

    func testDynamicContainerResetSeedAndOptionDisableRemovalTransitions() throws {
        enum Mode {
            case enabled
            case resetSeedChanged
            case animationsDisabled
        }

        func removalCounts(_ mode: Mode) -> (removed: Int, unused: Int) {
            let rendererHost = TestViewRendererHost()
            let viewGraph = ViewGraph(
                rootViewType: EmptyView.self,
                content: EmptyView(),
                rendererHost: rendererHost
            )
            rendererHost.storage = viewGraph
            let graph = viewGraph.data.graph

            return viewGraph.data.withCurrent {
                AGSubgraph.withCurrent(viewGraph.data.rootSubgraph) {
                    var graphInputs = makeGraphInputs(
                        graph: graph,
                        transaction: Transaction()
                    )
                    if case .animationsDisabled = mode {
                        graphInputs.options.insert(.animationsDisabled)
                    }
                    let viewInputs = makeViewInputs(graph: graph, base: graphInputs)
                    let source = graph.makeInput(
                        value: makeTransitionList(
                            inputs: graphInputs,
                            transition: .opacity
                        )
                    )
                    let info = graph.makeStatefulRule(
                        DynamicContainerInfo(
                            retainingViewListAttr: source,
                            inputs: viewInputs
                        )
                    )
                    XCTAssertEqual(info.value.activeItems.count, 1)

                    if case .resetSeedChanged = mode {
                        var phase = graphInputs.phase.value
                        phase.resetSeed &+= 1
                        graphInputs.phase.setValue(phase)
                    }
                    let removal = Transaction(animation: .linear(duration: 1))
                    source.setValue(
                        makeTransitionList(
                            inputs: graphInputs,
                            rows: [],
                            transition: .opacity
                        ),
                        transaction: removal
                    )
                    let result = info.value
                    return (result.removedCount, result.unusedCount)
                }
            }
        }

        let enabled = removalCounts(.enabled)
        XCTAssertEqual(enabled.removed, 1)
        XCTAssertEqual(enabled.unused, 0)

        let resetSeedChanged = removalCounts(.resetSeedChanged)
        XCTAssertEqual(resetSeedChanged.removed, 0)
        XCTAssertEqual(resetSeedChanged.unused, 1)

        let animationsDisabled = removalCounts(.animationsDisabled)
        XCTAssertEqual(animationsDisabled.removed, 0)
        XCTAssertEqual(animationsDisabled.unused, 1)
        // ASSERTIONS dynamicContainerInsertionContinuationDisassemblyObserved
    }

    private func makeTransitionList(
        inputs: _GraphInputs,
        rows: [String] = ["row"],
        transition: AnyTransition = .opacity
    ) -> any ViewList {
        makeTransitionList(
            inputs: inputs,
            rows: rows,
            transition: transition,
            makeOutputs: Self.makeFixedLayoutOutputs
        )
    }

    private func makeTransitionList(
        inputs: _GraphInputs,
        rows: [String],
        transition: AnyTransition = .opacity,
        makeOutputs: @escaping (_ViewInputs) -> _ViewOutputs
    ) -> any ViewList {
        var traits = ViewTraitCollection()
        traits[CanTransitionTraitKey.self] = true
        traits[TransitionTraitKey.self] = transition

        return TestDynamicRowsViewList(
            rows: rows,
            traits: traits,
            baseInputs: inputs,
            makeOutputs: makeOutputs
        )
    }

    private func makePreferenceList(
        inputs: _GraphInputs,
        rows: [String]
    ) -> any ViewList {
        var traits = ViewTraitCollection()
        traits[CanTransitionTraitKey.self] = true
        traits[TransitionTraitKey.self] = .opacity

        return TestPreferenceRowsViewList(
            rows: rows,
            traits: traits,
            baseInputs: inputs,
            makeOutputs: Self.makePreferenceLayoutOutputs
        )
    }

    private static func makeFixedLayoutOutputs(_ inputs: _ViewInputs) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("DynamicContainer test element built outside AG context.")
        }
        let layout = graph.makeInput(
            value: LayoutComputer.fixed(CGSize(width: 10, height: 10))
        )
        return _ViewOutputs(layoutComputer: OptionalAttribute(layout))
    }

    private func transitionPhases(in value: Any) -> [TransitionPhase] {
        let mirror = Mirror(reflecting: value)
        var phases: [TransitionPhase] = []
        for child in mirror.children {
            if child.label == "phase", let phase = child.value as? TransitionPhase {
                phases.append(phase)
            }
            phases.append(contentsOf: transitionPhases(in: child.value))
        }
        return phases
    }

    private static func makePreferenceLayoutOutputs(
        row: String,
        inputs: _ViewInputs
    ) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("DynamicContainer preference test element built outside AG context.")
        }
        let layout = graph.makeInput(
            value: LayoutComputer.fixed(CGSize(width: 10, height: 10))
        )
        let displayList = graph.makeInput(
            value: makeDisplayList(debugItemCount: row == "first" ? 1 : 2)
        )
        let ordinary = graph.makeInput(value: "\(row),")
        var preferences = PreferencesOutputs()
        preferences.append(DisplayList.Key.self, node: displayList.identifier)
        preferences.append(RetainedRemovalOrdinaryPreferenceKey.self, node: ordinary.identifier)
        return _ViewOutputs(
            preferences: preferences,
            layoutComputer: OptionalAttribute(layout)
        )
    }

    private static func makeLifecycleLayoutOutputs(
        _ inputs: _ViewInputs,
        appear: @escaping () -> Void,
        disappear: @escaping () -> Void
    ) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("DynamicContainer lifecycle test element built outside AG context.")
        }
        let modifier = graph.makeInput(
            value: _AppearanceActionModifier(appear: appear, disappear: disappear)
        )
        let effect = graph.makeStatefulRule(
            AppearanceEffect(modifier: modifier, phase: inputs.base.phase)
        )
        graph.makeSideEffectRule {
            _ = effect.value
            return ()
        }
        let layout = graph.makeInput(
            value: LayoutComputer.fixed(CGSize(width: 10, height: 10))
        )
        return _ViewOutputs(layoutComputer: OptionalAttribute(layout))
    }

    private struct TestDynamicRowsViewList: ViewList {
        var rows: [String]
        var traits: ViewTraitCollection
        var baseInputs: _GraphInputs
        var makeOutputs: (_ViewInputs) -> _ViewOutputs

        func count(style: _ViewList_IteratorStyle) -> Int {
            rows.count
        }

        func estimatedCount(style: _ViewList_IteratorStyle) -> Int {
            rows.count
        }

        func applyNodes(
            from: inout Int,
            style: _ViewList_IteratorStyle,
            list: Attribute<any ViewList>?,
            transform: _ViewList_TemporarySublistTransform,
            to: (inout Int, _ViewList_IteratorStyle, _ViewList_Node, _ViewList_TemporarySublistTransform) -> Bool
        ) -> Bool {
            for row in rows {
                if from > 0 {
                    from -= 1
                    continue
                }
                let sublist = _ViewList_Sublist(
                    start: 0,
                    count: 1,
                    id: _ViewList_ID(explicitID: row),
                    elements: _ViewList_SubgraphElements(
                        base: UnaryElements(
                            body: BodyUnaryViewGenerator(
                                body: makeOutputs,
                                viewType: EmptyView.self
                            ),
                            baseInputs: baseInputs
                        )
                    ),
                    traits: traits,
                    list: list
                )
                let shouldContinue = to(&from, style, .sublist(sublist), transform)
                from = 0
                if !shouldContinue {
                    return false
                }
            }
            return true
        }

        var debugDescription: String {
            "TestDynamicRowsViewList(\(rows))"
        }
    }

    private struct TestPreferenceRowsViewList: ViewList {
        var rows: [String]
        var traits: ViewTraitCollection
        var baseInputs: _GraphInputs
        var makeOutputs: (String, _ViewInputs) -> _ViewOutputs

        func count(style: _ViewList_IteratorStyle) -> Int {
            rows.count
        }

        func estimatedCount(style: _ViewList_IteratorStyle) -> Int {
            rows.count
        }

        func applyNodes(
            from: inout Int,
            style: _ViewList_IteratorStyle,
            list: Attribute<any ViewList>?,
            transform: _ViewList_TemporarySublistTransform,
            to: (inout Int, _ViewList_IteratorStyle, _ViewList_Node, _ViewList_TemporarySublistTransform) -> Bool
        ) -> Bool {
            for row in rows {
                if from > 0 {
                    from -= 1
                    continue
                }
                let rowValue = row
                let sublist = _ViewList_Sublist(
                    start: 0,
                    count: 1,
                    id: _ViewList_ID(explicitID: row),
                    elements: _ViewList_SubgraphElements(
                        base: UnaryElements(
                            body: BodyUnaryViewGenerator(
                                body: { inputs in
                                    makeOutputs(rowValue, inputs)
                                },
                                viewType: EmptyView.self
                            ),
                            baseInputs: baseInputs
                        )
                    ),
                    traits: traits,
                    list: list
                )
                let shouldContinue = to(&from, style, .sublist(sublist), transform)
                from = 0
                if !shouldContinue {
                    return false
                }
            }
            return true
        }

        var debugDescription: String {
            "TestPreferenceRowsViewList(\(rows))"
        }
    }

    private func makeViewInputs(
        graph: _AGGraph,
        base: _GraphInputs,
        preferenceKeys: PreferenceKeys = PreferenceKeys()
    ) -> _ViewInputs {
        _ViewInputs(
            base: base,
            customInputs: PropertyList(),
            preferences: PreferencesInputs(
                keys: preferenceKeys,
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

    private func makeGraphInputs(
        graph: _AGGraph,
        transaction: Transaction
    ) -> _GraphInputs {
        _GraphInputs(
            time: graph.makeInput(value: Time(seconds: 0)),
            phase: graph.makeInput(value: _GraphInputs.Phase()),
            environment: graph.makeInput(value: EnvironmentValues()),
            transaction: graph.makeInput(value: transaction)
        )
    }

    private static func makeDisplayList(debugItemCount: Int) -> DisplayList {
        var list = DisplayList()
        for _ in 0..<debugItemCount {
            list.appendDebugItem { _ in }
        }
        return list
    }

    private static func flushGraphActions(_ graph: _AGGraph) {
        graph.drainActionOutbox()
    }

    private func makeDisplayMapItem(
        id: String,
        viewCount: Int = 1,
        zIndex: Double,
        phase: TransitionPhase?
    ) -> DynamicContainer.ItemInfo {
        let uniqueId = id.utf8.reduce(UInt32(2_166_136_261)) {
            ($0 ^ UInt32($1)) &* 16_777_619
        }
        return DynamicContainer.ItemInfo(
            subgraph: AGSubgraph(),
            uniqueId: uniqueId,
            viewCount: Int32(viewCount),
            outputs: _ViewOutputs(),
            zIndex: zIndex,
            phase: phase
        )
    }
}

private final class DynamicContainerDelegateGraphHost: GraphHost {
    private let delegateRecorder: DynamicContainerGraphDelegateRecorder

    init(delegate: DynamicContainerGraphDelegateRecorder) {
        self.delegateRecorder = delegate
        super.init(data: Data())
        delegate.host = self
    }

    override var graphDelegate: (any GraphDelegate)? {
        delegateRecorder
    }
}

private final class DynamicContainerGraphDelegateRecorder: GraphDelegate {
    weak var host: GraphHost?
    private(set) var events: [String] = []

    func updateGraph<T>(body: (GraphHost) -> T) -> T {
        guard let host else {
            fatalError("DynamicContainerGraphDelegateRecorder used before attaching a host.")
        }
        events.append("update")
        return body(host)
    }

    func graphDidChange() {
        events.append("change")
    }
}

private final class DynamicContainerLifecycleRecorder {
    var events: [String] = []

    func append(_ event: String) {
        events.append(event)
    }
}

private final class DynamicContainerTransitionPhaseRecorder {
    var events: [String] = []

    func record(_ phase: TransitionPhase) {
        let label: String
        switch phase {
        case .identity:
            label = "identity"
        case .willAppear:
            label = "willAppear"
        case .didDisappear:
            label = "didDisappear"
        }
        if events.last != label {
            events.append(label)
        }
    }
}

private struct DynamicContainerPhaseRecordingTransition: Transition {
    var recorder: DynamicContainerTransitionPhaseRecorder

    func body(content: Content, phase: TransitionPhase) -> some View {
        content.modifier(
            DynamicContainerPhaseRecordingModifier(
                phase: phase,
                recorder: recorder
            )
        )
    }
}

private struct DynamicContainerPhaseRecordingModifier: ViewModifier {
    var phase: TransitionPhase
    var recorder: DynamicContainerTransitionPhaseRecorder

    typealias Body = Never

    static func _makeView(
        modifier: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("\(Self.self)._makeView called outside AG context.")
        }
        var outputs = body(_Graph(), inputs)
        guard let childLayout = outputs._layoutComputer.attribute else {
            let value = modifier._attribute.value
            value.recorder.record(value.phase)
            return outputs
        }
        let layout = graph.makeRule {
            let value = modifier._attribute.value
            value.recorder.record(value.phase)
            return childLayout.value
        }
        outputs._layoutComputer = OptionalAttribute(layout)
        return outputs
    }
}

private final class DynamicContainerForkRetargetCapture {
    var animated: Attribute<_OpacityEffect>?
}

private struct DynamicContainerForkRetargetRow: View {
    var row: String
    var effect: _OpacityEffect
    var recorder: AnimationCompletionRecorder
    var capture: DynamicContainerForkRetargetCapture

    var body: some View {
        DynamicContainerForkRetargetContent(
            effect: effect,
            capture: capture
        )
        .modifier(
            _AppearanceActionModifier(
                appear: { recorder.record("\(row) appear") },
                disappear: { recorder.record("\(row) disappear") }
            )
        )
    }
}

private struct DynamicContainerForkRetargetContent: View {
    var effect: _OpacityEffect
    var capture: DynamicContainerForkRetargetCapture

    static func _makeView(
        view: _GraphValue<Self>,
        inputs: _ViewInputs
    ) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("DynamicContainerForkRetargetContent._makeView called outside AG context.")
        }

        var graphValue = view[\.effect]
        _OpacityEffect._makeAnimatable(value: &graphValue, inputs: inputs.base)
        let animatedAttr = graphValue._attribute
        let captureAttr = view[\.capture]._attribute
        graph.makeSideEffectRule {
            captureAttr.value.animated = animatedAttr
            return ()
        }

        let layout = graph.makeRule {
            _ = animatedAttr.value
            return LayoutComputer.fixed(CGSize(width: 10, height: 10))
        }
        return _ViewOutputs(layoutComputer: OptionalAttribute(layout))
    }

    typealias Body = Never
}

extension DynamicContainerForkRetargetContent: TestPrimitiveView {}

private struct DynamicContainerLifecycleRow: View {
    var row: String
    var recorder: DynamicContainerLifecycleRecorder

    static func _makeView(
        view: _GraphValue<Self>,
        inputs: _ViewInputs
    ) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("DynamicContainerLifecycleRow._makeView called outside AG context.")
        }
        let modifier = graph.makeRule {
            let value = view._attribute.value
            return _AppearanceActionModifier(
                appear: { value.recorder.append("\(value.row) appear") },
                disappear: { value.recorder.append("\(value.row) disappear") }
            )
        }
        let effect = graph.makeStatefulRule(
            AppearanceEffect(modifier: modifier, phase: inputs.base.phase)
        )
        graph.makeSideEffectRule {
            _ = effect.value
            return ()
        }
        let layout = graph.makeInput(
            value: LayoutComputer.fixed(CGSize(width: 10, height: 10))
        )
        return _ViewOutputs(layoutComputer: OptionalAttribute(layout))
    }

    typealias Body = Never
}

extension DynamicContainerLifecycleRow: TestPrimitiveView {}

private struct DynamicContainerLifecycleSizedRow: View {
    var row: String
    var width: CGFloat
    var recorder: DynamicContainerLifecycleRecorder

    static func _makeView(
        view: _GraphValue<Self>,
        inputs: _ViewInputs
    ) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("DynamicContainerLifecycleSizedRow._makeView called outside AG context.")
        }
        let modifier = graph.makeRule {
            let value = view._attribute.value
            return _AppearanceActionModifier(
                appear: { value.recorder.append("\(value.row) appear") },
                disappear: { value.recorder.append("\(value.row) disappear") }
            )
        }
        let effect = graph.makeStatefulRule(
            AppearanceEffect(modifier: modifier, phase: inputs.base.phase)
        )
        graph.makeSideEffectRule {
            _ = effect.value
            return ()
        }
        let layout = graph.makeRule {
            let value = view._attribute.value
            return LayoutComputer.fixed(CGSize(width: value.width, height: 10))
        }
        return _ViewOutputs(layoutComputer: OptionalAttribute(layout))
    }

    typealias Body = Never
}

extension DynamicContainerLifecycleSizedRow: TestPrimitiveView {}

private enum DynamicContainerViewThatFitsSelectionKey: PreferenceKey {
    static var defaultValue: Int { 0 }

    static func reduce(value: inout Int, nextValue: () -> Int) {
        value = nextValue()
    }
}

private struct DynamicContainerViewThatFitsFallbackRoot: View {
    var primaryWidth: CGFloat
    var recorder: DynamicContainerLifecycleRecorder

    var body: some View {
        ViewThatFits(in: .horizontal) {
            DynamicContainerLifecycleSizedRow(
                row: "primary",
                width: primaryWidth,
                recorder: recorder
            )
            DynamicContainerLifecycleSizedRow(
                row: "fallback",
                width: 10,
                recorder: recorder
            )
        }
    }
}

private struct DynamicContainerConditionalForEachRoot: View {
    var rows: [String]
    var recorder: DynamicContainerLifecycleRecorder
    var showRows = true

    var body: some View {
        VStack {
            if showRows {
                ForEach(rows, id: \.self) { row in
                    DynamicContainerLifecycleRow(row: row, recorder: recorder)
                        .transition(.opacity)
                }
            } else {
                EmptyView()
            }
        }
    }
}

private struct DynamicContainerConditionalTransitionRoot: View {
    var showChild: Bool
    var lifecycleRecorder: DynamicContainerLifecycleRecorder
    var phaseRecorder: DynamicContainerTransitionPhaseRecorder

    var body: some View {
        VStack {
            if showChild {
                DynamicContainerLifecycleRow(row: "row", recorder: lifecycleRecorder)
                    .transition(
                        AnyTransition(
                            DynamicContainerPhaseRecordingTransition(recorder: phaseRecorder)
                        )
                    )
            } else {
                Text("empty")
            }
        }
    }
}

private final class DynamicContainerTransitionValueCapture {
    var source: Attribute<DynamicContainerTransitionValueModifier>?
    var animated: Attribute<DynamicContainerTransitionValueModifier>?
}

private struct DynamicContainerTransitionValueCaptureInput: GraphInput {
    typealias Value = DynamicContainerTransitionValueCapture?

    static var defaultValue: Value { nil }

    static func valuesEqual(_ lhs: Value, _ rhs: Value) -> Bool {
        lhs === rhs
    }
}

private struct DynamicContainerTransitionValueCaptureModifier:
    ViewModifier, _GraphInputsModifier
{
    typealias Body = Never

    var capture: DynamicContainerTransitionValueCapture

    static func _makeInputs(
        modifier: _GraphValue<Self>,
        inputs: inout _GraphInputs
    ) {
        inputs[DynamicContainerTransitionValueCaptureInput.self] =
            modifier._attribute.value.capture
    }
}

private struct DynamicContainerTransitionValueTransition: Transition {
    func body(content: Content, phase: TransitionPhase) -> some View {
        content.modifier(
            DynamicContainerTransitionValueModifier(
                value: phase.isIdentity ? 1 : 0
            )
        )
    }
}

private struct DynamicContainerTransitionValueModifier: ViewModifier, Animatable {
    var value: Double

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    typealias Body = Never

    static func _makeView(
        modifier: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        var animated = modifier
        Self._makeAnimatable(value: &animated, inputs: inputs.base)
        guard let capture =
                inputs.base[DynamicContainerTransitionValueCaptureInput.self]
        else {
            fatalError(
                "DynamicContainerTransitionValueModifier requires its " +
                    "test capture input."
            )
        }
        capture.source = modifier._attribute
        capture.animated = animated._attribute
        return _OpacityEffectSupport.makeView(
            modifier: animated,
            opacity: animated[\.value],
            inputs: inputs,
            body: body
        )
    }
}

private struct DynamicContainerConditionalValueTransitionRoot: View {
    var showChild: Bool
    var capture: DynamicContainerTransitionValueCapture

    var body: some View {
        VStack {
            if showChild {
                Text("child")
                    .transition(
                        AnyTransition(
                            DynamicContainerTransitionValueTransition()
                        )
                    )
            } else {
                Text("empty")
            }
        }
        .modifier(
            DynamicContainerTransitionValueCaptureModifier(capture: capture)
        )
    }
}

private struct DynamicContainerAsymmetricInsertionValueTransitionRoot: View {
    var showChild: Bool
    var capture: DynamicContainerTransitionValueCapture

    var body: some View {
        ZStack {
            Text("background")
            if showChild {
                Text("child")
                    .transition(
                        .asymmetric(
                            insertion: AnyTransition(
                                DynamicContainerTransitionValueTransition()
                            )
                            .combined(with: .opacity),
                            removal: .move(edge: .trailing)
                                .combined(with: .opacity)
                        )
                    )
            }
        }
        .modifier(
            DynamicContainerTransitionValueCaptureModifier(capture: capture)
        )
    }
}

private struct DynamicContainerZStackAsymmetricTransitionRoot: View {
    var showChild: Bool
    var capture: DynamicContainerTransitionValueCapture

    var body: some View {
        ZStack {
            Text("background")
            if showChild {
                Text("child")
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.65)
                                .combined(with: .opacity),
                            removal: AnyTransition(
                                DynamicContainerTransitionValueTransition()
                            )
                            .combined(with: .opacity)
                        )
                    )
            }
        }
        .modifier(
            DynamicContainerTransitionValueCaptureModifier(capture: capture)
        )
    }
}

private struct DynamicContainerOptionalForEachRoot: View {
    var rows: [String]
    var recorder: DynamicContainerLifecycleRecorder
    var showRows = true

    var optionalRows: ForEach<[String], String, DynamicContainerOptionalLifecycleRow>? {
        guard showRows else { return nil }
        return ForEach(rows, id: \.self) { row in
            DynamicContainerOptionalLifecycleRow(row: row, recorder: recorder)
        }
    }

    var body: some View {
        VStack {
            optionalRows
        }
    }
}

private struct DynamicContainerOptionalLifecycleRow: View {
    var row: String
    var recorder: DynamicContainerLifecycleRecorder

    var body: some View {
        DynamicContainerLifecycleRow(row: row, recorder: recorder)
            .transition(.opacity)
    }
}

private struct DynamicContainerMoveLayoutCustomLayoutRoot: View {
    var rows: [String]
    var recorder: DynamicContainerLifecycleRecorder

    var body: some View {
        DynamicContainerProbeHStackLayout(spacing: 0) {
            ForEach(rows, id: \.self) { row in
                DynamicContainerLifecycleSizedRow(
                    row: row,
                    width: 80,
                    recorder: recorder
                )
                .transition(.move(edge: .leading))
            }
        }
    }
}

private struct DynamicContainerOptionalForkRetargetRoot: View {
    var rows: [String]
    var target: Double
    var recorder: AnimationCompletionRecorder
    var capture: DynamicContainerForkRetargetCapture
    var showRows = true

    var optionalRows: ForEach<[String], String, DynamicContainerOptionalForkRetargetItem>? {
        guard showRows else { return nil }
        return ForEach(rows, id: \.self) { row in
            DynamicContainerOptionalForkRetargetItem(
                row: row,
                target: target,
                recorder: recorder,
                capture: capture
            )
        }
    }

    var body: some View {
        VStack {
            optionalRows
        }
    }
}

private struct DynamicContainerOptionalForkRetargetItem: View {
    var row: String
    var target: Double
    var recorder: AnimationCompletionRecorder
    var capture: DynamicContainerForkRetargetCapture

    var body: some View {
        DynamicContainerForkRetargetRow(
            row: row,
            effect: _OpacityEffect(opacity: row == "row" ? target : 0),
            recorder: recorder,
            capture: capture
        )
        .transition(.opacity)
    }
}

/// Lets the direct-attribute harness explicitly consume the transactional
/// collected-placement rule that a normal host update samples automatically.
private protocol DynamicContainerLazyPlacementSampler {
    func resampleCollectedPlacements()
}

extension LazyScrollable: DynamicContainerLazyPlacementSampler {
    fileprivate func resampleCollectedPlacements() {
        guard let cache else { return }
        cache._placedSubviews.invalidateValue()
        _ = cache._placedSubviews.value
    }

}

private struct DynamicContainerProbeHStackLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        var width: CGFloat = 0
        var height: CGFloat = 0
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            width += size.width
            height = max(height, size.height)
            if index > 0 {
                width += spacing
            }
        }
        return CGSize(width: width, height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var x = bounds.minX
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            subview.place(
                at: CGPoint(x: x, y: bounds.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(size)
            )
            x += size.width + spacing
        }
    }
}

private struct DynamicContainerProbeVStackLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        var width: CGFloat = 0
        var height: CGFloat = 0
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
            width = max(width, size.width)
            height += size.height
            if index > 0 {
                height += spacing
            }
        }
        return CGSize(width: width, height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var y = bounds.minY
        for subview in subviews {
            let childProposal = ProposedViewSize(width: bounds.width, height: nil)
            let size = subview.sizeThatFits(childProposal)
            subview.place(
                at: CGPoint(x: bounds.minX, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(size)
            )
            y += size.height + spacing
        }
    }
}

private struct RetainedRemovalOrdinaryPreferenceKey: PreferenceKey {
    static let defaultValue = ""

    static func reduce(value: inout String, nextValue: () -> String) {
        value += nextValue()
    }
}
