import XCTest
@testable import VUI

final class SystemScrollViewHostTests: XCTestCase {
    func testHostingScrollViewAppliesBounceRoleAndSpringsBackFromOverscroll() {
        func makeHost(
            behavior: ScrollBounceBehavior
        ) -> (_AGGraph, Attribute<SystemScrollLayoutState>, Attribute<ScrollPhaseState>, HostingScrollView) {
            let graph = _AGGraph()
            let graphRef = _AGGraphContext(graph: graph)
            return _AGGraph.withCurrent(graph) {
                let state = graph.makeInput(value: SystemScrollLayoutState())
                let phase = graph.makeInput(value: ScrollPhaseState())
                let host = HostingScrollView(
                    graphRef: graphRef,
                    layoutState: state.asWeak(),
                    phaseState: phase.asWeak()
                )
                host.updateConfiguration(ScrollViewConfiguration(axes: .vertical))
                var properties = ScrollEnvironmentProperties()
                properties.verticalBounceBehavior = behavior.role
                host.updateProperties(properties)
                _ = host.updateContext(HostingScrollViewUpdateContext(
                    contentOffset: .zero,
                    contentFrame: CGRect(x: 0, y: 0, width: 100, height: 70),
                    containingSize: CGSize(width: 100, height: 100),
                    offsetMode: .system,
                    safeInsets: EdgeInsets()
                ))
                return (graph, state, phase, host)
            }
        }

        let (automaticGraph, automaticState, automaticPhase, automaticHost) = makeHost(
            behavior: .automatic
        )
        _AGGraph.withCurrent(automaticGraph) {
            let active = PanGesture.Value(
                timestamp: Time(seconds: 1),
                translation: CGSize(width: 0, height: 40),
                touchType: .indirect,
                velocity: _Velocity(valuePerSecond: .zero)
            )
            automaticHost.dispatchScrollGesturePhase(.active(.pan(active)))
            XCTAssertEqual(
                automaticState.value.contentOffset.y,
                -3.846153846153843,
                accuracy: 0.0000000001
            )
            XCTAssertEqual(automaticPhase.value.phase, .interacting)

            automaticHost.dispatchScrollGesturePhase(.ended(.pan(active)))
            XCTAssertTrue(automaticHost.isDecelerating)
            XCTAssertEqual(automaticPhase.value.phase, .decelerating)
            XCTAssertTrue(automaticHost.updateMotion(at: Time(seconds: 1)))
            XCTAssertTrue(automaticHost.updateMotion(at: Time(seconds: 1.5)))
            XCTAssertEqual(automaticState.value.contentOffset.y, 0, accuracy: 0.0000000001)
            XCTAssertEqual(automaticPhase.value.phase, .idle)
        }

        let (sizedGraph, sizedState, sizedPhase, sizedHost) = makeHost(
            behavior: .basedOnSize
        )
        _AGGraph.withCurrent(sizedGraph) {
            sizedHost.dispatchScrollGesturePhase(.active(.pan(PanGesture.Value(
                timestamp: Time(seconds: 1),
                translation: CGSize(width: 0, height: 40),
                touchType: .indirect,
                velocity: _Velocity(valuePerSecond: .zero)
            ))))
            XCTAssertEqual(sizedState.value.contentOffset, .zero)
            XCTAssertEqual(sizedPhase.value.phase, .tracking)
        }
    }

    func testHostingScrollViewConsumesPanIntoSystemOffsetAndPhase() {
        let graph = _AGGraph()
        let graphRef = _AGGraphContext(graph: graph)

        _AGGraph.withCurrent(graph) {
            let state = graph.makeInput(value: SystemScrollLayoutState(
                contentOffset: CGPoint(x: 0, y: 20)
            ))
            let phase = graph.makeInput(value: ScrollPhaseState())
            let host = HostingScrollView(
                graphRef: graphRef,
                layoutState: state.asWeak(),
                phaseState: phase.asWeak()
            )
            host.updateConfiguration(ScrollViewConfiguration(axes: .vertical))
            _ = host.updateContext(HostingScrollViewUpdateContext(
                contentOffset: state.value.contentOffset,
                contentFrame: CGRect(x: 0, y: 0, width: 100, height: 400),
                containingSize: CGSize(width: 100, height: 100),
                offsetMode: .system,
                safeInsets: EdgeInsets()
            ))

            host.dispatchScrollGesturePhase(.active(.pan(PanGesture.Value(
                timestamp: Time(seconds: 1),
                translation: CGSize(width: 0, height: -30),
                touchType: .indirect,
                velocity: _Velocity(valuePerSecond: CGSize(width: 0, height: -300))
            ))))

            XCTAssertEqual(state.value.contentOffset, CGPoint(x: 0, y: 50))
            XCTAssertEqual(state.value.contentOffsetMode, .system)
            XCTAssertEqual(phase.value.phase, .interacting)
            XCTAssertEqual(phase.value.velocity, CGVector(dx: 0, dy: -300))

            host.dispatchScrollGesturePhase(.ended(.pan(PanGesture.Value(
                timestamp: Time(seconds: 1.1),
                translation: CGSize(width: 0, height: -30),
                touchType: .indirect,
                velocity: _Velocity(valuePerSecond: CGSize(width: 0, height: -300))
            ))))

            XCTAssertEqual(state.value.contentOffset, CGPoint(x: 0, y: 50))
            XCTAssertEqual(phase.value.phase, .decelerating)
            XCTAssertEqual(phase.value.velocity, CGVector(dx: 0, dy: 300))
            XCTAssertTrue(host.updateMotion(at: Time(seconds: 1.1)))
            XCTAssertTrue(host.updateMotion(at: Time(seconds: 1.2)))
            XCTAssertGreaterThan(state.value.contentOffset.y, 50)
        }
    }

    func testHostingScrollViewResolvesTerminalOffsetThroughScrollTargetBehavior() {
        let graph = _AGGraph()
        let graphRef = _AGGraphContext(graph: graph)

        _AGGraph.withCurrent(graph) {
            let state = graph.makeInput(value: SystemScrollLayoutState(
                contentOffset: CGPoint(x: 0, y: 50)
            ))
            let phase = graph.makeInput(value: ScrollPhaseState())
            let recorder = HostScrollTargetBehaviorRecorder()
            let host = HostingScrollView(
                graphRef: graphRef,
                layoutState: state.asWeak(),
                phaseState: phase.asWeak()
            )
            host.updateConfiguration(ScrollViewConfiguration(axes: .vertical))
            var properties = ScrollEnvironmentProperties()
            properties.decelerationRate = .viewAligned
            properties.scrollBehavior = ResolvedScrollBehavior(
                base: HostRecordingScrollTargetBehavior(
                    recorder: recorder,
                    targetOrigin: CGPoint(x: 10, y: 190)
                ),
                axes: .vertical
            )
            host.updateProperties(properties)
            _ = host.updateContext(HostingScrollViewUpdateContext(
                contentOffset: state.value.contentOffset,
                contentFrame: CGRect(x: 0, y: 0, width: 100, height: 500),
                containingSize: CGSize(width: 100, height: 100),
                offsetMode: .system,
                safeInsets: EdgeInsets(top: 10, leading: 10, bottom: 0, trailing: 0)
            ))

            let pan = PanGesture.Value(
                timestamp: Time(seconds: 1),
                translation: CGSize(width: 0, height: -10),
                touchType: .indirect,
                velocity: _Velocity(valuePerSecond: CGSize(width: 0, height: -300))
            )
            host.dispatchScrollGesturePhase(.active(.pan(pan)))
            host.dispatchScrollGesturePhase(.ended(.pan(pan)))

            XCTAssertTrue(host.isDecelerating)
            XCTAssertEqual(recorder.originalTarget?.rect.origin, CGPoint(x: 10, y: 60))
            XCTAssertEqual(recorder.originalTarget?.rect.size, CGSize(width: 100, height: 100))
            XCTAssertEqual(recorder.proposedTarget?.rect.size, CGSize(width: 100, height: 100))
            XCTAssertGreaterThan(recorder.proposedTarget?.rect.minY ?? 0, 70)
            XCTAssertEqual(recorder.velocity, CGVector(dx: 0, dy: 300))
            XCTAssertEqual(recorder.geometry?.contentOffset, CGPoint(x: 0, y: 60))
            XCTAssertEqual(recorder.geometry?.contentInsets.top, 10)
            XCTAssertEqual(recorder.axes, .vertical)
            XCTAssertEqual(recorder.decelerationRate, .viewAligned)

            XCTAssertTrue(host.updateMotion(at: Time(seconds: 1)))
            XCTAssertTrue(host.updateMotion(at: Time(seconds: 4)))
            XCTAssertFalse(host.isDecelerating)
            XCTAssertEqual(state.value.contentOffset, CGPoint(x: 0, y: 180))
            XCTAssertEqual(phase.value.phase, .idle)
        }
    }

    func testHostingScrollViewStartsTargetedMotionAfterZeroVelocityDrag() {
        let graph = _AGGraph()
        let graphRef = _AGGraphContext(graph: graph)

        _AGGraph.withCurrent(graph) {
            let state = graph.makeInput(value: SystemScrollLayoutState(
                contentOffset: CGPoint(x: 0, y: 50)
            ))
            let host = HostingScrollView(
                graphRef: graphRef,
                layoutState: state.asWeak()
            )
            host.updateConfiguration(ScrollViewConfiguration(axes: .vertical))
            var properties = ScrollEnvironmentProperties()
            properties.scrollBehavior = ResolvedScrollBehavior(
                base: HostRecordingScrollTargetBehavior(
                    recorder: HostScrollTargetBehaviorRecorder(),
                    targetOrigin: CGPoint(x: 0, y: 180)
                ),
                axes: .vertical
            )
            host.updateProperties(properties)
            _ = host.updateContext(HostingScrollViewUpdateContext(
                contentOffset: state.value.contentOffset,
                contentFrame: CGRect(x: 0, y: 0, width: 100, height: 500),
                containingSize: CGSize(width: 100, height: 100),
                offsetMode: .system,
                safeInsets: EdgeInsets()
            ))

            let pan = PanGesture.Value(
                timestamp: Time(seconds: 1),
                translation: CGSize(width: 0, height: -10),
                touchType: .indirect,
                velocity: _Velocity(valuePerSecond: .zero)
            )
            host.dispatchScrollGesturePhase(.active(.pan(pan)))
            host.dispatchScrollGesturePhase(.ended(.pan(pan)))

            XCTAssertTrue(host.isDecelerating)
            XCTAssertTrue(host.updateMotion(at: Time(seconds: 1)))
            XCTAssertTrue(host.updateMotion(at: Time(seconds: 4)))
            XCTAssertFalse(host.isDecelerating)
            XCTAssertEqual(state.value.contentOffset, CGPoint(x: 0, y: 180))
        }
    }

    func testHostingScrollViewRetargetsActiveBehaviorAfterLayoutUpdate() {
        let graph = _AGGraph()
        let graphRef = _AGGraphContext(graph: graph)

        _AGGraph.withCurrent(graph) {
            let state = graph.makeInput(value: SystemScrollLayoutState(
                contentOffset: CGPoint(x: 0, y: 50)
            ))
            let recorder = HostScrollTargetBehaviorRecorder()
            let host = HostingScrollView(
                graphRef: graphRef,
                layoutState: state.asWeak()
            )
            host.updateConfiguration(ScrollViewConfiguration(axes: .vertical))
            var properties = ScrollEnvironmentProperties()
            properties.scrollBehavior = ResolvedScrollBehavior(
                base: HostRecordingScrollTargetBehavior(
                    recorder: recorder,
                    targetOrigin: CGPoint(x: 0, y: 180)
                ),
                axes: .vertical
            )
            host.updateProperties(properties)
            let context = HostingScrollViewUpdateContext(
                contentOffset: state.value.contentOffset,
                contentFrame: CGRect(x: 0, y: 0, width: 100, height: 500),
                containingSize: CGSize(width: 100, height: 100),
                offsetMode: .system,
                safeInsets: EdgeInsets()
            )
            _ = host.updateContext(context)

            let pan = PanGesture.Value(
                timestamp: Time(seconds: 1),
                translation: CGSize(width: 0, height: -10),
                touchType: .indirect,
                velocity: _Velocity(valuePerSecond: CGSize(width: 0, height: -300))
            )
            host.dispatchScrollGesturePhase(.active(.pan(pan)))
            host.dispatchScrollGesturePhase(.ended(.pan(pan)))
            XCTAssertEqual(recorder.invocationCount, 1)

            recorder.overrideTargetOrigin = CGPoint(x: 0, y: 260)
            _ = host.updateContext(HostingScrollViewUpdateContext(
                contentOffset: state.value.contentOffset,
                contentFrame: context.contentFrame,
                containingSize: context.containingSize,
                offsetMode: .system,
                safeInsets: context.safeInsets
            ))
            XCTAssertEqual(recorder.invocationCount, 2)

            XCTAssertTrue(host.updateMotion(at: Time(seconds: 1)))
            XCTAssertTrue(host.updateMotion(at: Time(seconds: 4)))
            XCTAssertFalse(host.isDecelerating)
            XCTAssertEqual(state.value.contentOffset, CGPoint(x: 0, y: 260))
        }
    }

    func testHostingScrollViewTargetUpdateHonorsVelocityPreservation() {
        let graph = _AGGraph()
        let graphRef = _AGGraphContext(graph: graph)

        _AGGraph.withCurrent(graph) {
            let state = graph.makeInput(value: SystemScrollLayoutState(
                contentOffset: CGPoint(x: 0, y: 50)
            ))
            let phase = graph.makeInput(value: ScrollPhaseState())
            let host = HostingScrollView(
                graphRef: graphRef,
                layoutState: state.asWeak(),
                phaseState: phase.asWeak()
            )
            host.updateConfiguration(ScrollViewConfiguration(axes: .vertical))
            let context = HostingScrollViewUpdateContext(
                contentOffset: state.value.contentOffset,
                contentFrame: CGRect(x: 0, y: 0, width: 100, height: 500),
                containingSize: CGSize(width: 100, height: 100),
                offsetMode: .system,
                safeInsets: EdgeInsets()
            )
            _ = host.updateContext(context)
            let pan = PanGesture.Value(
                timestamp: Time(seconds: 1),
                translation: CGSize(width: 0, height: -20),
                touchType: .indirect,
                velocity: _Velocity(valuePerSecond: CGSize(width: 0, height: -240))
            )
            host.dispatchScrollGesturePhase(.active(.pan(pan)))
            host.dispatchScrollGesturePhase(.ended(.pan(pan)))
            XCTAssertTrue(host.isDecelerating)
            let preservedVelocity = host.currentMotionVelocity

            _ = host.updateContext(HostingScrollViewUpdateContext(
                contentOffset: state.value.contentOffset,
                contentFrame: context.contentFrame,
                containingSize: context.containingSize,
                offsetMode: .target(
                    { _, _ in ScrollTarget(rect: CGRect(x: 0, y: 220, width: 100, height: 40)) },
                    config: ScrollTargetConfiguration(preservesVelocity: true)
                ),
                safeInsets: context.safeInsets
            ))
            XCTAssertTrue(host.isDecelerating)
            XCTAssertEqual(host.currentMotionVelocity, preservedVelocity)

            _ = host.updateContext(HostingScrollViewUpdateContext(
                contentOffset: state.value.contentOffset,
                contentFrame: context.contentFrame,
                containingSize: context.containingSize,
                offsetMode: .target(
                    { _, _ in ScrollTarget(rect: CGRect(x: 0, y: 40, width: 100, height: 40)) },
                    config: ScrollTargetConfiguration(preservesVelocity: false)
                ),
                safeInsets: context.safeInsets
            ))
            XCTAssertFalse(host.isDecelerating)
            XCTAssertEqual(host.currentMotionVelocity.valuePerSecond, .zero)
        }
    }

    func testContentOffsetAdjustmentReasonMatchesProbedCases() {
        func name(_ reason: ContentOffsetAdjustmentReason) -> String {
            switch reason {
            case .translation: "translation"
            case .positionTranslation: "positionTranslation"
            case .alignment: "alignment"
            case .reset: "reset"
            case .resetPosition: "resetPosition"
            }
        }

        XCTAssertEqual(
            [
                .translation,
                .positionTranslation,
                .alignment,
                .reset,
                .resetPosition,
            ].map(name),
            [
                "translation",
                "positionTranslation",
                "alignment",
                "reset",
                "resetPosition",
            ]
        )
    }

    func testSystemScrollLayoutStateMergesOffsetModeAndReasonSeeds() {
        var adjustment = SystemScrollLayoutState(contentOffsetSeed: VersionSeed(value: 7))
        adjustment.updateContentOffset(mode: .adjustment(reason: .reset), updateSeed: 4)
        XCTAssertEqual(adjustment.contentOffsetMode, .adjustment(reason: .reset))
        XCTAssertEqual(adjustment.contentOffsetSeed, VersionSeed(value: 2_340_873_906))

        var target = SystemScrollLayoutState(contentOffsetSeed: VersionSeed(value: 7))
        target.updateContentOffset(mode: .target(nil, config: ScrollTargetConfiguration()), updateSeed: 4)
        XCTAssertEqual(target.contentOffsetSeed, VersionSeed(value: 186_384_208))

        var system = SystemScrollLayoutState()
        system.updateContentOffset(mode: .system, updateSeed: 9)
        XCTAssertEqual(system.contentOffsetSeed, VersionSeed(value: 9))

        var invalid = SystemScrollLayoutState(contentOffsetSeed: VersionSeed(value: .max))
        invalid.updateContentOffset(mode: .adjustment(reason: .alignment), updateSeed: 2)
        XCTAssertEqual(invalid.contentOffsetSeed, VersionSeed(value: .max))
    }

    func testScrollTargetConfigurationCopiesObservedTransactionValues() {
        var transaction = Transaction(animation: .linear(duration: 1))
        transaction.scrollToRequiresCompleteVisibility = true
        transaction.scrollPositionUpdatePreservesVelocity = true

        XCTAssertEqual(
            ScrollTargetConfiguration(transaction: transaction),
            ScrollTargetConfiguration(
                animation: .linear(duration: 1),
                requiresVisibility: true,
                preservesVelocity: true
            )
        )

        var disabled = transaction
        disabled.disablesAnimations = true
        XCTAssertNil(ScrollTargetConfiguration(transaction: disabled).animation)
        XCTAssertTrue(ScrollTargetConfiguration(transaction: disabled).requiresVisibility)
        XCTAssertTrue(ScrollTargetConfiguration(transaction: disabled).preservesVelocity)
    }

    func testScrollViewAnimationOffsetMatchesObservedVisibilityAndClampRows() {
        let viewport = CGRect(x: 100, y: 100, width: 200, height: 200)
        let content = CGRect(x: 0, y: 0, width: 1_000, height: 1_000)

        func offset(
            _ target: CGRect,
            anchor: UnitPoint? = nil,
            requiresVisibility: Bool = false,
            contentFrame: CGRect? = nil
        ) -> CGPoint {
            ScrollViewUtilities.animationOffset(
                targetFrame: target,
                anchor: anchor,
                viewPortFrame: viewport,
                contentFrame: contentFrame ?? content,
                requiresVisibility: requiresVisibility
            )
        }

        let anchoredTarget = CGRect(x: 350, y: 450, width: 100, height: 80)
        XCTAssertEqual(offset(anchoredTarget, anchor: .topLeading), CGPoint(x: 350, y: 450))
        XCTAssertEqual(offset(anchoredTarget, anchor: .center), CGPoint(x: 300, y: 390))
        XCTAssertEqual(offset(anchoredTarget, anchor: .bottomTrailing), CGPoint(x: 250, y: 330))

        XCTAssertEqual(
            offset(CGRect(x: 150, y: 150, width: 50, height: 50)),
            CGPoint(x: 100, y: 100)
        )
        XCTAssertEqual(
            offset(CGRect(x: 150, y: 150, width: 50, height: 50), requiresVisibility: true),
            CGPoint(x: 100, y: 100)
        )
        XCTAssertEqual(
            offset(CGRect(x: 250, y: 150, width: 100, height: 50)),
            CGPoint(x: 100, y: 100)
        )
        XCTAssertEqual(
            offset(
                CGRect(x: 250, y: 150, width: 100, height: 50),
                requiresVisibility: true
            ),
            CGPoint(x: 150, y: 100)
        )
        XCTAssertEqual(
            offset(
                CGRect(x: 50, y: 150, width: 100, height: 50),
                requiresVisibility: true
            ),
            CGPoint(x: 50, y: 100)
        )
        XCTAssertEqual(
            offset(
                CGRect(x: 150, y: 250, width: 50, height: 100),
                requiresVisibility: true
            ),
            CGPoint(x: 100, y: 150)
        )
        XCTAssertEqual(
            offset(CGRect(x: 350, y: 150, width: 50, height: 50)),
            CGPoint(x: 200, y: 100)
        )
        XCTAssertEqual(
            offset(
                CGRect(x: 350, y: 150, width: 50, height: 50),
                requiresVisibility: true
            ),
            CGPoint(x: 200, y: 100)
        )
        XCTAssertEqual(
            offset(
                CGRect(x: 20, y: 30, width: 40, height: 40),
                requiresVisibility: true
            ),
            CGPoint(x: 20, y: 30)
        )
        XCTAssertEqual(
            offset(CGRect(x: 300, y: 150, width: 50, height: 50)),
            CGPoint(x: 150, y: 100)
        )
        XCTAssertEqual(
            offset(
                CGRect(x: 300, y: 150, width: 50, height: 50),
                requiresVisibility: true
            ),
            CGPoint(x: 150, y: 100)
        )
        XCTAssertEqual(
            offset(CGRect(x: 50, y: 150, width: 400, height: 50)),
            CGPoint(x: 100, y: 100)
        )
        XCTAssertEqual(
            offset(
                CGRect(x: 50, y: 150, width: 400, height: 50),
                requiresVisibility: true
            ),
            CGPoint(x: 100, y: 100)
        )
        XCTAssertEqual(
            offset(
                CGRect(x: 350, y: 150, width: 400, height: 50),
                requiresVisibility: true
            ),
            CGPoint(x: 350, y: 100)
        )
        XCTAssertEqual(
            offset(
                CGRect(x: -400, y: 150, width: 400, height: 50),
                requiresVisibility: true,
                contentFrame: CGRect(x: -500, y: 0, width: 1_500, height: 1_000)
            ),
            CGPoint(x: -200, y: 100)
        )
        XCTAssertEqual(
            offset(
                CGRect(x: -100, y: -80, width: 20, height: 20),
                anchor: .center,
                contentFrame: CGRect(x: 25, y: 35, width: 500, height: 600)
            ),
            CGPoint(x: 25, y: 35)
        )
    }

    func testScrollAnchorStorageUsesRoleDefaultAndRightToLeftAdjustment() {
        var anchors = ScrollAnchorStorage(defaultValue: .center)
        XCTAssertTrue(ScrollAnchorStorage().isEmpty)
        XCTAssertFalse(anchors.isEmpty)
        XCTAssertEqual(anchors.initialOffset, .center)
        XCTAssertEqual(anchors.sizeChanges, .center)
        XCTAssertEqual(anchors.alignment, .center)

        anchors.anchors[.initialOffset] = UnitPoint(x: 0.25, y: 0.75)
        XCTAssertEqual(
            anchors.adjustedAnchor(role: .initialOffset, layoutDirection: .leftToRight),
            UnitPoint(x: 0.25, y: 0.75)
        )
        XCTAssertEqual(
            anchors.adjustedAnchor(role: .initialOffset, layoutDirection: .rightToLeft),
            UnitPoint(x: 0.75, y: 0.75)
        )
        XCTAssertEqual(anchors.sizeChanges, .center)
    }

    func testAdjustedStateInitialOffsetUsesAnchorPerActiveAxisAndClamps() {
        let frame = CGRect(x: 40, y: 50, width: 300, height: 500)
        let container = CGSize(width: 100, height: 200)

        XCTAssertEqual(
            ScrollViewAdjustedState.initialOffset(
                containerSize: container,
                contentFrame: frame,
                axes: [.horizontal, .vertical],
                anchors: ScrollAnchorStorage(defaultValue: .center),
                layoutDirection: .leftToRight
            ),
            CGPoint(x: 100, y: 150)
        )
        XCTAssertEqual(
            ScrollViewAdjustedState.initialOffset(
                containerSize: container,
                contentFrame: frame,
                axes: .horizontal,
                anchors: ScrollAnchorStorage(
                    anchors: [.initialOffset: .leading],
                    defaultValue: .bottom
                ),
                layoutDirection: .rightToLeft
            ),
            CGPoint(x: 200, y: 0)
        )
        XCTAssertEqual(
            ScrollViewAdjustedState.initialOffset(
                containerSize: CGSize(width: 400, height: 600),
                contentFrame: frame,
                axes: [.horizontal, .vertical],
                anchors: ScrollAnchorStorage(defaultValue: .bottomTrailing),
                layoutDirection: .leftToRight
            ),
            .zero
        )
    }

    func testScrollPositionInitialOffsetMatchesObservedStorageAxisAndRTLBranches() {
        let container = CGSize(width: 100, height: 120)
        let frame = CGRect(x: 0, y: 0, width: 300, height: 400)

        XCTAssertNil(ScrollPosition().initialContentOffset(
            containerSize: container,
            contentFrame: frame,
            axes: [.horizontal, .vertical],
            layoutDirection: .leftToRight
        ))
        XCTAssertNil(ScrollPosition(id: "target").initialContentOffset(
            containerSize: container,
            contentFrame: frame,
            axes: [.horizontal, .vertical],
            layoutDirection: .leftToRight
        ))
        XCTAssertEqual(ScrollPosition(edge: .bottom).initialContentOffset(
            containerSize: container,
            contentFrame: frame,
            axes: .vertical,
            layoutDirection: .leftToRight
        ), CGPoint(x: 0, y: 280))
        XCTAssertEqual(ScrollPosition(edge: .trailing).initialContentOffset(
            containerSize: container,
            contentFrame: frame,
            axes: .horizontal,
            layoutDirection: .rightToLeft
        ), .zero)
        XCTAssertEqual(ScrollPosition(point: CGPoint(x: 70, y: 230)).initialContentOffset(
            containerSize: container,
            contentFrame: frame,
            axes: [.horizontal, .vertical],
            layoutDirection: .leftToRight
        ), CGPoint(x: 70, y: 0))
        XCTAssertEqual(ScrollPosition(point: CGPoint(x: 70, y: 230)).initialContentOffset(
            containerSize: container,
            contentFrame: frame,
            axes: .vertical,
            layoutDirection: .leftToRight
        ), CGPoint(x: 0, y: 230))
        XCTAssertEqual(ScrollPosition(x: 70).initialContentOffset(
            containerSize: container,
            contentFrame: frame,
            axes: .horizontal,
            layoutDirection: .rightToLeft
        ), CGPoint(x: 130, y: 0))
        XCTAssertNil(ScrollPosition(y: 230).initialContentOffset(
            containerSize: container,
            contentFrame: frame,
            axes: .horizontal,
            layoutDirection: .leftToRight
        ))
    }

    func testAdjustedStateUsesBoundInitialPositionAndResetPositionReason() {
        let graph = _AGGraph()
        let graphRef = _AGGraphContext(graph: graph)

        graphRef.withCurrent {
            var stored = ScrollPosition(y: 230)
            let binding = Binding<ScrollPosition>(
                get: { stored },
                set: { value, _ in stored = value }
            )
            let adjusted = graph.makeStatefulRule(ScrollViewAdjustedState(
                _size: graph.makeInput(value: ViewSize(width: 100, height: 120)),
                _configuration: graph.makeInput(value: ScrollViewConfiguration(axes: .vertical)),
                _defaultAnchors: graph.makeInput(value: ScrollAnchorStorage()),
                _state: graph.makeInput(value: SystemScrollLayoutState()),
                _phaseState: graph.makeInput(value: ScrollPhaseState()),
                _contentFrame: graph.makeInput(value: ViewFrame(
                    origin: .zero,
                    size: ViewSize(width: 300, height: 400)
                )),
                _pixelLength: graph.makeInput(value: CGFloat(1)),
                _phase: graph.makeInput(value: Phase()),
                _transaction: graph.makeInput(value: Transaction()),
                _layoutDirection: graph.makeInput(value: LayoutDirection.leftToRight),
                _positionBinding: binding
            ))

            let state = adjusted.value
            XCTAssertEqual(state.contentOffset, CGPoint(x: 0, y: 230))
            XCTAssertEqual(state.contentOffsetMode, .adjustment(reason: .resetPosition))
        }
    }

    func testAdjustedStateAlignsInitialSizeChangeAndUndersizedRoles() {
        var initial = CGPoint.zero
        XCTAssertTrue(ScrollViewAdjustedState.alignIfNeeded(
            &initial,
            axis: .horizontal,
            newSize: CGSize(width: 100, height: 100),
            newContentFrame: CGRect(x: 0, y: 0, width: 300, height: 100),
            anchors: ScrollAnchorStorage(anchors: [.initialOffset: .center]),
            layoutDirection: .leftToRight,
            oldFrame: .zero,
            oldSize: CGSize(width: -CGFloat.infinity, height: -CGFloat.infinity),
            oldOffset: .zero,
            hasScrolled: false,
            pixelLength: 1
        ))
        XCTAssertEqual(initial.x, 100)

        var sizeChange = CGPoint(x: 100, y: 0)
        XCTAssertTrue(ScrollViewAdjustedState.alignIfNeeded(
            &sizeChange,
            axis: .horizontal,
            newSize: CGSize(width: 100, height: 100),
            newContentFrame: CGRect(x: 0, y: 0, width: 500, height: 100),
            anchors: ScrollAnchorStorage(anchors: [.sizeChanges: .center]),
            layoutDirection: .leftToRight,
            oldFrame: CGRect(x: 0, y: 0, width: 300, height: 100),
            oldSize: CGSize(width: 100, height: 100),
            oldOffset: CGPoint(x: 100, y: 0),
            hasScrolled: true,
            pixelLength: 1
        ))
        XCTAssertEqual(sizeChange.x, 200)

        var alignment = CGPoint.zero
        XCTAssertTrue(ScrollViewAdjustedState.alignIfNeeded(
            &alignment,
            axis: .horizontal,
            newSize: CGSize(width: 100, height: 100),
            newContentFrame: CGRect(x: 0, y: 0, width: 200, height: 100),
            anchors: ScrollAnchorStorage(anchors: [.alignment: .trailing]),
            layoutDirection: .leftToRight,
            oldFrame: CGRect(x: 0, y: 0, width: 80, height: 100),
            oldSize: CGSize(width: 100, height: 100),
            oldOffset: .zero,
            hasScrolled: true,
            pixelLength: 1
        ))
        XCTAssertEqual(alignment.x, 100)

        var centeredUndersized = CGPoint(x: 10, y: 0)
        XCTAssertTrue(ScrollViewAdjustedState.alignIfNeeded(
            &centeredUndersized,
            axis: .horizontal,
            newSize: CGSize(width: 100, height: 100),
            newContentFrame: CGRect(x: 0, y: 0, width: 180, height: 100),
            anchors: ScrollAnchorStorage(anchors: [.sizeChanges: .center]),
            layoutDirection: .leftToRight,
            oldFrame: CGRect(x: 0, y: 0, width: 80, height: 100),
            oldSize: CGSize(width: 100, height: 100),
            oldOffset: CGPoint(x: 10, y: 0),
            hasScrolled: true,
            pixelLength: 1
        ))
        XCTAssertEqual(centeredUndersized.x, 0)
    }

    func testAdjustedStateAlignmentUsesPixelRoundingAndChangeTolerance() {
        var rounded = CGPoint.zero
        XCTAssertTrue(ScrollViewAdjustedState.alignIfNeeded(
            &rounded,
            axis: .horizontal,
            newSize: CGSize(width: 100, height: 100),
            newContentFrame: CGRect(x: 0, y: 0, width: 305, height: 100),
            anchors: ScrollAnchorStorage(anchors: [.initialOffset: .center]),
            layoutDirection: .leftToRight,
            oldFrame: .zero,
            oldSize: CGSize(width: -CGFloat.infinity, height: -CGFloat.infinity),
            oldOffset: .zero,
            hasScrolled: false,
            pixelLength: 2
        ))
        XCTAssertEqual(rounded.x, 102)

        var unchanged = CGPoint(x: 20, y: 7)
        XCTAssertFalse(ScrollViewAdjustedState.alignIfNeeded(
            &unchanged,
            axis: .horizontal,
            newSize: CGSize(width: 100, height: 100),
            newContentFrame: CGRect(x: 0, y: 0, width: 500, height: 100),
            anchors: ScrollAnchorStorage(anchors: [.sizeChanges: .center]),
            layoutDirection: .leftToRight,
            oldFrame: CGRect(x: 0, y: 0, width: 300, height: 100),
            oldSize: CGSize(width: 100, height: 100),
            oldOffset: CGPoint(x: 20, y: 7),
            hasScrolled: true,
            pixelLength: 1
        ))
        XCTAssertEqual(unchanged, CGPoint(x: 20, y: 7))
    }

    func testAdjustedStateAppliesAutomaticAlignmentAndSkipsDisabledBehavior() {
        func offsets(
            for behavior: ScrollContentOffsetAdjustmentBehavior
        ) -> [CGPoint] {
            let graph = _AGGraph()
            let graphRef = _AGGraphContext(graph: graph)
            return graphRef.withCurrent {
                let rawState = graph.makeInput(value: SystemScrollLayoutState())
                let configuration = graph.makeInput(value: ScrollViewConfiguration(axes: .horizontal))
                let anchors = graph.makeInput(value: ScrollAnchorStorage(
                    anchors: [.sizeChanges: .center]
                ))
                let frame = graph.makeInput(value: ViewFrame(
                    origin: .zero,
                    size: ViewSize(width: 300, height: 100)
                ))
                let size = graph.makeInput(value: ViewSize(width: 100, height: 100))
                var transactionValue = Transaction()
                transactionValue.scrollContentOffsetAdjustmentBehavior = behavior
                let transaction = graph.makeInput(value: transactionValue)
                let adjusted = graph.makeStatefulRule(ScrollViewAdjustedState(
                    _size: size,
                    _configuration: configuration,
                    _defaultAnchors: anchors,
                    _state: rawState,
                    _phaseState: graph.makeInput(value: ScrollPhaseState()),
                    _contentFrame: frame,
                    _pixelLength: graph.makeInput(value: CGFloat(1)),
                    _phase: graph.makeInput(value: Phase()),
                    _transaction: transaction,
                    _layoutDirection: graph.makeInput(value: LayoutDirection.leftToRight)
                ))

                let initial = adjusted.value.contentOffset
                frame.setValue(ViewFrame(
                    origin: .zero,
                    size: ViewSize(width: 500, height: 100)
                ))
                return [initial, adjusted.value.contentOffset]
            }
        }

        XCTAssertEqual(offsets(for: .automatic), [
            CGPoint(x: 100, y: 0),
            CGPoint(x: 200, y: 0),
        ])
        XCTAssertEqual(offsets(for: .disabled), [.zero, .zero])
    }

    func testAdjustedStateMarksScrollOriginChangeBeforeLaterInitialAlignment() {
        let graph = _AGGraph()
        let graphRef = _AGGraphContext(graph: graph)

        graphRef.withCurrent {
            let rawState = graph.makeInput(value: SystemScrollLayoutState())
            let configuration = graph.makeInput(value: ScrollViewConfiguration(axes: .horizontal))
            let anchors = graph.makeInput(value: ScrollAnchorStorage(
                anchors: [.initialOffset: .center]
            ))
            let frame = graph.makeInput(value: ViewFrame(
                origin: .zero,
                size: ViewSize(width: 300, height: 100)
            ))
            let transaction = graph.makeInput(value: Transaction())
            let adjusted = graph.makeStatefulRule(ScrollViewAdjustedState(
                _size: graph.makeInput(value: ViewSize(width: 100, height: 100)),
                _configuration: configuration,
                _defaultAnchors: anchors,
                _state: rawState,
                _phaseState: graph.makeInput(value: ScrollPhaseState()),
                _contentFrame: frame,
                _pixelLength: graph.makeInput(value: CGFloat(1)),
                _phase: graph.makeInput(value: Phase()),
                _transaction: transaction,
                _layoutDirection: graph.makeInput(value: LayoutDirection.leftToRight)
            ))

            XCTAssertEqual(adjusted.value.contentOffset, CGPoint(x: 100, y: 0))

            var fromScrollView = Transaction()
            fromScrollView.fromScrollView = true
            transaction.setValue(fromScrollView)
            rawState.setValue(SystemScrollLayoutState(
                contentOffset: CGPoint(x: 100, y: 0),
                contentOffsetMode: .system
            ))
            XCTAssertEqual(adjusted.value.contentOffset, CGPoint(x: 100, y: 0))

            frame.setValue(ViewFrame(
                origin: .zero,
                size: ViewSize(width: 500, height: 100)
            ))
            XCTAssertEqual(adjusted.value.contentOffset, CGPoint(x: 100, y: 0))
        }
    }

    func testScrollHostInputRulesUseObservedDefaultAlignmentAndSafeArea() {
        let graph = _AGGraph()
        let graphRef = _AGGraphContext(graph: graph)

        graphRef.withCurrent {
            let configuration = graph.makeInput(value: ScrollViewConfiguration(
                axes: [.horizontal, .vertical]
            ))
            let sourceAnchors = graph.makeInput(value: ScrollAnchorStorage())
            let defaultRule = ScrollViewDefaultAnchors(
                _configuration: configuration,
                _anchors: sourceAnchors
            )
            XCTAssertEqual(
                Mirror(reflecting: defaultRule).children.compactMap(\.label),
                ["_configuration", "_anchors", "oldAnchors", "oldAxes"]
            )
            let defaultAnchors = graph.makeStatefulRule(defaultRule)
            XCTAssertEqual(defaultAnchors.value.defaultValue, .topLeading)

            sourceAnchors.setValue(ScrollAnchorStorage(
                anchors: [.alignment: .center]
            ))
            let frame = graph.makeInput(value: ViewFrame(
                origin: .zero,
                size: ViewSize(CGSize(width: 100, height: 80))
            ))
            let size = graph.makeInput(value: ViewSize(CGSize(width: 200, height: 200)))
            let alignmentRule = ScrollViewAlignmentAdjustment(
                _configuration: configuration,
                _scrollAnchors: defaultAnchors,
                _contentFrame: frame,
                _size: size
            )
            XCTAssertEqual(
                Mirror(reflecting: alignmentRule).children.compactMap(\.label),
                ["_configuration", "_scrollAnchors", "_contentFrame", "_size"]
            )
            let alignment = graph.makeRule(alignmentRule)
            XCTAssertEqual(alignment.value, CGSize(width: 50, height: 60))

            let direction = graph.makeInput(value: LayoutDirection.rightToLeft)
            sourceAnchors.setValue(ScrollAnchorStorage(
                anchors: [.alignment: .topLeading]
            ))
            let rtlRule = ScrollViewRTLAlignmentAdjustment(
                _configuration: configuration,
                _scrollAnchors: defaultAnchors,
                _contentFrame: frame,
                _size: size,
                _layoutDirection: direction
            )
            XCTAssertEqual(
                Mirror(reflecting: rtlRule).children.compactMap(\.label),
                [
                    "_configuration", "_scrollAnchors", "_contentFrame", "_size",
                    "_layoutDirection",
                ]
            )
            let rtl = graph.makeRule(rtlRule)
            XCTAssertEqual(rtl.value, CGSize(width: 100, height: 0))

            sourceAnchors.setValue(ScrollAnchorStorage(
                anchors: [.alignment: .center]
            ))
            let safeArea = graph.makeInput(value: EdgeInsets(
                top: 1,
                leading: 2,
                bottom: 3,
                trailing: 4
            ))
            let adjustedSafeAreaRule = ScrollViewAdjustedSafeArea(
                _safeArea: safeArea,
                _configuration: configuration,
                _alignmentAdjustment: alignment,
                _rtlAdjustment: rtl
            )
            XCTAssertEqual(
                Mirror(reflecting: adjustedSafeAreaRule).children.compactMap(\.label),
                ["_safeArea", "_configuration", "_alignmentAdjustment", "_rtlAdjustment"]
            )
            XCTAssertEqual(
                graph.makeRule(adjustedSafeAreaRule).value,
                EdgeInsets(top: 61, leading: 52, bottom: 3, trailing: 4)
            )
        }
    }

    func testScrollHostPropertyRulesStoreObservedFieldsAndApplyConfiguration() {
        let graph = _AGGraph()
        let graphRef = _AGGraphContext(graph: graph)

        graphRef.withCurrent {
            let configuration = graph.makeInput(value: ScrollViewConfiguration(
                axes: .vertical,
                isScrollEnabled: false
            ))
            var values = EnvironmentValues()
            values.layoutDirection = .rightToLeft
            let environment = graph.makeInput(value: values)
            var baseProperties = ScrollEnvironmentProperties(environment: values)
            baseProperties.horizontalBounceBehavior = ScrollBounceBehavior.always.role
            baseProperties.decelerationRate = .paging
            let storage = graph.makeInput(value: ScrollEnvironmentStorage(
                baseProperties
            ))
            let behaviorRule = ScrollViewAdjustedBehaviorProperties(
                _configuration: configuration,
                _environment: environment,
                _storage: storage
            )
            XCTAssertEqual(
                Mirror(reflecting: behaviorRule).children.compactMap(\.label),
                [
                    "_configuration", "_environment", "_storage", "tracker",
                    "oldBehavior", "oldAxes",
                ]
            )
            let behavior = graph.makeStatefulRule(behaviorRule)
            let layoutDirection = graph.makeInput(value: LayoutDirection.rightToLeft)
            let isEnabled = graph.makeInput(value: true)
            let isContainedInPlatter = graph.makeInput(value: true)
            let propertiesRule = ScrollViewAdjustedProperties(
                _configuration: configuration,
                _scrollStorage: storage,
                _behaviorProperties: behavior,
                _layoutDirection: layoutDirection,
                _isEnabled: isEnabled,
                _isContainedInPlatter: OptionalAttribute(isContainedInPlatter)
            )
            XCTAssertEqual(
                Mirror(reflecting: propertiesRule).children.compactMap(\.label),
                [
                    "_configuration", "_scrollStorage", "_behaviorProperties",
                    "_layoutDirection", "_isEnabled", "_isContainedInPlatter",
                ]
            )
            let adjustedProperties = graph.makeRule(propertiesRule)
            let properties = adjustedProperties.value
            XCTAssertFalse(properties.isEnabled)
            XCTAssertEqual(properties.layoutDirection, .rightToLeft)
            XCTAssertTrue(properties.isContainedInPlatter)
            XCTAssertEqual(properties.verticalBounceBehavior.rawValue, 3)
            XCTAssertEqual(properties.horizontalBounceBehavior.rawValue, 3)
            XCTAssertEqual(properties.decelerationRate, .standard)

            configuration.setValue(ScrollViewConfiguration(
                axes: .vertical,
                isScrollEnabled: true
            ))
            let enabledProperties = adjustedProperties.value
            XCTAssertTrue(enabledProperties.isEnabled)
            XCTAssertEqual(enabledProperties.verticalBounceBehavior.rawValue, 0)
            XCTAssertEqual(enabledProperties.horizontalBounceBehavior.rawValue, 1)
            XCTAssertEqual(enabledProperties.decelerationRate, .standard)
        }
    }

    func testSystemScrollLayoutStateStoresProbedFieldsInOrder() {
        XCTAssertEqual(
            Mirror(reflecting: ScrollAnchorStorage()).children.compactMap(\.label),
            ["anchors", "defaultValue"]
        )
        XCTAssertEqual(
            Mirror(reflecting: SystemScrollLayoutState()).children.compactMap(\.label),
            [
                "contentOffset",
                "contentInsets",
                "systemContentInsets",
                "systemTranslation",
                "contentRectToPrepare",
                "contentOffsetMode",
                "contentOffsetSeed",
            ]
        )
        XCTAssertEqual(
            Mirror(reflecting: ScrollTargetConfiguration()).children.compactMap(\.label),
            ["animation", "requiresVisibility", "preservesVelocity"]
        )
        XCTAssertEqual(
            Mirror(reflecting: HostingScrollViewUpdateContext(
                contentOffset: .zero,
                contentFrame: .zero,
                containingSize: .zero,
                offsetMode: .system,
                safeInsets: EdgeInsets()
            )).children.compactMap(\.label),
            ["contentOffset", "contentFrame", "containingSize", "offsetMode", "safeInsets"]
        )
    }

    func testHostingScrollViewRoundTripsGraphAndSystemState() {
        let graph = _AGGraph()
        let graphRef = _AGGraphContext(graph: graph)

        graphRef.withCurrent {
            let state = graph.makeInput(value: SystemScrollLayoutState(
                contentOffset: CGPoint(x: 2, y: 3),
                contentOffsetSeed: VersionSeed(value: 7)
            ))
            let host = HostingScrollView(graphRef: graphRef, layoutState: state.asWeak())
            let insets = EdgeInsets(top: 1, leading: 2, bottom: 3, trailing: 4)

            host.updateContext(HostingScrollViewUpdateContext(
                contentOffset: CGPoint(x: 10, y: 20),
                contentFrame: CGRect(x: 4, y: 5, width: 300, height: 400),
                containingSize: CGSize(width: 80, height: 120),
                offsetMode: .adjustment(reason: .translation),
                safeInsets: insets
            ))

            let platformState = host.makeLayoutState()
            XCTAssertEqual(platformState.contentOffset, CGPoint(x: 10, y: 20))
            XCTAssertEqual(platformState.contentInsets, insets)
            XCTAssertEqual(platformState.systemContentInsets, insets)
            XCTAssertEqual(platformState.contentOffsetMode, .system)
            XCTAssertEqual(platformState.contentOffsetSeed, VersionSeed())

            host.publishSystemContentOffset(CGPoint(x: 30, y: 40))
            XCTAssertEqual(state.value.contentOffset, CGPoint(x: 30, y: 40))
            XCTAssertEqual(state.value.contentOffsetMode, .system)
            XCTAssertEqual(state.value.contentOffsetSeed, VersionSeed(value: 8))
        }
    }

    func testHostingScrollViewResolvesVisibilityAwareTargetIntoPendingContext() {
        let graph = _AGGraph()
        let graphRef = _AGGraphContext(graph: graph)

        graphRef.withCurrent {
            let state = graph.makeInput(value: SystemScrollLayoutState())
            let host = HostingScrollView(graphRef: graphRef, layoutState: state.asWeak())
            let target = ScrollTarget(
                rect: CGRect(x: 250, y: 150, width: 100, height: 50)
            )
            let config = ScrollTargetConfiguration(
                animation: .linear(duration: 0.25),
                requiresVisibility: true,
                preservesVelocity: true
            )

            XCTAssertFalse(host.updateContext(HostingScrollViewUpdateContext(
                contentOffset: CGPoint(x: 100, y: 100),
                contentFrame: CGRect(x: 0, y: 0, width: 1_000, height: 1_000),
                containingSize: CGSize(width: 200, height: 200),
                offsetMode: .target({ _, _ in target }, config: config),
                safeInsets: EdgeInsets()
            )))

            XCTAssertEqual(host.pendingContext?.contentOffset, CGPoint(x: 150, y: 100))
            XCTAssertEqual(host.animationTarget, target)
            XCTAssertEqual(host.animationTargetConfig, config)

            host.updateContext(HostingScrollViewUpdateContext(
                contentOffset: CGPoint(x: 100, y: 100),
                contentFrame: CGRect(x: 0, y: 0, width: 1_000, height: 1_000),
                containingSize: CGSize(width: 200, height: 200),
                offsetMode: .system,
                safeInsets: EdgeInsets()
            ))
            XCTAssertNil(host.animationTarget)
            XCTAssertNil(host.animationTargetConfig)
        }
    }

    func testMakeHostingScrollViewReusesHostObject() {
        let graph = _AGGraph()
        let graphRef = _AGGraphContext(graph: graph)

        graphRef.withCurrent {
            let state = graph.makeInput(value: SystemScrollLayoutState())
            let host = graph.makeStatefulRule(MakeHostingScrollView(
                _layoutState: state,
                graphRef: graphRef
            ))

            let first = host.value
            state.setValue(SystemScrollLayoutState(contentOffset: CGPoint(x: 1, y: 2)))
            XCTAssertTrue(first === host.value)
        }
    }

    func testAdjustedStateAndUpdatedHostPreserveHostOriginatedState() {
        let graph = _AGGraph()
        let graphRef = _AGGraphContext(graph: graph)

        graphRef.withCurrent {
            let rawState = graph.makeInput(value: SystemScrollLayoutState(
                contentOffset: CGPoint(x: 12, y: 34),
                systemContentInsets: EdgeInsets(top: 9, leading: 0, bottom: 0, trailing: 0),
                systemTranslation: CGSize(width: 2, height: 3),
                contentOffsetSeed: VersionSeed(value: 5)
            ))
            let insets = EdgeInsets(top: 1, leading: 2, bottom: 3, trailing: 4)
            let configuration = graph.makeInput(value: ScrollViewConfiguration(contentInsets: insets))
            let frame = graph.makeInput(value: ViewFrame(
                origin: CGPoint(x: 5, y: 6),
                size: ViewSize(CGSize(width: 300, height: 400))
            ))
            let size = graph.makeInput(value: ViewSize(CGSize(width: 80, height: 120)))
            let anchors = graph.makeInput(value: ScrollAnchorStorage())
            let phaseState = graph.makeInput(value: ScrollPhaseState())
            let pixelLength = graph.makeInput(value: CGFloat(1))
            let phase = graph.makeInput(value: Phase())
            let transaction = graph.makeInput(value: Transaction())
            let layoutDirection = graph.makeInput(value: LayoutDirection.leftToRight)
            let adjustedRule = ScrollViewAdjustedState(
                _size: size,
                _configuration: configuration,
                _defaultAnchors: anchors,
                _state: rawState,
                _phaseState: phaseState,
                _contentFrame: frame,
                _pixelLength: pixelLength,
                _phase: phase,
                _transaction: transaction,
                _layoutDirection: layoutDirection
            )
            XCTAssertEqual(
                Mirror(reflecting: adjustedRule).children.compactMap(\.label),
                [
                    "_size", "_configuration", "_defaultAnchors", "_state",
                    "_phaseState", "_contentFrame", "_pixelLength", "_phase",
                    "_transaction", "_layoutDirection", "_positionBinding",
                    "oldFrame", "oldSize", "oldOffset", "hasScrolled",
                    "resetSeed", "_lastUpdateSeed",
                ]
            )
            let adjusted = graph.makeStatefulRule(adjustedRule)

            XCTAssertEqual(adjusted.value.contentOffset, .zero)
            XCTAssertEqual(adjusted.value.contentInsets, insets)
            XCTAssertEqual(
                adjusted.value.systemContentInsets,
                EdgeInsets(top: 9, leading: 0, bottom: 0, trailing: 0)
            )
            XCTAssertEqual(adjusted.value.systemTranslation, CGSize(width: 2, height: 3))
            XCTAssertEqual(adjusted.value.contentOffsetMode, .adjustment(reason: .reset))
            XCTAssertEqual(adjusted.value.contentOffsetSeed, VersionSeed(value: 3_470_406_040))

            rawState.setValue(SystemScrollLayoutState(
                contentOffset: CGPoint(x: 12, y: 34),
                systemContentInsets: EdgeInsets(top: 9, leading: 0, bottom: 0, trailing: 0),
                systemTranslation: CGSize(width: 2, height: 3),
                contentOffsetMode: .system,
                contentOffsetSeed: VersionSeed(value: 6)
            ))
            XCTAssertEqual(adjusted.value.contentOffset, CGPoint(x: 12, y: 34))
            XCTAssertEqual(adjusted.value.contentOffsetMode, .system)
            XCTAssertEqual(adjusted.value.contentOffsetSeed, VersionSeed(value: 6))

            let host = graph.makeInput(value: HostingScrollView(
                graphRef: graphRef,
                layoutState: rawState.asWeak()
            ))
            var environmentValues = EnvironmentValues()
            environmentValues.automaticContentMargins = OptionalEdgeInsets(
                EdgeInsets(top: 7, leading: 8, bottom: 9, trailing: 10)
            )
            let environment = graph.makeInput(value: environmentValues)
            var propertiesValue = ScrollEnvironmentProperties(environment: environmentValues)
            propertiesValue.isClippingEnabled = false
            let properties = graph.makeInput(value: propertiesValue)
            let containerSize = graph.makeInput(value: CGSize(width: 80, height: 120))
            let safeAreaInsets = graph.makeInput(value: insets)
            let rtlAdjustment = graph.makeInput(value: CGSize.zero)
            let updatedRule = UpdatedHostingScrollView(
                _scrollView: host,
                _configuration: configuration,
                _properties: properties,
                _contentFrame: frame,
                _size: containerSize,
                _safeAreaInsets: safeAreaInsets,
                _rtlAdjustment: rtlAdjustment,
                _adjustedState: adjusted,
                _environment: environment
            )
            XCTAssertEqual(
                Mirror(reflecting: updatedRule).children.compactMap(\.label),
                [
                    "_descendantScrollViewsAxes", "_container", "_scrollView",
                    "_configuration", "_properties", "_contentFrame", "_size",
                    "_safeAreaInsets", "_rtlAdjustment", "_adjustedState",
                    "_environment", "lastUpdateSeed", "tracker", "oldProperties",
                    "oldMargins",
                ]
            )
            let updated = graph.makeStatefulRule(updatedRule)

            XCTAssertTrue(updated.value === host.value)
            XCTAssertEqual(host.value.configuration.contentInsets, insets)
            XCTAssertEqual(host.value.properties, propertiesValue)
            XCTAssertEqual(
                host.value.contentMargins.automatic,
                OptionalEdgeInsets(EdgeInsets(top: 7, leading: 8, bottom: 9, trailing: 10))
            )

            environmentValues.automaticContentMargins = OptionalEdgeInsets(
                EdgeInsets(top: 11, leading: 12, bottom: 13, trailing: 14)
            )
            environment.setValue(environmentValues)
            propertiesValue.isEnabled = false
            properties.setValue(propertiesValue)
            _ = updated.value
            XCTAssertEqual(host.value.properties, propertiesValue)
            XCTAssertEqual(
                host.value.contentMargins.automatic,
                OptionalEdgeInsets(EdgeInsets(top: 11, leading: 12, bottom: 13, trailing: 14))
            )
            XCTAssertEqual(host.value.pendingContext, HostingScrollViewUpdateContext(
                contentOffset: CGPoint(x: 12, y: 34),
                contentFrame: CGRect(x: 5, y: 6, width: 300, height: 400),
                containingSize: CGSize(width: 80, height: 120),
                offsetMode: .system,
                safeInsets: insets
            ))
        }
    }
}

private final class HostScrollTargetBehaviorRecorder {
    var originalTarget: ScrollTarget?
    var proposedTarget: ScrollTarget?
    var velocity: CGVector?
    var geometry: ScrollGeometry?
    var axes: Axis.Set?
    var decelerationRate: ScrollDecelerationRate?
    var overrideTargetOrigin: CGPoint?
    var invocationCount = 0
}

private struct HostRecordingScrollTargetBehavior: ScrollTargetBehavior {
    var recorder: HostScrollTargetBehaviorRecorder
    var targetOrigin: CGPoint

    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        recorder.invocationCount += 1
        recorder.originalTarget = context.originalTarget
        recorder.proposedTarget = target
        recorder.velocity = context.velocity
        recorder.geometry = context.geometry
        recorder.axes = context.axes
        recorder.decelerationRate = context.decelerationRate
        target.rect.origin = recorder.overrideTargetOrigin ?? targetOrigin
    }
}
