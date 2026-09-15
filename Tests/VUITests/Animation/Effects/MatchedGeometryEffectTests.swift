import XCTest
import class VVD.AudioDeviceContext
import protocol VVD.CommandBuffer
import enum VVD.GraphicsAPI
import class VVD.GraphicsDeviceContext
import class VVD.TextureFont
import func VVD.makeGraphicsDeviceContext
@testable import VUI

private final class MatchedGeometryRootScopeCapture: @unchecked Sendable {
    var hasScope = false
}

private final class MatchedGeometryTransformCapture: @unchecked Sendable {
    var transform: Attribute<ViewTransform>?
    var position: Attribute<CGPoint>?
    var containerPosition: Attribute<CGPoint>?
    var size: Attribute<ViewSize>?
    var requestsLayoutComputer = false
    var cachedFramePosition: Attribute<CGPoint>?
    var cachedAnimatedPosition: Attribute<CGPoint>?
}

private final class MatchedGeometryPlacementCapture: @unchecked Sendable {
    var position: CGPoint?
    var anchor: UnitPoint?
    var proposal: ProposedViewSize?
}

private struct MatchedGeometryAnimatedFrameCaptureEntry {
    var frame: AGAttribute
    var targetPosition: AGAttribute
    var targetSize: AGAttribute
    var transaction: AGAttribute
    var phase: AGAttribute
}

private final class MatchedGeometryAnimatedFrameCapture: @unchecked Sendable {
    var entries: [AGAttribute: MatchedGeometryAnimatedFrameCaptureEntry] = [:]
}

private final class SecondaryLayerPlacementCapture: @unchecked Sendable {
    var position: Attribute<CGPoint>?
    var size: Attribute<ViewSize>?
    var containerPosition: Attribute<CGPoint>?
    var containerSize: Attribute<ViewSize>?
}

private struct SecondaryLayerPlacementProbe: View, TestPrimitiveView {
    typealias Body = Never

    var capture: SecondaryLayerPlacementCapture

    static func _makeView(
        view: _GraphValue<Self>,
        inputs: _ViewInputs
    ) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("SecondaryLayerPlacementProbe called outside an active graph.")
        }
        let capture = view._attribute.value.capture
        capture.position = inputs.position
        capture.size = inputs.size
        capture.containerPosition = inputs.containerPosition
        capture.containerSize = inputs.containerSize.attribute
        return _ViewOutputs(
            layoutComputer: OptionalAttribute(
                graph.makeInput(value: LayoutComputer.fixed(
                    CGSize(width: 40, height: 20)
                ))
            )
        )
    }
}

private final class LayoutGeometryCapture: @unchecked Sendable {
    var position: Attribute<CGPoint>?
    var size: Attribute<ViewSize>?
    var transform: Attribute<ViewTransform>?
}

private struct LayoutGeometryProbe: View, TestPrimitiveView {
    typealias Body = Never

    var capture: LayoutGeometryCapture

    static func _makeView(
        view: _GraphValue<Self>,
        inputs: _ViewInputs
    ) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("LayoutGeometryProbe called outside an active graph.")
        }
        let capture = view._attribute.value.capture
        capture.position = inputs.position
        capture.size = inputs.size
        capture.transform = inputs.transform
        return _ViewOutputs(
            layoutComputer: OptionalAttribute(
                graph.makeInput(value: LayoutComputer.fixed(
                    CGSize(width: 40, height: 20)
                ))
            )
        )
    }
}

private struct MatchedGeometryTextDisplayProbe: View, TestPrimitiveView {
    typealias Body = Never

    var animatedFrameCapture: MatchedGeometryAnimatedFrameCapture? = nil
    var foreground: Color = .white

    static func _makeView(
        view: _GraphValue<Self>,
        inputs: _ViewInputs
    ) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("MatchedGeometryTextDisplayProbe called outside an active graph.")
        }
        if let capture = view._attribute.value.animatedFrameCapture,
           let frame = inputs.base.cachedEnvironment.value.animatedFrame {
            capture.entries[frame.animatedFrame.identifier] =
                MatchedGeometryAnimatedFrameCaptureEntry(
                    frame: frame.animatedFrame.identifier,
                    targetPosition: frame.position.identifier,
                    targetSize: frame.size.identifier,
                    transaction: frame.transaction.identifier,
                    phase: frame.viewPhase.identifier
                )
        }
        let displayList: Attribute<DisplayList> = graph.makeRule {
            var list = DisplayList()
            list.appendTextItem(
                foreground: .color(view._attribute.value.foreground),
                bounds: CGRect(
                    origin: CGPoint(
                        x: inputs.position.value.x - inputs.containerPosition.value.x,
                        y: inputs.position.value.y - inputs.containerPosition.value.y
                    ),
                    size: inputs.size.value.value
                )
            ) { _ in }
            return list
        }
        var preferences = PreferencesOutputs()
        preferences.append(
            DisplayList.Key.self,
            node: displayList.identifier
        )
        return _ViewOutputs(
            preferences: preferences,
            layoutComputer: OptionalAttribute(
                graph.makeInput(value: LayoutComputer.fixed(
                    CGSize(width: 60, height: 20)
                ))
            )
        )
    }
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
        viewGraph.setSize(CGSize(width: 1, height: 1))
        viewGraph.instantiateIfNeeded()

        XCTAssertTrue(capture.hasScope)
    }

    // ASSERTIONS matchedGeometryFieldMetadataObserved matchedGeometryDirectRegistrationInputsObserved
    func testRegistrationStorageMatchesFieldMetadata() {
        let graph = _AGGraph()
        _AGGraph.withCurrent(graph) {
            let value = registration(
                graph: graph,
                owner: graph.makeInput(value: true).identifier,
                isSource: true,
                position: CGPoint(x: 12, y: 34),
                size: CGSize(width: 56, height: 78)
            )

            XCTAssertEqual(
                Mirror(reflecting: value).children.compactMap(\.label),
                [
                    "attribute",
                    "args",
                    "transaction",
                    "phase",
                    "size",
                    "position",
                    "transform",
                ]
            )
        }
    }

    // ASSERTIONS secondaryLayerContainerInputPropagationObserved
    func testOverlaySecondaryGeometryComesFromDedicatedQuery() throws {
        let graph = _AGGraph()
        try _AGGraph.withCurrent(graph) {
            let capture = SecondaryLayerPlacementCapture()
            var inputs = makeViewInputs(graph: graph)
            inputs.position = graph.makeInput(value: CGPoint(x: 50, y: 50))
            inputs.size = graph.makeInput(value: ViewSize(width: 100, height: 60))
            let containerPosition = graph.makeInput(
                value: CGPoint(x: 15, y: 25)
            )
            let containerSize = graph.makeInput(
                value: ViewSize(width: 240, height: 180)
            )
            inputs.containerPosition = containerPosition
            inputs.containerSize = OptionalAttribute(containerSize)
            let modifier = graph.makeInput(value: _OverlayModifier(
                overlay: SecondaryLayerPlacementProbe(capture: capture),
                alignment: .center
            ))
            let primaryLayoutComputer = graph.makeInput(value: LayoutComputer.fixed(
                CGSize(width: 100, height: 60)
            ))

            let outputs = _OverlayModifier<SecondaryLayerPlacementProbe>._makeView(
                modifier: _GraphValue(_attribute: modifier),
                inputs: inputs
            ) { _, _ in
                _ViewOutputs(
                    layoutComputer: OptionalAttribute(primaryLayoutComputer)
                )
            }

            XCTAssertEqual(
                outputs._layoutComputer.attribute?.identifier,
                primaryLayoutComputer.identifier
            )
            XCTAssertEqual(
                try XCTUnwrap(capture.position).value,
                CGPoint(x: 80, y: 70)
            )
            let secondarySize = try XCTUnwrap(capture.size).value
            XCTAssertEqual(secondarySize.value, CGSize(width: 40, height: 20))
            XCTAssertEqual(
                secondarySize.proposal,
                _ProposedSize(width: 100, height: 60)
            )
            XCTAssertEqual(
                try XCTUnwrap(capture.containerPosition).identifier,
                containerPosition.identifier
            )
            XCTAssertEqual(
                try XCTUnwrap(capture.containerSize).identifier,
                containerSize.identifier
            )
        }
    }

    // ASSERTIONS matchedGeometryUnaryLayoutOwnershipObserved
    func testUnaryLayoutSeparatesOuterFrameFromBodyGeometry() throws {
        let graph = _AGGraph()
        try _AGGraph.withCurrent(graph) {
            let capture = LayoutGeometryCapture()
            var inputs = makeViewInputs(graph: graph)
            inputs.needsGeometry = true
            inputs.requestsLayoutComputer = true
            inputs.position = graph.makeInput(value: CGPoint(x: 100, y: 50))
            inputs.size = graph.makeInput(value: ViewSize(
                width: 120,
                height: 60
            ))
            let modifier = graph.makeInput(value: _FrameLayout(
                width: 120,
                height: 60,
                alignment: .center
            ))
            let outputs = _FrameLayout._makeView(
                modifier: _GraphValue(_attribute: modifier),
                inputs: inputs
            ) { _, childInputs in
                capture.position = childInputs.position
                capture.size = childInputs.size
                return _ViewOutputs(
                    layoutComputer: OptionalAttribute(
                        graph.makeInput(value: LayoutComputer.fixed(
                            CGSize(width: 20, height: 10)
                        ))
                    )
                )
            }
            let layout = try XCTUnwrap(outputs._layoutComputer.attribute?.value)
            let proposal = ProposedViewSize(width: 120, height: 60)
            layout.place(
                at: CGPoint(x: 160, y: 80),
                anchor: .center,
                proposal: proposal
            )

            XCTAssertEqual(inputs.position.value, CGPoint(x: 100, y: 50))
            XCTAssertEqual(inputs.size.value.value, CGSize(width: 120, height: 60))
            XCTAssertEqual(
                try XCTUnwrap(capture.position).value,
                CGPoint(x: 150, y: 75)
            )
            XCTAssertEqual(
                try XCTUnwrap(capture.size).value.value,
                CGSize(width: 20, height: 10)
            )
        }
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
                shared.frame?.origin,
                CGPoint(x: 100, y: 50)
            )
            XCTAssertEqual(
                shared.frame?.size.value,
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
            XCTAssertEqual(
                scope.sourceInfo(frameIndex: try XCTUnwrap(sourceIndex))?.frame.origin,
                CGPoint(x: 100, y: 50)
            )

            scope.releaseFrame(index: try XCTUnwrap(sourceIndex), owner: sourceOwner.identifier)
            XCTAssertNil(
                scope.sourceInfo(frameIndex: try XCTUnwrap(followerIndex))
            )
        }
    }

    // ASSERTIONS matchedGeometryRegistrationLifecycleObserved
    func testScopeKeepsSoleRemovingSourceUntilReplacementRegisters() throws {
        let graph = _AGGraph()
        try _AGGraph.withCurrent(graph) {
            var inputs = makeViewInputs(graph: graph)
            inputs.makeRootMatchedGeometryScope()
            let scope = try XCTUnwrap(
                inputs.base.customInputs.value(forKey: MatchedGeometryScope.self)
            )
            let namespace = Namespace().wrappedValue
            let key = AnyHashable(MatchedGeometryKeyForTest(
                id: "hero",
                namespace: namespace
            ))
            let phase = graph.makeInput(value: _GraphInputs.Phase())
            var frameIndex: Int?
            _ = scope.frame(
                index: &frameIndex,
                for: key,
                view: registration(
                    graph: graph,
                    owner: graph.makeInput(value: 1).identifier,
                    isSource: true,
                    position: CGPoint(x: 100, y: 50),
                    size: CGSize(width: 80, height: 40),
                    phase: phase
                )
            )

            var removed = _GraphInputs.Phase()
            removed.isBeingRemoved = true
            phase.setValue(removed)

            let source = try XCTUnwrap(
                scope.sourceInfo(frameIndex: try XCTUnwrap(frameIndex))
            )
            XCTAssertEqual(source.frame.origin, CGPoint(x: 100, y: 50))
            XCTAssertTrue(source.phase.isBeingRemoved)
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
            let firstPhase = graph.makeInput(value: _GraphInputs.Phase())
            let secondPhase = graph.makeInput(value: _GraphInputs.Phase())

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

            var removed = _GraphInputs.Phase()
            removed.isBeingRemoved = true
            firstPhase.setValue(removed)
            XCTAssertEqual(scope.sourceInfo(frameIndex: frameIndex)?.frame.origin,
                           CGPoint(x: 200, y: 150))

            secondPhase.setValue(removed)
            XCTAssertNil(scope.sourceInfo(frameIndex: frameIndex))
        }
    }

    // ASSERTIONS matchedGeometryGraphAndDisplayDisassemblyObserved
    func testFrameMatchProjectsFollowerLayoutFrameIntoSourceFrame() throws {
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
                sourceCapture.position = childInputs.position
                sourceCapture.size = childInputs.size
                return _ViewOutputs(
                    layoutComputer: OptionalAttribute(
                        graph.makeInput(value: LayoutComputer.fixed(
                            CGSize(width: 80, height: 40)
                        ))
                    )
                )
            }
            _ = try XCTUnwrap(sourceCapture.position).value

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
                followerCapture.position = childInputs.position
                followerCapture.size = childInputs.size
                return _ViewOutputs(
                    layoutComputer: OptionalAttribute(
                        graph.makeInput(value: LayoutComputer.fixed(
                            CGSize(width: 20, height: 10)
                        ))
                    )
                )
            }

            XCTAssertEqual(
                try XCTUnwrap(followerCapture.position).value,
                CGPoint(x: 130, y: 65)
            )
            XCTAssertEqual(
                try XCTUnwrap(followerCapture.size).value.value,
                CGSize(width: 20, height: 10)
            )
        }
    }

    // ASSERTIONS matchedGeometryBodyInputAnimationPolicyObserved
    // ASSERTIONS matchedGeometryPositionTransformCompositionObserved
    func testSourceRegistrationUsesTargetGeometryDuringLayoutAnimation() throws {
        let graph = _AGGraph()
        try _AGGraph.withCurrent(graph) {
            var inputs = makeViewInputs(graph: graph)
            inputs.makeRootMatchedGeometryScope()

            let targetPosition = graph.makeInput(value: CGPoint(x: 300, y: 200))
            let targetSize = graph.makeInput(
                value: ViewSize(CGSize(width: 120, height: 60))
            )
            let presentationPosition = graph.makeInput(value: CGPoint.zero)
            let presentationSize = graph.makeInput(value: ViewSize.zero)
            let presentationFrame = graph.makeInput(
                value: ViewFrame(origin: .zero, size: .zero)
            )
            var cachedEnvironment = inputs.base.cachedEnvironment.value
            cachedEnvironment.animatedFrame = CachedEnvironment.AnimatedFrame(
                position: targetPosition,
                size: targetSize,
                pixelLength: graph.makeInput(value: 1),
                time: inputs.base.time,
                transaction: inputs.base.transaction,
                viewPhase: inputs.base.phase,
                animatedFrame: presentationFrame,
                _animatedPosition: presentationPosition,
                _animatedSize: presentationSize,
                _animatedCGSize: nil
            )
            inputs.base.cachedEnvironment = MutableBox(cachedEnvironment)
            inputs.position = targetPosition
            inputs.size = targetSize
            inputs.transform = graph.makeRule {
                var transform = ViewTransform()
                transform.appendPosition(targetPosition.value)
                return transform
            }

            let modifier = graph.makeInput(value: _MatchedGeometryEffect(
                id: "hero",
                namespace: Namespace().wrappedValue,
                properties: .frame,
                anchor: UnitPoint.center,
                isSource: true
            ))
            let capture = MatchedGeometryTransformCapture()
            var forcesAnimationsDisabled = false
            _ = _MatchedGeometryEffect<String>._makeView(
                modifier: _GraphValue(_attribute: modifier),
                inputs: inputs
            ) { _, childInputs in
                capture.transform = childInputs.transform
                capture.position = childInputs.position
                capture.containerPosition = childInputs.containerPosition
                capture.size = childInputs.size
                capture.requestsLayoutComputer = childInputs.requestsLayoutComputer
                let cachedFrame = childInputs.base.cachedEnvironment.value.animatedFrame
                capture.cachedFramePosition = cachedFrame?.position
                capture.cachedAnimatedPosition = cachedFrame?._animatedPosition
                forcesAnimationsDisabled = childInputs.base.options.contains(
                    .animationsDisabled
                )
                return _ViewOutputs(
                    layoutComputer: OptionalAttribute(
                        graph.makeInput(value: LayoutComputer.fixed(
                            CGSize(width: 120, height: 60)
                        ))
                    )
                )
            }

            XCTAssertEqual(
                try XCTUnwrap(capture.position).value,
                CGPoint(x: 300, y: 200)
            )
            XCTAssertEqual(
                try XCTUnwrap(capture.containerPosition).value,
                CGPoint(x: 300, y: 200)
            )
            XCTAssertEqual(
                try XCTUnwrap(capture.size).value.value,
                CGSize(width: 120, height: 60)
            )
            XCTAssertEqual(
                try XCTUnwrap(capture.transform).identifier,
                inputs.transform.identifier
            )
            XCTAssertEqual(
                try XCTUnwrap(capture.cachedFramePosition).identifier,
                try XCTUnwrap(capture.position).identifier
            )
            XCTAssertEqual(
                try XCTUnwrap(capture.cachedAnimatedPosition).identifier,
                try XCTUnwrap(capture.containerPosition).identifier
            )
            XCTAssertTrue(capture.requestsLayoutComputer)
            XCTAssertFalse(forcesAnimationsDisabled)
        }
    }

    // ASSERTIONS matchedGeometryGraphAndDisplayDisassemblyObserved
    func testFrameMatchLaysOutDescendantsInTargetFrame() throws {
        let graph = _AGGraph()
        try _AGGraph.withCurrent(graph) {
            var baseInputs = makeViewInputs(graph: graph)
            baseInputs.makeRootMatchedGeometryScope()
            let namespace = Namespace().wrappedValue

            func makeMatchedOutputs(
                isSource: Bool,
                position: CGPoint,
                size: CGSize,
                placement: MatchedGeometryPlacementCapture
            ) -> _ViewOutputs {
                let modifier = graph.makeInput(value: _MatchedGeometryEffect(
                    id: "hero",
                    namespace: namespace,
                    properties: .frame,
                    anchor: UnitPoint.center,
                    isSource: isSource
                ))
                let inputs = matchedInputs(
                    from: baseInputs,
                    graph: graph,
                    position: position,
                    size: size
                )
                return _MatchedGeometryEffect<String>._makeView(
                    modifier: _GraphValue(_attribute: modifier),
                    inputs: inputs
                ) { _, childInputs in
                    _ = childInputs.transform.value
                    return _ViewOutputs(
                        layoutComputer: OptionalAttribute(
                            graph.makeInput(value: testLayoutComputer(
                                sizeThatFits: { proposal in
                                    proposal.fixingUnspecifiedDimensions()
                                },
                                place: { position, anchor, proposal in
                                    placement.position = position
                                    placement.anchor = anchor
                                    placement.proposal = proposal
                                }
                            ))
                        )
                    )
                }
            }

            let sourcePlacement = MatchedGeometryPlacementCapture()
            _ = makeMatchedOutputs(
                isSource: true,
                position: CGPoint(x: 100, y: 50),
                size: CGSize(width: 80, height: 40),
                placement: sourcePlacement
            )

            let followerPlacement = MatchedGeometryPlacementCapture()
            let followerOutputs = makeMatchedOutputs(
                isSource: false,
                position: CGPoint(x: 300, y: 200),
                size: CGSize(width: 120, height: 60),
                placement: followerPlacement
            )
            let layout = try XCTUnwrap(followerOutputs._layoutComputer.attribute?.value)
            layout.place(
                at: CGPoint(x: 360, y: 230),
                anchor: .center,
                proposal: ProposedViewSize(width: 120, height: 60)
            )

            XCTAssertEqual(followerPlacement.position, CGPoint(x: 360, y: 230))
            XCTAssertEqual(followerPlacement.anchor, .center)
            XCTAssertEqual(
                followerPlacement.proposal,
                ProposedViewSize(width: 120, height: 60)
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
                    capture.position = childInputs.position
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
                try XCTUnwrap(capture.position).value
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
                _ = try XCTUnwrap(source.position).value
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

            let flexible = testLayoutComputer(sizeThatFits: { proposal in
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
            _ = try XCTUnwrap(sizeSource.position).value
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

    // ASSERTIONS matchedGeometryDisplayListCanonicalizationObserved
    func testMatchedDisplayUsesIdentityWrapperWithPresentationFrame() throws {
        let graph = _AGGraph()
        try _AGGraph.withCurrent(graph) {
            var baseInputs = makeViewInputs(graph: graph)
            baseInputs.makeRootMatchedGeometryScope()
            let namespace = Namespace().wrappedValue

            func makeMatchedOutputs(
                isSource: Bool,
                position: CGPoint,
                size: CGSize,
                itemCount: Int
            ) -> _ViewOutputs {
                let modifier = graph.makeInput(value: _MatchedGeometryEffect(
                    id: "hero",
                    namespace: namespace,
                    properties: .frame,
                    anchor: UnitPoint.center,
                    isSource: isSource
                ))
                let inputs = matchedInputs(
                    from: baseInputs,
                    graph: graph,
                    position: position,
                    size: size
                )
                return _MatchedGeometryEffect<String>._makeView(
                    modifier: _GraphValue(_attribute: modifier),
                    inputs: inputs
                ) { _, childInputs in
                    let contentAttribute: Attribute<DisplayList> = graph.makeRule {
                        var content = DisplayList()
                        let presentationPosition = childInputs.position.value
                        for index in 0..<itemCount {
                            content.appendItem(bounds: CGRect(
                                x: presentationPosition.x + CGFloat(index),
                                y: presentationPosition.y,
                                width: 1,
                                height: 1
                            )) { _ in }
                        }
                        return content
                    }
                    var preferences = PreferencesOutputs()
                    preferences.append(
                        DisplayList.Key.self,
                        node: contentAttribute.identifier
                    )
                    return _ViewOutputs(
                        preferences: preferences,
                        layoutComputer: OptionalAttribute(
                            graph.makeInput(value: LayoutComputer.fixed(size))
                        )
                    )
                }
            }

            let sourceOutputs = makeMatchedOutputs(
                isSource: true,
                position: CGPoint(x: 100, y: 50),
                size: CGSize(width: 80, height: 40),
                itemCount: 1
            )
            let sourceDisplay = Attribute<DisplayList>(try XCTUnwrap(
                sourceOutputs.preferences.value(for: DisplayList.Key.self)
            ))
            _ = sourceDisplay.value

            let followerOutputs = makeMatchedOutputs(
                isSource: false,
                position: CGPoint(x: 300, y: 200),
                size: CGSize(width: 120, height: 60),
                itemCount: 64
            )
            let followerDisplay = Attribute<DisplayList>(try XCTUnwrap(
                followerOutputs.preferences.value(for: DisplayList.Key.self)
            )).value

            XCTAssertEqual(followerDisplay.items.count, 1)
            let item = try XCTUnwrap(followerDisplay.items.first)
            XCTAssertEqual(item.frame.origin, CGPoint(x: 80, y: 40))
            XCTAssertEqual(item.frame.size, CGSize(width: 120, height: 60))
            XCTAssertNotEqual(item.identity, .none)
            XCTAssertGreaterThan(item.version.value, 0)
            guard case let .effect(.identity, content) = item.value else {
                return XCTFail("expected one matched display-list identity item")
            }
            XCTAssertEqual(content.renderItems.count, 64)
            XCTAssertTrue(content.effects.isEmpty)
            XCTAssertEqual(
                content.renderItems.first?.command.bounds?.origin,
                CGPoint(x: 80, y: 40)
            )
            XCTAssertEqual(
                content.renderItems.last?.command.bounds?.origin,
                CGPoint(x: 143, y: 40)
            )
        }
    }

    // ASSERTIONS matchedGeometryPresentationHitTestObserved
    // ASSERTIONS matchedGeometryPositionTransformCompositionObserved
    func testNestedDisplayTracksPresentationWhileBodyTransformKeepsTargetInput() throws {
        let graph = _AGGraph()
        try _AGGraph.withCurrent(graph) {
            var baseInputs = makeViewInputs(graph: graph)
            baseInputs.makeRootMatchedGeometryScope()
            let namespace = Namespace().wrappedValue

            func makeMatchedOutputs(
                isSource: Bool,
                position: CGPoint,
                capture: LayoutGeometryCapture
            ) -> _ViewOutputs {
                let modifier = graph.makeInput(value: _MatchedGeometryEffect(
                    id: "hero",
                    namespace: namespace,
                    properties: .frame,
                    anchor: UnitPoint.center,
                    isSource: isSource
                ))
                let inputs = matchedInputs(
                    from: baseInputs,
                    graph: graph,
                    position: position,
                    size: CGSize(width: 100, height: 60)
                )
                return _MatchedGeometryEffect<String>._makeView(
                    modifier: _GraphValue(_attribute: modifier),
                    inputs: inputs
                ) { _, childInputs in
                    let root = ZStack {
                        LayoutGeometryProbe(capture: capture)
                    }
                    let source = graph.makeInput(value: root)
                    var outputs = type(of: root)._makeView(
                        view: _GraphValue(_attribute: source),
                        inputs: childInputs
                    )
                    let display = graph.makeRule {
                        var list = DisplayList()
                        let origin = capture.position?.value ?? .zero
                        list.appendItem(bounds: CGRect(
                            origin: origin,
                            size: CGSize(width: 40, height: 20)
                        )) { _ in }
                        return list
                    }
                    outputs.preferences.setValue(
                        display.identifier,
                        for: DisplayList.Key.self
                    )
                    return outputs
                }
            }

            let sourceCapture = LayoutGeometryCapture()
            let sourceOutputs = makeMatchedOutputs(
                isSource: true,
                position: CGPoint(x: 100, y: 50),
                capture: sourceCapture
            )
            let sourceLayout = try XCTUnwrap(sourceOutputs._layoutComputer.attribute?.value)
            sourceLayout.place(
                at: CGPoint(x: 150, y: 80),
                anchor: .center,
                proposal: ProposedViewSize(width: 100, height: 60)
            )
            _ = Attribute<DisplayList>(try XCTUnwrap(
                sourceOutputs.preferences.value(for: DisplayList.Key.self)
            )).value

            let followerCapture = LayoutGeometryCapture()
            let followerOutputs = makeMatchedOutputs(
                isSource: false,
                position: CGPoint(x: 300, y: 200),
                capture: followerCapture
            )
            let followerLayout = try XCTUnwrap(
                followerOutputs._layoutComputer.attribute?.value
            )
            followerLayout.place(
                at: CGPoint(x: 350, y: 230),
                anchor: .center,
                proposal: ProposedViewSize(width: 100, height: 60)
            )

            let display = Attribute<DisplayList>(try XCTUnwrap(
                followerOutputs.preferences.value(for: DisplayList.Key.self)
            )).value
            let item = try XCTUnwrap(display.items.first)
            guard case let .effect(.identity, content) = item.value else {
                return XCTFail("expected matched display identity item")
            }
            let presentationOrigin = try XCTUnwrap(followerCapture.position).value
            let contentOrigin = try XCTUnwrap(
                content.renderItems.first?.command.bounds?.origin
            )
            XCTAssertEqual(contentOrigin, presentationOrigin)
            var points = [CGPoint.zero]
            try XCTUnwrap(followerCapture.transform).value.convertGlobal(
                from: .local,
                points: &points
            )
            XCTAssertEqual(points[0], CGPoint(x: 300, y: 200))
        }
    }

    // ASSERTIONS matchedGeometryReplacementCompletionRuntimeObserved
    // ASSERTIONS matchedGeometrySharedFrameListenerOwnershipObserved
    @MainActor
    func testPublicReplacementPreservesReplacementThenOriginalCompletionOrder() throws {
        let recorder = AnimationCompletionRecorder()
        let probe = MatchedGeometryReplacementRuntimeProbe()
        let controller = WindowController(
            content: MatchedGeometryReplacementRuntimeRoot(probe: probe),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(MatchedGeometryReplacementRuntimeRoot.self)
            )
        )
        let withGC: WindowContext.WithGraphicsContext = { _, _ in }
        var tick: UInt64 = 0

        func update(_ time: Double) {
            controller.updateFrame(
                tick: tick,
                delta: time - controller.animationTimestamp.seconds,
                date: controller.date.addingTimeInterval(time),
                contentSize: CGSize(width: 340, height: 230),
                shouldDrawFrame: false,
                withGC
            )
            tick &+= 1
        }

        func advance(from start: Double, through end: Double) {
            let interval = 1.0 / 60.0
            var time = start + interval
            while time < end {
                update(time)
                time += interval
            }
            update(end)
        }

        update(0)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.20))
        update(0)

        try XCTUnwrap(probe.setStage)(
            1,
            completionTransaction(
                animation: .linear(duration: 1.0),
                label: "first",
                recorder: recorder
            )
        )
        update(0)
        XCTAssertEqual(recorder.events, [])

        advance(from: 0, through: 0.25)
        try XCTUnwrap(probe.setStage)(
            2,
            completionTransaction(
                animation: .linear(duration: 0.4),
                label: "replacement",
                recorder: recorder
            )
        )
        update(0.25)
        XCTAssertEqual(recorder.events, [])

        advance(from: 0.25, through: 0.70)
        XCTAssertEqual(
            recorder.events,
            [
                "replacement removed",
                "replacement logical",
            ]
        )

        advance(from: 0.70, through: 1.05)
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

    // ASSERTIONS matchedGeometryDisplayListCanonicalizationObserved
    @MainActor
    func testRetainedReplacementKeepsOverlayInSharedPresentationFrame() throws {
        let probe = MatchedGeometryTextRuntimeProbe()
        let controller = WindowController(
            content: MatchedGeometryTextRuntimeRoot(probe: probe),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(MatchedGeometryTextRuntimeRoot.self)
            )
        )
        let withGC: WindowContext.WithGraphicsContext = { _, _ in }

        func update(_ time: Double, tick: UInt64) {
            controller.updateFrame(
                tick: tick,
                delta: time - controller.animationTimestamp.seconds,
                date: controller.date.addingTimeInterval(time),
                contentSize: CGSize(width: 700, height: 500),
                shouldDrawFrame: false,
                withGC
            )
        }

        func displayList() throws -> DisplayList {
            try controller.viewGraph.data.withCurrent {
                try XCTUnwrap(controller.viewGraph.rootDisplayList?.value)
            }
        }

        func matchedFrames() throws -> [CGRect] {
            try displayList().items.compactMap {
                guard case let .effect(.identity, contents) = $0.value else {
                    return nil
                }
                return contents.interpolationBounds == nil ? nil : $0.frame
            }
        }

        func assertFrameEqual(
            _ lhs: CGRect,
            _ rhs: CGRect,
            accuracy: CGFloat = 0.001,
            file: StaticString = #filePath,
            line: UInt = #line
        ) {
            XCTAssertEqual(lhs.origin.x, rhs.origin.x, accuracy: accuracy, file: file, line: line)
            XCTAssertEqual(lhs.origin.y, rhs.origin.y, accuracy: accuracy, file: file, line: line)
            XCTAssertEqual(lhs.size.width, rhs.size.width, accuracy: accuracy, file: file, line: line)
            XCTAssertEqual(lhs.size.height, rhs.size.height, accuracy: accuracy, file: file, line: line)
        }

        func assertSharedPresentation(
            _ list: DisplayList,
            file: StaticString = #filePath,
            line: UInt = #line
        ) {
            let matchedItems: [(frame: CGRect, contents: DisplayList)] = list.items.compactMap {
                guard case let .effect(.identity, contents) = $0.value else {
                    return nil
                }
                guard contents.interpolationBounds != nil else {
                    return nil
                }
                return ($0.frame, contents)
            }
            XCTAssertEqual(matchedItems.count, 2, file: file, line: line)
            guard matchedItems.count == 2 else { return }
            XCTAssertEqual(matchedItems[0].frame, matchedItems[1].frame, file: file, line: line)

            let textFrames = matchedItems.flatMap { item in
                let bounds = item.contents.interpolationBounds ?? .zero
                let transform = CGAffineTransform(
                    translationX: item.frame.minX - bounds.minX,
                    y: item.frame.minY - bounds.minY
                )
                return recursiveTextFrames(
                    in: item.contents,
                    inheritedTransform: transform
                )
            }
            XCTAssertEqual(textFrames.count, 2, file: file, line: line)
            guard textFrames.count == 2 else { return }
            XCTAssertEqual(
                textFrames[0].origin.x,
                textFrames[1].origin.x,
                accuracy: 0.001,
                file: file,
                line: line
            )
            XCTAssertEqual(
                textFrames[0].origin.y,
                textFrames[1].origin.y,
                accuracy: 0.001,
                file: file,
                line: line
            )
            XCTAssertEqual(
                textFrames[0].midX,
                matchedItems[0].frame.midX,
                // Text drawing is pixel-aligned while the matched wrapper keeps
                // its subpixel presentation frame.
                accuracy: 0.501,
                file: file,
                line: line
            )
            XCTAssertEqual(
                textFrames[0].midY,
                matchedItems[0].frame.midY,
                accuracy: 0.501,
                file: file,
                line: line
            )
        }

        func textColors(in list: DisplayList) -> [Color] {
            list.items.reduce(into: []) { colors, item in
                switch item.value {
                case let .content(content):
                    if case let .text(record, _) = content.command,
                       case let .color(color)? = record.foreground {
                        colors.append(color)
                    }
                    switch content.value {
                    case let .style(style):
                        colors.append(contentsOf: textColors(in: style.contents))
                    case let .crossFade(crossFade):
                        if let source = crossFade.source {
                            colors.append(contentsOf: textColors(in: source.contents))
                        }
                        if let target = crossFade.target {
                            colors.append(contentsOf: textColors(in: target.contents))
                        }
                    case let .flattened(contents, _, _):
                        colors.append(contentsOf: textColors(in: contents))
                    case let .drawing(contents, _, _):
                        if let local = contents as? DisplayList.LocalContents {
                            colors.append(contentsOf: textColors(in: local.list))
                        }
                    case .backend, .color, .shape, .image, .text:
                        break
                    }
                case let .effect(_, contents):
                    colors.append(contentsOf: textColors(in: contents))
                case let .states(states):
                    for (_, contents) in states {
                        colors.append(contentsOf: textColors(in: contents))
                    }
                case .empty:
                    break
                }
            }
        }

        var tick: UInt64 = 0
        func sample(_ time: Double) {
            update(time, tick: tick)
            tick &+= 1
        }

        sample(0)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.20))
        sample(0)
        let initialFrames = try matchedFrames()
        let initialFrame = try XCTUnwrap(initialFrames.first)
        XCTAssertEqual(initialFrames.count, 1)

        try XCTUnwrap(probe.toggle)()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        sample(0)
        var sampledForwardMidFrame: CGRect?
        var sampledForwardFirstColors: [Color]?
        var sampledForwardMidColors: [Color]?
        for frame in 1...240 {
            let time = Double(frame) / 60.0
            sample(time)
            if frame == 1 {
                sampledForwardFirstColors = textColors(in: try displayList())
            }
            if frame == 30 {
                let list = try displayList()
                assertSharedPresentation(list)
                sampledForwardMidColors = textColors(in: list)
                sampledForwardMidFrame = try XCTUnwrap(matchedFrames().first)
            }
        }
        let forwardFrames = try matchedFrames()
        let forwardFrame = try XCTUnwrap(forwardFrames.first)
        let forwardMidFrame = try XCTUnwrap(sampledForwardMidFrame)
        XCTAssertEqual(forwardFrames.count, 1)
        XCTAssertGreaterThan(forwardMidFrame.minX, initialFrame.minX)
        XCTAssertLessThan(forwardMidFrame.minX, forwardFrame.minX)
        XCTAssertGreaterThan(forwardMidFrame.width, initialFrame.width)
        XCTAssertLessThan(forwardMidFrame.width, forwardFrame.width)
        XCTAssertGreaterThan(forwardMidFrame.height, initialFrame.height)
        XCTAssertLessThan(forwardMidFrame.height, forwardFrame.height)
        for colors in [
            try XCTUnwrap(sampledForwardFirstColors),
            try XCTUnwrap(sampledForwardMidColors),
        ] {
            XCTAssertTrue(colors.contains(.red), "\(colors)")
            XCTAssertTrue(colors.contains(.green), "\(colors)")
        }
        XCTAssertGreaterThan(forwardFrame.minX, initialFrame.minX)
        XCTAssertGreaterThan(forwardFrame.width, initialFrame.width)
        XCTAssertGreaterThan(forwardFrame.height, initialFrame.height)

        try XCTUnwrap(probe.toggle)()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        sample(4.0)
        let reverseStartFrames = try matchedFrames()
        XCTAssertEqual(reverseStartFrames.count, 2)
        for frame in reverseStartFrames {
            assertFrameEqual(frame, forwardFrame)
        }

        for frame in 1...240 {
            let time = 4.0 + Double(frame) / 60.0
            sample(time)
            if frame == 30 {
                assertSharedPresentation(try displayList())
                let reverseMidFrames = try matchedFrames()
                let reverseMidFrame = try XCTUnwrap(reverseMidFrames.first)
                XCTAssertGreaterThan(reverseMidFrame.minX, initialFrame.minX)
                XCTAssertLessThan(reverseMidFrame.minX, forwardFrame.minX)
                XCTAssertGreaterThan(reverseMidFrame.width, initialFrame.width)
                XCTAssertLessThan(reverseMidFrame.width, forwardFrame.width)
            }
        }
        let reverseEndFrames = try matchedFrames()
        XCTAssertEqual(reverseEndFrames.count, 1)
        assertFrameEqual(try XCTUnwrap(reverseEndFrames.first), initialFrame)
    }

    @MainActor
    func testResolvedTextReplacementKeepsSourceAndDestinationDuringFirstToggle() throws {
        guard let deviceContext = makeGraphicsDeviceContext(api: .metal),
              let renderQueue = deviceContext.renderQueue(),
              let fontURL = defaultFontURL,
              let textureFont = TextureFont(
                deviceContext: deviceContext,
                path: fontURL.path
              ) else {
            throw XCTSkip("Metal graphics device unavailable")
        }
        let previousAppContext = appContext
        appContext = MatchedGeometryAppContext(
            graphicsDeviceContext: deviceContext
        )
        defer { appContext = previousAppContext }

        let probe = MatchedGeometryTextRuntimeProbe()
        let controller = WindowController(
            content: MatchedGeometryResolvedTextRuntimeRoot(
                probe: probe,
                font: VUI.Font(textureFont)
            ),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(MatchedGeometryResolvedTextRuntimeRoot.self)
            )
        )
        let withGC: WindowContext.WithGraphicsContext = { _, handler in
            guard let commandBuffer = renderQueue.makeCommandBuffer(),
                  let context = GraphicsContext(
                    sceneResources: controller.sceneResources,
                    environment: controller.environment,
                    viewport: CGRect(x: 0, y: 0, width: 700, height: 500),
                    contentOffset: .zero,
                    contentScaleFactor: 1,
                    resolution: CGSize(width: 700, height: 500),
                    commandBuffer: commandBuffer
                  ) else {
                return XCTFail("Unable to create the text resource graphics context.")
            }
            handler(context)
            XCTAssertTrue(commandBuffer.commit())
        }
        let startDate = controller.date
        let renderer = DisplayList.GraphicsRenderer()
        var tick: UInt64 = 0

        func update(_ time: Double) throws -> DisplayList {
            controller.updateFrame(
                tick: tick,
                delta: time - controller.animationTimestamp.seconds,
                date: startDate.addingTimeInterval(time),
                contentSize: CGSize(width: 700, height: 500),
                shouldDrawFrame: false,
                withGC
            )
            tick &+= 1
            return try controller.viewGraph.data.withCurrent {
                try XCTUnwrap(controller.viewGraph.rootDisplayList?.value)
            }
        }

        func renderedTextPixelCounts(
            _ list: DisplayList
        ) throws -> (source: Int, destination: Int) {
            let commandBuffer = try XCTUnwrap(renderQueue.makeCommandBuffer())
            let context = try XCTUnwrap(GraphicsContext(
                sceneResources: controller.sceneResources,
                environment: controller.environment,
                viewport: CGRect(x: 0, y: 0, width: 700, height: 500),
                contentOffset: .zero,
                contentScaleFactor: 1,
                resolution: CGSize(width: 700, height: 500),
                commandBuffer: commandBuffer
            ))
            context.clear(with: .clear)
            renderer.render(
                list: list,
                at: controller.animationTimestamp,
                in: context
            )
            try waitForCompletion(commandBuffer)

            let staging = try XCTUnwrap(
                deviceContext.makeCPUAccessible(texture: context.backdrop)
            )
            let pointer = try XCTUnwrap(staging.contents())
            let bytes = UnsafeRawBufferPointer(
                start: pointer,
                count: 700 * 500 * 4
            )
            var source = 0
            var destination = 0
            for index in 0..<(700 * 500) {
                let red = Int(bytes[index * 4])
                let green = Int(bytes[index * 4 + 1])
                let blue = Int(bytes[index * 4 + 2])
                if red > green + 24, red > blue + 24 {
                    source += 1
                }
                if green > red + 24, green > blue + 24 {
                    destination += 1
                }
            }
            return (source, destination)
        }

        func animationEffects(
            in list: DisplayList,
            path: String = ""
        ) -> [String] {
            list.items.enumerated().reduce(into: []) { records, entry in
                let itemPath = "\(path)/\(entry.offset)"
                switch entry.element.value {
                case let .effect(effect, contents):
                    if case let .animation(animation) = effect,
                       let opacity = animation as? DisplayList.OpacityAnimation {
                        records.append(
                            "\(itemPath) id=\(entry.element.identity) " +
                            "version=\(entry.element.version.value) " +
                            "opacity=\(opacity.from.opacity)->\(opacity.to.opacity)"
                        )
                    }
                    records.append(contentsOf: animationEffects(
                        in: contents,
                        path: itemPath
                    ))
                case let .content(content):
                    switch content.value {
                    case let .style(style):
                        records.append(contentsOf: animationEffects(
                            in: style.contents,
                            path: itemPath
                        ))
                    case let .crossFade(crossFade):
                        if let source = crossFade.source {
                            records.append(contentsOf: animationEffects(
                                in: source.contents,
                                path: itemPath + "/source"
                            ))
                        }
                        if let target = crossFade.target {
                            records.append(contentsOf: animationEffects(
                                in: target.contents,
                                path: itemPath + "/target"
                            ))
                        }
                    case let .flattened(contents, _, _):
                        records.append(contentsOf: animationEffects(
                            in: contents,
                            path: itemPath
                        ))
                    case let .drawing(contents, _, _):
                        if let local = contents as? DisplayList.LocalContents {
                            records.append(contentsOf: animationEffects(
                                in: local.list,
                                path: itemPath
                            ))
                        }
                    case .backend, .color, .shape, .image, .text:
                        break
                    }
                case let .states(states):
                    if let contents = states.last?.1 {
                        records.append(contentsOf: animationEffects(
                            in: contents,
                            path: itemPath
                        ))
                    }
                case .empty:
                    break
                }
            }
        }

        func renderLeaves(
            in list: DisplayList,
            path: String = ""
        ) -> [String] {
            list.items.enumerated().reduce(into: []) { records, entry in
                let itemPath = "\(path)/\(entry.offset)"
                switch entry.element.value {
                case let .effect(_, contents):
                    records.append(contentsOf: renderLeaves(
                        in: contents,
                        path: itemPath + "/effect"
                    ))
                case let .content(content):
                    switch content.value {
                    case .shape:
                        records.append("\(itemPath):shape")
                    case let .text(text):
                        records.append(
                            "\(itemPath):text=\(text.view.text.storage?.string ?? "?")"
                        )
                    case let .style(style):
                        records.append(contentsOf: renderLeaves(
                            in: style.contents,
                            path: itemPath + "/style"
                        ))
                    case let .crossFade(crossFade):
                        if let source = crossFade.source {
                            records.append(contentsOf: renderLeaves(
                                in: source.contents,
                                path: itemPath + "/cross-source"
                            ))
                        }
                        if let target = crossFade.target {
                            records.append(contentsOf: renderLeaves(
                                in: target.contents,
                                path: itemPath + "/cross-target"
                            ))
                        }
                    case let .flattened(contents, _, _):
                        records.append(contentsOf: renderLeaves(
                            in: contents,
                            path: itemPath + "/flattened"
                        ))
                    case let .drawing(contents, _, _):
                        if let local = contents as? DisplayList.LocalContents {
                            records.append(contentsOf: renderLeaves(
                                in: local.list,
                                path: itemPath + "/drawing"
                            ))
                        }
                    case .backend, .color, .image:
                        break
                    }
                case let .states(states):
                    if let contents = states.last?.1 {
                        records.append(contentsOf: renderLeaves(
                            in: contents,
                            path: itemPath + "/state"
                        ))
                    }
                case .empty:
                    break
                }
            }
        }

        _ = try update(0)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.20))
        let initial = try update(0)
        XCTAssertEqual(
            resolvedTextSamples(in: initial).map(\.string),
            ["Source"]
        )
        print("MATCHED_TEXT_PIXELS initial=\(try renderedTextPixelCounts(initial))")

        try XCTUnwrap(probe.toggle)()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        _ = try update(0)

        var coexistence: (
            samples: [MatchedGeometryResolvedTextSample],
            pixels: (source: Int, destination: Int)
        )?
        var sawSourcePixels = false
        var sawDestinationPixels = false
        for frame in 1...30 {
            let list = try update(Double(frame) / 60.0)
            let samples = resolvedTextSamples(in: list).filter {
                $0.string == "Source" || $0.string == "Destination"
            }
            let pixels = try renderedTextPixelCounts(list)
            sawSourcePixels = sawSourcePixels || pixels.source > 0
            sawDestinationPixels = sawDestinationPixels || pixels.destination > 0
            if frame == 1 || frame.isMultiple(of: 5) {
                print("MATCHED_TEXT_PIXELS frame=\(frame) pixels=\(pixels)")
                print("MATCHED_TEXT_SAMPLES frame=\(frame) samples=\(samples)")
                print("MATCHED_TEXT_EFFECTS frame=\(frame) \(animationEffects(in: list))")
                print("MATCHED_TEXT_LEAVES frame=\(frame) \(renderLeaves(in: list))")
            }
            if coexistence == nil &&
                samples.contains(where: { $0.string == "Source" && $0.opacity > 0 }) &&
                samples.contains(where: { $0.string == "Destination" && $0.opacity > 0 }) {
                coexistence = (samples, pixels)
            }
        }

        let coexisting = try XCTUnwrap(coexistence)
        let samples = coexisting.samples
        let source = try XCTUnwrap(samples.last { $0.string == "Source" })
        let destination = try XCTUnwrap(samples.last { $0.string == "Destination" })
        XCTAssertEqual(source.frame.midX, destination.frame.midX, accuracy: 2)
        XCTAssertEqual(source.frame.midY, destination.frame.midY, accuracy: 2)
        XCTAssertTrue(sawSourcePixels)
        XCTAssertTrue(sawDestinationPixels)
    }

    private func waitForCompletion(_ commandBuffer: CommandBuffer) throws {
        let condition = NSCondition()
        var completed = false
        commandBuffer.addCompletedHandler { _ in
            condition.lock()
            completed = true
            condition.broadcast()
            condition.unlock()
        }
        condition.lock()
        defer { condition.unlock() }
        XCTAssertTrue(commandBuffer.commit())
        let timeout = Date(timeIntervalSinceNow: 5)
        while !completed {
            if !condition.wait(until: timeout) {
                XCTFail("GPU command buffer timed out")
                break
            }
        }
    }

    // ASSERTIONS matchedGeometryNonSourceReplacementObserved
    @MainActor
    func testNonSourceReplacementKeepsRetainedPresentationFrameAtActivation() throws {
        let probe = MatchedGeometryNonSourceRuntimeProbe()
        let controller = WindowController(
            content: MatchedGeometryNonSourceRuntimeRoot(probe: probe),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(MatchedGeometryNonSourceRuntimeRoot.self)
            )
        )
        let withGC: WindowContext.WithGraphicsContext = { _, _ in }
        var tick: UInt64 = 0

        func update(_ time: Double) {
            controller.updateFrame(
                tick: tick,
                delta: time - controller.animationTimestamp.seconds,
                date: controller.date.addingTimeInterval(time),
                contentSize: CGSize(width: 700, height: 500),
                shouldDrawFrame: false,
                withGC
            )
            tick &+= 1
        }

        func matchedPresentations() throws -> [(frame: CGRect, contentBounds: CGRect)] {
            try controller.viewGraph.data.withCurrent {
                try XCTUnwrap(controller.viewGraph.rootDisplayList?.value).items.compactMap {
                    guard case let .effect(.identity, contents) = $0.value,
                          let contentBounds = contents.interpolationBounds else {
                        return nil
                    }
                    return ($0.frame, contentBounds)
                }
            }
        }

        func effectiveFrame(
            _ presentation: (frame: CGRect, contentBounds: CGRect)
        ) -> CGRect {
            CGRect(
                origin: CGPoint(
                    x: presentation.contentBounds.origin.x + presentation.frame.origin.x,
                    y: presentation.contentBounds.origin.y + presentation.frame.origin.y
                ),
                size: presentation.frame.size
            )
        }

        update(0)
        let initialPresentation = try XCTUnwrap(matchedPresentations().first)
        let initial = effectiveFrame(initialPresentation)

        try XCTUnwrap(probe.toggleSource)()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        update(1.3)
        XCTAssertEqual(
            effectiveFrame(try XCTUnwrap(matchedPresentations().first)),
            initial
        )

        try XCTUnwrap(probe.toggleLayout)()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        update(1.3)
        let activation = try matchedPresentations()
        XCTAssertEqual(activation.count, 2)
        let retained = try XCTUnwrap(activation.first {
            abs($0.frame.width - initial.width) < 0.001
        })
        let effectiveRetained = effectiveFrame(retained)
        XCTAssertEqual(effectiveRetained.origin.x, initial.origin.x, accuracy: 0.001)
        XCTAssertEqual(effectiveRetained.origin.y, initial.origin.y, accuracy: 0.001)
    }

    // ASSERTIONS matchedGeometryMidflightNoSourceAnimatorObserved
    @MainActor
    func testMidflightSourceFlagKeepsExistingMatchedSpringInFlight() throws {
        func run(togglesSource: Bool) throws -> [CGRect] {
            let probe = MatchedGeometryNonSourceRuntimeProbe()
            let controller = WindowController(
                content: MatchedGeometryNonSourceRuntimeRoot(probe: probe),
                scene: WindowKey(
                    namespace: .app,
                    sceneID: SceneID(MatchedGeometryNonSourceRuntimeRoot.self)
                )
            )
            let withGC: WindowContext.WithGraphicsContext = { _, _ in }
            var tick: UInt64 = 0

            func update(_ time: Double) {
                controller.updateFrame(
                    tick: tick,
                    delta: time - controller.animationTimestamp.seconds,
                    date: controller.date.addingTimeInterval(time),
                    contentSize: CGSize(width: 700, height: 500),
                    shouldDrawFrame: false,
                    withGC
                )
                tick &+= 1
            }

            func effectiveFrame() throws -> CGRect {
                try controller.viewGraph.data.withCurrent {
                    let list = try XCTUnwrap(controller.viewGraph.rootDisplayList?.value)
                    let presentations: [(frame: CGRect, contentBounds: CGRect)] = list.items.compactMap {
                        guard case let .effect(.identity, contents) = $0.value,
                              let contentBounds = contents.interpolationBounds else {
                            return nil
                        }
                        return (frame: $0.frame, contentBounds: contentBounds)
                    }
                    let frames = presentations.map { presentation in
                        CGRect(
                            origin: CGPoint(
                                x: presentation.contentBounds.origin.x + presentation.frame.origin.x,
                                y: presentation.contentBounds.origin.y + presentation.frame.origin.y
                            ),
                            size: presentation.frame.size
                        )
                    }
                    return try XCTUnwrap(frames.max { $0.minX < $1.minX })
                }
            }

            update(0)
            let initial = try effectiveFrame()
            try XCTUnwrap(probe.toggleLayout)()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
            update(0)
            update(0.001)
            update(0.45)
            var frames = [try effectiveFrame()]
            XCTAssertGreaterThan(frames[0].minX, initial.minX)

            if togglesSource {
                try XCTUnwrap(probe.toggleSource)()
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
            }
            update(0.45)
            frames.append(try effectiveFrame())
            for time in [0.75, 1.0, 1.5, 2.1] {
                update(time)
                frames.append(try effectiveFrame())
            }
            return frames
        }

        let baseline = try run(togglesSource: false)
        let sourceFlag = try run(togglesSource: true)
        XCTAssertEqual(sourceFlag.count, baseline.count)
        for (flagged, unmodified) in zip(sourceFlag, baseline) {
            XCTAssertEqual(flagged.minX, unmodified.minX, accuracy: 0.001)
            XCTAssertEqual(flagged.minY, unmodified.minY, accuracy: 0.001)
            XCTAssertEqual(flagged.width, unmodified.width, accuracy: 0.001)
            XCTAssertEqual(flagged.height, unmodified.height, accuracy: 0.001)
        }
    }

    // ASSERTIONS matchedGeometryMidflightSourceSelectionPhaseObserved
    func testNoSourceAnimatorStopsWhenLastSourceRegistrationBeginsRemoval() throws {
        let rendererHost = TestViewRendererHost()
        let viewGraph = ViewGraph(
            rootViewType: EmptyView.self,
            content: EmptyView(),
            rendererHost: rendererHost
        )
        rendererHost.storage = viewGraph
        let graph = viewGraph.data.graph
        try viewGraph.data.withCurrent {
            var inputs = makeViewInputs(graph: graph)
            inputs.makeRootMatchedGeometryScope()
            let scope = try XCTUnwrap(
                inputs.base.customInputs.value(forKey: MatchedGeometryScope.self)
            )
            let key = AnyHashable(MatchedGeometryKeyForTest(
                id: "hero",
                namespace: Namespace().wrappedValue
            ))

            func makeRegistration(
                owner: AGAttribute,
                args: Attribute<MatchedGeometryArguments>,
                phase: Attribute<_GraphInputs.Phase>,
                transaction: Attribute<Transaction>,
                position: CGPoint,
                size: CGSize
            ) -> MatchedGeometryScope.ViewRegistration {
                var transform = ViewTransform()
                transform.appendPosition(position)
                return MatchedGeometryScope.ViewRegistration(
                    attribute: owner,
                    args: args,
                    transaction: transaction,
                    phase: phase,
                    size: graph.makeInput(value: ViewSize(size)),
                    position: graph.makeInput(value: position),
                    transform: graph.makeInput(value: transform)
                )
            }

            let firstOwner = graph.makeInput(value: true)
            let firstArgs: Attribute<MatchedGeometryArguments> = graph.makeInput(value: (
                properties: .frame,
                anchor: .center,
                isSource: true
            ))
            let firstPhase = graph.makeInput(value: _GraphInputs.Phase())
            let firstTransaction = graph.makeInput(value: Transaction())
            var firstIndex: Int?
            _ = scope.frame(
                index: &firstIndex,
                for: key,
                view: makeRegistration(
                    owner: firstOwner.identifier,
                    args: firstArgs,
                    phase: firstPhase,
                    transaction: firstTransaction,
                    position: CGPoint(x: 79, y: 137),
                    size: CGSize(width: 110, height: 78)
                )
            )
            let frameIndex = try XCTUnwrap(firstIndex)
            let sharedFrame = try XCTUnwrap(scope.frames[frameIndex].sharedFrame)
            XCTAssertNotNil(sharedFrame.value.frame)

            var removed = _GraphInputs.Phase()
            removed.isBeingRemoved = true
            firstPhase.setValue(removed)

            let secondOwner = graph.makeInput(value: true)
            let secondArgs: Attribute<MatchedGeometryArguments> = graph.makeInput(value: (
                properties: .frame,
                anchor: .center,
                isSource: true
            ))
            let secondPhase = graph.makeInput(value: _GraphInputs.Phase())
            let secondTransaction = graph.makeInput(
                value: Transaction(animation: .spring(duration: 2.0, bounce: 0.25))
            )
            var secondIndex: Int?
            _ = scope.frame(
                index: &secondIndex,
                for: key,
                view: makeRegistration(
                    owner: secondOwner.identifier,
                    args: secondArgs,
                    phase: secondPhase,
                    transaction: secondTransaction,
                    position: CGPoint(x: 426, y: 137),
                    size: CGSize(width: 230, height: 130)
                )
            )
            XCTAssertEqual(secondIndex, firstIndex)
            XCTAssertNotNil(sharedFrame.value.frame)

            inputs.base.time.setValue(Time(seconds: 0.45))
            XCTAssertNotNil(sharedFrame.value.frame)

            secondArgs.setValue((properties: .frame, anchor: .center, isSource: false))
            XCTAssertNotNil(
                sharedFrame.value.frame,
                "an active last-source registration keeps the in-flight animator alive"
            )

            firstArgs.setValue((properties: .frame, anchor: .center, isSource: false))
            firstPhase.setValue(_GraphInputs.Phase())
            secondPhase.setValue(removed)
            XCTAssertNil(
                sharedFrame.value.frame,
                "a retained-removal last source must not carry the shared animator"
            )
        }
    }

    // ASSERTIONS matchedGeometryMidflightRetainedRegistrationReinsertObserved
    // ASSERTIONS matchedGeometryMidflightIncomingFrameAnimationObserved
    // ASSERTIONS matchedGeometryMidflightActivationTransactionObserved
    // ASSERTIONS dynamicViewItemUnmanagedInvalidationObserved
    @MainActor
    func testMidflightSourceThenReverseSeparatesRetainedAndReinsertedPresentations() throws {
        let probe = MatchedGeometryNonSourceRuntimeProbe()
        let controller = WindowController(
            content: MatchedGeometryNonSourceRuntimeRoot(probe: probe),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(MatchedGeometryNonSourceRuntimeRoot.self)
            )
        )
        let withGC: WindowContext.WithGraphicsContext = { _, _ in }
        var tick: UInt64 = 0

        func update(_ time: Double) {
            controller.updateFrame(
                tick: tick,
                delta: time - controller.animationTimestamp.seconds,
                date: controller.date.addingTimeInterval(time),
                contentSize: CGSize(width: 700, height: 500),
                shouldDrawFrame: false,
                withGC
            )
            tick &+= 1
        }

        struct FrameSnapshot: CustomStringConvertible {
            var id: AGAttribute
            var frame: ViewFrame
            var target: ViewFrame
            var isBeingRemoved: Bool

            var description: String {
                "id=\(id) frame=\(frame) target=\(target) removed=\(isBeingRemoved)"
            }
        }

        func animatedFrames() -> [FrameSnapshot] {
            controller.viewGraph.data.withCurrent {
                let graph = controller.viewGraph.data.graph
                return probe.animatedFrameCapture.entries.values.compactMap { entry in
                    guard
                        let frame = graph.weakAttributeIfValid(for: entry.frame),
                        let position = graph.weakAttributeIfValid(for: entry.targetPosition),
                        let size = graph.weakAttributeIfValid(for: entry.targetSize),
                        let phase = graph.weakAttributeIfValid(for: entry.phase)
                    else {
                        return nil
                    }
                    return FrameSnapshot(
                        id: entry.frame,
                        frame: Attribute<ViewFrame>(frame.toStrong()).value,
                        target: ViewFrame(
                            origin: Attribute<CGPoint>(position.toStrong()).value,
                            size: Attribute<ViewSize>(size.toStrong()).value
                        ),
                        isBeingRemoved: Attribute<_GraphInputs.Phase>(phase.toStrong()).value.isBeingRemoved
                    )
                }
            }
        }

        update(0)
        try XCTUnwrap(probe.toggleLayout)()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        update(0)
        update(0.001)
        update(0.10)
        update(0.20)
        update(0.30)
        update(0.45)

        try XCTUnwrap(probe.toggleSource)()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        update(0.45)

        try XCTUnwrap(probe.toggleLayout)()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        update(0.45)

        let activation = animatedFrames()
        XCTAssertEqual(activation.count, 2, "\(activation)")
        let activationOrigin = try XCTUnwrap(activation.first).frame.origin
        for snapshot in activation {
            XCTAssertEqual(snapshot.frame.origin.x, activationOrigin.x, accuracy: 0.001, "\(activation)")
            XCTAssertEqual(snapshot.frame.origin.y, activationOrigin.y, accuracy: 0.001, "\(activation)")
        }
        XCTAssertEqual(Set(activation.map(\.target.origin.x)).count, 2, "\(activation)")
        XCTAssertLessThan(try XCTUnwrap(activation.map(\.target.origin.x).min()), activationOrigin.x)
        XCTAssertGreaterThan(try XCTUnwrap(activation.map(\.target.origin.x).max()), activationOrigin.x)

        update(0.46)
        update(0.47)
        update(0.55)
        update(0.75)
        let separated = animatedFrames()
        XCTAssertEqual(separated.count, 2)
        let horizontalSpan = try XCTUnwrap(separated.map(\.frame.origin.x).max())
            - XCTUnwrap(separated.map(\.frame.origin.x).min())
        XCTAssertGreaterThan(horizontalSpan, 20, "\(separated)")
        XCTAssertLessThan(try XCTUnwrap(separated.map(\.frame.origin.x).min()), activationOrigin.x)
        XCTAssertGreaterThan(try XCTUnwrap(separated.map(\.frame.origin.x).max()), activationOrigin.x)
    }

    private func recursiveTextFrames(
        in list: DisplayList,
        inheritedTransform: CGAffineTransform = .identity
    ) -> [CGRect] {
        list.items.reduce(into: []) { frames, item in
            let recordedBounds: CGRect?
            switch item.value {
            case let .content(content):
                recordedBounds = content.command.bounds
            case let .effect(_, contents):
                recordedBounds = contents.interpolationBounds
            case let .states(states):
                recordedBounds = states.last?.1.interpolationBounds
            case .empty:
                recordedBounds = nil
            }
            let itemTransform: CGAffineTransform
            if let recordedBounds, !recordedBounds.isNull {
                itemTransform = CGAffineTransform(
                    translationX: item.frame.minX - recordedBounds.minX,
                    y: item.frame.minY - recordedBounds.minY
                ).concatenating(inheritedTransform)
            } else {
                itemTransform = inheritedTransform
            }
            switch item.value {
            case let .content(content):
                if case .text = content.command {
                    frames.append(item.frame.applying(inheritedTransform).standardized)
                }
                switch content.value {
                case .text:
                    break
                case let .style(style):
                    frames.append(contentsOf: recursiveTextFrames(
                        in: style.contents,
                        inheritedTransform: style.transform.concatenating(itemTransform)
                    ))
                case let .crossFade(crossFade):
                    if let source = crossFade.source {
                        if let transform =
                            DisplayList.Content.CrossFadeValue.Branch
                                .interpolationTransform(
                                    from: source.sourceBounds,
                                    to: source.outputBounds
                                ) {
                            frames.append(contentsOf: recursiveTextFrames(
                                in: source.contents,
                                inheritedTransform: transform
                                    .concatenating(crossFade.transform)
                                    .concatenating(itemTransform)
                            ))
                        }
                    }
                    if let target = crossFade.target {
                        if let transform =
                            DisplayList.Content.CrossFadeValue.Branch
                                .interpolationTransform(
                                    from: target.sourceBounds,
                                    to: target.outputBounds
                                ) {
                            frames.append(contentsOf: recursiveTextFrames(
                                in: target.contents,
                                inheritedTransform: transform
                                    .concatenating(crossFade.transform)
                                    .concatenating(itemTransform)
                            ))
                        }
                    }
                case let .flattened(contents, origin, _):
                    frames.append(contentsOf: recursiveTextFrames(
                        in: contents,
                        inheritedTransform: CGAffineTransform(
                            translationX: origin.x,
                            y: origin.y
                        ).concatenating(itemTransform)
                    ))
                case let .drawing(contents, origin, _):
                    if let local = contents as? DisplayList.LocalContents {
                        frames.append(contentsOf: recursiveTextFrames(
                            in: local.list,
                            inheritedTransform: CGAffineTransform(
                                translationX: origin.x,
                                y: origin.y
                            ).concatenating(itemTransform)
                        ))
                    }
                case .backend, .color, .shape, .image:
                    break
                }
            case let .effect(effect, contents):
                let effectTransform: CGAffineTransform
                if case let .transform(transform) = effect,
                   transform.isAffine {
                    effectTransform = CGAffineTransform(
                        a: transform.m11,
                        b: transform.m12,
                        c: transform.m21,
                        d: transform.m22,
                        tx: transform.m31,
                        ty: transform.m32
                    ).concatenating(itemTransform)
                } else {
                    effectTransform = itemTransform
                }
                frames.append(contentsOf: recursiveTextFrames(
                    in: contents,
                    inheritedTransform: effectTransform
                ))
            case let .states(states):
                for (_, contents) in states {
                    frames.append(contentsOf: recursiveTextFrames(
                        in: contents,
                        inheritedTransform: itemTransform
                    ))
                }
            case .empty:
                break
            }
        }
    }

    private func resolvedTextSamples(
        in displayList: DisplayList,
        inheritedOpacity: Double = 1,
        inheritedTransform: CGAffineTransform = .identity
    ) -> [MatchedGeometryResolvedTextSample] {
        displayList.items.reduce(into: []) { samples, item in
            let itemOpacity = inheritedOpacity * Double(item.opacity)
            let recordedBounds: CGRect?
            switch item.value {
            case let .content(content):
                recordedBounds = content.command.bounds
            case let .effect(_, contents):
                recordedBounds = contents.interpolationBounds
            case let .states(states):
                recordedBounds = states.last?.1.interpolationBounds
            case .empty:
                recordedBounds = nil
            }
            let itemTransform: CGAffineTransform
            if let recordedBounds, !recordedBounds.isNull {
                itemTransform = CGAffineTransform(
                    translationX: item.frame.minX - recordedBounds.minX,
                    y: item.frame.minY - recordedBounds.minY
                ).concatenating(inheritedTransform)
            } else {
                itemTransform = inheritedTransform
            }
            switch item.value {
            case let .content(content):
                if case let .text(text) = content.value,
                   let string = text.view.text.storage?.string {
                    samples.append(MatchedGeometryResolvedTextSample(
                        string: string,
                        frame: text.frame.applying(
                            text.transform.concatenating(itemTransform)
                        ).standardized,
                        opacity: itemOpacity
                    ))
                }
                switch content.value {
                case let .style(style):
                    let styleOpacity: Double
                    if case let .opacity(opacity) = style.style {
                        styleOpacity = opacity
                    } else {
                        styleOpacity = 1
                    }
                    samples.append(contentsOf: resolvedTextSamples(
                        in: style.contents,
                        inheritedOpacity: itemOpacity * styleOpacity,
                        inheritedTransform: style.transform.concatenating(
                            itemTransform
                        )
                    ))
                case let .crossFade(crossFade):
                    let sourceOpacity: Double
                    let targetOpacity: Double
                    if case let .effect(
                        .crossFade(sourceFraction, targetFraction),
                        _
                    ) = crossFade.command {
                        sourceOpacity = 1 - Double(sourceFraction)
                        targetOpacity = Double(targetFraction)
                    } else {
                        sourceOpacity = 1
                        targetOpacity = 1
                    }
                    if let source = crossFade.source {
                        if let branchTransform =
                            DisplayList.Content.CrossFadeValue.Branch
                                .interpolationTransform(
                                    from: source.sourceBounds,
                                    to: source.outputBounds
                                ) {
                            samples.append(contentsOf: resolvedTextSamples(
                                in: source.contents,
                                inheritedOpacity:
                                    itemOpacity * sourceOpacity,
                                inheritedTransform: branchTransform
                                    .concatenating(crossFade.transform)
                                    .concatenating(itemTransform)
                            ))
                        }
                    }
                    if let target = crossFade.target {
                        if let branchTransform =
                            DisplayList.Content.CrossFadeValue.Branch
                                .interpolationTransform(
                                    from: target.sourceBounds,
                                    to: target.outputBounds
                                ) {
                            samples.append(contentsOf: resolvedTextSamples(
                                in: target.contents,
                                inheritedOpacity:
                                    itemOpacity * targetOpacity,
                                inheritedTransform: branchTransform
                                    .concatenating(crossFade.transform)
                                    .concatenating(itemTransform)
                            ))
                        }
                    }
                case let .flattened(contents, origin, _):
                    samples.append(contentsOf: resolvedTextSamples(
                        in: contents,
                        inheritedOpacity: itemOpacity,
                        inheritedTransform: CGAffineTransform(
                            translationX: origin.x,
                            y: origin.y
                        ).concatenating(itemTransform)
                    ))
                case let .drawing(contents, origin, _):
                    if let local = contents as? DisplayList.LocalContents {
                        samples.append(contentsOf: resolvedTextSamples(
                            in: local.list,
                            inheritedOpacity: itemOpacity,
                            inheritedTransform: CGAffineTransform(
                                translationX: origin.x,
                                y: origin.y
                            ).concatenating(itemTransform)
                        ))
                    }
                case .backend, .color, .shape, .image, .text:
                    break
                }
            case let .effect(effect, contents):
                let effectOpacity: Double
                let effectTransform: CGAffineTransform
                if case let .opacity(opacity) = effect {
                    effectOpacity = Double(opacity)
                } else {
                    effectOpacity = 1
                }
                if case let .transform(transform) = effect,
                   transform.isAffine {
                    effectTransform = CGAffineTransform(
                        a: transform.m11,
                        b: transform.m12,
                        c: transform.m21,
                        d: transform.m22,
                        tx: transform.m31,
                        ty: transform.m32
                    ).concatenating(itemTransform)
                } else {
                    effectTransform = itemTransform
                }
                samples.append(contentsOf: resolvedTextSamples(
                    in: contents,
                    inheritedOpacity: itemOpacity * effectOpacity,
                    inheritedTransform: effectTransform
                ))
            case let .states(states):
                if let contents = states.last?.1 {
                    samples.append(contentsOf: resolvedTextSamples(
                        in: contents,
                        inheritedOpacity: itemOpacity,
                        inheritedTransform: itemTransform
                    ))
                }
            case .empty:
                break
            }
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
        phase: Attribute<_GraphInputs.Phase>? = nil
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
            phase: phase ?? graph.makeInput(value: _GraphInputs.Phase()),
            size: graph.makeInput(value: ViewSize(size)),
            position: graph.makeInput(value: position),
            transform: graph.makeInput(value: transform)
        )
    }

    private func makeViewInputs(graph: _AGGraph) -> _ViewInputs {
        let environment = graph.makeInput(value: EnvironmentValues())
        return _ViewInputs(
            base: _GraphInputs(
                time: graph.makeInput(value: Time(seconds: 0)),
                phase: graph.makeInput(value: _GraphInputs.Phase()),
                environment: environment,
                transaction: graph.makeInput(value: Transaction())
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

private final class MatchedGeometryReplacementRuntimeProbe {
    var setStage: ((Int, Transaction) -> Void)?
}

private struct MatchedGeometryReplacementRuntimeRoot: View {
    let probe: MatchedGeometryReplacementRuntimeProbe

    @Namespace private var namespace
    @State private var stage = 0

    var body: some View {
        probe.setStage = { nextStage, transaction in
            withTransaction(transaction) {
                stage = nextStage
            }
        }
        return ZStack(alignment: .topLeading) {
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

    private func matchedBox(
        size: CGSize,
        position: CGPoint
    ) -> some View {
        Rectangle()
            .fill(Color.red)
            .frame(width: size.width, height: size.height)
            .matchedGeometryEffect(id: "hero", in: namespace, properties: .frame)
            .offset(x: position.x, y: position.y)
    }
}

private final class MatchedGeometryTextRuntimeProbe {
    var toggle: (() -> Void)?
}

private final class MatchedGeometryNonSourceRuntimeProbe {
    var toggleSource: (() -> Void)?
    var toggleLayout: (() -> Void)?
    let animatedFrameCapture = MatchedGeometryAnimatedFrameCapture()
}

private struct MatchedGeometryNonSourceRuntimeRoot: View {
    let probe: MatchedGeometryNonSourceRuntimeProbe

    @Namespace private var namespace
    @State private var expanded = false
    @State private var alternateSource = false

    var body: some View {
        probe.toggleSource = {
            withAnimation(.easeInOut(duration: 1.2)) {
                alternateSource.toggle()
            }
        }
        probe.toggleLayout = {
            withAnimation(.spring(duration: 2.0, bounce: 0.25)) {
                expanded.toggle()
            }
        }
        return ZStack {
            if expanded {
                HStack {
                    Spacer()
                    card
                        .frame(width: 230, height: 130)
                }
                .padding(24)
            } else {
                HStack {
                    card
                        .frame(width: 110, height: 78)
                    Spacer()
                }
                .padding(24)
            }
        }
        .frame(width: 560, height: 210)
    }

    private var card: some View {
        RoundedRectangle(cornerRadius: expanded ? 30 : 12)
            .fill(Color.indigo)
            .overlay {
                MatchedGeometryTextDisplayProbe(
                    animatedFrameCapture: probe.animatedFrameCapture
                )
            }
            .matchedGeometryEffect(
                id: "matched-card",
                in: namespace,
                properties: .frame,
                isSource: !alternateSource
            )
    }
}

private struct MatchedGeometryTextRuntimeRoot: View {
    let probe: MatchedGeometryTextRuntimeProbe

    @Namespace private var namespace
    @State private var expanded = false

    var body: some View {
        probe.toggle = {
            withAnimation(.spring(duration: 2.0, bounce: 0.25)) {
                expanded.toggle()
            }
        }
        return ZStack {
            if expanded {
                HStack {
                    Spacer()
                    card
                        .frame(width: 230, height: 130)
                }
                .padding(24)
            } else {
                HStack {
                    card
                        .frame(width: 110, height: 78)
                    Spacer()
                }
                .padding(24)
            }
        }
        .frame(width: 560, height: 210)
    }

    private var card: some View {
        RoundedRectangle(cornerRadius: expanded ? 30 : 12)
            .fill(Color.indigo)
            .overlay {
                MatchedGeometryTextDisplayProbe(
                    foreground: expanded ? .green : .red
                )
            }
            .matchedGeometryEffect(
                id: "matched-card",
                in: namespace,
                properties: .frame
            )
    }
}

private struct MatchedGeometryResolvedTextRuntimeRoot: View {
    let probe: MatchedGeometryTextRuntimeProbe
    let font: VUI.Font

    @Namespace private var namespace
    @State private var expanded = false

    var body: some View {
        probe.toggle = {
            withAnimation(.spring(duration: 2.0, bounce: 0.25)) {
                expanded.toggle()
            }
        }
        return ZStack {
            if expanded {
                HStack {
                    Spacer()
                    card
                        .frame(width: 230, height: 130)
                }
                .padding(24)
            } else {
                HStack {
                    card
                        .frame(width: 110, height: 78)
                    Spacer()
                }
                .padding(24)
            }
        }
        .frame(width: 560, height: 210)
    }

    private var card: some View {
        RoundedRectangle(cornerRadius: expanded ? 30 : 12)
            .fill(Color.indigo)
            .overlay {
                Text(expanded ? "Destination" : "Source")
                    .font(font)
                    .foregroundColor(
                        expanded
                            ? Color(red: 0, green: 1, blue: 0)
                            : Color(red: 1, green: 0, blue: 0)
                    )
            }
            .matchedGeometryEffect(
                id: "matched-card",
                in: namespace,
                properties: .frame
            )
    }
}

private struct MatchedGeometryResolvedTextSample {
    var string: String
    var frame: CGRect
    var opacity: Double
}

private final class MatchedGeometryAppContext: AppContext {
    let graphicsDeviceContext: GraphicsDeviceContext?
    let audioDeviceContext: AudioDeviceContext? = nil
    var appWindowsController: AppWindowsController? { nil }
    private var resources: [URL: any DataProtocol] = [:]

    init(graphicsDeviceContext: GraphicsDeviceContext) {
        self.graphicsDeviceContext = graphicsDeviceContext
    }

    func resourceData(forURL url: URL) -> (any DataProtocol)? {
        resources[url]
    }

    func setResource(data: (any DataProtocol)?, forURL url: URL) {
        resources[url] = data
    }
}
