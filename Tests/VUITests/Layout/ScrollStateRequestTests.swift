import XCTest
@testable import VUI

private func assertRequestKindEqual(
    _ actual: ScrollStateRequestKind,
    _ expected: ScrollStateRequestKind,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    switch (actual, expected) {
    case (.scrollTo, .scrollTo):
        return
    case let (.updateValue(actual), .updateValue(expected)):
        XCTAssertEqual(actual, expected, file: file, line: line)
    default:
        XCTFail("request kinds differ: \(actual), \(expected)", file: file, line: line)
    }
}

final class ScrollStateRequestTests: XCTestCase {
    func testScrollGeometrySurface() {
        let insets = EdgeInsets(top: 1, leading: 4, bottom: 5, trailing: 6)
        var geometry = ScrollGeometry(
            contentOffset: CGPoint(x: 2, y: 3),
            contentSize: CGSize(width: 200, height: 300),
            contentInsets: insets,
            containerSize: CGSize(width: 20, height: 30)
        )

        XCTAssertEqual(
            Mirror(reflecting: geometry).children.map(\.label),
            ["contentOffset", "contentSize", "contentInsets", "containerSize", "visibleRect"]
        )
        XCTAssertEqual(geometry.contentOffset, CGPoint(x: 2, y: 3))
        XCTAssertEqual(geometry.contentSize, CGSize(width: 200, height: 300))
        XCTAssertEqual(geometry.contentInsets, insets)
        XCTAssertEqual(geometry.containerSize, CGSize(width: 20, height: 30))
        XCTAssertEqual(geometry.visibleRect, CGRect(x: 2, y: 3, width: 20, height: 30))
        XCTAssertEqual(geometry.bounds, geometry.visibleRect)
        XCTAssertEqual(
            geometry.debugDescription,
            "<ScrollGeometry: contentOffset (2.0, 3.0), contentSize (200.0, 300.0), " +
            "contentInsets <top: 1.0, leading: 4.0, bottom: 5.0, trailing: 6.0>, " +
            "containerSize (20.0, 30.0), visibleRect (2.0, 3.0, 20.0, 30.0)>"
        )

        geometry.contentOffset = CGPoint(x: 10, y: 11)
        XCTAssertEqual(geometry.visibleRect, CGRect(x: 10, y: 11, width: 20, height: 30))

        geometry.containerSize = CGSize(width: 40, height: 50)
        XCTAssertEqual(geometry.visibleRect, CGRect(x: 10, y: 11, width: 40, height: 50))

        geometry.contentSize = CGSize(width: 1, height: 2)
        geometry.contentInsets = EdgeInsets(top: 9, leading: 8, bottom: 7, trailing: 6)
        XCTAssertEqual(geometry.visibleRect, CGRect(x: 10, y: 11, width: 40, height: 50))

        var customVisibleGeometry = ScrollGeometry(
            contentOffset: CGPoint(x: 2, y: 3),
            contentSize: CGSize(width: 200, height: 300),
            contentInsets: insets,
            containerSize: CGSize(width: 20, height: 30),
            visibleRect: CGRect(x: -4, y: -5, width: 32, height: 44)
        )
        customVisibleGeometry.contentOffset = CGPoint(x: 12, y: 18)
        XCTAssertEqual(
            customVisibleGeometry.visibleRect,
            CGRect(x: 6, y: 10, width: 32, height: 44)
        )
        customVisibleGeometry.containerSize = CGSize(width: 25, height: 40)
        XCTAssertEqual(
            customVisibleGeometry.visibleRect,
            CGRect(x: 6, y: 10, width: 37, height: 54)
        )
    }

    func testScrollPhaseAndPhaseStateSurface() {
        XCTAssertEqual(
            Mirror(reflecting: ScrollPhaseState()).children.map(\.label),
            ["phase", "velocity"]
        )

        XCTAssertEqual(ScrollPhase.idle.debugDescription, "idle")
        XCTAssertEqual(ScrollPhase.tracking.debugDescription, "tracking")
        XCTAssertEqual(ScrollPhase.interacting.debugDescription, "interacting")
        XCTAssertEqual(ScrollPhase.decelerating.debugDescription, "decelerating")
        XCTAssertEqual(ScrollPhase.animating.debugDescription, "animating")
        XCTAssertFalse(ScrollPhase.idle.isScrolling)
        XCTAssertTrue(ScrollPhase.animating.isScrolling)

        let tracking = ScrollPhaseState(
            phase: .tracking,
            velocity: CGVector(dx: 3, dy: 4)
        )
        XCTAssertTrue(tracking.isScrolling)
        XCTAssertTrue(tracking.isTracking)
        XCTAssertFalse(tracking.isInteracting)
        XCTAssertEqual(tracking.velocity, CGVector(dx: 3, dy: 4))
        XCTAssertTrue(tracking.shouldUpdateValue)

        XCTAssertTrue(ScrollPhaseState(phase: .interacting).shouldUpdateValue)
        XCTAssertTrue(ScrollPhaseState(phase: .decelerating).shouldUpdateValue)
        XCTAssertFalse(ScrollPhaseState(phase: .idle).shouldUpdateValue)
        XCTAssertFalse(ScrollPhaseState(phase: .animating).shouldUpdateValue)
    }

    func testScrollGeometryStatePreferenceAndProviderSurface() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            let geometry = ScrollGeometry(
                contentOffset: CGPoint(x: 2, y: 3),
                contentSize: CGSize(width: 200, height: 300),
                containerSize: CGSize(width: 20, height: 30)
            )
            var transform = ViewTransform.identity
            transform.appendScrollGeometry(geometry, isClipped: true)

            let geometryAttr = graph.makeInput(value: geometry)
            let axesAttr = graph.makeInput(value: Axis.Set.vertical)
            let transformAttr = graph.makeInput(value: transform)
            let state = ScrollGeometryState(
                geometry: geometry,
                scrollableAxes: .vertical,
                transform: transformAttr.asWeak()
            )

            XCTAssertEqual(
                Mirror(reflecting: state).children.map(\.label),
                ["geometry", "scrollableAxes", "transformAttribute"]
            )
            XCTAssertEqual(ScrollGeometryState.zero.geometry, ScrollGeometry())
            XCTAssertEqual(ScrollGeometryState.zero.scrollableAxes, [])
            XCTAssertNil(ScrollGeometryState.zero.transform)
            XCTAssertEqual(state.geometry, geometry)
            XCTAssertEqual(state.scrollableAxes, .vertical)
            XCTAssertEqual(state.transform, transform)

            let provider = ScrollGeometryStateProvider(
                geometry: geometryAttr,
                scrollableAxes: axesAttr,
                transform: transformAttr
            )
            XCTAssertEqual(
                Mirror(reflecting: provider).children.map(\.label),
                ["geometry", "scrollableAxes", "transform"]
            )

            let provided = provider.value
            XCTAssertEqual(provided.count, 1)
            XCTAssertEqual(provided[0], state)
            XCTAssertEqual(provided[0].transform, transform)

            var reduced = ScrollGeometryPreferenceKey.defaultValue
            XCTAssertTrue(reduced.isEmpty)
            ScrollGeometryPreferenceKey.reduce(value: &reduced) { [state] }
            ScrollGeometryPreferenceKey.reduce(value: &reduced) { [ScrollGeometryState.zero] }
            XCTAssertEqual(reduced, [state, ScrollGeometryState.zero])
        }
    }

    func testUpdateScrollStateRequestShapeAndScopedValueTransaction() {
        var stored = ScrollPosition(id: "old")
        var observedTransactions: [Transaction] = []
        let binding = Binding<ScrollPosition>(
            get: { stored },
            set: { value, transaction in
                stored = value
                observedTransactions.append(transaction)
            }
        )
        let newPosition = ScrollPosition(id: "new")
        var request = UpdateScrollStateRequest(
            binding: binding,
            newPosition: newPosition,
            isVisible: true,
            targetDistance: 12
        )

        XCTAssertEqual(
            Mirror(reflecting: request).children.map(\.label),
            ["binding", "newPosition", "isVisible", "targetDistance"]
        )
        guard case let .updateValue(config) = request.kind else {
            return XCTFail("expected updateValue request kind")
        }
        XCTAssertEqual(config.targetDistance, 12)
        XCTAssertTrue(request.hasUpdate)
        XCTAssertTrue(request.transaction.isScrollStateValueUpdate)
        XCTAssertNil(request.transaction.animation)

        XCTAssertTrue(request.update())

        XCTAssertEqual(stored, newPosition)
        XCTAssertEqual(observedTransactions.count, 1)
        XCTAssertTrue(observedTransactions[0].isScrollStateValueUpdate)
        XCTAssertNil(observedTransactions[0].animation)
    }

    func testScrollStateRequestOverrideOrderingMatchesProbedKinds() {
        let currentIdentity = NSObject()
        let previousIdentity = NSObject()
        let scrollTo = TestScrollStateRequest(
            id: ObjectIdentifier(currentIdentity),
            kind: .scrollTo
        )
        let otherScrollTo = TestScrollStateRequest(
            id: ObjectIdentifier(previousIdentity),
            kind: .scrollTo
        )
        let nearUpdate = TestScrollStateRequest(
            id: ObjectIdentifier(currentIdentity),
            kind: .updateValue(.init(targetDistance: 4))
        )
        let farUpdate = TestScrollStateRequest(
            id: ObjectIdentifier(previousIdentity),
            kind: .updateValue(.init(targetDistance: 8))
        )
        let equalUpdate = TestScrollStateRequest(
            id: ObjectIdentifier(previousIdentity),
            kind: .updateValue(.init(targetDistance: 4))
        )

        XCTAssertTrue(scrollTo.overrides(nil))
        XCTAssertTrue(scrollTo.overrides(farUpdate))
        XCTAssertFalse(scrollTo.overrides(otherScrollTo))
        XCTAssertFalse(farUpdate.overrides(scrollTo))
        XCTAssertTrue(nearUpdate.overrides(farUpdate))
        XCTAssertFalse(farUpdate.overrides(nearUpdate))
        XCTAssertFalse(nearUpdate.overrides(equalUpdate))
    }

    func testUpdateScrollStateRequestMergesAmbientTransactionAndRestoresScope() {
        var stored = ScrollPosition(id: "old")
        var observedTransactions: [Transaction] = []
        var bindingTransaction = Transaction(animation: .linear(duration: 1))
        bindingTransaction[ScrollBindingMarkerKey.self] = 66
        let binding = Binding<ScrollPosition>(
            get: { stored },
            set: { value, transaction in
                stored = value
                observedTransactions.append(transaction)
            }
        ).transaction(bindingTransaction)
        let newPosition = ScrollPosition(id: "new")
        var request = UpdateScrollStateRequest(
            binding: binding,
            newPosition: newPosition,
            isVisible: true,
            targetDistance: 12
        )
        var ambient = Transaction()
        ambient[ScrollAmbientMarkerKey.self] = 88

        Transaction.withScopedThreadTransaction(ambient) {
            XCTAssertTrue(request.update())
            XCTAssertEqual(Transaction.current[ScrollAmbientMarkerKey.self], 88)
            XCTAssertEqual(Transaction.current[ScrollBindingMarkerKey.self], 0)
            XCTAssertFalse(Transaction.current.isScrollStateValueUpdate)
        }

        XCTAssertEqual(stored, newPosition)
        XCTAssertEqual(observedTransactions.count, 1)
        XCTAssertTrue(observedTransactions[0].isScrollStateValueUpdate)
        XCTAssertNil(observedTransactions[0].animation)
        XCTAssertEqual(observedTransactions[0][ScrollBindingMarkerKey.self], 66)
        XCTAssertEqual(observedTransactions[0][ScrollAmbientMarkerKey.self], 88)
        XCTAssertEqual(Transaction.current[ScrollAmbientMarkerKey.self], 0)
    }

    func testUpdateScrollStateRequestSkipsInvisibleOrEqualValue() {
        var stored = ScrollPosition(id: "row")
        var setterCount = 0
        let binding = Binding<ScrollPosition>(
            get: { stored },
            set: { value, _ in
                stored = value
                setterCount += 1
            }
        )
        var invisible = UpdateScrollStateRequest(
            binding: binding,
            newPosition: ScrollPosition(id: "next"),
            isVisible: false,
            targetDistance: 3
        )
        var equal = UpdateScrollStateRequest(
            binding: binding,
            newPosition: stored,
            isVisible: true,
            targetDistance: 3
        )

        XCTAssertFalse(invisible.hasUpdate)
        XCTAssertFalse(invisible.update())
        XCTAssertFalse(equal.hasUpdate)
        XCTAssertFalse(equal.update())
        XCTAssertEqual(setterCount, 0)
    }

    func testUpdateScrollStateRequestSkipsSameViewIDWithDifferentSeed() {
        var stored = ScrollPosition(id: "row")
        var newPosition = stored
        newPosition.scrollTo(id: "row")
        var setterCount = 0
        let binding = Binding<ScrollPosition>(
            get: { stored },
            set: { value, _ in
                stored = value
                setterCount += 1
            }
        )
        var request = UpdateScrollStateRequest(
            binding: binding,
            newPosition: newPosition,
            isVisible: true,
            targetDistance: 1
        )

        XCTAssertNotEqual(stored, newPosition)
        XCTAssertFalse(request.hasUpdate)
        XCTAssertFalse(request.update())
        XCTAssertEqual(setterCount, 0)
    }

    func testPositionedByUserRequestShapeAndScopedValueTransaction() {
        var stored = ScrollPosition(id: "row")
        var observedTransactions: [Transaction] = []
        var baseTransaction = Transaction()
        baseTransaction[ScrollRequestMarkerKey.self] = 19
        let binding = Binding<ScrollPosition>(
            get: { stored },
            set: { value, transaction in
                stored = value
                observedTransactions.append(transaction)
            }
        ).transaction(baseTransaction)
        var request = PositionedByUserScrollStateRequest(binding: binding)

        XCTAssertEqual(
            Mirror(reflecting: request).children.map(\.label),
            ["binding", "id", "currentPosition", "positionedByUserPosition"]
        )
        assertRequestKindEqual(request.kind, .updateValue(.init(targetDistance: 0)))
        XCTAssertTrue(request.hasUpdate)
        XCTAssertTrue(request.transaction.isScrollStateValueUpdate)
        XCTAssertNil(request.transaction.animation)
        XCTAssertEqual(request.transaction[ScrollRequestMarkerKey.self], 19)

        XCTAssertTrue(request.update())

        XCTAssertTrue(stored.isPositionedByUser)
        XCTAssertNil(stored.viewID(type: String.self))
        XCTAssertEqual(observedTransactions.count, 1)
        XCTAssertTrue(observedTransactions[0].isScrollStateValueUpdate)
        XCTAssertNil(observedTransactions[0].animation)
        XCTAssertEqual(observedTransactions[0][ScrollRequestMarkerKey.self], 19)

        XCTAssertTrue(request.hasUpdate)
        XCTAssertTrue(request.update())
        XCTAssertEqual(observedTransactions.count, 2)
    }

    func testPositionedByUserRequestMergesAmbientTransactionAndRestoresScope() {
        var stored = ScrollPosition(id: "row")
        var observedTransactions: [Transaction] = []
        var bindingTransaction = Transaction(animation: .linear(duration: 1))
        bindingTransaction[ScrollBindingMarkerKey.self] = 66
        let binding = Binding<ScrollPosition>(
            get: { stored },
            set: { value, transaction in
                stored = value
                observedTransactions.append(transaction)
            }
        ).transaction(bindingTransaction)
        var request = PositionedByUserScrollStateRequest(binding: binding)
        var ambient = Transaction()
        ambient[ScrollAmbientMarkerKey.self] = 88

        Transaction.withScopedThreadTransaction(ambient) {
            XCTAssertTrue(request.update())
            XCTAssertEqual(Transaction.current[ScrollAmbientMarkerKey.self], 88)
            XCTAssertEqual(Transaction.current[ScrollBindingMarkerKey.self], 0)
            XCTAssertFalse(Transaction.current.isScrollStateValueUpdate)
        }

        XCTAssertTrue(stored.isPositionedByUser)
        XCTAssertNil(stored.viewID(type: String.self))
        XCTAssertEqual(observedTransactions.count, 1)
        XCTAssertTrue(observedTransactions[0].isScrollStateValueUpdate)
        XCTAssertNil(observedTransactions[0].animation)
        XCTAssertEqual(observedTransactions[0][ScrollBindingMarkerKey.self], 66)
        XCTAssertEqual(observedTransactions[0][ScrollAmbientMarkerKey.self], 88)
        XCTAssertEqual(Transaction.current[ScrollAmbientMarkerKey.self], 0)
    }

    func testScrollToRequestScopesScrollTransactionAndUpdatesBindingOnSuccess() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            let scrollable = RecordingScrollable(shouldScroll: true)
            let scrollableAttr = graph.makeInput(value: scrollable as any Scrollable)
            var stored = ScrollPosition(id: "old")
            var observedBindingTransactions: [Transaction] = []
            var bindingTransaction = Transaction()
            bindingTransaction[ScrollBindingMarkerKey.self] = 66
            let binding = Binding<ScrollPosition>(
                get: { stored },
                set: { value, transaction in
                    stored = value
                    observedBindingTransactions.append(transaction)
                }
            ).transaction(bindingTransaction)
            var base = Transaction()
            base[ScrollRequestMarkerKey.self] = 44
            let value = ScrollPosition(id: "target", anchor: .bottom)
            var request = ScrollToScrollStateRequest(
                binding: binding,
                anchor: .top,
                id: ObjectIdentifier(scrollable),
                value: value,
                baseTransaction: base
            )

            XCTAssertEqual(
                Mirror(reflecting: request).children.map(\.label),
                ["binding", "anchor", "id", "value", "baseTransaction", "scrollableAttribute"]
            )
            assertRequestKindEqual(request.kind, .scrollTo)
            XCTAssertFalse(request.hasUpdate)

            request.updateScrollable(scrollableAttr)

            XCTAssertTrue(request.hasUpdate)
            XCTAssertEqual(request.transaction[ScrollRequestMarkerKey.self], 44)
            XCTAssertEqual(request.transaction.scrollTargetAnchor, .top)
            XCTAssertTrue(request.update())

            XCTAssertEqual(scrollable.scrolledIDs, [AnyHashable("target")])
            XCTAssertEqual(scrollable.observedTransactions.map { $0[ScrollRequestMarkerKey.self] }, [44])
            XCTAssertEqual(scrollable.observedTransactions.map(\.scrollTargetAnchor), [.top])
            XCTAssertEqual(stored, value)
            XCTAssertEqual(observedBindingTransactions.count, 1)
            XCTAssertEqual(observedBindingTransactions[0][ScrollRequestMarkerKey.self], 0)
            XCTAssertEqual(observedBindingTransactions[0][ScrollBindingMarkerKey.self], 66)
            XCTAssertNil(observedBindingTransactions[0].scrollTargetAnchor)
        }
    }

    func testScrollToRequestRestoresAmbientTransactionBeforeBindingSetter() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            let scrollable = RecordingScrollable(shouldScroll: true)
            let scrollableAttr = graph.makeInput(value: scrollable as any Scrollable)
            var stored = ScrollPosition(id: "old")
            var observedBindingTransactions: [Transaction] = []
            var bindingTransaction = Transaction()
            bindingTransaction[ScrollBindingMarkerKey.self] = 66
            let binding = Binding<ScrollPosition>(
                get: { stored },
                set: { value, transaction in
                    stored = value
                    observedBindingTransactions.append(transaction)
                }
            ).transaction(bindingTransaction)
            XCTAssertEqual(binding.transaction[ScrollBindingMarkerKey.self], 66)
            var requestTransaction = Transaction()
            requestTransaction[ScrollRequestMarkerKey.self] = 44
            var ambientTransaction = Transaction()
            ambientTransaction[ScrollAmbientMarkerKey.self] = 88
            let value = ScrollPosition(id: "target")
            var request = ScrollToScrollStateRequest(
                binding: binding,
                anchor: .top,
                id: ObjectIdentifier(scrollable),
                value: value,
                baseTransaction: requestTransaction
            )
            XCTAssertEqual(request.binding.transaction[ScrollBindingMarkerKey.self], 66)
            request.updateScrollable(scrollableAttr)

            Transaction.withScopedThreadTransaction(ambientTransaction) {
                XCTAssertTrue(request.update())
            }

            XCTAssertEqual(scrollable.observedTransactions.count, 1)
            XCTAssertEqual(scrollable.observedTransactions[0][ScrollRequestMarkerKey.self], 44)
            XCTAssertEqual(scrollable.observedTransactions[0][ScrollAmbientMarkerKey.self], 88)
            XCTAssertEqual(scrollable.observedTransactions[0].scrollTargetAnchor, .top)
            XCTAssertEqual(stored, value)
            XCTAssertEqual(observedBindingTransactions.count, 1)
            XCTAssertEqual(observedBindingTransactions[0][ScrollRequestMarkerKey.self], 0)
            XCTAssertEqual(observedBindingTransactions[0][ScrollAmbientMarkerKey.self], 0)
            XCTAssertEqual(observedBindingTransactions[0][ScrollBindingMarkerKey.self], 66)
            XCTAssertNil(observedBindingTransactions[0].scrollTargetAnchor)
        }
    }

    func testScrollToRequestDoesNotUpdateBindingWhenScrollFails() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            let scrollable = RecordingScrollable(shouldScroll: false)
            let scrollableAttr = graph.makeInput(value: scrollable as any Scrollable)
            var stored = ScrollPosition(id: "old")
            var setterCount = 0
            let binding = Binding<ScrollPosition>(
                get: { stored },
                set: { value, _ in
                    stored = value
                    setterCount += 1
                }
            )
            var request = ScrollToScrollStateRequest(
                binding: binding,
                anchor: nil,
                id: ObjectIdentifier(scrollable),
                value: ScrollPosition(id: "target"),
                baseTransaction: Transaction()
            )

            request.updateScrollable(scrollableAttr)

            XCTAssertFalse(request.update())
            XCTAssertEqual(scrollable.scrolledIDs, [AnyHashable("target")])
            XCTAssertEqual(setterCount, 0)
            XCTAssertEqual(stored.viewID(type: String.self), "old")
        }
    }

    func testScrollableScrollToPositionRoutesViewIDAndNoOpTargets() {
        let scrollable = RecordingScrollable(shouldScroll: true)
        var positioned = ScrollPosition(id: "row")
        positioned.isPositionedByUser = true

        XCTAssertTrue(scrollable.scrollToPosition(ScrollPosition(id: "target")))
        XCTAssertTrue(scrollable.scrollToPosition(ScrollPosition(idType: String.self)))
        XCTAssertTrue(scrollable.scrollToPosition(positioned))

        XCTAssertEqual(scrollable.scrolledIDs, [AnyHashable("target")])
        XCTAssertTrue(scrollable.contentTargets.isEmpty)
    }

    func testScrollableScrollToPositionRoutesEdgePointAndAxisTargets() {
        let scrollable = RecordingScrollable(shouldScroll: true)
        let geometry = ScrollGeometry(
            contentOffset: CGPoint(x: 3, y: 4),
            contentSize: CGSize(width: 100, height: 200),
            containerSize: CGSize(width: 10, height: 20)
        )

        XCTAssertTrue(scrollable.scrollToPosition(ScrollPosition(idType: String.self, edge: .bottom)))
        XCTAssertTrue(scrollable.scrollToPosition(ScrollPosition(idType: String.self, edge: .leading)))
        XCTAssertTrue(scrollable.scrollToPosition(ScrollPosition(idType: String.self, edge: .trailing)))
        XCTAssertTrue(scrollable.scrollToPosition(ScrollPosition(idType: String.self, point: CGPoint(x: 12, y: 34))))
        XCTAssertTrue(scrollable.scrollToPosition(ScrollPosition(idType: String.self, x: 7)))
        XCTAssertTrue(scrollable.scrollToPosition(ScrollPosition(idType: String.self, y: 8)))

        XCTAssertEqual(scrollable.contentTargets.count, 6)
        XCTAssertEqual(
            scrollable.contentTargets[0](geometry, .leftToRight)?.rect,
            CGRect(x: 3, y: 180, width: 10, height: 20)
        )
        XCTAssertEqual(
            scrollable.contentTargets[1](geometry, .rightToLeft)?.rect,
            CGRect(x: 90, y: 4, width: 10, height: 20)
        )
        XCTAssertEqual(
            scrollable.contentTargets[2](geometry, .rightToLeft)?.rect,
            CGRect(x: 0, y: 4, width: 10, height: 20)
        )
        XCTAssertEqual(
            scrollable.contentTargets[3](geometry, .rightToLeft)?.rect,
            CGRect(x: 88, y: 34, width: 10, height: 20)
        )
        XCTAssertEqual(
            scrollable.contentTargets[4](geometry, .rightToLeft)?.rect,
            CGRect(x: 93, y: 4, width: 10, height: 20)
        )
        XCTAssertEqual(
            scrollable.contentTargets[5](geometry, .leftToRight)?.rect,
            CGRect(x: 3, y: 8, width: 10, height: 20)
        )
        XCTAssertTrue(scrollable.contentTargets.allSatisfy { target in
            target(geometry, .leftToRight)?.anchor == nil
        })
        XCTAssertTrue(scrollable.scrolledIDs.isEmpty)
    }

    func testScrollStateEnqueueRequestsQueuesReason11AndStoresRequest() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            let scrollable = RecordingScrollable(shouldScroll: true)
            let scrollableAttr = graph.makeInput(value: scrollable as any Scrollable)
            var stored = ScrollPosition(id: "old")
            let binding = Binding<ScrollPosition>(
                get: { stored },
                set: { value, _ in stored = value }
            )
            let request = ScrollToScrollStateRequest(
                binding: binding,
                anchor: .center,
                id: ObjectIdentifier(scrollable),
                value: ScrollPosition(id: "target"),
                baseTransaction: Transaction()
            )
            let requestAttr = graph.makeInput(value: Optional<any ScrollStateRequest>.some(request))
            var inputs = makeViewInputs(graph: graph)
            inputs.base.updateScrollStateRequest = OptionalAttribute(requestAttr)
            let phaseState = graph.makeInput(value: ScrollPhaseState(phase: .tracking))
            let rule = ScrollStateEnqueueRequests(
                phaseState: phaseState,
                scrollable: scrollableAttr,
                inputs: inputs,
                outputs: _ViewOutputs()
            )
            let ruleAttr = graph.makeStatefulRule(rule)

            Update.begin()
            _ = ruleAttr.value

            XCTAssertEqual(Update.queuedActionReasons, [nil])

            Update.end()

            var requestCount = 0
            graph.mutateStatefulRule(ruleAttr.identifier, as: ScrollStateEnqueueRequests.self) { rule in
                requestCount = rule.requests.count
            }
            XCTAssertEqual(stored.viewID(type: String.self), "target")
            XCTAssertEqual(requestCount, 1)
            XCTAssertEqual(scrollable.scrolledIDs, [AnyHashable("target")])
        }
    }

    func testScrollStateEnqueueRequestsQueuesPositionedByUserWhenContentBindingPhaseChanges() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            let scrollable = RecordingScrollable(shouldScroll: true)
            let scrollableAttr = graph.makeInput(value: scrollable as any Scrollable)
            var stored = ScrollPosition(id: "visible")
            var observedTransactions: [Transaction] = []
            var baseTransaction = Transaction()
            baseTransaction[ScrollRequestMarkerKey.self] = 27
            let binding = Binding<ScrollPosition>(
                get: { stored },
                set: { value, transaction in
                    stored = value
                    observedTransactions.append(transaction)
                }
            ).transaction(baseTransaction)
            let bindingAttr = graph.makeInput(value: binding)
            var inputs = makeViewInputs(graph: graph)
            inputs.base.setScrollPosition(storage: .binding(bindingAttr), kind: .scrollContent)
            let phaseState = graph.makeInput(value: ScrollPhaseState(phase: .tracking))
            let rule = ScrollStateEnqueueRequests(
                phaseState: phaseState,
                scrollable: scrollableAttr,
                inputs: inputs,
                outputs: _ViewOutputs()
            )
            let ruleAttr = graph.makeStatefulRule(rule)

            Update.begin()
            _ = ruleAttr.value

            XCTAssertEqual(Update.queuedActionReasons, [nil])

            Update.end()

            var requestCount = 0
            graph.mutateStatefulRule(ruleAttr.identifier, as: ScrollStateEnqueueRequests.self) { rule in
                requestCount = rule.requests.count
            }
            XCTAssertEqual(requestCount, 1)
            XCTAssertTrue(stored.isPositionedByUser)
            XCTAssertNil(stored.viewID(type: String.self))
            XCTAssertEqual(observedTransactions.count, 1)
            XCTAssertTrue(observedTransactions[0].isScrollStateValueUpdate)
            XCTAssertNil(observedTransactions[0].animation)
            XCTAssertEqual(observedTransactions[0][ScrollRequestMarkerKey.self], 27)
            XCTAssertTrue(scrollable.scrolledIDs.isEmpty)
        }
    }

    func testScrollStateEnqueueRequestsQueuesOutputPreferenceRequests() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            let scrollable = RecordingScrollable(shouldScroll: true)
            let scrollableAttr = graph.makeInput(value: scrollable as any Scrollable)
            var stored = ScrollPosition(id: "old")
            let binding = Binding<ScrollPosition>(
                get: { stored },
                set: { value, _ in stored = value }
            )
            let request = ScrollToScrollStateRequest(
                binding: binding,
                anchor: .center,
                id: ObjectIdentifier(scrollable),
                value: ScrollPosition(id: "preference"),
                baseTransaction: Transaction()
            )
            let requests: [any ScrollStateRequest] = [request]
            let requestsAttr = graph.makeInput(value: requests)
            var preferences = PreferencesOutputs()
            preferences.append(UpdateScrollStateRequestKey.self, node: requestsAttr.identifier)
            let phaseState = graph.makeInput(value: ScrollPhaseState(phase: .tracking))
            let rule = ScrollStateEnqueueRequests(
                phaseState: phaseState,
                scrollable: scrollableAttr,
                inputs: makeViewInputs(graph: graph),
                outputs: _ViewOutputs(preferences: preferences)
            )
            let ruleAttr = graph.makeStatefulRule(rule)

            Update.begin()
            _ = ruleAttr.value

            XCTAssertEqual(Update.queuedActionReasons, [nil])

            Update.end()

            var requestCount = 0
            graph.mutateStatefulRule(ruleAttr.identifier, as: ScrollStateEnqueueRequests.self) { rule in
                requestCount = rule.requests.count
            }
            XCTAssertEqual(requestCount, 1)
            XCTAssertEqual(stored.viewID(type: String.self), "preference")
            XCTAssertEqual(scrollable.scrolledIDs, [AnyHashable("preference")])
        }
    }

    func testScrollStateEnqueueRequestsMergesOutputPreferenceRequestsInOrder() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            let scrollable = RecordingScrollable(shouldScroll: true)
            let scrollableAttr = graph.makeInput(value: scrollable as any Scrollable)
            var stored = ScrollPosition(id: "old")
            let binding = Binding<ScrollPosition>(
                get: { stored },
                set: { value, _ in stored = value }
            )

            func makeRequest(_ targetID: String) -> ScrollToScrollStateRequest {
                ScrollToScrollStateRequest(
                    binding: binding,
                    anchor: nil,
                    id: ObjectIdentifier(scrollable),
                    value: ScrollPosition(id: targetID),
                    baseTransaction: Transaction()
                )
            }

            let firstRequests: [any ScrollStateRequest] = [makeRequest("first")]
            let secondRequests: [any ScrollStateRequest] = [makeRequest("second")]
            let firstRequestsAttr = graph.makeInput(value: firstRequests)
            let secondRequestsAttr = graph.makeInput(value: secondRequests)
            var firstOutputs = PreferencesOutputs()
            var secondOutputs = PreferencesOutputs()
            firstOutputs.append(UpdateScrollStateRequestKey.self, node: firstRequestsAttr.identifier)
            secondOutputs.append(UpdateScrollStateRequestKey.self, node: secondRequestsAttr.identifier)
            let mergedOutputs = PreferencesOutputs.merge([firstOutputs, secondOutputs], in: graph)
            let phaseState = graph.makeInput(value: ScrollPhaseState(phase: .tracking))
            let rule = ScrollStateEnqueueRequests(
                phaseState: phaseState,
                scrollable: scrollableAttr,
                inputs: makeViewInputs(graph: graph),
                outputs: _ViewOutputs(preferences: mergedOutputs)
            )
            let ruleAttr = graph.makeStatefulRule(rule)

            Update.begin()
            _ = ruleAttr.value

            XCTAssertEqual(Update.queuedActionReasons, [nil])

            Update.end()

            var requestCount = 0
            graph.mutateStatefulRule(ruleAttr.identifier, as: ScrollStateEnqueueRequests.self) { rule in
                requestCount = rule.requests.count
            }
            XCTAssertEqual(requestCount, 1)
            XCTAssertEqual(stored.viewID(type: String.self), "second")
            XCTAssertEqual(scrollable.scrolledIDs, [AnyHashable("first"), AnyHashable("second")])
        }
    }

    func testScrollStateEnqueueRequestsPreferenceRequestSuppressesPositionedByUserAdjustment() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            let scrollable = RecordingScrollable(shouldScroll: true)
            let scrollableAttr = graph.makeInput(value: scrollable as any Scrollable)
            var stored = ScrollPosition(id: "visible")
            let binding = Binding<ScrollPosition>(
                get: { stored },
                set: { value, _ in stored = value }
            )
            let request = ScrollToScrollStateRequest(
                binding: binding,
                anchor: nil,
                id: ObjectIdentifier(scrollable),
                value: ScrollPosition(id: "preference"),
                baseTransaction: Transaction()
            )
            let requests: [any ScrollStateRequest] = [request]
            let requestsAttr = graph.makeInput(value: requests)
            var preferences = PreferencesOutputs()
            preferences.append(UpdateScrollStateRequestKey.self, node: requestsAttr.identifier)
            let bindingAttr = graph.makeInput(value: binding)
            var inputs = makeViewInputs(graph: graph)
            inputs.base.setScrollPosition(storage: .binding(bindingAttr), kind: .scrollContent)
            let phaseState = graph.makeInput(value: ScrollPhaseState(phase: .tracking))
            let rule = ScrollStateEnqueueRequests(
                phaseState: phaseState,
                scrollable: scrollableAttr,
                inputs: inputs,
                outputs: _ViewOutputs(preferences: preferences)
            )
            let ruleAttr = graph.makeStatefulRule(rule)

            Update.begin()
            _ = ruleAttr.value
            Update.end()

            var requestCount = 0
            graph.mutateStatefulRule(ruleAttr.identifier, as: ScrollStateEnqueueRequests.self) { rule in
                requestCount = rule.requests.count
            }
            XCTAssertEqual(requestCount, 1)
            XCTAssertFalse(stored.isPositionedByUser)
            XCTAssertEqual(stored.viewID(type: String.self), "preference")
            XCTAssertEqual(scrollable.scrolledIDs, [AnyHashable("preference")])
        }
    }

    func testScrollStateEnqueueRequestsEmptyPreferenceRequestsAllowPositionedByUserAdjustment() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            let scrollable = RecordingScrollable(shouldScroll: true)
            let scrollableAttr = graph.makeInput(value: scrollable as any Scrollable)
            var stored = ScrollPosition(id: "visible")
            let binding = Binding<ScrollPosition>(
                get: { stored },
                set: { value, _ in stored = value }
            )
            let requests: [any ScrollStateRequest] = []
            let requestsAttr = graph.makeInput(value: requests)
            var preferences = PreferencesOutputs()
            preferences.append(UpdateScrollStateRequestKey.self, node: requestsAttr.identifier)
            let bindingAttr = graph.makeInput(value: binding)
            var inputs = makeViewInputs(graph: graph)
            inputs.base.setScrollPosition(storage: .binding(bindingAttr), kind: .scrollContent)
            let phaseState = graph.makeInput(value: ScrollPhaseState(phase: .tracking))
            let rule = ScrollStateEnqueueRequests(
                phaseState: phaseState,
                scrollable: scrollableAttr,
                inputs: inputs,
                outputs: _ViewOutputs(preferences: preferences)
            )
            let ruleAttr = graph.makeStatefulRule(rule)

            Update.begin()
            _ = ruleAttr.value
            Update.end()

            var requestCount = 0
            graph.mutateStatefulRule(ruleAttr.identifier, as: ScrollStateEnqueueRequests.self) { rule in
                requestCount = rule.requests.count
            }
            XCTAssertEqual(requestCount, 1)
            XCTAssertTrue(stored.isPositionedByUser)
            XCTAssertNil(stored.viewID(type: String.self))
            XCTAssertTrue(scrollable.scrolledIDs.isEmpty)
        }
    }

    func testScrollStateEnqueueRequestsExplicitRequestSuppressesPositionedByUserAdjustment() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            let scrollable = RecordingScrollable(shouldScroll: true)
            let scrollableAttr = graph.makeInput(value: scrollable as any Scrollable)
            var stored = ScrollPosition(id: "visible")
            let binding = Binding<ScrollPosition>(
                get: { stored },
                set: { value, _ in stored = value }
            )
            let request = ScrollToScrollStateRequest(
                binding: binding,
                anchor: nil,
                id: ObjectIdentifier(scrollable),
                value: ScrollPosition(id: "target"),
                baseTransaction: Transaction()
            )
            let requestAttr = graph.makeInput(value: Optional<any ScrollStateRequest>.some(request))
            let bindingAttr = graph.makeInput(value: binding)
            var inputs = makeViewInputs(graph: graph)
            inputs.base.updateScrollStateRequest = OptionalAttribute(requestAttr)
            inputs.base.setScrollPosition(storage: .binding(bindingAttr), kind: .scrollContent)
            let phaseState = graph.makeInput(value: ScrollPhaseState(phase: .tracking))
            let rule = ScrollStateEnqueueRequests(
                phaseState: phaseState,
                scrollable: scrollableAttr,
                inputs: inputs,
                outputs: _ViewOutputs()
            )
            let ruleAttr = graph.makeStatefulRule(rule)

            Update.begin()
            _ = ruleAttr.value
            Update.end()

            var requestCount = 0
            graph.mutateStatefulRule(ruleAttr.identifier, as: ScrollStateEnqueueRequests.self) { rule in
                requestCount = rule.requests.count
            }
            XCTAssertEqual(requestCount, 1)
            XCTAssertFalse(stored.isPositionedByUser)
            XCTAssertEqual(stored.viewID(type: String.self), "target")
            XCTAssertEqual(scrollable.scrolledIDs, [AnyHashable("target")])
        }
    }

    func testScrollStateEnqueueRequestsExplicitRequestSuppressesPreferenceAndPositionedByUserAdjustment() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            let scrollable = RecordingScrollable(shouldScroll: true)
            let scrollableAttr = graph.makeInput(value: scrollable as any Scrollable)
            var stored = ScrollPosition(id: "visible")
            let binding = Binding<ScrollPosition>(
                get: { stored },
                set: { value, _ in stored = value }
            )
            let explicitRequest = ScrollToScrollStateRequest(
                binding: binding,
                anchor: nil,
                id: ObjectIdentifier(scrollable),
                value: ScrollPosition(id: "explicit"),
                baseTransaction: Transaction()
            )
            let preferenceRequest = ScrollToScrollStateRequest(
                binding: binding,
                anchor: .bottom,
                id: ObjectIdentifier(scrollable),
                value: ScrollPosition(id: "preference"),
                baseTransaction: Transaction()
            )
            let explicitAttr = graph.makeInput(value: Optional<any ScrollStateRequest>.some(explicitRequest))
            let preferenceRequests: [any ScrollStateRequest] = [preferenceRequest]
            let preferenceRequestsAttr = graph.makeInput(value: preferenceRequests)
            var preferences = PreferencesOutputs()
            preferences.append(UpdateScrollStateRequestKey.self, node: preferenceRequestsAttr.identifier)
            let bindingAttr = graph.makeInput(value: binding)
            var inputs = makeViewInputs(graph: graph)
            inputs.base.updateScrollStateRequest = OptionalAttribute(explicitAttr)
            inputs.base.setScrollPosition(storage: .binding(bindingAttr), kind: .scrollContent)
            let phaseState = graph.makeInput(value: ScrollPhaseState(phase: .tracking))
            let rule = ScrollStateEnqueueRequests(
                phaseState: phaseState,
                scrollable: scrollableAttr,
                inputs: inputs,
                outputs: _ViewOutputs(preferences: preferences)
            )
            let ruleAttr = graph.makeStatefulRule(rule)

            Update.begin()
            _ = ruleAttr.value
            Update.end()

            var requestCount = 0
            graph.mutateStatefulRule(ruleAttr.identifier, as: ScrollStateEnqueueRequests.self) { rule in
                requestCount = rule.requests.count
            }
            XCTAssertEqual(requestCount, 1)
            XCTAssertFalse(stored.isPositionedByUser)
            XCTAssertEqual(stored.viewID(type: String.self), "explicit")
            XCTAssertEqual(scrollable.scrolledIDs, [AnyHashable("explicit")])
        }
    }

    func testGraphInputsScrollRequestAndScrollableOptionalAttributesRoundTrip() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            let scrollable = RecordingScrollable(shouldScroll: true)
            let scrollableAttr = graph.makeInput(value: scrollable as any Scrollable)
            let requestAttr = graph.makeInput(value: Optional<any ScrollStateRequest>.none)
            var inputs = makeGraphInputs(graph: graph)

            XCTAssertNil(inputs.scrollable.attribute)
            XCTAssertNil(inputs.updateScrollStateRequest.attribute)

            inputs.scrollable = OptionalAttribute(scrollableAttr)
            inputs.updateScrollStateRequest = OptionalAttribute(requestAttr)

            XCTAssertEqual(inputs.scrollable.attribute?.identifier, scrollableAttr.identifier)
            XCTAssertEqual(inputs.updateScrollStateRequest.attribute?.identifier, requestAttr.identifier)
        }
    }

    func testGraphInputsScrollPositionStorageAndAnchorKindRouting() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            let valueAttr = graph.makeInput(value: ScrollPosition(id: "value"))
            let anchorAttr = graph.makeInput(value: Optional<UnitPoint>.some(.bottom))
            let binding = Binding<ScrollPosition>(
                get: { ScrollPosition(id: "binding") },
                set: { _, _ in }
            )
            let bindingAttr = graph.makeInput(value: binding)
            var inputs = makeGraphInputs(graph: graph)

            XCTAssertNil(inputs.scrollPositionValue().attribute)
            XCTAssertNil(inputs.scrollPositionBinding(kind: .scrollView).attribute)
            XCTAssertNil(inputs.scrollPositionBinding(kind: .scrollContent).attribute)
            XCTAssertFalse(inputs.hasValueScrollPosition(kind: .scrollView))

            inputs.setScrollPosition(storage: .value(valueAttr), kind: .scrollView)
            inputs.setScrollPositionAnchor(OptionalAttribute(anchorAttr), kind: .scrollView)
            inputs.setScrollPosition(storage: .binding(bindingAttr), kind: .scrollContent)

            XCTAssertEqual(inputs.scrollPositionValue().attribute?.identifier, valueAttr.identifier)
            XCTAssertTrue(inputs.hasValueScrollPosition(kind: .scrollView))
            XCTAssertFalse(inputs.hasValueScrollPosition(kind: .scrollContent))
            XCTAssertEqual(
                inputs.scrollPositionAnchor(kind: .scrollView).attribute?.identifier,
                anchorAttr.identifier
            )
            XCTAssertEqual(
                inputs.scrollPositionBinding(kind: .scrollContent).attribute?.identifier,
                bindingAttr.identifier
            )
            XCTAssertNil(inputs.scrollPositionBinding(kind: .scrollView).attribute)

            inputs.resetScrollPosition(kind: .scrollContent)

            XCTAssertNil(inputs.scrollPositionBinding(kind: .scrollContent).attribute)
            XCTAssertNil(inputs.scrollPositionAnchor(kind: .scrollContent).attribute)
            XCTAssertEqual(inputs.scrollPositionValue().attribute?.identifier, valueAttr.identifier)
        }
    }

    func testScrollValueModifierWritesValueScrollPositionInput() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            let modifier = ScrollValueModifier(value: ScrollPosition(id: "value"))
            let modifierAttr = graph.makeInput(value: modifier)
            var inputs = makeGraphInputs(graph: graph)

            ScrollValueModifier._makeInputs(
                modifier: _GraphValue(_attribute: modifierAttr),
                inputs: &inputs
            )

            XCTAssertEqual(
                inputs.scrollPositionValue().attribute?.value.viewID(type: String.self),
                "value"
            )
            XCTAssertNil(inputs.scrollPositionBinding(kind: .scrollView).attribute)
            XCTAssertNil(inputs.scrollPositionAnchor(kind: .scrollView).attribute)
        }
    }

    func testScrollPositionBindingModifierWritesInputsAndDefersInitialScrollToRequest() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            var stored = ScrollPosition(id: "target")
            let binding = Binding<ScrollPosition>(
                get: { stored },
                set: { value, _ in stored = value }
            )
            let modifier = ScrollPositionBindingModifier(binding: binding, anchor: .bottom)
            let modifierAttr = graph.makeInput(value: modifier)
            var baseTransaction = Transaction()
            baseTransaction[ScrollRequestMarkerKey.self] = 91
            var inputs = makeGraphInputs(graph: graph)
            inputs.transaction.setValue(baseTransaction)

            ScrollPositionBindingModifier._makeInputs(
                modifier: _GraphValue(_attribute: modifierAttr),
                inputs: &inputs
            )

            XCTAssertEqual(
                inputs.scrollPositionBinding(kind: .scrollView).attribute?.value.wrappedValue.viewID(type: String.self),
                "target"
            )
            XCTAssertEqual(inputs.scrollPositionAnchor(kind: .scrollView).attribute?.value, .bottom)
            XCTAssertNil(inputs.scrollPositionValue().attribute)

            guard let requestAttr = inputs.updateScrollStateRequest.attribute else {
                XCTFail("expected scroll position binding request attribute")
                return
            }
            XCTAssertNil(requestAttr.value)

            stored = ScrollPosition(id: "next", anchor: .top)
            graph.markNeedsEvaluation(requestAttr.identifier)

            guard let request = requestAttr.value else {
                XCTFail("expected scroll position binding request")
                return
            }
            assertRequestKindEqual(request.kind, .scrollTo)
            XCTAssertFalse(request.hasUpdate)
            XCTAssertEqual(request.transaction[ScrollRequestMarkerKey.self], 91)
            XCTAssertEqual(request.transaction.scrollTargetAnchor, .bottom)
            XCTAssertEqual((request as? ScrollToScrollStateRequest)?.value.viewID(type: String.self), "next")
        }
    }

    func testScrollPositionBindingModifierAdjustedAnchorKeepsNilUnderCurrentSemantics() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            var stored = ScrollPosition(id: "target")
            let binding = Binding<ScrollPosition>(
                get: { stored },
                set: { value, _ in stored = value }
            )
            let modifier = ScrollPositionBindingModifier(binding: binding, anchor: nil)
            let modifierAttr = graph.makeInput(value: modifier)
            var inputs = makeGraphInputs(graph: graph)

            ScrollPositionBindingModifier._makeInputs(
                modifier: _GraphValue(_attribute: modifierAttr),
                inputs: &inputs
            )

            XCTAssertNil(inputs.scrollPositionAnchor(kind: .scrollView).attribute?.value)

            guard let requestAttr = inputs.updateScrollStateRequest.attribute else {
                XCTFail("expected scroll position binding request attribute")
                return
            }
            XCTAssertNil(requestAttr.value)

            stored = ScrollPosition(id: "next")
            graph.markNeedsEvaluation(requestAttr.identifier)

            guard let request = requestAttr.value else {
                XCTFail("expected scroll position binding request")
                return
            }
            XCTAssertNil(request.transaction.scrollTargetAnchor)
        }
    }

    func testScrollPositionBindingModifierSkipsUnchangedRequestAfterInitialEvaluation() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            var stored = ScrollPosition(idType: String.self, edge: .bottom)
            let binding = Binding<ScrollPosition>(
                get: { stored },
                set: { value, _ in stored = value }
            )
            let modifier = ScrollPositionBindingModifier(binding: binding, anchor: .center)
            let modifierAttr = graph.makeInput(value: modifier)
            var inputs = makeGraphInputs(graph: graph)

            ScrollPositionBindingModifier._makeInputs(
                modifier: _GraphValue(_attribute: modifierAttr),
                inputs: &inputs
            )

            guard let requestAttr = inputs.updateScrollStateRequest.attribute else {
                XCTFail("expected scroll position binding request attribute")
                return
            }
            XCTAssertNil(requestAttr.value)

            graph.markNeedsEvaluation(requestAttr.identifier)
            XCTAssertNil(requestAttr.value)

            stored.scrollTo(edge: .bottom)
            graph.markNeedsEvaluation(requestAttr.identifier)
            XCTAssertNotNil(requestAttr.value)
        }
    }

    func testScrollPositionBindingModifierSkipsRequestDuringValueUpdateTransaction() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            let binding = Binding<ScrollPosition>(
                get: { ScrollPosition(id: "target") },
                set: { _, _ in }
            )
            let modifier = ScrollPositionBindingModifier(binding: binding, anchor: nil)
            let modifierAttr = graph.makeInput(value: modifier)
            var transaction = Transaction()
            transaction.isScrollStateValueUpdate = true
            var inputs = makeGraphInputs(graph: graph)
            inputs.transaction.setValue(transaction)

            ScrollPositionBindingModifier._makeInputs(
                modifier: _GraphValue(_attribute: modifierAttr),
                inputs: &inputs
            )

            XCTAssertNil(inputs.updateScrollStateRequest.attribute?.value)
        }
    }

    func testValueToScrollPositionProjectionTransformsOptionalIDBindingAndCachesLocation() {
        var stored: String? = "row"
        var observedTransactions: [Transaction] = []
        var transaction = Transaction()
        transaction[ScrollRequestMarkerKey.self] = 117
        let idBinding = Binding<String?>(
            get: { stored },
            set: { value, transaction in
                stored = value
                observedTransactions.append(transaction)
            }
        ).transaction(transaction)
        let projection = ValueToScrollPosition(idBinding, anchor: .bottom)
        let positionBinding = idBinding.projecting(projection)
        let repeated = idBinding.projecting(projection)

        XCTAssertTrue(positionBinding.location === repeated.location)
        XCTAssertEqual(positionBinding.transaction[ScrollRequestMarkerKey.self], 117)
        XCTAssertEqual(positionBinding.wrappedValue._viewID(type: String.self), "row")
        XCTAssertEqual(
            positionBinding.wrappedValue,
            ScrollPosition(_scrollPositionID: "row", anchor: .bottom)
        )

        positionBinding.wrappedValue = ScrollPosition(_scrollPositionID: "next", anchor: .top)

        XCTAssertEqual(stored, "next")
        XCTAssertEqual(observedTransactions.count, 1)
        XCTAssertEqual(observedTransactions[0][ScrollRequestMarkerKey.self], 117)

        positionBinding.wrappedValue = ScrollPosition(_scrollPositionIDType: String.self)

        XCTAssertNil(stored)
    }

    func testScrollPositionToValueProjectionReadsAndMutatesScrollPosition() {
        let idBinding = Binding<String?>.constant(nil)
        let projection = ScrollPositionToValue(idBinding, anchor: .top)
        var position = ScrollPosition(_scrollPositionID: "old", anchor: .bottom)

        XCTAssertEqual(projection.get(base: position), "old")

        projection.set(base: &position, newValue: "new")

        var expected = ScrollPosition(_scrollPositionID: "old", anchor: .bottom)
        expected._scrollTo(id: "new", anchor: .top)
        XCTAssertEqual(position._viewID(type: String.self), "new")
        XCTAssertEqual(position, expected)

        projection.set(base: &position, newValue: nil)

        XCTAssertNil(position._viewID(type: String.self))
    }

    func testScrollPositionIDOverloadAcceptsHashableOnlyIDBinding() {
        final class Box {}
        struct NonSendableHashable: Hashable {
            let box: Box

            static func == (lhs: NonSendableHashable, rhs: NonSendableHashable) -> Bool {
                lhs.box === rhs.box
            }

            func hash(into hasher: inout Hasher) {
                hasher.combine(ObjectIdentifier(box))
            }
        }

        let binding = Binding<NonSendableHashable?>.constant(
            NonSendableHashable(box: Box())
        )
        _ = EmptyView().scrollPosition(id: binding, anchor: .top)
    }

    func testZeroWeakAttributeIsInvalidAndFirstSlotWeakAttributeUsesNonzeroSeed() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            let first = graph.makeInput(value: 42)
            let weak = first.asWeak()
            let invalid = WeakAttribute<Int>()

            XCTAssertEqual(first.identifier.rawValue, 0)
            XCTAssertEqual(weak.base.identifier, 0)
            XCTAssertNotEqual(weak.base.seed, 0)
            XCTAssertTrue(weak.isValid(in: graph))
            XCTAssertFalse(invalid.isValid(in: graph))
            XCTAssertTrue(invalid.isInvalid)
            XCTAssertEqual(invalid.base.identifier, 0)
            XCTAssertEqual(invalid.base.seed, 0)
            XCTAssertEqual(weak.toStrong().value, 42)
        }
    }

    func testViewInputsWeakScrollableReturnsInvalidWhenAbsentAndWeakWhenPresent() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            let scrollable = RecordingScrollable(shouldScroll: true)
            let scrollableAttr = graph.makeInput(value: scrollable as any Scrollable)
            var inputs = makeViewInputs(graph: graph)

            XCTAssertTrue(inputs.weakScrollable.isInvalid)
            XCTAssertFalse(inputs.weakScrollable.isValid(in: graph))

            inputs.scrollable = OptionalAttribute(scrollableAttr)

            let weak = inputs.weakScrollable
            XCTAssertFalse(weak.isInvalid)
            XCTAssertTrue(weak.isValid(in: graph))
            XCTAssertEqual(weak.base.identifier, scrollableAttr.identifier.rawValue)
            XCTAssertEqual(weak.toStrong().identifier, scrollableAttr.identifier)
        }
    }

    func testScrollablePreferenceKeyAndUnaryProviderSurface() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            let first = RecordingScrollable(shouldScroll: true)
            let second = RecordingScrollable(shouldScroll: false)
            let scrollableAttr = graph.makeInput(value: first as any Scrollable)
            let provider = UnaryScrollablePreferenceProvider(scrollable: scrollableAttr)

            XCTAssertEqual(
                Mirror(reflecting: provider).children.map(\.label),
                ["scrollable"]
            )

            let provided = provider.value
            XCTAssertEqual(provided.count, 1)
            XCTAssertTrue((provided[0] as? RecordingScrollable) === first)

            var reduced = ScrollablePreferenceKey.defaultValue
            XCTAssertTrue(reduced.isEmpty)

            ScrollablePreferenceKey.reduce(value: &reduced) {
                [first as any Scrollable]
            }
            ScrollablePreferenceKey.reduce(value: &reduced) {
                [second as any Scrollable]
            }

            XCTAssertEqual(reduced.count, 2)
            XCTAssertTrue((reduced[0] as? RecordingScrollable) === first)
            XCTAssertTrue((reduced[1] as? RecordingScrollable) === second)
        }
    }

    func testScrollableCollectionSurfaceDefaultsAndSubviewShape() {
        let collection = RecordingCollectionScrollable(shouldScroll: true)
        let visibleIDs = collection.visibleCollectionViewIDs

        XCTAssertEqual(PinnedScrollableViews.sectionHeaders.rawValue, 1)
        XCTAssertEqual(PinnedScrollableViews.sectionFooters.rawValue, 2)
        XCTAssertNil(RecordingCollectionScrollable.accessibilityRole)
        XCTAssertFalse(collection.isLazy)
        XCTAssertFalse(RecordingCollectionScrollable.hasMultipleViewsInAxis(.horizontal))
        XCTAssertTrue(RecordingCollectionScrollable.hasMultipleViewsInAxis(.vertical))

        let subviews = collection.visibleSubviews
        XCTAssertEqual(subviews.count, 1)
        XCTAssertEqual(subviews[0].id.canonicalID, visibleIDs[0])
        XCTAssertEqual(subviews[0].frame, CGRect(x: 1, y: 2, width: 30, height: 40))
        XCTAssertEqual(subviews[0].frameInContent, CGRect(x: 5, y: 6, width: 30, height: 40))
        XCTAssertEqual(
            Mirror(reflecting: subviews[0]).children.map(\.label),
            ["id", "frame", "frameInContent", "transform"]
        )

        XCTAssertEqual(collection.subviewClosestTo(rect: .zero)?.id.canonicalID, visibleIDs[0])
        XCTAssertEqual(
            collection.nextVisibleCollectionViewID(
                towards: .bottom,
                from: visibleIDs[0],
                border: .zero,
                ignoring: [.sectionHeaders]
            ),
            visibleIDs[0]
        )
        XCTAssertEqual(collection.firstCollectionViewIndex(of: visibleIDs[0]), 0)

        var index = 0
        var appliedIDs: [_ViewList_ID.Canonical] = []
        XCTAssertTrue(collection.applyCollectionViewIDs(from: &index) { id, stop in
            appliedIDs.append(id)
            stop = false
        })
        XCTAssertEqual(index, 1)
        XCTAssertEqual(appliedIDs, visibleIDs)

        XCTAssertTrue(collection.scroll(to: "row"))
        XCTAssertEqual(collection.scrolledCollectionIDs.count, 1)
        XCTAssertEqual(collection.scrolledCollectionIDs[0].explicitID, AnyHashable("row"))
        XCTAssertNil(collection.scrolledCollectionAnchors[0])

        var transaction = Transaction()
        transaction.scrollTargetAnchor = .bottom
        withTransaction(transaction) {
            XCTAssertTrue(collection.scroll(to: "anchored"))
        }
        XCTAssertEqual(collection.scrolledCollectionIDs.count, 2)
        XCTAssertEqual(collection.scrolledCollectionIDs[1].explicitID, AnyHashable("anchored"))
        XCTAssertEqual(collection.scrolledCollectionAnchors[1], .bottom)
    }

    func testScrollStateRequestTransformPublishesNearestVisibleUpdateRequest() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            let collection = RecordingCollectionScrollable(shouldScroll: true)
            let collectionAttr = graph.makeInput(value: collection as any ScrollableCollection)
            var stored = ScrollPosition(id: "visible")
            let binding = Binding<ScrollPosition>(
                get: { stored },
                set: { value, _ in stored = value }
            )
            let bindingAttr = graph.makeInput(value: binding)
            let anchorAttr = graph.makeInput(value: Optional<UnitPoint>.some(.bottom))
            var transform = ViewTransform.identity
            transform.appendScrollGeometry(
                ScrollGeometry(
                    contentOffset: CGPoint(x: 5, y: 6),
                    contentSize: CGSize(width: 200, height: 300),
                    containerSize: CGSize(width: 50, height: 60)
                ),
                isClipped: true
            )
            var inputs = makeViewInputs(graph: graph)
            inputs.transform = graph.makeInput(value: transform)
            inputs.size = graph.makeInput(value: ViewSize(CGSize(width: 10, height: 10)))
            inputs.base.setScrollPosition(storage: .binding(bindingAttr), kind: .scrollContent)
            inputs.base.setScrollPositionAnchor(OptionalAttribute(anchorAttr), kind: .scrollContent)

            let rule = ScrollStateRequestTransform(collection: collectionAttr, inputs: inputs)
            let ruleAttr = graph.makeStatefulRule(rule)
            let requests = ruleAttr.value

            XCTAssertEqual(requests.count, 1)
            guard let request = requests.first as? UpdateScrollStateRequest else {
                XCTFail("expected UpdateScrollStateRequest")
                return
            }
            assertRequestKindEqual(
                request.kind,
                .updateValue(.init(targetDistance: (CGFloat(18 * 18 + 18 * 18)).squareRoot()))
            )
            XCTAssertEqual(request.newPosition._anyViewID, AnyHashable("visible"))
            XCTAssertEqual(request.newPosition, ScrollPosition(_scrollPositionID: AnyHashable("visible"), anchor: .bottom))
            XCTAssertTrue(request.isVisible)
        }
    }

    func testScrollStateRequestTransformConvertsSubviewFrameThroughTransform() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            var selectedTransform = ViewTransform.identity
            selectedTransform.appendTranslation(CGSize(width: 100, height: 100))

            let collection = FixedVisibleCollectionScrollable(subviews: [
                ScrollableCollectionSubview(
                    id: _ViewList_ID(explicitID: AnyHashable("frameInContent-near")),
                    frame: CGRect(x: 80, y: 80, width: 10, height: 10),
                    frameInContent: CGRect(x: 0, y: 0, width: 10, height: 10),
                    transform: .identity
                ),
                ScrollableCollectionSubview(
                    id: _ViewList_ID(explicitID: AnyHashable("transformed-near")),
                    frame: CGRect(x: 100, y: 100, width: 10, height: 10),
                    frameInContent: CGRect(x: 200, y: 200, width: 10, height: 10),
                    transform: selectedTransform
                ),
            ])
            let collectionAttr = graph.makeInput(value: collection as any ScrollableCollection)
            var stored = ScrollPosition(id: "transformed-near")
            let binding = Binding<ScrollPosition>(
                get: { stored },
                set: { value, _ in stored = value }
            )
            let bindingAttr = graph.makeInput(value: binding)
            var inputs = makeViewInputs(graph: graph)
            inputs.size = graph.makeInput(value: ViewSize(CGSize(width: 10, height: 10)))
            inputs.base.setScrollPosition(storage: .binding(bindingAttr), kind: .scrollContent)

            let rule = ScrollStateRequestTransform(collection: collectionAttr, inputs: inputs)
            let ruleAttr = graph.makeStatefulRule(rule)
            let requests = ruleAttr.value

            XCTAssertEqual(requests.count, 1)
            guard let request = requests.first as? UpdateScrollStateRequest else {
                XCTFail("expected UpdateScrollStateRequest")
                return
            }
            XCTAssertEqual(request.newPosition._anyViewID, AnyHashable("transformed-near"))
            assertRequestKindEqual(request.kind, .updateValue(.init(targetDistance: 0)))
        }
    }

    func testViewTransformConvertsPointsToNearestScrollCoordinateSpaceMarker() {
        var transform = ViewTransform.identity
        transform.appendTranslation(CGSize(width: 300, height: 300))
        transform.appendSizedSpace(
            id: ScrollCoordinateSpace.all.id,
            size: CGSize(width: 200, height: 200)
        )
        transform.appendTranslation(CGSize(width: 100, height: 100))
        transform.appendSizedSpace(
            id: ScrollCoordinateSpace.all.id,
            size: CGSize(width: 50, height: 50)
        )
        transform.appendTranslation(CGSize(width: -25, height: -40))

        var points = [
            CGPoint(x: 25, y: 40),
            CGPoint(x: 35, y: 60),
        ]
        transform.convert(to: .all, points: &points)

        XCTAssertEqual(points[0], CGPoint(x: 50, y: 80))
        XCTAssertEqual(points[1], CGPoint(x: 60, y: 100))
    }

    func testViewTransformScrollCoordinateConversionComposesFoldedPositionAfterMarker() {
        var transform = ViewTransform.identity
        transform.appendTranslation(CGSize(width: 300, height: 300))
        transform.appendSizedSpace(
            id: ScrollCoordinateSpace.all.id,
            size: CGSize(width: 200, height: 200)
        )
        transform.appendTranslation(CGSize(width: -25, height: -40))
        transform.appendPosition(CGPoint(x: 1_000, y: 2_000))

        var points = [
            CGPoint(x: 25, y: 40),
            CGPoint(x: 35, y: 60),
        ]
        transform.convert(to: .all, points: &points)

        XCTAssertEqual(points[0], CGPoint(x: 1_050, y: 2_080))
        XCTAssertEqual(points[1], CGPoint(x: 1_060, y: 2_100))
    }

    func testViewTransformScrollCoordinateConversionFallsBackToGlobalWhenMarkerIsMissing() {
        var transform = ViewTransform.identity
        transform.appendTranslation(CGSize(width: 3, height: 4))

        var points = [CGPoint(x: 5, y: 6)]
        transform.convert(to: .all, points: &points)

        XCTAssertEqual(points, [CGPoint(x: 2, y: 2)])
    }

    func testViewTransformConvertsContentAndSafeAreaUsingNearestMarkers() {
        var nestedContent = ViewTransform.identity
        nestedContent.appendTranslation(CGSize(width: 100, height: 100))
        nestedContent.appendSizedSpace(
            id: ScrollCoordinateSpace.content.id,
            size: CGSize(width: 300, height: 300)
        )
        nestedContent.appendTranslation(CGSize(width: 40, height: 50))
        nestedContent.appendSizedSpace(
            id: ScrollCoordinateSpace.content.id,
            size: CGSize(width: 80, height: 90)
        )
        nestedContent.appendTranslation(CGSize(width: -5, height: -7))

        var points = [CGPoint(x: 10, y: 20)]
        nestedContent.convert(to: .content, points: &points)
        XCTAssertEqual(points, [CGPoint(x: 15, y: 27)])

        var safeArea = ViewTransform.identity
        safeArea.appendSizedSpace(
            id: ScrollCoordinateSpace.content.id,
            size: CGSize(width: 100, height: 120)
        )
        safeArea.appendTranslation(CGSize(width: 6, height: 8))
        safeArea.appendSizedSpace(
            id: ScrollCoordinateSpace.safeArea.id,
            size: CGSize(width: 88, height: 104)
        )
        safeArea.appendTranslation(CGSize(width: -6, height: -8))

        let rect = CGRect(x: 10, y: 20, width: 30, height: 40)
            .converted(to: .safeArea, using: safeArea)
        XCTAssertEqual(rect, CGRect(x: 16, y: 28, width: 30, height: 40))
    }

    func testScrollStateRequestTransformConvertsSubviewFrameToNearestScrollCoordinateSpace() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            var selectedTransform = ViewTransform.identity
            selectedTransform.appendTranslation(CGSize(width: 200, height: 200))
            selectedTransform.appendSizedSpace(
                id: ScrollCoordinateSpace.all.id,
                size: CGSize(width: 50, height: 50)
            )
            selectedTransform.appendTranslation(CGSize(width: 100, height: 100))

            let collection = FixedVisibleCollectionScrollable(subviews: [
                ScrollableCollectionSubview(
                    id: _ViewList_ID(explicitID: AnyHashable("global-near")),
                    frame: CGRect(x: 20, y: 20, width: 10, height: 10),
                    frameInContent: CGRect(x: 20, y: 20, width: 10, height: 10),
                    transform: .identity
                ),
                ScrollableCollectionSubview(
                    id: _ViewList_ID(explicitID: AnyHashable("scroll-space-near")),
                    frame: CGRect(x: 100, y: 100, width: 10, height: 10),
                    frameInContent: CGRect(x: 100, y: 100, width: 10, height: 10),
                    transform: selectedTransform
                ),
            ])
            let collectionAttr = graph.makeInput(value: collection as any ScrollableCollection)
            var stored = ScrollPosition(id: "scroll-space-near")
            let binding = Binding<ScrollPosition>(
                get: { stored },
                set: { value, _ in stored = value }
            )
            let bindingAttr = graph.makeInput(value: binding)
            var inputs = makeViewInputs(graph: graph)
            inputs.size = graph.makeInput(value: ViewSize(CGSize(width: 10, height: 10)))
            inputs.base.setScrollPosition(storage: .binding(bindingAttr), kind: .scrollContent)

            let rule = ScrollStateRequestTransform(collection: collectionAttr, inputs: inputs)
            let ruleAttr = graph.makeStatefulRule(rule)
            let requests = ruleAttr.value

            XCTAssertEqual(requests.count, 1)
            guard let request = requests.first as? UpdateScrollStateRequest else {
                XCTFail("expected UpdateScrollStateRequest")
                return
            }
            XCTAssertEqual(request.newPosition._anyViewID, AnyHashable("scroll-space-near"))
            assertRequestKindEqual(request.kind, .updateValue(.init(targetDistance: 0)))
        }
    }

    func testScrollStateRequestTransformComposesPositionAfterScrollCoordinateMarker() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            var selectedTransform = ViewTransform.identity
            selectedTransform.appendTranslation(CGSize(width: 200, height: 200))
            selectedTransform.appendSizedSpace(
                id: ScrollCoordinateSpace.all.id,
                size: CGSize(width: 50, height: 50)
            )
            selectedTransform.appendPosition(CGPoint(x: -100, y: -100))

            let collection = FixedVisibleCollectionScrollable(subviews: [
                ScrollableCollectionSubview(
                    id: _ViewList_ID(explicitID: AnyHashable("other")),
                    frame: CGRect(x: 20, y: 20, width: 10, height: 10),
                    frameInContent: CGRect(x: 20, y: 20, width: 10, height: 10),
                    transform: .identity
                ),
                ScrollableCollectionSubview(
                    id: _ViewList_ID(explicitID: AnyHashable("selected")),
                    frame: CGRect(x: 100, y: 100, width: 10, height: 10),
                    frameInContent: CGRect(x: 100, y: 100, width: 10, height: 10),
                    transform: selectedTransform
                ),
            ])
            let collectionAttr = graph.makeInput(value: collection as any ScrollableCollection)
            var stored = ScrollPosition(id: "selected")
            let binding = Binding<ScrollPosition>(
                get: { stored },
                set: { value, _ in stored = value }
            )
            let bindingAttr = graph.makeInput(value: binding)
            var inputs = makeViewInputs(graph: graph)
            inputs.size = graph.makeInput(value: ViewSize(CGSize(width: 10, height: 10)))
            inputs.base.setScrollPosition(storage: .binding(bindingAttr), kind: .scrollContent)

            let rule = ScrollStateRequestTransform(collection: collectionAttr, inputs: inputs)
            let ruleAttr = graph.makeStatefulRule(rule)
            let requests = ruleAttr.value

            XCTAssertEqual(requests.count, 1)
            guard let request = requests.first as? UpdateScrollStateRequest else {
                XCTFail("expected UpdateScrollStateRequest")
                return
            }
            XCTAssertEqual(request.newPosition._anyViewID, AnyHashable("selected"))
            assertRequestKindEqual(request.kind, .updateValue(.init(targetDistance: 0)))
        }
    }

    func testScrollStateRequestTransformCapturesLayoutDirectionEnvironment() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            let collection = RecordingCollectionScrollable(shouldScroll: true)
            let collectionAttr = graph.makeInput(value: collection as any ScrollableCollection)
            var environment = EnvironmentValues.tracking()
            environment.layoutDirection = .rightToLeft
            let environmentAttr = graph.makeInput(value: environment)
            let inputs = makeViewInputs(graph: graph, environment: environmentAttr)

            let rule = ScrollStateRequestTransform(collection: collectionAttr, inputs: inputs)
            let mirror = Mirror(reflecting: rule)
            XCTAssertEqual(
                mirror.children.map(\.label),
                ["collection", "layoutDirection", "inputs", "request", "phaseRawValue"]
            )

            guard let layoutDirection = mirror.children.first(where: { $0.label == "layoutDirection" })?.value
                as? Attribute<LayoutDirection> else {
                XCTFail("expected layoutDirection attribute")
                return
            }

            XCTAssertEqual(layoutDirection.value, .rightToLeft)

            environment.layoutDirection = .leftToRight
            environmentAttr.setValue(environment)
            XCTAssertEqual(layoutDirection.value, .leftToRight)
        }
    }

    func testScrollStateRequestTransformKeepsRepeatedRequestAndClearsMismatchedBinding() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            let collection = RecordingCollectionScrollable(shouldScroll: true)
            let collectionAttr = graph.makeInput(value: collection as any ScrollableCollection)
            var stored = ScrollPosition(id: "other")
            let binding = Binding<ScrollPosition>(
                get: { stored },
                set: { value, _ in stored = value }
            )
            let bindingAttr = graph.makeInput(value: binding)
            var inputs = makeViewInputs(graph: graph)
            inputs.base.setScrollPosition(storage: .binding(bindingAttr), kind: .scrollContent)
            let rule = ScrollStateRequestTransform(collection: collectionAttr, inputs: inputs)
            let ruleAttr = graph.makeStatefulRule(rule)

            XCTAssertTrue(ruleAttr.value.isEmpty)

            stored = ScrollPosition(id: "visible")
            graph.markNeedsEvaluation(ruleAttr.identifier)
            XCTAssertEqual(ruleAttr.value.count, 1)

            graph.markNeedsEvaluation(ruleAttr.identifier)
            XCTAssertEqual(ruleAttr.value.count, 1)

            stored = ScrollPosition(id: "other")
            graph.markNeedsEvaluation(ruleAttr.identifier)
            XCTAssertTrue(ruleAttr.value.isEmpty)
        }
    }

    func testScrollStateRequestTransformUsesTargetDistanceTolerance() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            let collection = RecordingCollectionScrollable(shouldScroll: true)
            let collectionAttr = graph.makeInput(value: collection as any ScrollableCollection)
            let position = ScrollPosition(_scrollPositionID: "visible")
            let binding = Binding<ScrollPosition>(
                get: { position },
                set: { _, _ in }
            )
            var transform = ScrollStateRequestTransform(
                collection: collectionAttr,
                inputs: makeViewInputs(graph: graph)
            )
            transform.request = UpdateScrollStateRequest(
                binding: binding,
                newPosition: position,
                isVisible: true,
                targetDistance: 0
            )

            XCTAssertFalse(transform.shouldUpdate(to: UpdateScrollStateRequest(
                binding: binding,
                newPosition: position,
                isVisible: true,
                targetDistance: 0.099
            )))
            XCTAssertTrue(transform.shouldUpdate(to: UpdateScrollStateRequest(
                binding: binding,
                newPosition: position,
                isVisible: true,
                targetDistance: 0.1
            )))
        }
    }

    func testGraphInputsScrollPhaseStateStackRoundTrip() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            let first = graph.makeInput(value: ScrollPhaseState(phase: .tracking))
            let second = graph.makeInput(value: ScrollPhaseState(phase: .decelerating))
            var inputs = makeGraphInputs(graph: graph)

            XCTAssertNil(inputs.scrollPhaseState.attribute)
            XCTAssertTrue(inputs.scrollPhaseStates.isEmpty)

            inputs.appendScrollPhaseState(OptionalAttribute(first))

            XCTAssertEqual(inputs.scrollPhaseState.attribute?.identifier, first.identifier)

            inputs.appendScrollPhaseState(OptionalAttribute(second))

            XCTAssertEqual(inputs.scrollPhaseState.attribute?.identifier, second.identifier)

            var stack = inputs.scrollPhaseStates
            XCTAssertEqual(stack.pop()?.attribute?.identifier, second.identifier)
            XCTAssertEqual(stack.pop()?.attribute?.identifier, first.identifier)
            XCTAssertNil(stack.pop())
        }
    }

    func testDelayedPreferenceViewConnectsWeakValueToChildPreference() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            var capturedValue: _PreferenceValue<DelayedPreferenceTestKey>?
            let delayed = _DelayedPreferenceView<DelayedPreferenceTestKey, DelayedPreferenceProbeContent> {
                value in
                capturedValue = value
                return DelayedPreferenceProbeContent(value: 37)
            }
            let delayedAttr = graph.makeInput(value: delayed)
            let outputs = _DelayedPreferenceView<
                DelayedPreferenceTestKey,
                DelayedPreferenceProbeContent
            >._makeView(
                view: _GraphValue(_attribute: delayedAttr),
                inputs: makeViewInputs(graph: graph)
            )

            let output = outputs.preferences.value(for: DelayedPreferenceTestKey.self)
            XCTAssertNotNil(output)
            XCTAssertEqual(output.map { Attribute<Int>($0).value }, 37)

            let captured = capturedValue?.attribute
            XCTAssertNotNil(captured)
            XCTAssertEqual(captured.map { $0.toStrong().value }, 37)
            XCTAssertEqual(
                Mirror(reflecting: delayed).children.compactMap(\.label),
                ["transform"]
            )
            XCTAssertEqual(
                capturedValue.map { Mirror(reflecting: $0).children.compactMap(\.label) },
                ["attribute"]
            )
        }
    }

    func testScrollViewReaderAndProxyStorageSurface() {
        let reader = ScrollViewReader { _ in EmptyView() }
        let body = reader.body

        XCTAssertEqual(
            Mirror(reflecting: reader).children.compactMap(\.label),
            ["content"]
        )
        XCTAssertEqual(
            Mirror(reflecting: body).children.compactMap(\.label),
            ["transform"]
        )
        XCTAssertTrue(
            String(reflecting: type(of: body)).contains(
                "_DelayedPreferenceView<VUI.ScrollablePreferenceKey, VUI.EmptyView>"
            )
        )

        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)
        ref.withCurrent {
            let values = graph.makeInput(value: [any Scrollable]())
            let proxy = ScrollViewProxy(_values: values.asWeak())
            XCTAssertEqual(
                Mirror(reflecting: proxy).children.compactMap(\.label),
                ["_values"]
            )
        }
    }

    func testScrollViewProxyStopsAtFirstHandledScrollableAndCarriesAnchor() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            let first = RecordingScrollable(shouldScroll: false)
            let second = RecordingScrollable(shouldScroll: true)
            let third = RecordingScrollable(shouldScroll: true)
            let values = graph.makeInput(value: [
                first as any Scrollable,
                second as any Scrollable,
                third as any Scrollable,
            ])
            let proxy = ScrollViewProxy(_values: values.asWeak())

            proxy.scrollTo("target", anchor: .bottom)

            XCTAssertEqual(first.scrolledIDs, [AnyHashable("target")])
            XCTAssertEqual(second.scrolledIDs, [AnyHashable("target")])
            XCTAssertTrue(third.scrolledIDs.isEmpty)
            XCTAssertEqual(first.observedTransactions.map(\.scrollTargetAnchor), [.bottom])
            XCTAssertEqual(second.observedTransactions.map(\.scrollTargetAnchor), [.bottom])
            XCTAssertNil(Transaction.current.scrollTargetAnchor)
        }
    }

    func testScrollViewProxyNilAnchorPreservesCurrentTransactionAnchor() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            let scrollable = RecordingScrollable(shouldScroll: true)
            let values = graph.makeInput(value: [scrollable as any Scrollable])
            let proxy = ScrollViewProxy(_values: values.asWeak())
            var transaction = Transaction()
            transaction.scrollTargetAnchor = .top

            withTransaction(transaction) {
                proxy.scrollTo(9)
            }

            XCTAssertEqual(scrollable.scrolledIDs, [AnyHashable(9)])
            XCTAssertEqual(scrollable.observedTransactions.map(\.scrollTargetAnchor), [.top])
            XCTAssertNil(Transaction.current.scrollTargetAnchor)
        }
    }

    private func makeViewInputs(
        graph: _AGGraph,
        environment: Attribute<EnvironmentValues>? = nil
    ) -> _ViewInputs {
        _ViewInputs(
            base: makeGraphInputs(graph: graph, environment: environment),
            customInputs: PropertyList(),
            preferences: PreferencesInputs(
                keys: PreferenceKeys(),
                hostKeys: graph.makeInput(value: PreferenceKeys())
            ),
            transform: graph.makeInput(value: ViewTransform.identity),
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
        environment: Attribute<EnvironmentValues>? = nil
    ) -> _GraphInputs {
        _GraphInputs(
            time: graph.makeInput(value: Time()),
            phase: graph.makeInput(value: _GraphInputs.Phase()),
            environment: environment ?? graph.makeInput(value: EnvironmentValues.tracking()),
            transaction: graph.makeInput(value: Transaction())
        )
    }
}

private struct DelayedPreferenceTestKey: PreferenceKey {
    static var defaultValue: Int { 0 }

    static func reduce(value: inout Int, nextValue: () -> Int) {
        value += nextValue()
    }
}

private struct DelayedPreferenceProbeContent: View {
    var value: Int

    static func _makeView(
        view: _GraphValue<Self>,
        inputs: _ViewInputs
    ) -> _ViewOutputs {
        var preferences = PreferencesOutputs()
        preferences.append(
            DelayedPreferenceTestKey.self,
            node: view[\.value]._attribute.identifier
        )
        return _ViewOutputs(preferences: preferences)
    }

    typealias Body = Never
}

extension DelayedPreferenceProbeContent: PrimitiveView, UnaryView {
}

private final class RecordingScrollable: Scrollable {
    let shouldScroll: Bool
    var scrolledIDs: [AnyHashable] = []
    var observedTransactions: [Transaction] = []
    var contentTargets: [(ScrollGeometry, LayoutDirection) -> ScrollTarget?] = []

    init(shouldScroll: Bool) {
        self.shouldScroll = shouldScroll
    }

    func scroll<ID>(to id: ID) -> Bool where ID: Hashable {
        scrolledIDs.append(AnyHashable(id))
        observedTransactions.append(Transaction.current)
        return shouldScroll
    }

    func setContentTarget(_ target: @escaping (ScrollGeometry, LayoutDirection) -> ScrollTarget?) -> Bool {
        contentTargets.append(target)
        return shouldScroll
    }

    var allowsContentOffsetAdjustments: Bool {
        false
    }

    func adjustContentOffset(by offset: CGSize, reason: ContentOffsetAdjustmentReason) -> Bool {
        false
    }

    func mapFirstChild<A, B>(ofType type: A.Type, body: (A) -> B) -> B? {
        nil
    }
}

private final class RecordingCollectionScrollable: ScrollableCollection {
    let shouldScroll: Bool
    var scrolledCollectionIDs: [_ViewList_ID.Canonical] = []
    var scrolledCollectionAnchors: [UnitPoint?] = []

    init(shouldScroll: Bool) {
        self.shouldScroll = shouldScroll
    }

    func scroll<ID>(to id: ID) -> Bool where ID: Hashable {
        scroll(
            toCollectionViewID: _ViewList_ID(explicitID: AnyHashable(id)).canonicalID,
            anchor: Transaction.current.scrollTargetAnchor
        )
    }

    var visibleCollectionViewIDs: [_ViewList_ID.Canonical] {
        [_ViewList_ID(explicitID: AnyHashable("visible")).canonicalID]
    }

    func forEachVisibleSubview(_ body: (ScrollableCollectionSubview, inout Bool) -> Void) {
        var stop = false
        var transform = ViewTransform.identity
        transform.appendTranslation(CGSize(width: 4, height: 4))
        body(
            ScrollableCollectionSubview(
                id: _ViewList_ID(explicitID: AnyHashable("visible")),
                frame: CGRect(x: 1, y: 2, width: 30, height: 40),
                frameInContent: CGRect(x: 5, y: 6, width: 30, height: 40),
                transform: transform
            ),
            &stop
        )
    }

    func subviewClosestTo(rect: CGRect) -> ScrollableCollectionSubview? {
        visibleSubviews.first
    }

    func nextVisibleCollectionViewID(
        towards point: UnitPoint,
        from id: _ViewList_ID.Canonical,
        border: CGSize,
        ignoring pinnedViews: PinnedScrollableViews
    ) -> _ViewList_ID.Canonical? {
        visibleCollectionViewIDs.first
    }

    static func hasMultipleViewsInAxis(_ axis: Axis) -> Bool {
        axis == .vertical
    }

    func firstCollectionViewIndex(of id: _ViewList_ID.Canonical) -> Int? {
        visibleCollectionViewIDs.firstIndex(of: id)
    }

    func applyCollectionViewIDs(
        from index: inout Int,
        to body: (_ViewList_ID.Canonical, inout Bool) -> Void
    ) -> Bool {
        let ids = visibleCollectionViewIDs
        guard index < ids.count else { return false }

        while index < ids.count {
            var stop = false
            body(ids[index], &stop)
            index += 1
            if stop { break }
        }
        return true
    }

    func collectionViewID(for subgraph: AGSubgraph) -> _ViewList_ID.Canonical? {
        visibleCollectionViewIDs.first
    }

    func scroll(toCollectionViewID id: _ViewList_ID.Canonical, anchor: UnitPoint?) -> Bool {
        scrolledCollectionIDs.append(id)
        scrolledCollectionAnchors.append(anchor)
        return shouldScroll
    }

    func setContentTarget(_ target: @escaping (ScrollGeometry, LayoutDirection) -> ScrollTarget?) -> Bool {
        false
    }

    var allowsContentOffsetAdjustments: Bool {
        false
    }

    func adjustContentOffset(by offset: CGSize, reason: ContentOffsetAdjustmentReason) -> Bool {
        false
    }

    func mapFirstChild<A, B>(ofType type: A.Type, body: (A) -> B) -> B? {
        nil
    }
}

private final class FixedVisibleCollectionScrollable: ScrollableCollection {
    let subviews: [ScrollableCollectionSubview]
    var scrolledCollectionIDs: [_ViewList_ID.Canonical] = []
    var scrolledCollectionAnchors: [UnitPoint?] = []

    init(subviews: [ScrollableCollectionSubview]) {
        self.subviews = subviews
    }

    func scroll<ID>(to id: ID) -> Bool where ID: Hashable {
        scroll(
            toCollectionViewID: _ViewList_ID(explicitID: AnyHashable(id)).canonicalID,
            anchor: Transaction.current.scrollTargetAnchor
        )
    }

    var visibleCollectionViewIDs: [_ViewList_ID.Canonical] {
        subviews.map { $0.id.canonicalID }
    }

    func forEachVisibleSubview(_ body: (ScrollableCollectionSubview, inout Bool) -> Void) {
        for subview in subviews {
            var stop = false
            body(subview, &stop)
            if stop { break }
        }
    }

    func subviewClosestTo(rect: CGRect) -> ScrollableCollectionSubview? {
        subviews.first
    }

    func nextVisibleCollectionViewID(
        towards point: UnitPoint,
        from id: _ViewList_ID.Canonical,
        border: CGSize,
        ignoring pinnedViews: PinnedScrollableViews
    ) -> _ViewList_ID.Canonical? {
        visibleCollectionViewIDs.first
    }

    static func hasMultipleViewsInAxis(_ axis: Axis) -> Bool {
        false
    }

    func firstCollectionViewIndex(of id: _ViewList_ID.Canonical) -> Int? {
        visibleCollectionViewIDs.firstIndex(of: id)
    }

    func applyCollectionViewIDs(
        from index: inout Int,
        to body: (_ViewList_ID.Canonical, inout Bool) -> Void
    ) -> Bool {
        let ids = visibleCollectionViewIDs
        guard index < ids.count else { return false }

        while index < ids.count {
            var stop = false
            body(ids[index], &stop)
            index += 1
            if stop { break }
        }
        return true
    }

    func collectionViewID(for subgraph: AGSubgraph) -> _ViewList_ID.Canonical? {
        visibleCollectionViewIDs.first
    }

    func scroll(toCollectionViewID id: _ViewList_ID.Canonical, anchor: UnitPoint?) -> Bool {
        scrolledCollectionIDs.append(id)
        scrolledCollectionAnchors.append(anchor)
        return true
    }

    func setContentTarget(_ target: @escaping (ScrollGeometry, LayoutDirection) -> ScrollTarget?) -> Bool {
        false
    }

    var allowsContentOffsetAdjustments: Bool {
        false
    }

    func adjustContentOffset(by offset: CGSize, reason: ContentOffsetAdjustmentReason) -> Bool {
        false
    }

    func mapFirstChild<A, B>(ofType type: A.Type, body: (A) -> B) -> B? {
        nil
    }
}

private struct ScrollRequestMarkerKey: TransactionKey {
    static let defaultValue = 0
}

private struct ScrollAmbientMarkerKey: TransactionKey {
    static let defaultValue = 0
}

private struct ScrollBindingMarkerKey: TransactionKey {
    static let defaultValue = 0
}

private struct TestScrollStateRequest: ScrollStateRequest {
    var id: ObjectIdentifier
    var kind: ScrollStateRequestKind
    var transaction: Transaction { Transaction() }
    var hasUpdate: Bool { false }

    mutating func update() -> Bool {
        false
    }
}
