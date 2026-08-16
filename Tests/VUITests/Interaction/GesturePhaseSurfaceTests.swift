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

    // ASSERTIONS gestureModifierProtocolSurfaceObserved
    // ASSERTIONS modifierGestureFieldOwnershipObserved
    func testModifierGestureStoresContentBeforeModifier() {
        let gesture = ModifierGesture(
            content: PhaseTestGesture(phase: GesturePhase<Int>.active(3)),
            modifier: MapGesture<Int, Int>(body: { $0 })
        )

        XCTAssertEqual(
            Mirror(reflecting: gesture).children.compactMap(\.label),
            ["content", "modifier"]
        )
    }

    // ASSERTIONS gestureCombinedMap2ControlFlowObserved
    // ASSERTIONS map2GesturePreferenceMergeObserved
    func testCombinedUsesMap2AndReducesBothPreferenceOutputs() throws {
        let graph = _AGGraph()
        try _AGGraph.withCurrent(graph) {
            let primary = PhaseTestGesture(
                phase: GesturePhase<Int>.active(4)
            )
            let secondary = PreferencePhaseTestGesture(
                phase: .active(6),
                preference: [2]
            )
            let combined = primary.combined(with: secondary) { first, second in
                switch (first, second) {
                case (.active(let first), .active(let second)):
                    return .active(first + second)
                default:
                    return .failed
                }
            }

            XCTAssertEqual(
                Mirror(reflecting: combined.modifier).children.compactMap(\.label),
                ["content", "body"]
            )

            let combinedAttribute = graph.makeInput(value: combined)
            let inputs = makeGestureInputs(graph: graph)
            let outputs = type(of: combined)._makeGesture(
                gesture: _GraphValue(_attribute: combinedAttribute),
                inputs: inputs
            )

            XCTAssertEqual(outputs.phase.value, .active(10))
            let preference = try XCTUnwrap(
                outputs.preferences.reducedValue(
                    for: PairwiseGesturePreferenceKey.self,
                    in: graph
                )
            )
            XCTAssertEqual(preference.value, [1, 2])
            XCTAssertEqual(
                outputs.preferences.values(
                    for: PairwiseGesturePreferenceKey.self
                ).count,
                1
            )
        }
    }

    // ASSERTIONS gestureGateFailureControlFlowObserved
    func testGatedCopiesPrimaryPhaseUnlessEnablerFails() {
        let gated = PhaseTestGesture(
            phase: GesturePhase<Int>.possible(7)
        ).gated(by: PhaseTestGesture(
            phase: GesturePhase<String>.possible("waiting")
        ))
        let gate = gated.modifier.body
        let primary = GesturePhase<Int>.possible(7)

        XCTAssertEqual(gate(primary, .possible("waiting")), primary)
        XCTAssertEqual(gate(primary, .active("active")), primary)
        XCTAssertEqual(gate(primary, .ended("ended")), primary)
        XCTAssertEqual(gate(primary, GesturePhase<String>.failed), .failed)
    }

    // ASSERTIONS endedByWrapperFieldOwnershipObserved
    // ASSERTIONS endedByWrapperControlFlowObserved
    // ASSERTIONS longPressPlatformBehaviorSelectionObserved
    func testEndedByWrapperOwnsGestureConditionAndUsesExactPhaseTransitions() {
        let graph = _AGGraph()
        _AGGraph.withCurrent(graph) {
            let wrapper = EndedByWrapper(
                base: PhaseTestGesture(
                    phase: GesturePhase<Int>.ended(7)
                ),
                condition: PhaseTestGesture(
                    phase: GesturePhase<String>.possible("waiting")
                )
            )
            XCTAssertEqual(
                Mirror(reflecting: wrapper).children.compactMap(\.label),
                ["base", "condition"]
            )

            let wrapperAttribute = graph.makeInput(value: wrapper)
            let child = EndedByWrapper<
                PhaseTestGesture<Int>,
                PhaseTestGesture<String>
            >.Child(
                _wrapper: wrapperAttribute,
                hasChangedCallbacks: false
            )
            XCTAssertEqual(
                Mirror(reflecting: child).children.compactMap(\.label),
                ["_wrapper", "hasChangedCallbacks"]
            )

            let transition = child.value.modifier.body
            XCTAssertEqual(
                transition(.active(1), .active("condition")),
                .active(1)
            )
            XCTAssertEqual(
                transition(.ended(2), .ended("condition")),
                .ended(2)
            )
            XCTAssertEqual(
                transition(.active(3), .failed),
                .failed
            )
            XCTAssertEqual(
                transition(.active(4), .possible("waiting")),
                .possible(4)
            )
            XCTAssertEqual(
                transition(.ended(5), .possible("waiting")),
                .possible(5)
            )

            let immediate = EndedByWrapper<
                PhaseTestGesture<Int>,
                PhaseTestGesture<String>
            >.Child(
                _wrapper: wrapperAttribute,
                hasChangedCallbacks: true
            ).value.modifier.body
            XCTAssertEqual(
                immediate(.ended(6), .possible("waiting")),
                .active(6)
            )
            XCTAssertEqual(
                immediate(.active(6), .possible("waiting")),
                .failed
            )
            XCTAssertEqual(
                immediate(.possible(6), .possible("waiting")),
                .failed
            )
        }
    }

    // ASSERTIONS singleLongPressGestureFieldOwnershipObserved
    // ASSERTIONS singleLongPressGestureControlFlowObserved
    func testSingleLongPressBuildsDurationDistanceFilterAndDependencyChain() {
        let base = EventListener<TappableEvent>().longPressPhase()
        let gesture = SingleLongPressGesture(
            base: base,
            minimumDuration: 0.6,
            maximumDistance: 12
        )
        XCTAssertEqual(
            Mirror(reflecting: gesture).children.compactMap(\.label),
            ["base", "minimumDuration", "maximumDistance"]
        )

        let body = gesture.body
        XCTAssertEqual(body.modifier.dependency, .pausedUntilFailed)

        let filter = body.content.modifier
        let primary = MouseEvent(
            timestamp: .zero,
            binding: nil,
            button: .primary,
            phase: .active,
            location: .zero,
            globalLocation: .zero,
            modifiers: []
        )
        let secondary = MouseEvent(
            timestamp: .zero,
            binding: nil,
            button: .secondary,
            phase: .active,
            location: .zero,
            globalLocation: .zero,
            modifiers: []
        )
        XCTAssertTrue(filter.predicate(primary))
        XCTAssertFalse(filter.predicate(secondary))

        let gated = body.content.content
        let enabler = gated.modifier.content
        XCTAssertEqual(
            Mirror(reflecting: enabler).children.compactMap(\.label),
            ["base", "condition"]
        )
        XCTAssertEqual(enabler.base.modifier.minimumDuration, 0.6)
        XCTAssertEqual(enabler.base.modifier.maximumDuration, .infinity)
        XCTAssertFalse(enabler.base.modifier.trackFromEventStart)
        XCTAssertFalse(enabler.base.content.ignoresOtherEvents)

        XCTAssertEqual(enabler.condition.modifier.coordinateSpace, .local)
        XCTAssertEqual(enabler.condition.content.minimumDistance, 0)
        XCTAssertEqual(enabler.condition.content.maximumDistance, 12)
    }

    // ASSERTIONS gestureDiscretePhaseControlFlowObserved
    func testDiscreteDemotesOnlyActivePhasesWhenEnabled() {
        let transform = PhaseTestGesture(
            phase: GesturePhase<Int>.active(1)
        ).discrete(true).modifier.body

        XCTAssertEqual(transform(.possible(2)), .possible(2))
        XCTAssertEqual(transform(.active(3)), .possible(3))
        XCTAssertEqual(transform(.ended(4)), .ended(4))
        XCTAssertEqual(transform(.failed), .failed)

        let disabled = PhaseTestGesture(
            phase: GesturePhase<Int>.active(1)
        ).discrete(false).modifier.body
        XCTAssertEqual(disabled(.active(5)), .active(5))
    }

    // ASSERTIONS singleTapGestureRecognitionChainObserved
    // ASSERTIONS tapMovementPlatformThresholdObserved
    func testSingleTapIsFieldlessAndBuildsTheCommonRecognitionChain() {
        let gesture = SingleTapGesture<TappableEvent>()
        XCTAssertTrue(Mirror(reflecting: gesture).children.isEmpty)

        let body: SingleTapGesture<TappableEvent>.Body = gesture.body
        XCTAssertEqual(body.content.modifier.content.modifier.coordinateSpace, .local)
        XCTAssertEqual(
            body.content.modifier.content.content.minimumDistance,
            0
        )
#if os(iOS)
        XCTAssertEqual(body.content.modifier.content.content.maximumDistance, 45)
#else
        XCTAssertEqual(body.content.modifier.content.content.maximumDistance, 5)
#endif

        let duration = body.content.content.modifier.content.modifier
        XCTAssertEqual(duration.minimumDuration, 0)
        XCTAssertEqual(duration.maximumDuration, 0.75)
        XCTAssertFalse(duration.trackFromEventStart)

        let listener = body.content.content.content
        XCTAssertEqual(listener.modifier.dependency, .failIfActive)
        XCTAssertFalse(listener.content.content.ignoresOtherEvents)

        let primary = MouseEvent(
            timestamp: .zero,
            binding: nil,
            button: .primary,
            phase: .active,
            location: .zero,
            globalLocation: .zero,
            modifiers: []
        )
        let secondary = MouseEvent(
            timestamp: .zero,
            binding: nil,
            button: .secondary,
            phase: .active,
            location: .zero,
            globalLocation: .zero,
            modifiers: []
        )
        XCTAssertTrue(body.modifier.predicate(primary))
        XCTAssertFalse(body.modifier.predicate(secondary))
    }

    // ASSERTIONS tapGestureLegacyControlFlowObserved
    // ASSERTIONS tapGestureLegacyFieldOwnershipObserved
    func testTapChildOwnsRepeatCategoryAndOptionalCountWriter() {
        let graph = _AGGraph()
        _AGGraph.withCurrent(graph) {
            let tap = graph.makeInput(value: TapGesture(count: 2))
            let child = TapGesture.Child(_gesture: tap)
            XCTAssertEqual(
                Mirror(reflecting: child).children.compactMap(\.label),
                ["_gesture"]
            )

            let value = child.value
            XCTAssertEqual(value.modifier.count, 2)
            XCTAssertEqual(value.content.modifier.category, .select)
            XCTAssertTrue(value.content.modifier.includeChildren)
            XCTAssertEqual(value.content.content.modifier.count, 2)
            XCTAssertEqual(value.content.content.modifier.maximumDelay, 0.35)
            XCTAssertTrue(
                Mirror(reflecting: value.content.content.content)
                    .children.isEmpty
            )

            let source = graph.makeInput(
                value: GesturePhase<TappableEvent>.active(
                    makeTappableEvent(phase: .active, time: 1)
                )
            )
            let phase = TapGesture.Phase(_phase: source)
            guard case .active = phase.value else {
                return XCTFail("Tap phase did not preserve the active case")
            }
        }
    }

    // ASSERTIONS tapGestureLegacyFieldOwnershipObserved
    func testRequiredTapCountWriterUsesAnOptionalPreferenceTransform() throws {
        let graph = _AGGraph()
        try _AGGraph.withCurrent(graph) {
            var inputs = makeGestureInputs(graph: graph)
            inputs.preferences.add(RequiredTapCountKey.self)
            let writer = RequiredTapCountWriter<TappableEvent>(count: 3)
            XCTAssertEqual(
                Mirror(reflecting: writer).children.compactMap(\.label),
                ["count"]
            )
            XCTAssertEqual(writer.count, 3)

            let modifier = graph.makeInput(value: writer)
            let childPhase = graph.makeInput(
                value: GesturePhase<TappableEvent>.possible(nil)
            )
            let outputs = RequiredTapCountWriter<TappableEvent>._makeGesture(
                modifier: _GraphValue(_attribute: modifier),
                inputs: inputs
            ) { _ in
                _GestureOutputs(phase: childPhase)
            }
            let count = try XCTUnwrap(outputs.preferences.reducedValue(
                for: RequiredTapCountKey.self,
                in: graph
            ))
            XCTAssertEqual(count.value, 3)
        }
    }

    // ASSERTIONS requiredTapCountReductionControlFlowObserved
    func testRequiredTapCountReductionUsesCurrentCompatibilitySelection() {
        var empty: Int?
        RequiredTapCountKey.reduce(value: &empty) { 3 }
        XCTAssertEqual(empty, 3)
        RequiredTapCountKey.reduce(value: &empty) { nil }
        XCTAssertEqual(empty, 3)

#if os(iOS)
        let previousOverride = GestureContainerFeature.isEnabledOverride
        defer {
            GestureContainerFeature.isEnabledOverride = previousOverride
        }

        GestureContainerFeature.isEnabledOverride = true
        var minimum: Int? = 3
        RequiredTapCountKey.reduce(value: &minimum) { 1 }
        XCTAssertEqual(minimum, 1)

        GestureContainerFeature.isEnabledOverride = false
        var maximum: Int? = 3
        RequiredTapCountKey.reduce(value: &maximum) { 1 }
        XCTAssertEqual(maximum, 3)
#else
        var reduced: Int? = 3
        RequiredTapCountKey.reduce(value: &reduced) { 1 }
        XCTAssertEqual(
            reduced,
            isLinkedOnOrAfter(.v6) ? 1 : 3
        )
#endif
    }

    // ASSERTIONS categoryGesturePreferenceOwnershipObserved
    func testCategoryGestureReplacesOrUnionsChildPreference() throws {
        let graph = _AGGraph()
        try _AGGraph.withCurrent(graph) {
            var inputs = makeGestureInputs(graph: graph)
            inputs.preferences.add(GestureCategory.Key.self)

            func category(includeChildren: Bool) throws -> GestureCategory {
                let modifier = graph.makeInput(value: CategoryGesture<Int>(
                    category: .select,
                    includeChildren: includeChildren
                ))
                let childPhase = graph.makeInput(
                    value: GesturePhase<Int>.possible(nil)
                )
                let childCategory = graph.makeInput(
                    value: GestureCategory.drag
                )
                let outputs = CategoryGesture<Int>._makeGesture(
                    modifier: _GraphValue(_attribute: modifier),
                    inputs: inputs
                ) { _ in
                    var outputs = _GestureOutputs(phase: childPhase)
                    outputs.preferences.setValue(
                        childCategory.identifier,
                        for: GestureCategory.Key.self
                    )
                    return outputs
                }
                return try XCTUnwrap(outputs.preferences.reducedValue(
                    for: GestureCategory.Key.self,
                    in: graph
                )).value
            }

            XCTAssertEqual(try category(includeChildren: false), .select)
            XCTAssertEqual(
                try category(includeChildren: true),
                GestureCategory.select.union(.drag)
            )
        }
    }

    // ASSERTIONS windowDragGesturePreferenceObserved
    func testWindowDragGesturePreferenceDefaultsFalseAndReducesWithOr() {
        XCTAssertFalse(WindowDragGestureIsActiveKey.defaultValue)

        var inactive = false
        WindowDragGestureIsActiveKey.reduce(value: &inactive) { false }
        XCTAssertFalse(inactive)
        WindowDragGestureIsActiveKey.reduce(value: &inactive) { true }
        XCTAssertTrue(inactive)

        var active = true
        WindowDragGestureIsActiveKey.reduce(value: &active) { false }
        XCTAssertTrue(active)
    }

    // ASSERTIONS durationGestureFieldOwnershipObserved
    func testDurationGestureAndPhaseStoreCompleteTimingState() {
        let graph = _AGGraph()
        _AGGraph.withCurrent(graph) {
            let modifier = DurationGesture<Int>(
                minimumDuration: 1,
                maximumDuration: 3,
                trackFromEventStart: true
            )
            XCTAssertEqual(
                Mirror(reflecting: modifier).children.compactMap(\.label),
                [
                    "minimumDuration",
                    "maximumDuration",
                    "trackFromEventStart",
                ]
            )

            let phase = DurationPhase<Int>(
                _modifier: graph.makeInput(value: modifier),
                _childPhase: graph.makeInput(value: .possible(nil)),
                _time: graph.makeInput(value: .zero),
                _resetSeed: graph.makeInput(value: 0),
                useGestureGraph: false,
                start: nil,
                lastResetSeed: 0
            )
            XCTAssertEqual(
                Mirror(reflecting: phase).children.compactMap(\.label),
                [
                    "_modifier",
                    "_childPhase",
                    "_time",
                    "_resetSeed",
                    "useGestureGraph",
                    "start",
                    "lastResetSeed",
                ]
            )
        }
    }

    // ASSERTIONS durationGestureControlFlowObserved
    func testDurationPhaseUsesExclusiveMaximumAndSchedulesNextBoundary() {
        let rendererHost = TestViewRendererHost()
        let viewGraph = ViewGraph(
            rootViewType: EmptyView.self,
            content: EmptyView(),
            rendererHost: rendererHost
        )
        rendererHost.storage = viewGraph

        viewGraph.data.withCurrent {
            let graph = viewGraph.data.graph
            let modifier = graph.makeInput(value: DurationGesture<Int>(
                minimumDuration: 1,
                maximumDuration: 3
            ))
            let childPhase = graph.makeInput(
                value: GesturePhase<Int>.possible(9)
            )
            let inputs = makeGestureInputs(graph: graph)
            inputs._time.setValue(Time(seconds: 10))
            let outputs = DurationGesture<Int>._makeGesture(
                modifier: _GraphValue(_attribute: modifier),
                inputs: inputs
            ) { _ in
                _GestureOutputs(phase: childPhase)
            }

            XCTAssertEqual(outputs.phase.value, .possible(0))
            XCTAssertEqual(viewGraph.nextUpdate.gestures.time, .infinity)

            childPhase.setValue(.active(9))
            XCTAssertEqual(outputs.phase.value, .possible(0))
            XCTAssertEqual(
                viewGraph.nextUpdate.gestures.time,
                Time(seconds: 11)
            )

            viewGraph.nextUpdate.gestures = ViewGraph.NextUpdate()
            inputs._time.setValue(Time(seconds: 11))
            XCTAssertEqual(outputs.phase.value, .active(1))
            XCTAssertEqual(
                viewGraph.nextUpdate.gestures.time,
                Time(seconds: 13)
            )

            viewGraph.nextUpdate.gestures = ViewGraph.NextUpdate()
            inputs._time.setValue(Time(seconds: 13))
            XCTAssertEqual(outputs.phase.value, .failed)
            XCTAssertEqual(viewGraph.nextUpdate.gestures.time, .infinity)

            inputs._resetSeed.setValue(1)
            inputs._time.setValue(Time(seconds: 20))
            childPhase.setValue(.active(9))
            XCTAssertEqual(outputs.phase.value, .possible(0))
            inputs._time.setValue(Time(seconds: 21))
            childPhase.setValue(.ended(9))
            XCTAssertEqual(outputs.phase.value, .ended(1))
        }
    }

    // ASSERTIONS durationGestureControlFlowObserved
    func testDurationPhaseCanStartWhileChildIsPossible() {
        let rendererHost = TestViewRendererHost()
        let viewGraph = ViewGraph(
            rootViewType: EmptyView.self,
            content: EmptyView(),
            rendererHost: rendererHost
        )
        rendererHost.storage = viewGraph

        viewGraph.data.withCurrent {
            let graph = viewGraph.data.graph
            let modifier = graph.makeInput(value: DurationGesture<Int>(
                minimumDuration: 1,
                maximumDuration: 3,
                trackFromEventStart: true
            ))
            let childPhase = graph.makeInput(
                value: GesturePhase<Int>.possible(nil)
            )
            let inputs = makeGestureInputs(graph: graph)
            inputs._time.setValue(Time(seconds: 30))
            let outputs = DurationGesture<Int>._makeGesture(
                modifier: _GraphValue(_attribute: modifier),
                inputs: inputs
            ) { _ in
                _GestureOutputs(phase: childPhase)
            }

            XCTAssertEqual(outputs.phase.value, .possible(0))
            XCTAssertEqual(
                viewGraph.nextUpdate.gestures.time,
                Time(seconds: 31)
            )
        }
    }

    // ASSERTIONS distanceGestureFieldOwnershipObserved
    // ASSERTIONS distanceGestureControlFlowObserved
    func testDistanceGestureTracksMaximumEuclideanDistanceAndBounds() {
        let distance = DistanceGesture(
            minimumDistance: 2,
            maximumDistance: 5
        )
        XCTAssertEqual(
            Mirror(reflecting: distance).children.compactMap(\.label),
            ["minimumDistance", "maximumDistance"]
        )

        let transform = distance.body.modifier.body
        var state = DistanceGesture.StateType()
        XCTAssertEqual(
            Mirror(reflecting: state).children.compactMap(\.label),
            ["start", "maxDistance"]
        )

        XCTAssertEqual(
            transform(&state, .possible(spatialEvent(at: .zero))),
            .possible(0)
        )
        XCTAssertEqual(
            transform(
                &state,
                .active(spatialEvent(at: CGPoint(x: 1, y: 0)))
            ),
            .possible(1)
        )
        XCTAssertEqual(
            transform(
                &state,
                .active(spatialEvent(at: CGPoint(x: 3, y: 4)))
            ),
            .active(5)
        )
        XCTAssertEqual(
            transform(&state, .active(spatialEvent(at: .zero))),
            .active(5)
        )

        var endedState = DistanceGesture.StateType()
        _ = transform(
            &endedState,
            .possible(spatialEvent(at: .zero))
        )
        XCTAssertEqual(
            transform(
                &endedState,
                .ended(spatialEvent(at: CGPoint(x: 3, y: 4)))
            ),
            .failed
        )

        var successfulState = DistanceGesture.StateType()
        _ = transform(
            &successfulState,
            .possible(spatialEvent(at: .zero))
        )
        XCTAssertEqual(
            transform(
                &successfulState,
                .ended(spatialEvent(at: CGPoint(x: 0, y: 4)))
            ),
            .ended(4)
        )
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

    func testEventFilterProjectsFilteredEventsAndFailsOnRemoval() throws {
        let graph = _AGGraph()
        try _AGGraph.withCurrent(graph) {
            let primaryID = EventID(type: VUI.MouseEvent.self, serial: 1)
            let secondaryID = EventID(type: VUI.MouseEvent.self, serial: 2)
            let unrelatedID = EventID(type: Event.self, serial: 3)
            let primary = VUI.MouseEvent(
                timestamp: .zero,
                binding: nil,
                button: .primary,
                phase: .began,
                location: .zero,
                globalLocation: .zero,
                modifiers: []
            )
            let secondary = VUI.MouseEvent(
                timestamp: .zero,
                binding: nil,
                button: .secondary,
                phase: .began,
                location: .zero,
                globalLocation: .zero,
                modifiers: []
            )
            let unrelated = Event(primary)
            let events = graph.makeInput(value: [
                primaryID: primary,
                secondaryID: secondary,
                unrelatedID: unrelated,
            ] as [EventID: any EventType])
            var inputs = makeGestureInputs(graph: graph)
            inputs._events = events
            let modifier = graph.makeInput(value: EventFilter<Int> { event in
                guard let event = event as? VUI.MouseEvent else { return true }
                return event.button == .primary
            })
            let childPhase = graph.makeInput(value: GesturePhase<Int>.active(7))
            var projectedEvents: Attribute<[EventID: any EventType]>?

            let outputs = EventFilter<Int>._makeGesture(
                modifier: _GraphValue(_attribute: modifier),
                inputs: inputs
            ) { childInputs in
                projectedEvents = childInputs.events
                return _GestureOutputs(phase: childPhase)
            }

            let filtered = try XCTUnwrap(projectedEvents).value
            XCTAssertNotNil(filtered[primaryID] as? VUI.MouseEvent)
            XCTAssertNil(filtered[secondaryID])
            XCTAssertNotNil(filtered[unrelatedID] as? Event)
            XCTAssertEqual(outputs.phase.value, .failed)

            events.setValue([
                primaryID: primary,
                unrelatedID: unrelated,
            ] as [EventID: any EventType])
            XCTAssertEqual(outputs.phase.value, .active(7))
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

    // ASSERTIONS viewResponderDescendantTraversalObserved
    func testResponderArbitrationMatchesPriorityDependencyAndTapCountRules() {
        let defaultParent = ArbitrationTestResponder(exclusionPolicy: .default)
        let defaultChild = ArbitrationTestResponder(exclusionPolicy: .default)
        defaultChild.parent = defaultParent

        XCTAssertFalse(defaultParent.isDescendant(of: defaultParent))
        XCTAssertTrue(defaultChild.isDescendant(of: defaultParent))
        XCTAssertFalse(defaultParent.isDescendant(of: defaultChild))

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
            let responder = ArbitrationTestResponder(exclusionPolicy: .default)
            let graph = UpdateScopeGestureGraph(rootResponder: responder)
            responder.installGestureGraph(graph)
            return (responder, graph)
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

    func testResponderGestureEventsAdvanceHostSeedsWithoutChangingResetSeed() {
        let responder = ArbitrationTestResponder(exclusionPolicy: .default)
        let gestureGraph = responder.gestureGraph

        gestureGraph.data.updateSeed = 30
        gestureGraph.data.transactionSeed = 40
        gestureGraph.data.withCurrent {
            gestureGraph._gestureResetSeed.setValue(9)
        }

        _ = gestureGraph.sendEvents(
            [:],
            rootNode: responder,
            at: Time(seconds: 5)
        )

        XCTAssertEqual(gestureGraph.data.transactionSeed, 41)
        XCTAssertEqual(gestureGraph.data.updateSeed, 31)
        gestureGraph.data.withCurrent {
            XCTAssertEqual(gestureGraph._gestureResetSeed.value, 9)
        }

        _ = gestureGraph.sendEvents(
            [:],
            rootNode: responder,
            at: Time(seconds: 5)
        )

        XCTAssertEqual(gestureGraph.data.transactionSeed, 42)
        XCTAssertEqual(gestureGraph.data.updateSeed, 31)
        gestureGraph.data.withCurrent {
            XCTAssertEqual(gestureGraph._gestureResetSeed.value, 9)
        }
    }

    // ASSERTIONS repeatGesturePhaseFieldOwnershipObserved
    // ASSERTIONS repeatGesturePhaseControlFlowObserved
    func testRepeatGestureRearmsChildAndPreservesPossiblePayloads() throws {
        let rendererHost = TestViewRendererHost()
        let viewGraph = ViewGraph(
            rootViewType: EmptyView.self,
            content: EmptyView(),
            rendererHost: rendererHost
        )
        rendererHost.storage = viewGraph

        try viewGraph.data.withCurrent {
            let graph = viewGraph.data.graph
            let modifier = graph.makeInput(value: RepeatGesture<TappableEvent>(
                count: 2,
                maximumDelay: 0.5
            ))
            let first = makeTappableEvent(phase: .began, time: 1)
            let second = makeTappableEvent(phase: .active, time: 1.1)
            let third = makeTappableEvent(phase: .ended, time: 1.2)
            let childPhase = graph.makeInput(
                value: GesturePhase<TappableEvent>.possible(first)
            )
            let inputs = makeGestureInputs(graph: graph)
            inputs._time.setValue(Time(seconds: 1))
            var childResetSeed: Attribute<UInt32>?

            let outputs = RepeatGesture<TappableEvent>._makeGesture(
                modifier: _GraphValue(_attribute: modifier),
                inputs: inputs
            ) { childInputs in
                childResetSeed = childInputs.resetSeed
                return _GestureOutputs(phase: childPhase)
            }
            let resetSeed = try XCTUnwrap(childResetSeed)

            XCTAssertEqual(outputs.phase.value, .possible(first))
            XCTAssertEqual(resetSeed.value, 0)

            childPhase.setValue(.active(second))
            XCTAssertEqual(outputs.phase.value, .possible(second))

            childPhase.setValue(.ended(third))
            XCTAssertEqual(outputs.phase.value, .possible(third))
            XCTAssertEqual(
                viewGraph.nextUpdate.gestures.time,
                Time(seconds: 1.5)
            )
            XCTAssertTrue(viewGraph.hasPendingTransactions)

            viewGraph.flushTransactions()
            XCTAssertEqual(resetSeed.value, 1)

            childPhase.setValue(.active(second))
            XCTAssertEqual(outputs.phase.value, .active(second))
            childPhase.setValue(.ended(third))
            XCTAssertEqual(outputs.phase.value, .ended(third))
        }
    }

    // ASSERTIONS repeatGesturePhaseControlFlowObserved
    func testRepeatGestureDeadlineAllowsEqualityAndFailsAfterward() {
        let rendererHost = TestViewRendererHost()
        let viewGraph = ViewGraph(
            rootViewType: EmptyView.self,
            content: EmptyView(),
            rendererHost: rendererHost
        )
        rendererHost.storage = viewGraph

        viewGraph.data.withCurrent {
            let graph = viewGraph.data.graph
            let modifier = graph.makeInput(value: RepeatGesture<TappableEvent>(
                count: 2,
                maximumDelay: 0.5
            ))
            let ended = makeTappableEvent(phase: .ended, time: 2)
            let possible = makeTappableEvent(phase: .began, time: 2.5)
            let childPhase = graph.makeInput(
                value: GesturePhase<TappableEvent>.ended(ended)
            )
            let time = graph.makeInput(value: Time(seconds: 2))
            let resetSeed = graph.makeInput(value: UInt32(0))
            let resetDelta = graph.makeInput(value: UInt32(0))
            let output = graph.makeStatefulRule(RepeatPhase<TappableEvent>(
                _modifier: modifier,
                _phase: childPhase,
                _time: time,
                _resetSeed: resetSeed,
                _resetDelta: resetDelta,
                useGestureGraph: false,
                deadline: nil,
                index: 0,
                lastResetSeed: 0
            ))

            XCTAssertEqual(output.value, .possible(ended))
            childPhase.setValue(.possible(possible))
            time.setValue(Time(seconds: 2.5))
            XCTAssertEqual(output.value, .possible(possible))

            time.setValue(Time(seconds: 2.500_001))
            XCTAssertEqual(output.value, .failed)
        }
    }

    // ASSERTIONS repeatGestureMutationFieldOwnershipObserved
    // ASSERTIONS repeatGestureMutationControlFlowObserved
    func testRepeatMutationCombinesLatestIndexForOneResetDelta() {
        let graph = _AGGraph()
        _AGGraph.withCurrent(graph) {
            let resetDelta = graph.makeInput(value: UInt32(0))
            let otherDelta = graph.makeInput(value: UInt32(0))
            var mutation = RepeatMutation(
                _resetDelta: resetDelta,
                index: 1
            )

            XCTAssertTrue(mutation.combine(with: RepeatMutation(
                _resetDelta: resetDelta,
                index: 3
            )))
            XCTAssertFalse(mutation.combine(with: RepeatMutation(
                _resetDelta: otherDelta,
                index: 4
            )))
            mutation.apply()
            XCTAssertEqual(resetDelta.value, 3)
            XCTAssertEqual(otherDelta.value, 0)
        }
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
            XCTAssertEqual(convertedNamed.location, CGPoint(x: 20, y: 34))
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
            XCTAssertEqual(namedPoints, [CGPoint(x: 20, y: 34)])

            var localPoints = [CGPoint(x: 115, y: 227)]
            inputs.transform.value.convertGlobal(to: .local, points: &localPoints)
            XCTAssertEqual(localPoints, [CGPoint(x: 20, y: 34)])

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

    private func makeTappableEvent(
        phase: EventPhase,
        time: Double
    ) -> TappableEvent {
        let source: any EventType = VUI.MouseEvent(
            timestamp: Time(seconds: time),
            binding: nil,
            button: .primary,
            phase: phase,
            location: .zero,
            globalLocation: .zero,
            modifiers: []
        )
        return TappableEvent(source)!
    }

    private func spatialEvent(at location: CGPoint) -> SpatialEvent {
        let event: any SpatialEventType = MouseEvent(
            timestamp: .zero,
            binding: nil,
            button: .primary,
            phase: .active,
            location: location,
            globalLocation: location,
            modifiers: []
        )
        return SpatialEvent(event)
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

private enum PairwiseGesturePreferenceKey: PreferenceKey {
    static var defaultValue: [Int] { [] }

    static func reduce(value: inout [Int], nextValue: () -> [Int]) {
        value.append(contentsOf: nextValue())
    }
}

private struct PhaseTestGesture<Value>: Gesture, PrimitiveGesture {
    let phase: GesturePhase<Value>

    static func _makeGesture(
        gesture: _GraphValue<Self>,
        inputs: _GestureInputs
    ) -> _GestureOutputs<Value> {
        guard let graph = _AGGraph.current else {
            fatalError("PhaseTestGesture._makeGesture requires AG context")
        }
        let phase = graph.makeRule {
            gesture._attribute.value.phase
        }
        var outputs = _GestureOutputs<Value>(phase: phase)
        let preference = graph.makeInput(value: [1])
        outputs.appendPreference(
            key: PairwiseGesturePreferenceKey.self,
            value: preference
        )
        return outputs
    }

    typealias Body = Never
}

private struct PreferencePhaseTestGesture: Gesture, PrimitiveGesture {
    let phase: GesturePhase<Int>
    let preference: [Int]

    static func _makeGesture(
        gesture: _GraphValue<Self>,
        inputs: _GestureInputs
    ) -> _GestureOutputs<Int> {
        guard let graph = _AGGraph.current else {
            fatalError(
                "PreferencePhaseTestGesture._makeGesture requires AG context"
            )
        }
        let phase = graph.makeRule {
            gesture._attribute.value.phase
        }
        let preference = graph.makeRule {
            gesture._attribute.value.preference
        }
        var outputs = _GestureOutputs<Int>(phase: phase)
        outputs.appendPreference(
            key: PairwiseGesturePreferenceKey.self,
            value: preference
        )
        return outputs
    }

    typealias Body = Never
}

private final class ArbitrationTestResponder: ViewResponder, AnyGestureResponder {
    var relatedAttribute: AGAttribute { .invalid }
    var inputs: _ViewInputs { fatalError("unused test responder input") }
    var childSubgraph: AGSubgraph?
    var childViewSubgraph: AGSubgraph?
    let exclusionPolicy: GestureResponderExclusionPolicy
    var label: String? { nil }
    var mask: GestureMask = .all
    private var gestureGraphStorage: GestureGraph?
    var gestureGraph: GestureGraph {
        if let gestureGraphStorage {
            return gestureGraphStorage
        }
        let graph = ArbitrationGestureGraph(rootResponder: self)
        configureGestureGraph(graph)
        gestureGraphStorage = graph
        return graph
    }
    var viewSubgraph: AGSubgraph { gestureGraph.rootSubgraph }
    var eventSources: [any EventBindingSource] { [] }
    var gestureType: Any.Type { Self.self }
    var isValid: Bool { true }

    init(
        exclusionPolicy: GestureResponderExclusionPolicy,
        dependency: GestureDependency = .none,
        requiredTapCount: Int? = nil,
        hitTestKey: UInt32 = 1
    ) {
        _ = hitTestKey
        self.exclusionPolicy = exclusionPolicy
        self.testDependency = dependency
        self.testRequiredTapCount = requiredTapCount
        super.init()
    }

    private let testDependency: GestureDependency
    private let testRequiredTapCount: Int?

    func installGestureGraph(_ graph: GestureGraph) {
        precondition(gestureGraphStorage == nil)
        configureGestureGraph(graph)
        gestureGraphStorage = graph
    }

    private func configureGestureGraph(_ gestureGraph: GestureGraph) {
        gestureGraph.data.withCurrent {
            let graph = gestureGraph.data.graph
            gestureGraph._gestureDependencyAttr = OptionalAttribute(
                graph.makeInput(value: testDependency)
            )
            if let testRequiredTapCount {
                gestureGraph._requiredTapCountAttr = OptionalAttribute(
                    graph.makeInput(value: Optional(testRequiredTapCount))
                )
            }
        }
    }

    func detachContainer() {}
}

private class ArbitrationGestureGraph: GestureGraph, @unchecked Sendable {
    override func instantiateOutputs() {}
}

private final class UpdateScopeGestureGraph:
    ArbitrationGestureGraph,
    @unchecked Sendable
{
    private(set) var observedUpdateActive = false

    override func instantiateOutputs() {
        observedUpdateActive = Update.isActive
    }
}
