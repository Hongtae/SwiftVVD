import XCTest
@testable import VUI

final class AppearanceActionModifierTests: XCTestCase {
    override func tearDown() {
        super.tearDown()
    }

    func testAppearanceEffectStorageLabelsMatchTrackedAttributeShape() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            let modifier = graph.makeInput(value: _AppearanceActionModifier())
            let phase = graph.makeInput(value: Phase())
            let effect = AppearanceEffect(modifier: modifier, phase: phase)

            XCTAssertEqual(
                Mirror(reflecting: effect).children.map(\.label),
                [
                    "modifier",
                    "phase",
                    "lastPhase",
                    "appear",
                    "disappear",
                    "isAppeared",
                    "isRemoved",
                    "attribute",
                ]
            )
        }
    }

    func testMakeViewMarksAppearanceEffectTransactionalAndRemovable() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            let inputs = makeAppearanceViewInputs(graph: graph)
            let modifier = graph.makeInput(value: _AppearanceActionModifier())
            let lowerBound = graph.makeInput(value: ())

            _ = _AppearanceActionModifier._makeView(
                modifier: _GraphValue(_attribute: modifier),
                inputs: inputs
            ) { _, _ in
                _ViewOutputs()
            }

            let upperBound = graph.makeInput(value: ())
            let effects = (lowerBound.identifier.rawValue + 1..<upperBound.identifier.rawValue)
                .map { AGAttribute(rawValue: $0) }
                .filter { $0._bodyType == AppearanceEffect.self }

            XCTAssertEqual(effects.count, 1)
            XCTAssertEqual(graph.flags(for: effects[0]).rawValue, 3)
        }
    }

    func testCrossGraphRootEvaluatesAppearanceEffectDuringTransactionalUpdate() {
        let sourceGraph = _AGGraph()
        let sourceContext = _AGGraphContext(graph: sourceGraph)
        let rendererHost = TestViewRendererHost()
        var appearCount = 0

        let viewGraph = sourceContext.withCurrent {
            let content = sourceGraph.makeInput(
                value: AnyView(
                    EmptyView().onAppear {
                        appearCount += 1
                    }
                )
            )
            return ViewGraph(
                crossGraphContentAttr: content,
                sourceGraph: sourceGraph,
                rendererHost: rendererHost,
                requestedOutputs: []
            )
        }
        rendererHost.storage = viewGraph

        viewGraph.updateOutputs(at: Time(seconds: 0))

        XCTAssertEqual(appearCount, 1)
    }

    func testDynamicLayoutOmitsLayoutEmptyAppearanceAndUpdatesMaterializedControl() throws {
        let rendererHost = TestViewRendererHost()
        var emptyAppearCount = 0
        var controlAppearCount = 0
        let content = VStack {
            EmptyView().onAppear {
                emptyAppearCount += 1
            }
            Color.clear
                .frame(width: 1, height: 1)
                .onAppear {
                    controlAppearCount += 1
                }
        }
        let viewGraph = ViewGraph(
            rootViewType: type(of: content),
            content: content,
            rendererHost: rendererHost,
            requestedOutputs: []
        )
        rendererHost.storage = viewGraph

        try viewGraph.data.withCurrent {
            try AGSubgraph.withCurrent(viewGraph.data.rootSubgraph) {
                let rootLayoutComputer = try XCTUnwrap(viewGraph.rootLayoutComputer)
                _ = rootLayoutComputer.value.sizeThatFits(.unspecified)
            }
        }
        XCTAssertEqual(emptyAppearCount, 0)
        XCTAssertEqual(controlAppearCount, 0)

        viewGraph.updateOutputs(at: Time(seconds: 0))

        XCTAssertEqual(emptyAppearCount, 0)
        XCTAssertEqual(controlAppearCount, 1)
    }

    func testAppearanceEffectStoresCurrentAttributeDuringUpdate() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            let modifier = graph.makeInput(value: _AppearanceActionModifier())
            let phase = graph.makeInput(value: Phase())
            let effect = graph.makeStatefulRule(
                AppearanceEffect(modifier: modifier, phase: phase)
            )

            _ = effect.value

            var storedAttribute = AGAttribute.invalid
            graph.mutateStatefulRule(effect.identifier, as: AppearanceEffect.self) { effect in
                storedAttribute = effect.attribute
            }
            XCTAssertEqual(storedAttribute, effect.identifier)
        }
    }

    func testAppearanceEffectQueuesAppearOnceUntilPhaseChanges() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            var events: [String] = []
            let modifier = graph.makeInput(
                value: _AppearanceActionModifier(
                    appear: { events.append("appear") },
                    disappear: { events.append("disappear") }
                )
            )
            let phase = graph.makeInput(value: Phase())
            let effect = graph.makeStatefulRule(
                AppearanceEffect(modifier: modifier, phase: phase)
            )

            graph.makeSideEffectRule {
                _ = effect.value
                return ()
            }

            XCTAssertEqual(events, ["appear"])

            _ = effect.value
            XCTAssertEqual(events, ["appear"])

            var nextPhase = phase.value
            nextPhase.resetSeed = 1
            phase.setValue(nextPhase)

            XCTAssertEqual(events, ["appear", "disappear", "appear"])
        }
    }

    func testAppearanceEffectPhaseChangeQueuesDisappearAndAppearWithoutRemovalReason() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            var events: [String] = []
            let modifier = graph.makeInput(
                value: _AppearanceActionModifier(
                    appear: { events.append("appear") },
                    disappear: { events.append("disappear") }
                )
            )
            let phase = graph.makeInput(value: Phase())
            let effect = graph.makeStatefulRule(
                AppearanceEffect(modifier: modifier, phase: phase)
            )

            _ = effect.value
            XCTAssertEqual(events, ["appear"])

            var nextPhase = phase.value
            nextPhase.resetSeed = 1
            phase.setValue(nextPhase)

            Update.begin()
            _ = effect.value

            XCTAssertEqual(Update.queuedActionReasons, [nil, nil])
            XCTAssertEqual(events, ["appear"])

            Update.end()

            XCTAssertEqual(Update.queuedActionReasons, [])
            XCTAssertEqual(events, ["appear", "disappear", "appear"])
        }
    }

    func testAppearanceEffectDoesNotAppearWhilePhaseIsBeingRemoved() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            var events: [String] = []
            let modifier = graph.makeInput(
                value: _AppearanceActionModifier(
                    appear: { events.append("appear") },
                    disappear: { events.append("disappear") }
                )
            )
            var initialPhase = Phase()
            initialPhase.isBeingRemoved = true
            let phase = graph.makeInput(value: initialPhase)
            let effect = graph.makeStatefulRule(
                AppearanceEffect(modifier: modifier, phase: phase)
            )

            graph.makeSideEffectRule {
                _ = effect.value
                return ()
            }

            XCTAssertEqual(events, [])

            var insertedPhase = phase.value
            insertedPhase.isBeingRemoved = false
            phase.setValue(insertedPhase)

            XCTAssertEqual(events, ["appear"])

            var removedPhase = phase.value
            removedPhase.isBeingRemoved = true
            phase.setValue(removedPhase)

            XCTAssertEqual(events, ["appear", "disappear"])
        }
    }

    func testAppearanceEffectUsesLatestCallbacksAfterModifierChange() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            var events: [String] = []
            let modifier = graph.makeInput(
                value: _AppearanceActionModifier(
                    appear: { events.append("first-appear") },
                    disappear: { events.append("first-disappear") }
                )
            )
            let phase = graph.makeInput(value: Phase())
            let effect = graph.makeStatefulRule(
                AppearanceEffect(modifier: modifier, phase: phase)
            )

            graph.makeSideEffectRule {
                _ = effect.value
                return ()
            }

            XCTAssertEqual(events, ["first-appear"])

            modifier.setValue(
                _AppearanceActionModifier(
                    appear: { events.append("second-appear") },
                    disappear: { events.append("second-disappear") }
                )
            )

            XCTAssertEqual(events, ["first-appear"])

            var nextPhase = phase.value
            nextPhase.resetSeed = 1
            phase.setValue(nextPhase)

            XCTAssertEqual(events, ["first-appear", "second-disappear", "second-appear"])
        }
    }

    func testOnDisappearOnlyModifierQueuesDisappearAfterPhaseChange() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            var events: [String] = []
            let modifier = graph.makeInput(
                value: _AppearanceActionModifier(
                    appear: nil,
                    disappear: { events.append("disappear") }
                )
            )
            let phase = graph.makeInput(value: Phase())
            let effect = graph.makeStatefulRule(
                AppearanceEffect(modifier: modifier, phase: phase)
            )

            graph.makeSideEffectRule {
                _ = effect.value
                return ()
            }

            XCTAssertEqual(events, [])

            var nextPhase = phase.value
            nextPhase.resetSeed = 1
            phase.setValue(nextPhase)

            XCTAssertEqual(events, ["disappear"])
        }
    }

    func testAppearanceEffectQueuesDisappearWhenHostSubgraphIsRemoved() {
        let host = GraphHost()

        host.data.withCurrent {
            AGSubgraph.withCurrent(host.data.rootSubgraph) {
                var events: [String] = []
                let modifier = host.data.graph.makeInput(
                    value: _AppearanceActionModifier(
                        appear: { events.append("appear") },
                        disappear: { events.append("disappear") }
                    )
                )
                let phase = host.data.graph.makeInput(value: Phase())
                let effect = host.data.graph.makeStatefulRule(
                    AppearanceEffect(modifier: modifier, phase: phase)
                )

                _ = effect.value
                XCTAssertEqual(events, ["appear"])

                host.removedState = .unattached
                XCTAssertEqual(events, ["appear", "disappear"])

                _ = effect.value
                XCTAssertEqual(events, ["appear", "disappear"])
            }
        }
    }

    func testAppearanceEffectWillRemoveQueuesDisappearWithRemovalReason() {
        let host = GraphHost()

        host.data.withCurrent {
            AGSubgraph.withCurrent(host.data.rootSubgraph) {
                var events: [String] = []
                let modifier = host.data.graph.makeInput(
                    value: _AppearanceActionModifier(
                        appear: { events.append("appear") },
                        disappear: { events.append("disappear") }
                    )
                )
                let phase = host.data.graph.makeInput(value: Phase())
                let effect = host.data.graph.makeStatefulRule(
                    AppearanceEffect(modifier: modifier, phase: phase)
                )

                _ = effect.value
                XCTAssertEqual(events, ["appear"])

                Update.begin()
                AppearanceEffect.willRemove(attribute: effect.identifier)

                XCTAssertEqual(Update.queuedActionReasons, [.onDisappear])
                XCTAssertEqual(events, ["appear"])

                Update.end()

                XCTAssertEqual(Update.queuedActionReasons, [])
                XCTAssertEqual(events, ["appear", "disappear"])
            }
        }
    }

    func testAppearanceEffectQueuesTrackedRemovalWhenFirstEvaluatedWhileHostIsUnattached() {
        let host = GraphHost()
        host.removedState = .unattached

        host.data.withCurrent {
            AGSubgraph.withCurrent(host.data.rootSubgraph) {
                var events: [String] = []
                let modifier = host.data.graph.makeInput(
                    value: _AppearanceActionModifier(
                        appear: { events.append("appear") },
                        disappear: { events.append("disappear") }
                    )
                )
                let phase = host.data.graph.makeInput(value: Phase())
                let effect = host.data.graph.makeStatefulRule(
                    AppearanceEffect(modifier: modifier, phase: phase)
                )

                _ = effect.value
                XCTAssertEqual(events, ["appear", "disappear"])

                _ = effect.value
                XCTAssertEqual(events, ["appear", "disappear"])
            }
        }
    }

    func testAppearanceEffectTrackedRemovalIsQueuedThroughUpdateAction() {
        let host = GraphHost()
        host.removedState = .unattached

        host.data.withCurrent {
            AGSubgraph.withCurrent(host.data.rootSubgraph) {
                var events: [String] = []
                let modifier = host.data.graph.makeInput(
                    value: _AppearanceActionModifier(
                        appear: { events.append("appear") },
                        disappear: { events.append("disappear") }
                    )
                )
                let phase = host.data.graph.makeInput(value: Phase())
                let effect = host.data.graph.makeStatefulRule(
                    AppearanceEffect(modifier: modifier, phase: phase)
                )

                Update.begin()
                _ = effect.value

                XCTAssertEqual(Update.queuedActionReasons, [nil, nil])
                XCTAssertEqual(events, [])

                Update.end()

                XCTAssertEqual(Update.queuedActionReasons, [])
                XCTAssertEqual(events, ["appear", "disappear"])
            }
        }
    }

    func testAppearanceEffectTrackedRemovalQueuesRemovalInNextDispatchPass() {
        let host = GraphHost()
        host.removedState = .unattached

        host.data.withCurrent {
            AGSubgraph.withCurrent(host.data.rootSubgraph) {
                var events: [String] = []
                let modifier = host.data.graph.makeInput(
                    value: _AppearanceActionModifier(
                        appear: {
                            events.append("appear")
                            Update.enqueueAction {
                                events.append("appear-followup")
                            }
                        },
                        disappear: { events.append("disappear") }
                    )
                )
                let phase = host.data.graph.makeInput(value: Phase())
                let effect = host.data.graph.makeStatefulRule(
                    AppearanceEffect(modifier: modifier, phase: phase)
                )

                Update.begin()
                _ = effect.value

                XCTAssertEqual(Update.queuedActionReasons, [nil, nil])
                XCTAssertEqual(events, [])

                Update.end()

                XCTAssertEqual(Update.queuedActionReasons, [])
                XCTAssertEqual(events, ["appear", "appear-followup", "disappear"])
            }
        }
    }

    func testAppearanceEffectTrackedRemovalDoesNotRecheckHostStateWhenActionDrains() {
        let host = GraphHost()
        host.removedState = .unattached

        host.data.withCurrent {
            AGSubgraph.withCurrent(host.data.rootSubgraph) {
                var events: [String] = []
                let modifier = host.data.graph.makeInput(
                    value: _AppearanceActionModifier(
                        appear: { events.append("appear") },
                        disappear: { events.append("disappear") }
                    )
                )
                let phase = host.data.graph.makeInput(value: Phase())
                let effect = host.data.graph.makeStatefulRule(
                    AppearanceEffect(modifier: modifier, phase: phase)
                )

                Update.begin()
                _ = effect.value

                XCTAssertEqual(events, [])
                XCTAssertEqual(Update.queuedActionReasons, [nil, nil])

                host.removedState = []
                Update.end()

                XCTAssertEqual(events, ["appear", "disappear"])
            }
        }
    }

    func testAppearanceEffectReappearsAfterHostSubgraphIsReinsertedAndUpdated() {
        let host = GraphHost()

        host.data.withCurrent {
            AGSubgraph.withCurrent(host.data.rootSubgraph) {
                var events: [String] = []
                let modifier = host.data.graph.makeInput(
                    value: _AppearanceActionModifier(
                        appear: { events.append("appear") },
                        disappear: { events.append("disappear") }
                    )
                )
                let phase = host.data.graph.makeInput(value: Phase())
                let effect = host.data.graph.makeStatefulRule(
                    AppearanceEffect(modifier: modifier, phase: phase)
                )

                _ = effect.value
                host.removedState = .unattached
                host.removedState = []
                _ = effect.value

                XCTAssertEqual(events, ["appear", "disappear", "appear"])
            }
        }
    }

    func testAppearanceEffectReinsertInvalidationNotifiesGraphDelegate() {
        let delegate = AppearanceGraphDelegateRecorder()
        let host = AppearanceDelegateGraphHost(delegate: delegate)

        host.data.withCurrent {
            AGSubgraph.withCurrent(host.data.rootSubgraph) {
                var events: [String] = []
                let modifier = host.data.graph.makeInput(
                    value: _AppearanceActionModifier(
                        appear: { events.append("appear") },
                        disappear: { events.append("disappear") }
                    )
                )
                let phase = host.data.graph.makeInput(value: Phase())
                let effect = host.data.graph.makeStatefulRule(
                    AppearanceEffect(modifier: modifier, phase: phase)
                )

                _ = effect.value
                host.removedState = .unattached

                XCTAssertTrue(delegate.events.isEmpty)

                host.removedState = []

                XCTAssertEqual(delegate.events, ["change"])
                XCTAssertEqual(events, ["appear", "disappear"])
            }
        }
    }

    func testAppearanceEffectReinsertSkipsDelegateWhenStoredAttributeIsInvalid() {
        let delegate = AppearanceGraphDelegateRecorder()
        let host = AppearanceDelegateGraphHost(delegate: delegate)

        host.data.withCurrent {
            AGSubgraph.withCurrent(host.data.rootSubgraph) {
                let modifier = host.data.graph.makeInput(value: _AppearanceActionModifier())
                let phase = host.data.graph.makeInput(value: Phase())
                let effect = host.data.graph.makeStatefulRule(
                    AppearanceEffect(modifier: modifier, phase: phase)
                )

                AppearanceEffect.didReinsert(attribute: effect.identifier)

                XCTAssertTrue(delegate.events.isEmpty)
            }
        }
    }

    func testAppearanceEffectSkipsAppearUpdatesWhileRemoved() {
        let host = GraphHost()

        host.data.withCurrent {
            AGSubgraph.withCurrent(host.data.rootSubgraph) {
                var events: [String] = []
                let modifier = host.data.graph.makeInput(
                    value: _AppearanceActionModifier(
                        appear: { events.append("appear") },
                        disappear: { events.append("disappear") }
                    )
                )
                let phase = host.data.graph.makeInput(value: Phase())
                let effect = host.data.graph.makeStatefulRule(
                    AppearanceEffect(modifier: modifier, phase: phase)
                )

                _ = effect.value
                host.removedState = .unattached

                var nextPhase = phase.value
                nextPhase.resetSeed = 1
                phase.setValue(nextPhase)
                _ = effect.value

                XCTAssertEqual(events, ["appear", "disappear"])

                host.removedState = []
                _ = effect.value

                XCTAssertEqual(events, ["appear", "disappear", "appear"])
            }
        }
    }
}

private func makeAppearanceViewInputs(graph: _AGGraph) -> _ViewInputs {
    let environment = graph.makeInput(value: EnvironmentValues())
    let base = _GraphInputs(
        time: graph.makeInput(value: Time(seconds: 0)),
        phase: graph.makeInput(value: Phase()),
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
        size: graph.makeInput(value: ViewSize(width: 0, height: 0)),
        safeAreaInsets: OptionalAttribute(),
        containerSize: OptionalAttribute(),
        stackOrientation: nil
    )
}

private func drainActionOutbox(for host: GraphHost) {
    while !host.data.graph.actionOutbox.isEmpty {
        let actions = host.data.graph.actionOutbox
        host.data.graph.actionOutbox.removeAll()
        actions.forEach { $0() }
    }
}

private final class AppearanceDelegateGraphHost: GraphHost {
    private let delegateRecorder: AppearanceGraphDelegateRecorder

    init(delegate: AppearanceGraphDelegateRecorder) {
        self.delegateRecorder = delegate
        super.init(data: Data())
        delegate.host = self
    }

    override var graphDelegate: (any GraphDelegate)? {
        delegateRecorder
    }
}

private final class AppearanceGraphDelegateRecorder: GraphDelegate {
    weak var host: GraphHost?
    private(set) var events: [String] = []

    func updateGraph<T>(body: (GraphHost) -> T) -> T {
        guard let host else {
            fatalError("AppearanceGraphDelegateRecorder used before attaching a host.")
        }
        events.append("update")
        return body(host)
    }

    func graphDidChange() {
        events.append("change")
    }
}
