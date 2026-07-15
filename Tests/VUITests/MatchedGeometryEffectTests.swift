import XCTest
@testable import VUI

private final class MatchedGeometryRootScopeCapture: @unchecked Sendable {
    var hasScope = false
}

private final class MatchedGeometryTransformCapture: @unchecked Sendable {
    var transform: Attribute<ViewTransform>?
    var size: Attribute<ViewSize>?
}

private struct MatchedGeometryRootScopeProbe: View, TestPrimitiveView {
    typealias Body = Never

    var capture: MatchedGeometryRootScopeCapture

    static func _makeView(
        view: _GraphValue<Self>,
        inputs: _ViewInputs
    ) -> _ViewOutputs {
        view._attribute.value.capture.hasScope =
            inputs.base.customInputs.value(forKey: MatchedGeometryScope.self) != nil
        return _ViewOutputs()
    }
}

final class MatchedGeometryEffectTests: XCTestCase {
    // ASSERTIONS matchedGeometryPublicSurfaceObserved
    func testPublicSurfaceUsesObservedStorageAndRawValues() {
        XCTAssertEqual(MatchedGeometryProperties.position.rawValue, 1)
        XCTAssertEqual(MatchedGeometryProperties.size.rawValue, 2)
        XCTAssertEqual(MatchedGeometryProperties.frame.rawValue, 3)
        XCTAssertEqual(MemoryLayout<MatchedGeometryProperties>.size, 4)

        let namespace = Namespace().wrappedValue
        let effect = _MatchedGeometryEffect(
            id: "hero",
            namespace: namespace,
            properties: .frame,
            anchor: .bottomTrailing,
            isSource: false
        )
        XCTAssertEqual(effect.id, "hero")
        XCTAssertEqual(effect.namespace, namespace)
        XCTAssertEqual(effect.args.properties, .frame)
        XCTAssertEqual(effect.args.anchor, .bottomTrailing)
        XCTAssertFalse(effect.args.isSource)

        let wrapped = EmptyView().matchedGeometryEffect(id: 7, in: namespace)
        XCTAssertTrue(String(reflecting: type(of: wrapped)).contains("ModifiedContent"))
        XCTAssertTrue(String(reflecting: type(of: wrapped)).contains("_MatchedGeometryEffect"))
    }

    // ASSERTIONS matchedGeometryGraphAndDisplayDisassemblyObserved
    func testViewGraphInstallsRootScopeBeforeBuildingContent() {
        let capture = MatchedGeometryRootScopeCapture()
        let rendererHost = TestViewRendererHost()
        let viewGraph = ViewGraph(
            rootViewType: MatchedGeometryRootScopeProbe.self,
            content: MatchedGeometryRootScopeProbe(capture: capture),
            rendererHost: rendererHost
        )
        rendererHost.storage = viewGraph

        XCTAssertTrue(capture.hasScope)
    }

    // ASSERTIONS matchedGeometryGraphAndDisplayDisassemblyObserved
    func testScopeSelectsActiveSourceAndReleasesItByOwner() throws {
        let graph = _AGGraph()
        try _AGGraph.withCurrent(graph) {
            var inputs = makeViewInputs(graph: graph)
            inputs.makeRootMatchedGeometryScope()
            let scope = try XCTUnwrap(
                inputs.base.customInputs.value(forKey: MatchedGeometryScope.self)
            )
            let namespace = Namespace().wrappedValue
            let key = AnyHashable(MatchedGeometryKeyForTest(id: "hero", namespace: namespace))

            let sourceOwner = graph.makeInput(value: true)
            let source = registration(
                graph: graph,
                owner: sourceOwner.identifier,
                isSource: true,
                position: CGPoint(x: 100, y: 50),
                size: CGSize(width: 80, height: 40)
            )
            var sourceIndex: Int?
            let shared = scope.frame(index: &sourceIndex, for: key, view: source)
            XCTAssertEqual(
                shared.value?.origin,
                CGPoint(x: 100, y: 50)
            )
            XCTAssertEqual(
                shared.value?.size.value,
                CGSize(width: 80, height: 40)
            )

            let followerOwner = graph.makeInput(value: true)
            let follower = registration(
                graph: graph,
                owner: followerOwner.identifier,
                isSource: false,
                position: CGPoint(x: 10, y: 20),
                size: CGSize(width: 20, height: 10)
            )
            var followerIndex: Int?
            _ = scope.frame(index: &followerIndex, for: key, view: follower)
            XCTAssertEqual(shared.value?.origin, CGPoint(x: 100, y: 50))

            scope.releaseFrame(index: try XCTUnwrap(sourceIndex), owner: sourceOwner.identifier)
            XCTAssertNil(shared.value)
        }
    }

    // ASSERTIONS matchedGeometryGraphAndDisplayDisassemblyObserved
    func testScopeSelectsFirstInsertedSourceAndSkipsRemovedSources() throws {
        let graph = _AGGraph()
        try _AGGraph.withCurrent(graph) {
            var inputs = makeViewInputs(graph: graph)
            inputs.makeRootMatchedGeometryScope()
            let scope = try XCTUnwrap(
                inputs.base.customInputs.value(forKey: MatchedGeometryScope.self)
            )
            let namespace = Namespace().wrappedValue
            let key = AnyHashable(MatchedGeometryKeyForTest(id: "hero", namespace: namespace))
            let firstPhase = graph.makeInput(value: Phase())
            let secondPhase = graph.makeInput(value: Phase())

            var firstIndex: Int?
            _ = scope.frame(
                index: &firstIndex,
                for: key,
                view: registration(
                    graph: graph,
                    owner: graph.makeInput(value: 1).identifier,
                    isSource: true,
                    position: CGPoint(x: 100, y: 50),
                    size: CGSize(width: 80, height: 40),
                    phase: firstPhase
                )
            )
            var secondIndex: Int?
            _ = scope.frame(
                index: &secondIndex,
                for: key,
                view: registration(
                    graph: graph,
                    owner: graph.makeInput(value: 2).identifier,
                    isSource: true,
                    position: CGPoint(x: 200, y: 150),
                    size: CGSize(width: 100, height: 60),
                    phase: secondPhase
                )
            )
            let frameIndex = try XCTUnwrap(firstIndex)
            XCTAssertEqual(scope.sourceInfo(frameIndex: frameIndex)?.frame.origin,
                           CGPoint(x: 100, y: 50))

            var removed = Phase()
            removed.isBeingRemoved = true
            firstPhase.setValue(removed)
            XCTAssertEqual(scope.sourceInfo(frameIndex: frameIndex)?.frame.origin,
                           CGPoint(x: 200, y: 150))

            secondPhase.setValue(removed)
            XCTAssertNil(scope.sourceInfo(frameIndex: frameIndex))
        }
    }

    // ASSERTIONS matchedGeometryGraphAndDisplayDisassemblyObserved
    func testFrameMatchProjectsFollowerTransformIntoSourceFrame() throws {
        let graph = _AGGraph()
        try _AGGraph.withCurrent(graph) {
            var baseInputs = makeViewInputs(graph: graph)
            baseInputs.makeRootMatchedGeometryScope()
            let namespace = Namespace().wrappedValue

            let sourceCapture = MatchedGeometryTransformCapture()
            let sourceModifier = graph.makeInput(value: _MatchedGeometryEffect(
                id: "hero",
                namespace: namespace,
                properties: .frame,
                anchor: UnitPoint.center,
                isSource: true
            ))
            let sourceInputs = matchedInputs(
                from: baseInputs,
                graph: graph,
                position: CGPoint(x: 100, y: 50),
                size: CGSize(width: 80, height: 40)
            )
            _ = _MatchedGeometryEffect<String>._makeView(
                modifier: _GraphValue(_attribute: sourceModifier),
                inputs: sourceInputs
            ) { _, childInputs in
                sourceCapture.transform = childInputs.transform
                sourceCapture.size = childInputs.size
                return _ViewOutputs(
                    layoutComputer: OptionalAttribute(
                        graph.makeInput(value: LayoutComputer.fixed(
                            CGSize(width: 80, height: 40)
                        ))
                    )
                )
            }
            _ = try XCTUnwrap(sourceCapture.transform).value

            let followerCapture = MatchedGeometryTransformCapture()
            let followerModifier = graph.makeInput(value: _MatchedGeometryEffect(
                id: "hero",
                namespace: namespace,
                properties: .frame,
                anchor: UnitPoint.center,
                isSource: false
            ))
            let followerInputs = matchedInputs(
                from: baseInputs,
                graph: graph,
                position: CGPoint(x: 10, y: 20),
                size: CGSize(width: 20, height: 10)
            )
            _ = _MatchedGeometryEffect<String>._makeView(
                modifier: _GraphValue(_attribute: followerModifier),
                inputs: followerInputs
            ) { _, childInputs in
                followerCapture.transform = childInputs.transform
                followerCapture.size = childInputs.size
                return _ViewOutputs(
                    layoutComputer: OptionalAttribute(
                        graph.makeInput(value: LayoutComputer.fixed(
                            CGSize(width: 20, height: 10)
                        ))
                    )
                )
            }

            var points = [
                CGPoint(x: 0, y: 0),
                CGPoint(x: 20, y: 10),
                CGPoint(x: 10, y: 5),
            ]
            try XCTUnwrap(followerCapture.transform).value.convertGlobal(
                from: .local,
                points: &points
            )
            XCTAssertEqual(points[0], CGPoint(x: 130, y: 65))
            XCTAssertEqual(points[1], CGPoint(x: 150, y: 75))
            XCTAssertEqual(points[2], CGPoint(x: 140, y: 70))
            XCTAssertEqual(
                try XCTUnwrap(followerCapture.size).value.value,
                CGSize(width: 20, height: 10)
            )
        }
    }

    // ASSERTIONS matchedGeometryPropertyAnchorRuntimeObserved
    func testPropertiesAndAnchorControlMatchedLayoutFrameIndependently() throws {
        let graph = _AGGraph()
        try _AGGraph.withCurrent(graph) {
            var baseInputs = makeViewInputs(graph: graph)
            baseInputs.makeRootMatchedGeometryScope()
            let namespace = Namespace().wrappedValue

            func capture(
                id: String,
                properties: MatchedGeometryProperties,
                anchor: UnitPoint,
                isSource: Bool,
                position: CGPoint,
                size: CGSize,
                layoutComputer: LayoutComputer
            ) -> MatchedGeometryTransformCapture {
                let capture = MatchedGeometryTransformCapture()
                let modifier = graph.makeInput(value: _MatchedGeometryEffect(
                    id: id,
                    namespace: namespace,
                    properties: properties,
                    anchor: anchor,
                    isSource: isSource
                ))
                let inputs = matchedInputs(
                    from: baseInputs,
                    graph: graph,
                    position: position,
                    size: size
                )
                _ = _MatchedGeometryEffect<String>._makeView(
                    modifier: _GraphValue(_attribute: modifier),
                    inputs: inputs
                ) { _, childInputs in
                    capture.transform = childInputs.transform
                    capture.size = childInputs.size
                    return _ViewOutputs(
                        layoutComputer: OptionalAttribute(
                            graph.makeInput(value: layoutComputer)
                        )
                    )
                }
                return capture
            }

            func origin(of capture: MatchedGeometryTransformCapture) throws -> CGPoint {
                var points = [CGPoint.zero]
                try XCTUnwrap(capture.transform).value.convertGlobal(
                    from: .local,
                    points: &points
                )
                return points[0]
            }

            let sourceSize = CGSize(width: 80, height: 40)
            let followerSize = CGSize(width: 20, height: 10)
            let fixedSource = LayoutComputer.fixed(sourceSize)
            let fixedFollower = LayoutComputer.fixed(followerSize)

            for (id, properties, anchor, expectedOrigin) in [
                ("position", MatchedGeometryProperties.position, UnitPoint.center, CGPoint(x: 130, y: 65)),
                ("top", MatchedGeometryProperties.frame, UnitPoint.topLeading, CGPoint(x: 100, y: 50)),
                ("bottom", MatchedGeometryProperties.frame, UnitPoint.bottomTrailing, CGPoint(x: 160, y: 80)),
            ] {
                let source = capture(
                    id: id,
                    properties: properties,
                    anchor: anchor,
                    isSource: true,
                    position: CGPoint(x: 100, y: 50),
                    size: sourceSize,
                    layoutComputer: fixedSource
                )
                _ = try XCTUnwrap(source.transform).value
                let follower = capture(
                    id: id,
                    properties: properties,
                    anchor: anchor,
                    isSource: false,
                    position: CGPoint(x: 10, y: 20),
                    size: followerSize,
                    layoutComputer: fixedFollower
                )
                XCTAssertEqual(try origin(of: follower), expectedOrigin)
                XCTAssertEqual(
                    try XCTUnwrap(follower.size).value.value,
                    followerSize
                )
            }

            let flexible = LayoutComputer(sizeThatFits: { proposal in
                CGSize(
                    width: proposal.width ?? 0,
                    height: proposal.height ?? 0
                )
            })
            let sizeSource = capture(
                id: "size",
                properties: .size,
                anchor: .center,
                isSource: true,
                position: CGPoint(x: 100, y: 50),
                size: sourceSize,
                layoutComputer: fixedSource
            )
            _ = try XCTUnwrap(sizeSource.transform).value
            let sizeFollower = capture(
                id: "size",
                properties: .size,
                anchor: .center,
                isSource: false,
                position: CGPoint(x: 10, y: 20),
                size: followerSize,
                layoutComputer: flexible
            )
            XCTAssertEqual(try origin(of: sizeFollower), CGPoint(x: 10, y: 20))
            XCTAssertEqual(
                try XCTUnwrap(sizeFollower.size).value.value,
                sourceSize
            )
        }
    }

    // ASSERTIONS matchedGeometryReplacementCompletionRuntimeObserved
    func testPublicReplacementPreservesReplacementThenOriginalCompletionOrder() throws {
        let recorder = AnimationCompletionRecorder()
        let rendererHost = TestViewRendererHost()
        let viewGraph = ViewGraph(
            rootViewType: EmptyView.self,
            content: EmptyView(),
            rendererHost: rendererHost,
            requestedOutputs: []
        )
        rendererHost.storage = viewGraph
        let namespace = Namespace().wrappedValue
        var source: Attribute<MatchedGeometryReplacementRoot>!
        var inputs: _ViewInputs!
        var layout: Attribute<LayoutComputer>!
        var display: Attribute<DisplayList>!

        func root(stage: Int) -> MatchedGeometryReplacementRoot {
            MatchedGeometryReplacementRoot(stage: stage, namespace: namespace)
        }

        try viewGraph.data.withCurrent {
            let graph = viewGraph.data.graph
            inputs = makeViewInputs(graph: graph)
            inputs.makeRootMatchedGeometryScope()
            inputs.preferences.keys.insert(DisplayList.Key.self)
            source = graph.makeInput(value: root(stage: 0))
            let outputs = MatchedGeometryReplacementRoot._makeView(
                view: _GraphValue(_attribute: source),
                inputs: inputs
            )
            layout = try XCTUnwrap(outputs._layoutComputer.attribute)
            display = Attribute<DisplayList>(
                try XCTUnwrap(outputs.preferences.value(for: DisplayList.Key.self))
            )

            func finishTransactionBody() {
                Transaction.dispatchPendingListeners().forEach { $0() }
                flushCompletionActions(in: graph)
            }

            func sample() {
                _ = layout.value.sizeThatFits(.unspecified)
                _ = display.value
                graph.inbox.drain()
                _ = layout.value.sizeThatFits(.unspecified)
                _ = display.value
            }

            sample()

            source.setValue(
                root(stage: 1),
                transaction: completionTransaction(
                    animation: .linear(duration: 1.0),
                    label: "first",
                    recorder: recorder
                )
            )
            sample()
            finishTransactionBody()
            XCTAssertEqual(recorder.events, [])

            inputs.base.time.setValue(Time(seconds: 0.25))
            sample()
            source.setValue(
                root(stage: 2),
                transaction: completionTransaction(
                    animation: .linear(duration: 0.4),
                    label: "replacement",
                    recorder: recorder
                )
            )
            sample()
            finishTransactionBody()
            XCTAssertEqual(recorder.events, [])

            inputs.base.time.setValue(Time(seconds: 0.70))
            sample()
            flushCompletionActions(in: graph)
            XCTAssertEqual(
                recorder.events,
                [
                    "replacement removed",
                    "replacement logical",
                ]
            )

            inputs.base.time.setValue(Time(seconds: 1.05))
            sample()
            flushCompletionActions(in: graph)
            XCTAssertEqual(
                recorder.events,
                [
                    "replacement removed",
                    "replacement logical",
                    "first removed",
                    "first logical",
                ]
            )
        }
    }

    private func flushCompletionActions(in graph: _AGGraph) {
        while !graph.actionOutbox.isEmpty {
            let actions = graph.actionOutbox
            graph.actionOutbox.removeAll()
            actions.forEach { $0() }
        }
    }

    private func registration(
        graph: _AGGraph,
        owner: AGAttribute,
        isSource: Bool,
        position: CGPoint,
        size: CGSize,
        phase: Attribute<Phase>? = nil
    ) -> MatchedGeometryScope.ViewRegistration {
        var transform = ViewTransform()
        transform.appendPosition(position)
        return MatchedGeometryScope.ViewRegistration(
            attribute: owner,
            args: graph.makeInput(value: (
                properties: MatchedGeometryProperties.frame,
                anchor: UnitPoint.center,
                isSource: isSource
            )),
            transaction: graph.makeInput(value: Transaction()),
            phase: phase ?? graph.makeInput(value: Phase()),
            size: graph.makeInput(value: ViewSize(size)),
            position: graph.makeInput(value: position),
            transform: graph.makeInput(value: transform)
        )
    }

    private func makeViewInputs(graph: _AGGraph) -> _ViewInputs {
        let environment = graph.makeInput(value: EnvironmentValues())
        return _ViewInputs(
            base: _GraphInputs(
                customInputs: PropertyList(),
                time: graph.makeInput(value: Time(seconds: 0)),
                cachedEnvironment: MutableBox(CachedEnvironment(environment: environment)),
                phase: graph.makeInput(value: Phase()),
                transaction: graph.makeInput(value: Transaction()),
                changedDebugProperties: 0,
                options: [],
                mergedInputs: []
            ),
            customInputs: PropertyList(),
            preferences: PreferencesInputs(
                keys: PreferenceKeys(),
                hostKeys: graph.makeInput(value: PreferenceKeys())
            ),
            transform: graph.makeInput(value: ViewTransform()),
            position: graph.makeInput(value: CGPoint.zero),
            containerPosition: graph.makeInput(value: CGPoint.zero),
            size: graph.makeInput(value: ViewSize.zero),
            safeAreaInsets: OptionalAttribute(),
            containerSize: OptionalAttribute(),
            stackOrientation: nil
        )
    }

    private func matchedInputs(
        from base: _ViewInputs,
        graph: _AGGraph,
        position: CGPoint,
        size: CGSize
    ) -> _ViewInputs {
        var inputs = base
        var transform = ViewTransform()
        transform.appendPosition(position)
        inputs.position = graph.makeInput(value: position)
        inputs.size = graph.makeInput(value: ViewSize(size))
        inputs.transform = graph.makeInput(value: transform)
        return inputs
    }
}

private struct MatchedGeometryKeyForTest: Hashable {
    var id: String
    var namespace: Namespace.ID
}

private struct MatchedGeometryReplacementRoot: View {
    var stage: Int
    var namespace: Namespace.ID

    var body: some View {
        ZStack(alignment: .topLeading) {
            if stage == 0 {
                matchedBox(
                    size: CGSize(width: 40, height: 30),
                    position: CGPoint(x: 55, y: 45)
                )
            } else if stage == 1 {
                matchedBox(
                    size: CGSize(width: 80, height: 50),
                    position: CGPoint(x: 170, y: 105)
                )
            } else {
                matchedBox(
                    size: CGSize(width: 110, height: 70),
                    position: CGPoint(x: 265, y: 165)
                )
            }
        }
        .frame(width: 340, height: 230)
    }

    private func matchedBox(size: CGSize, position: CGPoint) -> some View {
        Rectangle()
            .fill(Color.red)
            .frame(width: size.width, height: size.height)
            .matchedGeometryEffect(id: "hero", in: namespace, properties: .frame)
            .offset(x: position.x, y: position.y)
    }
}
