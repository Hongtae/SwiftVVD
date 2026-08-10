import XCTest
@testable import VUI

final class GesturePhaseSurfaceTests: XCTestCase {
    func testEventDirectionRawValuesMatchSwiftUISurface() {
        let _: Int8 = _EventDirections.all.rawValue

        XCTAssertEqual(MemoryLayout<_EventDirections>.size, 1)
        XCTAssertEqual(MemoryLayout<_EventDirections>.stride, 1)
        XCTAssertEqual(MemoryLayout<_EventDirections>.alignment, 1)
        XCTAssertEqual(_EventDirections.left.rawValue, 0x01)
        XCTAssertEqual(_EventDirections.right.rawValue, 0x02)
        XCTAssertEqual(_EventDirections.up.rawValue, 0x04)
        XCTAssertEqual(_EventDirections.down.rawValue, 0x08)
        XCTAssertEqual(_EventDirections.horizontal, [.left, .right])
        XCTAssertEqual(_EventDirections.vertical, [.up, .down])
        XCTAssertEqual(_EventDirections.all, [.left, .right, .up, .down])
    }

    func testActiveIncludesEndedButNotPossibleOrFailed() {
        XCTAssertFalse(GesturePhase<Int>.possible(3).isActive)
        XCTAssertTrue(GesturePhase<Int>.active(4).isActive)
        XCTAssertTrue(GesturePhase<Int>.ended(5).isActive)
        XCTAssertFalse(GesturePhase<Int>.failed.isActive)
    }

    func testUnwrappedIgnoresPossiblePayloadAndReturnsActiveOrEndedPayload() {
        XCTAssertNil(GesturePhase<Int>.possible(3).unwrapped)
        XCTAssertEqual(GesturePhase<Int>.active(4).unwrapped, 4)
        XCTAssertEqual(GesturePhase<Int>.ended(5).unwrapped, 5)
        XCTAssertNil(GesturePhase<Int>.failed.unwrapped)
    }

    func testDefaultValueIsFailed() {
        XCTAssertEqual(GesturePhase<Int>.defaultValue, .failed)
    }

    func testGestureDependencyCasesAndReductionMatchSwiftUISurface() {
        XCTAssertEqual(MemoryLayout<GestureDependency>.size, 1)
        XCTAssertEqual(GestureDependency.none.rawValue, 0)
        XCTAssertEqual(GestureDependency.pausedWhileActive.rawValue, 1)
        XCTAssertEqual(GestureDependency.pausedUntilFailed.rawValue, 2)
        XCTAssertEqual(GestureDependency.failIfActive.rawValue, 3)

        var dependency = GestureDependency.pausedWhileActive
        GestureDependency.Key.reduce(value: &dependency) { .none }
        XCTAssertEqual(dependency, .pausedWhileActive)
        GestureDependency.Key.reduce(value: &dependency) { .pausedUntilFailed }
        XCTAssertEqual(dependency, .pausedUntilFailed)
        GestureDependency.Key.reduce(value: &dependency) { .failIfActive }
        XCTAssertEqual(dependency, .failIfActive)
    }

    func testDependentPhaseAppliesAllInheritedPhaseBranches() {
        let graph = _AGGraph()
        _AGGraph.withCurrent(graph) {
            let modifier = graph.makeInput(value: DependentGesture<Int>(dependency: .none))
            let phase = graph.makeInput(value: GesturePhase<Int>.active(7))
            let inherited = graph.makeInput(value: _GestureInputs.InheritedPhase.defaultValue)
            let output = graph.makeRule(DependentPhase(
                _modifier: modifier,
                _phase: phase,
                _inheritedPhase: inherited
            ))

            XCTAssertEqual(output.value, .active(7))

            modifier.setValue(DependentGesture(dependency: .pausedWhileActive))
            inherited.setValue([.active])
            XCTAssertEqual(output.value, .possible(7))

            modifier.setValue(DependentGesture(dependency: .pausedUntilFailed))
            inherited.setValue([])
            XCTAssertEqual(output.value, .possible(7))
            inherited.setValue([.failed])
            XCTAssertEqual(output.value, .active(7))

            modifier.setValue(DependentGesture(dependency: .failIfActive))
            inherited.setValue([.active])
            XCTAssertEqual(output.value, .failed)
            inherited.setValue([])
            XCTAssertEqual(output.value, .possible(7))
            inherited.setValue([.failed])
            XCTAssertEqual(output.value, .active(7))

            phase.setValue(.ended(9))
            inherited.setValue([])
            XCTAssertEqual(output.value, .possible(9))
        }
    }

    func testDependentGesturePublishesItsDependencyWhenChildHasNone() throws {
        let graph = _AGGraph()
        try _AGGraph.withCurrent(graph) {
            let modifier = graph.makeInput(value: DependentGesture<Int>(
                dependency: .pausedWhileActive
            ))
            let childPhase = graph.makeInput(value: GesturePhase<Int>.active(4))
            let outputs = DependentGesture<Int>._makeGesture(
                modifier: _GraphValue(_attribute: modifier),
                inputs: makeGestureInputs(graph: graph)
            ) { _ in
                _GestureOutputs(phase: childPhase)
            }

            let dependencyID = try XCTUnwrap(
                outputs.preferences.value(for: GestureDependency.Key.self)
            )
            XCTAssertEqual(
                Attribute<GestureDependency>(dependencyID).value,
                .pausedWhileActive
            )
            XCTAssertEqual(outputs.phase.value, .active(4))
        }
    }

    func testTruePreferenceWriterRemovesKeyFromChildAndPublishesTrue() throws {
        let host = GraphHost()
        try host.data.withCurrent {
            let graph = host.data.graph
            var inputs = makeGestureInputs(graph: graph)
            inputs.preferences.add(IsCancellableGestureKey.self)
            let modifier = graph.makeInput(
                value: TruePreferenceWritingGestureModifier<
                    IsCancellableGestureKey,
                    Int
                >()
            )
            let childPhase = graph.makeInput(value: GesturePhase<Int>.active(4))
            var childReceivedKey = true

            let outputs = TruePreferenceWritingGestureModifier<
                IsCancellableGestureKey,
                Int
            >._makeGesture(
                modifier: _GraphValue(_attribute: modifier),
                inputs: inputs
            ) { childInputs in
                childReceivedKey = childInputs.preferences.keys.contains(
                    IsCancellableGestureKey.self
                )
                return _GestureOutputs(phase: childPhase)
            }

            XCTAssertFalse(childReceivedKey)
            let preferenceID = try XCTUnwrap(
                outputs.preferences.value(for: IsCancellableGestureKey.self)
            )
            XCTAssertTrue(Attribute<Bool>(preferenceID).value)
        }
    }

    func testPrimitiveButtonCorePublishesCancellablePreference() throws {
        let host = GraphHost()
        try host.data.withCurrent {
            let graph = host.data.graph
            var inputs = makeGestureInputs(graph: graph)
            inputs.preferences.add(IsCancellableGestureKey.self)
            let gesture = graph.makeInput(value: PrimitiveButtonGestureCore(
                outset: 0,
                alwaysActive: false
            ))

            let outputs = PrimitiveButtonGestureCore._makeGesture(
                gesture: _GraphValue(_attribute: gesture),
                inputs: inputs
            )

            let preferenceID = try XCTUnwrap(
                outputs.preferences.value(for: IsCancellableGestureKey.self)
            )
            XCTAssertTrue(Attribute<Bool>(preferenceID).value)
        }
    }

    func testResponderArbitrationMatchesPriorityDependencyAndTapCountRules() {
        let defaultParent = ArbitrationTestResponder(exclusionPolicy: .default)
        let defaultChild = ArbitrationTestResponder(exclusionPolicy: .default)
        defaultChild.parent = defaultParent

        XCTAssertTrue(defaultChild.isPrioritized(
            over: defaultParent,
            otherExclusionPolicy: defaultParent.exclusionPolicy
        ))
        XCTAssertFalse(defaultParent.isPrioritized(
            over: defaultChild,
            otherExclusionPolicy: defaultChild.exclusionPolicy
        ))

        let highParent = ArbitrationTestResponder(exclusionPolicy: .highPriority)
        let highChild = ArbitrationTestResponder(exclusionPolicy: .highPriority)
        highChild.parent = highParent
        XCTAssertTrue(highParent.isPrioritized(
            over: highChild,
            otherExclusionPolicy: highChild.exclusionPolicy
        ))
        XCTAssertFalse(highChild.isPrioritized(
            over: highParent,
            otherExclusionPolicy: highParent.exclusionPolicy
        ))

        let high = ArbitrationTestResponder(exclusionPolicy: .highPriority)
        for dependency in [
            GestureDependency.none,
            .pausedWhileActive,
            .pausedUntilFailed,
            .failIfActive,
        ] {
            let other = ArbitrationTestResponder(
                exclusionPolicy: .default,
                dependency: dependency
            )
            XCTAssertEqual(
                high.canPrevent(other, otherExclusionPolicy: other.exclusionPolicy),
                dependency == .none || dependency == .failIfActive
            )
        }

        let single = ArbitrationTestResponder(
            exclusionPolicy: .default,
            requiredTapCount: 1
        )
        let double = ArbitrationTestResponder(
            exclusionPolicy: .default,
            requiredTapCount: 2
        )
        XCTAssertTrue(single.shouldRequireFailure(of: double))
        XCTAssertFalse(double.shouldRequireFailure(of: single))

        let dependentDefault = ArbitrationTestResponder(
            exclusionPolicy: .default,
            dependency: .pausedWhileActive
        )
        XCTAssertTrue(dependentDefault.shouldRequireFailure(of: high))
        let independentDefault = ArbitrationTestResponder(exclusionPolicy: .default)
        XCTAssertFalse(independentDefault.shouldRequireFailure(of: high))

        let simultaneous = ArbitrationTestResponder(
            exclusionPolicy: .simultaneous(.global),
            dependency: .pausedWhileActive
        )
        XCTAssertFalse(simultaneous.shouldRequireFailure(of: high))

        let simultaneousParent = ArbitrationTestResponder(
            exclusionPolicy: .simultaneous(.descendants)
        )
        let simultaneousChild = ArbitrationTestResponder(exclusionPolicy: .default)
        simultaneousChild.parent = simultaneousParent
        XCTAssertTrue(simultaneousParent.isSimultaneous(with: simultaneousChild))
        XCTAssertTrue(simultaneousChild.isSimultaneous(with: simultaneousParent))

        let global = ArbitrationTestResponder(
            exclusionPolicy: .simultaneous(.global)
        )
        XCTAssertTrue(global.isSimultaneous(with: high))
        XCTAssertTrue(high.isSimultaneous(with: global))
    }

    func testGestureResponderPreferenceGettersInstantiateInsideUpdateScope() {
        func makeResponder() -> (ArbitrationTestResponder, UpdateScopeGestureGraph) {
            let graph = UpdateScopeGestureGraph()
            return (
                ArbitrationTestResponder(
                    exclusionPolicy: .default,
                    gestureGraph: graph
                ),
                graph
            )
        }

        let (cancellableResponder, cancellableGraph) = makeResponder()
        XCTAssertFalse(cancellableResponder.isCancellable)
        XCTAssertTrue(cancellableGraph.observedUpdateActive)

        let (tapResponder, tapGraph) = makeResponder()
        XCTAssertNil(tapResponder.requiredTapCount)
        XCTAssertTrue(tapGraph.observedUpdateActive)

        let (dependencyResponder, dependencyGraph) = makeResponder()
        XCTAssertEqual(dependencyResponder.dependency, .none)
        XCTAssertTrue(dependencyGraph.observedUpdateActive)
    }

    func testViewResponderPreferenceReductionAppendsInTraversalOrder() {
        let first = MultiViewResponder()
        let second = MultiViewResponder()
        let third = MultiViewResponder()
        var responders: [ViewResponder] = [first]

        ViewRespondersKey.reduce(value: &responders) {
            [second as ViewResponder, third as ViewResponder]
        }

        XCTAssertTrue(responders[0] === first)
        XCTAssertTrue(responders[1] === second)
        XCTAssertTrue(responders[2] === third)
    }

    func testViewResponderHitTestConstantsAndCounterMatchObservedSurface() {
        XCTAssertEqual(ViewResponder.minOpacityForHitTest, 0.001)
        XCTAssertEqual(ViewResponder.gestureContainmentPriority, 16.0)

        let previous = ViewResponder.hitTestKey
        XCTAssertEqual(ViewResponder.nextHitTestKey(), previous &+ 1)
        XCTAssertEqual(ViewResponder.hitTestKey, previous &+ 1)
    }

    func testContainsPointsCacheOnlyReusesMatchingNonnilKeys() {
        var cache = ViewResponder.ContainsPointsCache()
        var bodyCalls = 0

        func result(_ rawValue: UInt64) -> ViewResponder.ContainsPointsResult {
            ViewResponder.ContainsPointsResult(
                mask: BitVector64(rawValue: rawValue),
                priority: 0,
                children: []
            )
        }

        let firstNil = cache.fetch(key: nil) {
            bodyCalls += 1
            return result(1)
        }
        let repeatedNil = cache.fetch(key: nil) {
            bodyCalls += 1
            return result(2)
        }
        XCTAssertEqual(firstNil.mask.rawValue, 1)
        XCTAssertEqual(repeatedNil.mask.rawValue, 2)
        XCTAssertNil(cache.storage?.key)
        XCTAssertEqual(bodyCalls, 2)

        let firstKey = cache.fetch(key: 7) {
            bodyCalls += 1
            return result(4)
        }
        let repeatedKey = cache.fetch(key: 7) {
            bodyCalls += 1
            return result(8)
        }
        XCTAssertEqual(firstKey.mask.rawValue, 4)
        XCTAssertEqual(repeatedKey.mask.rawValue, 4)
        XCTAssertEqual(cache.storage?.key, 7)
        XCTAssertEqual(bodyCalls, 3)

        let replacedNil = cache.fetch(key: nil) {
            bodyCalls += 1
            return result(16)
        }
        XCTAssertEqual(replacedNil.mask.rawValue, 16)
        XCTAssertNil(cache.storage?.key)
        XCTAssertEqual(bodyCalls, 4)
    }

    func testResponderVisitorSkipsChildrenAndCancelsTraversal() {
        let root = MultiViewResponder()
        let skipped = MultiViewResponder()
        let skippedChild = MultiViewResponder()
        let sibling = MultiViewResponder()
        skipped.children = [skippedChild]
        root.children = [skipped, sibling]

        var visited: [ObjectIdentifier] = []
        let completed = root.visit { responder in
            visited.append(ObjectIdentifier(responder))
            return responder === skipped ? .skipToNextSibling : .next
        }
        XCTAssertEqual(completed, .next)
        XCTAssertEqual(
            visited,
            [root, skipped, sibling].map(ObjectIdentifier.init)
        )

        visited.removeAll()
        let cancelled = root.visit { responder in
            visited.append(ObjectIdentifier(responder))
            return responder === skippedChild ? .cancel : .next
        }
        XCTAssertEqual(cancelled, .cancel)
        XCTAssertEqual(
            visited,
            [root, skipped, skippedChild].map(ObjectIdentifier.init)
        )
    }

    func testCoordinateSpaceEventsConvertsInputsBeforeRecognition() throws {
        let graph = _AGGraph()
        try _AGGraph.withCurrent(graph) {
            let eventID = EventID(type: VUI.MouseEvent.self, serial: 1)
            let modifier = graph.makeInput(value: CoordinateSpaceGesture<Int>(
                coordinateSpace: .local
            ))
            let events = graph.makeInput(value: [
                eventID: VUI.MouseEvent(
                    timestamp: .zero,
                    binding: nil,
                    button: .primary,
                    phase: .began,
                    location: CGPoint(x: 30, y: 50),
                    globalLocation: CGPoint(x: 30, y: 50),
                    modifiers: []
                )
            ] as [EventID: any EventType])
            var transform = ViewTransform()
            transform.appendPosition(CGPoint(x: 100, y: 200))
            let output = graph.makeRule(CoordinateSpaceEvents(
                _modifier: modifier,
                _events: events,
                _position: graph.makeInput(value: CGPoint(x: 10, y: 20)),
                _transform: graph.makeInput(value: transform)
            ))

            let local = try XCTUnwrap(output.value[eventID] as? VUI.MouseEvent)
            XCTAssertEqual(local.location, CGPoint(x: 20, y: 30))

            modifier.setValue(CoordinateSpaceGesture(
                coordinateSpace: .named(AnyHashable("named"))
            ))
            let named = try XCTUnwrap(output.value[eventID] as? VUI.MouseEvent)
            XCTAssertEqual(named.location, CGPoint(x: 30, y: 50))

            var namedTransform = ViewTransform()
            namedTransform.appendTranslation(CGSize(width: 5, height: 7))
            namedTransform.appendPosition(CGPoint(x: 100, y: 200))
            namedTransform.appendSizedSpace(
                name: AnyHashable("named"),
                size: CGSize(width: 40, height: 50)
            )
            let namedOutput = graph.makeRule(CoordinateSpaceEvents(
                _modifier: modifier,
                _events: graph.makeInput(value: [
                    eventID: VUI.MouseEvent(
                        timestamp: .zero,
                        binding: nil,
                        button: .primary,
                        phase: .began,
                        location: CGPoint(x: 115, y: 227),
                        globalLocation: CGPoint(x: 115, y: 227),
                        modifiers: []
                    )
                ] as [EventID: any EventType]),
                _position: graph.makeInput(value: CGPoint(x: 100, y: 200)),
                _transform: graph.makeInput(value: namedTransform)
            ))
            let convertedNamed = try XCTUnwrap(
                namedOutput.value[eventID] as? VUI.MouseEvent
            )
            XCTAssertEqual(convertedNamed.location, CGPoint(x: 15, y: 27))
        }
    }

    func testCoordinateSpaceModifierAppendsAnimatedSizedNamedSpace() {
        let graph = _AGGraph()
        _AGGraph.withCurrent(graph) {
            var inputs = makeViewInputs(graph: graph)
            var base = ViewTransform.identity
            base.appendTranslation(CGSize(width: 5, height: 7))
            inputs.transform = graph.makeInput(value: base)
            inputs.position = graph.makeInput(value: CGPoint(x: 100, y: 200))
            inputs.size = graph.makeInput(value: ViewSize(width: 40, height: 50))

            let modifier = graph.makeInput(value: _CoordinateSpaceModifier(
                name: "scroll-node"
            ))
            _CoordinateSpaceModifier<String>._makeViewInputs(
                modifier: _GraphValue(_attribute: modifier),
                inputs: &inputs
            )

            var namedPoints = [CGPoint(x: 115, y: 227)]
            inputs.transform.value.convertGlobal(
                to: .named(AnyHashable("scroll-node")),
                points: &namedPoints
            )
            XCTAssertEqual(namedPoints, [CGPoint(x: 15, y: 27)])

            var localPoints = [CGPoint(x: 115, y: 227)]
            inputs.transform.value.convertGlobal(to: .local, points: &localPoints)
            XCTAssertEqual(localPoints, [CGPoint(x: 10, y: 20)])

            var missingPoints = [CGPoint(x: 115, y: 227)]
            inputs.transform.value.convertGlobal(
                to: .named(AnyHashable("missing")),
                points: &missingPoints
            )
            XCTAssertEqual(missingPoints, [CGPoint(x: 115, y: 227)])
        }
    }

    private func makeGestureInputs(graph: _AGGraph) -> _GestureInputs {
        _GestureInputs(
            makeViewInputs(graph: graph),
            viewSubgraph: nil,
            events: graph.makeInput(value: [:] as [EventID: any EventType]),
            time: graph.makeInput(value: Time()),
            resetSeed: graph.makeInput(value: UInt32(0)),
            inheritedPhase: graph.makeInput(value: _GestureInputs.InheritedPhase.defaultValue),
            gesturePreferenceKeys: graph.makeInput(value: PreferenceKeys())
        )
    }

    private func makeViewInputs(graph: _AGGraph) -> _ViewInputs {
        _ViewInputs(
            base: _GraphInputs(
                time: graph.makeInput(value: Time()),
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
            size: graph.makeInput(value: ViewSize(.zero)),
            safeAreaInsets: OptionalAttribute(),
            containerSize: OptionalAttribute(),
            stackOrientation: nil
        )
    }
}

private final class ArbitrationTestResponder: ViewResponder, AnyGestureResponder {
    var relatedAttribute: AGAttribute { .invalid }
    var inputs: _ViewInputs { fatalError("unused test responder input") }
    var childSubgraph: AGSubgraph?
    var childViewSubgraph: AGSubgraph?
    let exclusionPolicy: GestureResponderExclusionPolicy
    var label: String? { nil }
    var mask: GestureMask = .all
    let gestureGraph: GestureGraph
    let viewSubgraph: AGSubgraph
    var eventSources: [any EventBindingSource] { [] }
    var gestureType: Any.Type { Self.self }
    var isValid: Bool { true }

    init(
        exclusionPolicy: GestureResponderExclusionPolicy,
        dependency: GestureDependency = .none,
        requiredTapCount: Int? = nil,
        hitTestKey: UInt32 = 1,
        gestureGraph suppliedGestureGraph: GestureGraph? = nil
    ) {
        _ = hitTestKey
        self.exclusionPolicy = exclusionPolicy
        let gestureGraph = suppliedGestureGraph ?? GestureGraph()
        self.gestureGraph = gestureGraph
        self.viewSubgraph = gestureGraph.data.withCurrent {
            AGSubgraph()
        }
        super.init()

        gestureGraph.data.withCurrent {
            let graph = gestureGraph.data.graph
            gestureGraph._gestureDependencyAttr = OptionalAttribute(
                graph.makeInput(value: dependency)
            )
            if let requiredTapCount {
                gestureGraph._requiredTapCountAttr = OptionalAttribute(
                    graph.makeInput(value: Optional(requiredTapCount))
                )
            }
        }
    }

    func detachContainer() {}
}

private final class UpdateScopeGestureGraph: GestureGraph, @unchecked Sendable {
    private(set) var observedUpdateActive = false

    override func instantiateOutputs() {
        observedUpdateActive = Update.isActive
        super.instantiateOutputs()
    }
}
