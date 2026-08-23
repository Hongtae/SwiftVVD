import Foundation
import XCTest
@testable import VUI
@testable import VVD

final class HoverEventDispatcherTests: XCTestCase {
    // ASSERTIONS eventBindingManagerCurrentOwnerObserved
    @MainActor
    func testCurrentBindingManagerComesFromCurrentViewRendererHost() {
        let controller = WindowController(
            content: EmptyView(),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(Self.self)
            )
        )

        controller.viewGraph.data.withCurrent {
            XCTAssertTrue(
                EventBindingManager.current === controller.eventBindingManager
            )
        }

        let nonViewHost = GraphHost()
        nonViewHost.data.withCurrent {
            XCTAssertNil(EventBindingManager.current)
        }
    }

    // ASSERTIONS hoverMakeViewIndependentBranchesObserved hoverPlatformItemBehaviorObserved
    func testPlatformItemHoverTransformDoesNotRequireEventHost() throws {
        let host = GraphHost()
        let graph = host.data.graph
        var hoverEvents: [Bool] = []
        var replacedEvents: [Bool] = []

        try host.data.withCurrent {
            var keys = PreferenceKeys()
            keys.add(PlatformItemList.Key.self)
            var inputs = makeHoverViewInputs(graph: graph)
            inputs.preferences = PreferencesInputs(
                keys: keys,
                hostKeys: graph.makeInput(value: keys)
            )
            inputs[PlatformItemListFlagsInput.self] =
                SelectionPlatformItemListFlags.flags

            let modifier = graph.makeInput(
                value: _HoverRegionModifier { hovering in
                    hoverEvents.append(hovering)
                }
            )
            var first = PlatformItemList.Item()
            first.text = NSAttributedString(string: "Primary")
            first.onHover = { hovering in
                replacedEvents.append(hovering)
            }
            var second = PlatformItemList.Item()
            second.text = NSAttributedString(string: "Secondary")
            second.tooltip = "details"
            let source = graph.makeInput(
                value: PlatformItemList(items: [first, second])
            )

            let outputs = _HoverRegionModifier._makeView(
                modifier: _GraphValue(_attribute: modifier),
                inputs: inputs
            ) { _, _ in
                var outputs = _ViewOutputs()
                outputs.preferences.append(
                    PlatformItemList.Key.self,
                    node: source.identifier
                )
                return outputs
            }

            let output = try XCTUnwrap(
                outputs.preferences.value(for: PlatformItemList.Key.self)
            )
            let list = Attribute<PlatformItemList>(output).value
            XCTAssertEqual(list.items.count, 1)
            XCTAssertEqual(list.items[0].text?.string, "Primary")
            XCTAssertEqual(list.items[0].secondaryText?.string, "Secondary")
            XCTAssertEqual(list.items[0].tooltip, "details")

            list.items[0].onHover?(true)
            list.items[0].onHover?(false)
        }

        XCTAssertEqual(hoverEvents, [true, false])
        XCTAssertTrue(replacedEvents.isEmpty)
    }

    // ASSERTIONS hoverResponderChildRemovalEndsPhaseObserved
    func testRemovingHoverResponderChildEndsItsActivePhase() {
        let recorder = HoverEventRecorder()
        let data = GraphHost.Data()
        var responder: HoverResponder!
        var responderChild: Attribute<[ViewResponder]>!

        data.withCurrent {
            AGSubgraph.withCurrent(data.rootSubgraph) {
                let inputs = makeHoverViewInputs(graph: data.graph)
                responder = HoverResponder(inputs: inputs)
                responder.transform = .identity
                responder.size = CGSize(width: 100, height: 100)
                responder.isEnabled = true

                responderChild = data.graph.makeStatefulRule(
                    HoverResponderChild(
                        responder: responder,
                        coordinateSpace: .eager(.local),
                        _callback: data.graph.makeInput(
                            value: HoverCallback.nonSpatial {
                                recorder.events.append("hover:\($0)")
                            }
                        ),
                        _children: data.graph.makeInput(value: []),
                        _position: inputs.position,
                        _transform: inputs.transform,
                        _size: inputs.size,
                        _isEnabled: data.graph.makeInput(value: true),
                        _updateBindingManager: data.graph.makeInput(value: ())
                    )
                )
                _ = responderChild.value
                responder.updatePhase(.active(CGPoint(x: 10, y: 10)))
                HoverResponderChild.willRemove(
                    attribute: responderChild.identifier
                )
            }
        }

        XCTAssertEqual(recorder.events, ["hover:true", "hover:false"])
        XCTAssertEqual(responder.currentPhase, .ended)
    }

    // ASSERTIONS responderNodeBaseBindEventNilObserved
    func testResponderNodeBaseBindingReturnsNoResponder() {
        XCTAssertNil(ResponderNode().bindEvent(hoverEvent(phase: .began)))
    }

    // ASSERTIONS hoverEventBindingAncestorDispatchObserved
    func testConsumedHoverUsesOneRootBindingPassAndSkipsGestureGraph() {
        let recorder = HoverEventRecorder()
        let fixture = makeHoverResponderFixture(recorder: recorder, name: "hover")
        let responder = fixture.responder
        let harness = HoverDispatchHarness(
            target: responder,
            retaining: [fixture]
        )
        let eventID = EventID(type: HoverEvent.self, serial: 7)

        XCTAssertEqual(
            harness.manager.send(
                [eventID: hoverEvent(phase: .began)]
            ),
            Set([eventID])
        )
        XCTAssertEqual(harness.root.bindCount, 1)
        XCTAssertEqual(harness.host.downstreamSendCount, 0)
        XCTAssertEqual(recorder.events, ["hover:true"])

        XCTAssertEqual(
            harness.manager.send(
                [eventID: hoverEvent(
                    phase: .active,
                    point: CGPoint(x: 12, y: 14)
                )]
            ),
            Set([eventID])
        )
        XCTAssertEqual(harness.root.bindCount, 2)
        XCTAssertEqual(harness.host.downstreamSendCount, 0)
        XCTAssertEqual(recorder.events, ["hover:true"])

        XCTAssertEqual(
            harness.manager.send(
                [eventID: hoverEvent(phase: .ended)]
            ),
            Set([eventID])
        )
        XCTAssertEqual(harness.root.bindCount, 2)
        XCTAssertEqual(harness.host.downstreamSendCount, 0)
        XCTAssertEqual(recorder.events, ["hover:true", "hover:false"])
    }

    // ASSERTIONS hoverEventBindingAncestorDispatchObserved scrollIndicatorPresentationGeometryObserved
    func testControlObserverSharesHoverRootBindingAndTerminalLifetime() {
        let recorder = HoverEventRecorder()
        let fixture = makeHoverResponderFixture(recorder: recorder, name: "hover")
        let observer = HoverObserverResponder()
        fixture.responder.parent = observer
        let harness = HoverDispatchHarness(
            target: fixture.responder,
            retaining: [fixture, observer]
        )
        let eventID = EventID(type: HoverEvent.self, serial: 9)

        XCTAssertEqual(
            harness.manager.send([
                eventID: hoverEvent(phase: .began)
            ]),
            Set([eventID])
        )
        XCTAssertEqual(harness.root.bindCount, 1)
        XCTAssertEqual(recorder.events, ["hover:true"])
        XCTAssertEqual(observer.updatedEventIDs, [eventID])

        XCTAssertEqual(
            harness.manager.send([
                eventID: hoverEvent(
                    phase: .active,
                    point: CGPoint(x: 12, y: 14)
                )
            ]),
            Set([eventID])
        )
        XCTAssertEqual(harness.root.bindCount, 2)
        XCTAssertEqual(observer.updatedEventIDs, [eventID, eventID])

        XCTAssertEqual(
            harness.manager.send([
                eventID: hoverEvent(phase: .ended)
            ]),
            Set([eventID])
        )
        XCTAssertEqual(harness.root.bindCount, 2)
        XCTAssertEqual(recorder.events, ["hover:true", "hover:false"])
        XCTAssertEqual(observer.endedEventIDs, [eventID])
        XCTAssertEqual(harness.host.downstreamSendCount, 0)
    }

    // ASSERTIONS hoverEventBindingAncestorDispatchObserved forwardedEventDispatcherRegistrationDispatchObserved
    func testFirstMissIsUnconsumedAndNeverReachesGestureGraph() {
        let recorder = HoverEventRecorder()
        let fixture = makeHoverResponderFixture(recorder: recorder, name: "hover")
        let responder = fixture.responder
        let harness = HoverDispatchHarness(target: nil)
        let eventID = EventID(type: HoverEvent.self, serial: 11)

        XCTAssertTrue(harness.manager.send(
            [eventID: hoverEvent(phase: .began)]
        ).isEmpty)
        XCTAssertEqual(harness.root.bindCount, 1)
        XCTAssertEqual(harness.host.downstreamSendCount, 0)

        harness.root.target = responder
        XCTAssertEqual(
            harness.manager.send(
                [eventID: hoverEvent(phase: .active)]
            ),
            Set([eventID])
        )
        XCTAssertEqual(recorder.events, ["hover:true"])
        XCTAssertEqual(harness.host.downstreamSendCount, 0)

        harness.root.target = nil
        XCTAssertEqual(
            harness.manager.send(
                [eventID: hoverEvent(phase: .active)]
            ),
            Set([eventID])
        )
        XCTAssertEqual(harness.root.bindCount, 3)
        XCTAssertEqual(harness.host.downstreamSendCount, 0)
        XCTAssertEqual(recorder.events, ["hover:true", "hover:false"])
        withExtendedLifetime(fixture) {}
    }

    // ASSERTIONS forwardedEventDispatcherRegistrationDispatchObserved
    func testForwardedDispatcherResetDropsBindingWithoutExitCallback() {
        let recorder = HoverEventRecorder()
        let fixture = makeHoverResponderFixture(recorder: recorder, name: "hover")
        let responder = fixture.responder
        let harness = HoverDispatchHarness(
            target: responder,
            retaining: [fixture]
        )
        let eventID = EventID(type: HoverEvent.self, serial: 13)

        _ = harness.manager.send(
            [eventID: hoverEvent(phase: .began)]
        )
        XCTAssertEqual(recorder.events, ["hover:true"])

        harness.manager.reset(resetForwardedEventDispatchers: true)
        harness.root.target = nil
        XCTAssertTrue(harness.manager.send(
            [eventID: hoverEvent(phase: .ended)]
        ).isEmpty)
        XCTAssertEqual(recorder.events, ["hover:true"])
        XCTAssertEqual(harness.host.downstreamSendCount, 0)
    }

    // ASSERTIONS hoverEventBindingAncestorDispatchObserved
    func testForwardedDispatcherResetClearsInternalHoverObserversOnly() {
        let recorder = HoverEventRecorder()
        let fixture = makeHoverResponderFixture(recorder: recorder, name: "hover")
        let observer = HoverObserverResponder()
        fixture.responder.parent = observer
        let harness = HoverDispatchHarness(
            target: fixture.responder,
            retaining: [fixture, observer]
        )
        let eventID = EventID(type: HoverEvent.self, serial: 15)

        _ = harness.manager.send([
            eventID: hoverEvent(phase: .began)
        ])
        XCTAssertEqual(recorder.events, ["hover:true"])
        XCTAssertEqual(observer.resetCount, 0)

        harness.manager.reset(resetForwardedEventDispatchers: true)
        XCTAssertEqual(observer.resetCount, 1)
        XCTAssertEqual(observer.endedEventIDs, [])
        XCTAssertEqual(recorder.events, ["hover:true"])
    }

    // ASSERTIONS hoverEventBindingAncestorDispatchObserved
    func testNestedHoverDiffEndsOnlyOldInnerResponder() {
        let recorder = HoverEventRecorder()
        let outerFixture = makeHoverResponderFixture(
            recorder: recorder,
            name: "outer"
        )
        let innerFixture = makeHoverResponderFixture(
            recorder: recorder,
            name: "inner"
        )
        let outer = outerFixture.responder
        let inner = innerFixture.responder
        outer.children = [inner]

        let harness = HoverDispatchHarness(
            target: outer,
            retaining: [outerFixture, innerFixture]
        )
        let eventID = EventID(type: HoverEvent.self, serial: 17)

        _ = harness.manager.send(
            [eventID: hoverEvent(phase: .began)]
        )
        harness.root.target = inner
        _ = harness.manager.send(
            [eventID: hoverEvent(phase: .active)]
        )
        harness.root.target = outer
        _ = harness.manager.send(
            [eventID: hoverEvent(phase: .active)]
        )

        XCTAssertEqual(recorder.events, [
            "outer:true",
            "inner:true",
            "inner:false",
        ])
        XCTAssertEqual(outer.currentPhase, .active(CGPoint(x: 10, y: 10)))
        XCTAssertEqual(inner.currentPhase, .ended)
    }

    // ASSERTIONS hoverNamedCoordinateSpaceObserved
    func testContinuousHoverUsesEachResponderCoordinateSpace() {
        let recorder = HoverCoordinateRecorder()
        let fixture = HoverCoordinateFixture(recorder: recorder)
        let harness = HoverDispatchHarness(
            target: fixture.local,
            retaining: [fixture]
        )
        let eventID = EventID(type: HoverEvent.self, serial: 19)

        XCTAssertEqual(
            harness.manager.send([
                eventID: hoverEvent(
                    phase: .began,
                    point: CGPoint(x: 120, y: 100)
                )
            ]),
            Set([eventID])
        )
        XCTAssertEqual(recorder.points["local"], CGPoint(x: 30, y: 30))
        XCTAssertEqual(recorder.points["named"], CGPoint(x: 100, y: 80))
        XCTAssertEqual(recorder.points["global"], CGPoint(x: 120, y: 100))
    }

    // ASSERTIONS hoverEventBindingAncestorDispatchObserved
    @MainActor
    func testScrollSurfaceHoverUsesOneHitTestBindingPassPerMove() throws {
        let recorder = HoverEventRecorder()
        let controller = WindowController(
            content: HoverScrollSurface(recorder: recorder),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(HoverScrollSurface.self)
            )
        )

        var redraw = false
        controller.updateView(
            tick: 0,
            delta: 0,
            date: controller.date,
            contentSize: CGSize(width: 420, height: 240),
            redraw: &redraw
        ) { _, _ in }
        let root = try XCTUnwrap(
            controller.viewGraph.responderNode as? ViewResponder
        )
        let responder = try XCTUnwrap(
            responderTree(root).compactMap { $0 as? HoverResponder }.first {
                $0.size.width > 0 && $0.size.height > 0
            }
        )
        var points = [CGPoint(
            x: responder.size.width / 2,
            y: responder.size.height / 2
        )]
        responder.transform.convertGlobal(from: .local, points: &points)

        let keyBefore = ViewResponder.hitTestKey
        XCTAssertTrue(controller.handleMouseHover(
            at: points[0],
            deviceID: 0,
            isTopMost: true,
            at: .zero
        ))
        XCTAssertEqual(ViewResponder.hitTestKey, keyBefore &+ 1)
        XCTAssertEqual(recorder.events, ["row:true"])
    }

    // ASSERTIONS hoverPlatformOccurrenceTimeObserved
    @MainActor
    func testRawHoverForwardsItsOccurrenceTime() {
        let recorder = HoverTimestampRecorder()
        let controller = WindowController(
            content: EmptyView(),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(HoverTimestampRecorder.self)
            )
        )
        controller.eventBindingManager.addForwardedEventDispatcher(
            TimestampRecordingHoverDispatcher(recorder: recorder)
        )

        let occurrenceTime = Time(seconds: 12.5)
        XCTAssertTrue(controller.handleMouseHover(
            at: CGPoint(x: 10, y: 20),
            deviceID: 0,
            isTopMost: true,
            at: occurrenceTime
        ))
        XCTAssertEqual(recorder.timestamps, [occurrenceTime])
    }

    // ASSERTIONS appKitBlockedMouseMoveCoalescingObserved
    @MainActor
    func testQueuedUnpressedMouseMovesKeepOnlyLatestHoverSample() throws {
        let recorder = HoverEventRecorder()
        let controller = WindowController(
            content: HoverScrollSurface(recorder: recorder),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(HoverScrollSurface.self)
            )
        )

        var redraw = false
        controller.updateView(
            tick: 0,
            delta: 0,
            date: controller.date,
            contentSize: CGSize(width: 420, height: 240),
            redraw: &redraw
        ) { _, _ in }
        for tick in 1...2 {
            controller.updateView(
                tick: UInt64(tick),
                delta: 1.0 / 60.0,
                date: controller.date.addingTimeInterval(
                    Double(tick) / 60.0
                ),
                contentSize: CGSize(width: 420, height: 240),
                redraw: &redraw
            ) { _, _ in }
        }

        let root = try XCTUnwrap(
            controller.viewGraph.responderNode as? ViewResponder
        )
        let responder = try XCTUnwrap(
            responderTree(root).compactMap { $0 as? HoverResponder }.first {
                $0.size.width > 8 && $0.size.height > 0
            }
        )
        var points = [CGPoint(
            x: responder.size.width / 2,
            y: responder.size.height / 2
        )]
        responder.transform.convertGlobal(from: .local, points: &points)

        for index in 0..<3 {
            let seconds = Double(index + 1)
            let location = CGPoint(
                x: points[0].x + CGFloat(index),
                y: points[0].y
            )
            let event = VVD.MouseEvent(
                type: .move,
                device: .genericMouse,
                deviceID: 0,
                buttonID: 0,
                location: location,
                timestamp: seconds
            )
            controller.enqueueMouseInputEvent(
                event
            )
        }

        let keyBefore = ViewResponder.hitTestKey
        controller.updateView(
            tick: 3,
            delta: 1.0 / 60.0,
            date: controller.date.addingTimeInterval(3.0 / 60.0),
            contentSize: CGSize(width: 420, height: 240),
            redraw: &redraw
        ) { _, _ in }

        XCTAssertEqual(ViewResponder.hitTestKey, keyBefore &+ 1)
        XCTAssertEqual(recorder.events, ["row:true"])
    }

    // ASSERTIONS eventBindingManagerActiveLifetimeObserved
    func testHoverUpdatePendingStateSurvivesResetUntilQueuedCallback() {
        let manager = EventBindingManager()
        let delegate = HoverUpdateRequestRecorder()
        manager.delegate = delegate

        Update.ensure {
            manager.enqueueHoverUpdateIfNeeded()
            manager.enqueueHoverUpdateIfNeeded()
            manager.reset()
            manager.enqueueHoverUpdateIfNeeded()
            XCTAssertEqual(delegate.requestCount, 0)
        }

        XCTAssertEqual(delegate.requestCount, 1)

        Update.ensure {
            manager.enqueueHoverUpdateIfNeeded()
        }
        XCTAssertEqual(delegate.requestCount, 2)
    }
}

private final class HoverEventRecorder {
    var events: [String] = []
}

private final class HoverTimestampRecorder {
    var timestamps: [Time] = []
}

private final class HoverCoordinateRecorder {
    var points: [String: CGPoint] = [:]
}

private struct TimestampRecordingHoverDispatcher: ForwardedEventDispatcher {
    static var eventType: any EventType.Type { HoverEvent.self }

    let recorder: HoverTimestampRecorder

    mutating func receiveEvents(
        _ events: [EventID: any EventType],
        manager: EventBindingManager
    ) -> Set<EventID> {
        var consumed: Set<EventID> = []
        for (eventID, event) in events {
            guard let event = event as? HoverEvent else { continue }
            recorder.timestamps.append(event.timestamp)
            consumed.insert(eventID)
        }
        return consumed
    }
}

private final class HoverUpdateRequestRecorder: EventBindingManagerDelegate {
    private(set) var requestCount = 0

    func didUpdate(
        phase: GesturePhase<Void>,
        in manager: EventBindingManager
    ) {}

    func requestHoverUpdate(in manager: EventBindingManager) {
        requestCount += 1
    }
}

private final class CountingBindingRoot: ResponderNode {
    var target: ResponderNode?
    private(set) var bindCount = 0

    init(target: ResponderNode?) {
        self.target = target
        super.init()
    }

    override var nextResponder: ResponderNode? { nil }

    override func bindEvent(_ event: any EventType) -> ResponderNode? {
        bindCount += 1
        return target
    }
}

private final class HoverObserverResponder: ViewResponder, HoverEventObserver {
    private(set) var updatedEventIDs: [EventID] = []
    private(set) var endedEventIDs: [EventID] = []
    private(set) var resetCount = 0

    func updateHoverEvent(
        id: EventID,
        at globalPoint: CGPoint,
        time: Time
    ) -> Bool {
        updatedEventIDs.append(id)
        return true
    }

    func endHoverEvent(id: EventID, time: Time) -> Bool {
        endedEventIDs.append(id)
        return true
    }

    func resetHoverEvents() {
        resetCount += 1
    }
}

private final class HoverTestEventGraphHost: EventGraphHost {
    let eventBindingManager = EventBindingManager()
    let root: ResponderNode
    private(set) var downstreamSendCount = 0

    init(root: ResponderNode) {
        self.root = root
        eventBindingManager.host = self
    }

    var responderNode: ResponderNode? { root }
    var focusedResponder: ResponderNode? { nil }
    var nextGestureUpdateTime: Time { .infinity }

    func sendEvents(
        _ events: [EventID: any EventType],
        rootNode: ResponderNode,
        at time: Time
    ) -> GesturePhase<Void> {
        downstreamSendCount += 1
        return .possible(nil)
    }

    func resetEvents() {}
    func gestureCategory() -> GestureCategory? { nil }
}

private final class HoverDispatchHarness {
    let root: CountingBindingRoot
    let host: HoverTestEventGraphHost
    private let retainedObjects: [AnyObject]

    var manager: EventBindingManager { host.eventBindingManager }

    init(target: ResponderNode?, retaining retainedObjects: [AnyObject] = []) {
        self.retainedObjects = retainedObjects
        root = CountingBindingRoot(target: target)
        host = HoverTestEventGraphHost(root: root)
        manager.addForwardedEventDispatcher(HoverEventDispatcher())
    }
}

private final class HoverResponderFixture {
    let data: GraphHost.Data
    let responder: HoverResponder

    init(recorder: HoverEventRecorder, name: String) {
        let data = GraphHost.Data()
        var responder: HoverResponder!
        data.withCurrent {
            AGSubgraph.withCurrent(data.rootSubgraph) {
                responder = HoverResponder(inputs: makeHoverViewInputs(
                    graph: data.graph
                ))
                responder.callback = .nonSpatial {
                    recorder.events.append("\(name):\($0)")
                }
                responder.transform = .identity
                responder.size = CGSize(width: 100, height: 100)
                responder.isEnabled = true
            }
        }
        self.data = data
        self.responder = responder
    }
}

private final class HoverCoordinateFixture {
    let data: GraphHost.Data
    let local: HoverResponder
    let named: HoverResponder
    let global: HoverResponder

    init(recorder: HoverCoordinateRecorder) {
        let data = GraphHost.Data()
        var local: HoverResponder!
        var named: HoverResponder!
        var global: HoverResponder!
        data.withCurrent {
            AGSubgraph.withCurrent(data.rootSubgraph) {
                var transform = ViewTransform.identity
                transform.appendPosition(CGPoint(x: 20, y: 20))
                transform.appendCoordinateSpace(name: AnyHashable("hover-named"))
                transform.appendPosition(CGPoint(x: 90, y: 70))

                func makeResponder(
                    name: String,
                    coordinateSpace: CoordinateSpace
                ) -> HoverResponder {
                    let responder = HoverResponder(
                        inputs: makeHoverViewInputs(graph: data.graph)
                    )
                    responder.callback = .spatial { phase in
                        guard case .active(let point) = phase else { return }
                        recorder.points[name] = point
                    }
                    responder.transform = transform
                    responder.size = CGSize(width: 120, height: 80)
                    responder.coordinateSpace = coordinateSpace
                    responder.isEnabled = true
                    return responder
                }

                local = makeResponder(name: "local", coordinateSpace: .local)
                named = makeResponder(
                    name: "named",
                    coordinateSpace: .named(AnyHashable("hover-named"))
                )
                global = makeResponder(name: "global", coordinateSpace: .global)
                global.children = [named]
                named.children = [local]
            }
        }
        self.data = data
        self.local = local
        self.named = named
        self.global = global
    }
}

private func makeHoverResponderFixture(
    recorder: HoverEventRecorder,
    name: String
) -> HoverResponderFixture {
    HoverResponderFixture(recorder: recorder, name: name)
}

private func makeHoverViewInputs(graph: _AGGraph) -> _ViewInputs {
    _ViewInputs(
        base: _GraphInputs(
            time: graph.makeInput(value: Time.zero),
            phase: graph.makeInput(value: _GraphInputs.Phase()),
            environment: graph.makeInput(value: EnvironmentValues()),
            transaction: graph.makeInput(value: Transaction())
        ),
        customInputs: PropertyList(),
        preferences: PreferencesInputs(
            keys: PreferenceKeys(),
            hostKeys: graph.makeInput(value: PreferenceKeys())
        ),
        transform: graph.makeInput(value: ViewTransform.identity),
        position: graph.makeInput(value: CGPoint.zero),
        containerPosition: graph.makeInput(value: CGPoint.zero),
        size: graph.makeInput(
            value: ViewSize(CGSize(width: 100, height: 100))
        ),
        safeAreaInsets: OptionalAttribute(),
        containerSize: OptionalAttribute(),
        stackOrientation: nil
    )
}

private func hoverEvent(
    phase: EventPhase,
    point: CGPoint = CGPoint(x: 10, y: 10)
) -> HoverEvent {
    HoverEvent(
        timestamp: .zero,
        phase: phase,
        binding: nil,
        globalLocation: point
    )
}

private func responderTree(_ responder: ViewResponder) -> [ViewResponder] {
    [responder] + responder.children.flatMap(responderTree)
}

private struct HoverScrollSurface: View {
    let recorder: HoverEventRecorder

    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 4) {
                ForEach(0..<24, id: \.self) { row in
                    Text("Row \(row)")
                        .frame(width: 300, height: 28)
                        .onHover { hovering in
                            _ = row
                            recorder.events.append("row:\(hovering)")
                        }
                }
            }
        }
    }
}
