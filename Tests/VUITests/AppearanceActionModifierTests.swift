import XCTest
@testable import VUI

final class AppearanceActionModifierTests: XCTestCase {
    override func tearDown() {
        Semantics.overrides = Semantics.Overrides()
        super.tearDown()
    }

    func testAppearanceEffectQueuesAppearOnceUntilPhaseChanges() {
        let graph = AttributeGraph()
        let ref = AttributeGraphRef(graph: graph)

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

    func testAppearanceEffectUsesLatestCallbacksAfterModifierChange() {
        let graph = AttributeGraph()
        let ref = AttributeGraphRef(graph: graph)

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
        let graph = AttributeGraph()
        let ref = AttributeGraphRef(graph: graph)

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
            AGSubgraph.$current.withValue(host.data.rootSubgraph) {
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

    func testAppearanceEffectQueuesTrackedRemovalWhenFirstEvaluatedWhileHostIsUnattached() {
        let host = GraphHost()
        host.removedState = .unattached

        host.data.withCurrent {
            AGSubgraph.$current.withValue(host.data.rootSubgraph) {
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
                drainActionOutbox(for: host)
                XCTAssertEqual(events, ["appear", "disappear"])

                _ = effect.value
                drainActionOutbox(for: host)
                XCTAssertEqual(events, ["appear", "disappear"])
            }
        }
    }

    func testAppearanceEffectTrackedRemovalIsQueuedThroughActionOutbox() {
        let host = GraphHost()
        host.removedState = .unattached

        host.data.withCurrent {
            AGSubgraph.$current.withValue(host.data.rootSubgraph) {
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
                XCTAssertEqual(Update.queuedActionReasons, [])
                XCTAssertEqual(host.data.graph.actionOutbox.count, 1)

                Update.begin()
                let actions = host.data.graph.actionOutbox
                host.data.graph.actionOutbox.removeAll()
                actions.forEach { $0() }

                XCTAssertEqual(Update.queuedActionReasons, [0x11])
                XCTAssertEqual(events, ["appear"])

                Update.end()

                XCTAssertEqual(Update.queuedActionReasons, [])
                XCTAssertEqual(events, ["appear", "disappear"])
            }
        }
    }

    func testAppearanceEffectTrackedRemovalUsesRuntimeV6Gate() {
        Semantics.overrides = Semantics.Overrides(build: nil, runtime: .v5)

        let host = GraphHost()
        host.removedState = .unattached

        host.data.withCurrent {
            AGSubgraph.$current.withValue(host.data.rootSubgraph) {
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
                drainActionOutbox(for: host)

                XCTAssertEqual(events, ["appear"])
            }
        }
    }

    func testAppearanceEffectReappearsAfterHostSubgraphIsReinsertedAndUpdated() {
        let host = GraphHost()

        host.data.withCurrent {
            AGSubgraph.$current.withValue(host.data.rootSubgraph) {
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
            AGSubgraph.$current.withValue(host.data.rootSubgraph) {
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

    func testAppearanceEffectSkipsAppearUpdatesWhileRemoved() {
        let host = GraphHost()

        host.data.withCurrent {
            AGSubgraph.$current.withValue(host.data.rootSubgraph) {
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
        super.init()
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
