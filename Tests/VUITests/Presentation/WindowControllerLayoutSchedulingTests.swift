import XCTest
@testable import VVD
@testable import VUI

final class WindowControllerLayoutSchedulingTests: XCTestCase {
    @MainActor
    func testAnimationTimeAccumulatesDeltaIndependentlyOfEventTime() {
        let counter = LayoutSchedulingCounter()
        let controller = WindowController(
            content: LayoutSchedulingRoot(counter: counter),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(LayoutSchedulingRoot.self)
            )
        )
        let referenceDate = controller.date
        let firstFrameDate = referenceDate.addingTimeInterval(10_000)
        let secondFrameDate = referenceDate.addingTimeInterval(-10_000)
        let withGC: WindowContext.WithGraphicsContext = { _, _ in }

        controller.updateFrame(
            tick: 0,
            delta: 0.125,
            date: firstFrameDate,
            contentSize: CGSize(width: 120, height: 80),
            shouldDrawFrame: false,
            withGC
        )
        XCTAssertEqual(controller.date, firstFrameDate)
        XCTAssertEqual(controller.animationTimestamp.seconds, 0.125)
        XCTAssertEqual(controller.viewGraph.currentTimestamp.seconds, 0.125)
        let firstEventTimestamp = controller.currentTimestamp

        controller.updateFrame(
            tick: 1,
            delta: 0.25,
            date: secondFrameDate,
            contentSize: CGSize(width: 120, height: 80),
            shouldDrawFrame: false,
            withGC
        )
        XCTAssertEqual(controller.date, secondFrameDate)
        XCTAssertEqual(controller.animationTimestamp.seconds, 0.375)
        XCTAssertEqual(controller.viewGraph.currentTimestamp.seconds, 0.375)
        XCTAssertEqual(
            controller.currentTimestamp.seconds - firstEventTimestamp.seconds,
            -20_000
        )
    }

    @MainActor
    func testAnimationTimeScaleDoesNotAffectEventTime() {
        let previousScale = WindowController.animationTimeScale
        WindowController.animationTimeScale = 0.25
        defer { WindowController.animationTimeScale = previousScale }

        let counter = LayoutSchedulingCounter()
        let controller = WindowController(
            content: LayoutSchedulingRoot(counter: counter),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(LayoutSchedulingRoot.self)
            )
        )
        let referenceDate = controller.date
        let withGC: WindowContext.WithGraphicsContext = { _, _ in }

        controller.updateFrame(
            tick: 0,
            delta: 0.4,
            date: referenceDate.addingTimeInterval(0.4),
            contentSize: CGSize(width: 120, height: 80),
            shouldDrawFrame: false,
            withGC
        )
        let firstEventTimestamp = controller.currentTimestamp
        XCTAssertEqual(controller.animationDelta, 0.1, accuracy: 0.000_001)
        XCTAssertEqual(controller.animationTimestamp.seconds, 0.1, accuracy: 0.000_001)

        controller.updateFrame(
            tick: 1,
            delta: 0.2,
            date: referenceDate.addingTimeInterval(0.6),
            contentSize: CGSize(width: 120, height: 80),
            shouldDrawFrame: false,
            withGC
        )
        XCTAssertEqual(controller.animationDelta, 0.05, accuracy: 0.000_001)
        XCTAssertEqual(controller.animationTimestamp.seconds, 0.15, accuracy: 0.000_001)
        XCTAssertEqual(controller.viewGraph.currentTimestamp.seconds, 0.15, accuracy: 0.000_001)
        XCTAssertEqual(
            controller.currentTimestamp.seconds - firstEventTimestamp.seconds,
            0.2,
            accuracy: 0.000_001
        )
    }

    @MainActor
    func testForcedIdleDrawReusesGraphOutputsWithoutAdvancingGraphTime() {
        let counter = LayoutSchedulingCounter()
        let controller = WindowController(
            content: LayoutSchedulingRoot(counter: counter),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(LayoutSchedulingRoot.self)
            )
        )
        var presentRequests = 0
        let withGC: WindowContext.WithGraphicsContext = { needsPresent, _ in
            if needsPresent {
                presentRequests += 1
            }
        }

        controller.updateFrame(
            tick: 0,
            delta: 0,
            date: controller.date,
            contentSize: CGSize(width: 120, height: 80),
            shouldDrawFrame: false,
            withGC
        )
        XCTAssertFalse(controller.viewGraph.hasScheduledViewUpdate)
        let graphCounter = controller.viewGraph.data.graph.graphCounter(lane: 1)
        let graphTime = controller.viewGraph.currentTimestamp
        let animationTime = controller.animationTimestamp
        presentRequests = 0

        controller.updateFrame(
            tick: 1,
            delta: 1.0 / 300.0,
            date: controller.date.addingTimeInterval(1.0 / 300.0),
            contentSize: CGSize(width: 120, height: 80),
            shouldDrawFrame: true,
            withGC
        )

        XCTAssertEqual(presentRequests, 1)
        XCTAssertEqual(
            controller.animationTimestamp.seconds,
            animationTime.seconds + 1.0 / 300.0,
            accuracy: 0.000_001
        )
        XCTAssertEqual(controller.viewGraph.currentTimestamp, graphTime)
        XCTAssertEqual(
            controller.viewGraph.data.graph.graphCounter(lane: 1),
            graphCounter
        )
    }

    @MainActor
    func testIdleUpdateDoesNotRepeatRootLayoutPlacement() {
        let counter = LayoutSchedulingCounter()
        let controller = WindowController(
            content: LayoutSchedulingRoot(counter: counter),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(LayoutSchedulingRoot.self)
            )
        )

        var redraw = false
        let withGC: WindowContext.WithGraphicsContext = { _, _ in
            XCTFail("Static layout scheduling test should not request graphics resources.")
        }

        controller.updateView(
            tick: 0,
            delta: 0,
            date: controller.date,
            contentSize: CGSize(width: 120, height: 80),
            redraw: &redraw,
            withGC
        )
        let initialPlacements = counter.placements
        XCTAssertGreaterThan(initialPlacements, 0)

        controller.updateView(
            tick: 1,
            delta: (1.0 / 60.0) - controller.animationTimestamp.seconds,
            date: controller.date.addingTimeInterval(1.0 / 60.0),
            contentSize: CGSize(width: 120, height: 80),
            redraw: &redraw,
            withGC
        )
        XCTAssertEqual(counter.placements, initialPlacements)

        controller.updateView(
            tick: 2,
            delta: (2.0 / 60.0) - controller.animationTimestamp.seconds,
            date: controller.date.addingTimeInterval(2.0 / 60.0),
            contentSize: CGSize(width: 140, height: 80),
            redraw: &redraw,
            withGC
        )
        XCTAssertGreaterThan(counter.placements, initialPlacements)
    }

    @MainActor
    func testConsecutivePlainInboxWritesUseOneRootLayoutPass() {
        let counter = LayoutSchedulingCounter()
        let controller = WindowController(
            content: LayoutSchedulingRoot(counter: counter),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(LayoutSchedulingRoot.self)
            )
        )
        let withGC: WindowContext.WithGraphicsContext = { _, _ in
            XCTFail("Plain inbox batching test should not request graphics resources.")
        }

        var redraw = false
        controller.updateView(
            tick: 0,
            delta: 0,
            date: controller.date,
            contentSize: CGSize(width: 120, height: 80),
            redraw: &redraw,
            withGC
        )
        let initialPlacements = counter.placements

        for _ in 0..<4 {
            controller.viewGraph.data.graph.inbox.enqueue {}
        }

        redraw = false
        controller.updateView(
            tick: 1,
            delta: (1.0 / 60.0) - controller.animationTimestamp.seconds,
            date: controller.date.addingTimeInterval(1.0 / 60.0),
            contentSize: CGSize(width: 120, height: 80),
            redraw: &redraw,
            withGC
        )

        XCTAssertEqual(counter.placements - initialPlacements, 1)
    }

    @MainActor
    func testScheduledAnimationUpdateSamplesIntermediateBounds() throws {
        let counter = LayoutSchedulingCounter()
        let probe = LayoutSchedulingAnimationProbe()
        let controller = WindowController(
            content: LayoutSchedulingAnimationRoot(counter: counter, probe: probe),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(LayoutSchedulingAnimationRoot.self)
            )
        )

        let withGC: WindowContext.WithGraphicsContext = { _, _ in
            XCTFail("Static animation scheduling test should not request graphics resources.")
        }

        var redraw = false
        controller.updateView(
            tick: 0,
            delta: 0,
            date: controller.date,
            contentSize: CGSize(width: 420, height: 240),
            redraw: &redraw,
            withGC
        )
        let initialPlacements = counter.placements
        let initialBounds = try displayBounds(in: controller)
        let toggle = try XCTUnwrap(probe.toggle)

        withAnimation(.linear(duration: 1.0)) {
            toggle()
        }

        redraw = false
        controller.updateView(
            tick: 1,
            delta: (1.0 / 60.0) - controller.animationTimestamp.seconds,
            date: controller.date.addingTimeInterval(1.0 / 60.0),
            contentSize: CGSize(width: 420, height: 240),
            redraw: &redraw,
            withGC
        )
        let targetPlacements = counter.placements
        XCTAssertGreaterThan(targetPlacements, initialPlacements)

        redraw = false
        controller.updateView(
            tick: 2,
            delta: 0.25 - controller.animationTimestamp.seconds,
            date: controller.date.addingTimeInterval(0.25),
            contentSize: CGSize(width: 420, height: 240),
            redraw: &redraw,
            withGC
        )

        let sampledBounds = try displayBounds(in: controller)
        XCTAssertTrue(redraw)
        XCTAssertNotEqual(sampledBounds, initialBounds)
    }

    @MainActor
    func testScheduledFullStackAnimationSamplesBoundsAndOpacity() throws {
        try assertScheduledFullStackAnimationSamplesBoundsAndOpacity(
            animation: .linear(duration: 1.0),
            sampleTimes: (0...10).map { Double($0) / 10.0 },
            finalTime: 2.0
        )
    }

    @MainActor
    func testScheduledSpringFullStackAnimationSamplesBoundsAndOpacity() throws {
        try assertScheduledFullStackAnimationSamplesBoundsAndOpacity(
            animation: .spring(duration: 20.0, bounce: 0.35),
            sampleTimes: [0, 0.1, 0.2, 0.5, 1.0, 2.0, 5.0, 10.0, 15.0, 20.0],
            finalTime: 30.0
        )
    }

    @MainActor
    func testScheduledSpringCompletionWaitsForRegisteredAnimation() throws {
        let counter = LayoutSchedulingCounter()
        let probe = LayoutSchedulingAnimationProbe()
        let controller = WindowController(
            content: LayoutSchedulingCompletionAnimationRoot(counter: counter, probe: probe),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(LayoutSchedulingCompletionAnimationRoot.self)
            )
        )

        let withGC: WindowContext.WithGraphicsContext = { _, _ in
            XCTFail("Static animation scheduling test should not request graphics resources.")
        }

        var redraw = false
        controller.updateView(
            tick: 0,
            delta: 0,
            date: controller.date,
            contentSize: CGSize(width: 420, height: 240),
            redraw: &redraw,
            withGC
        )
        let runSpringMove = try XCTUnwrap(probe.toggle)

        runSpringMove()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        XCTAssertEqual(probe.completions, [])

        for (index, sampleTime) in [0.0, 1.0 / 60.0, 2.0 / 60.0, 0.1, 1.0, 10.0].enumerated() {
            redraw = false
            controller.updateView(
                tick: UInt64(index + 1),
                delta: sampleTime - controller.animationTimestamp.seconds,
                date: controller.date.addingTimeInterval(sampleTime),
                contentSize: CGSize(width: 420, height: 240),
                redraw: &redraw,
                withGC
            )
            _ = try displayList(in: controller)
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
            XCTAssertEqual(probe.completions, [])
        }

        redraw = false
        controller.updateView(
            tick: 20,
            delta: 20.1 - controller.animationTimestamp.seconds,
            date: controller.date.addingTimeInterval(20.1),
            contentSize: CGSize(width: 420, height: 240),
            redraw: &redraw,
            withGC
        )
        _ = try displayList(in: controller)
        redraw = false
        controller.updateView(
            tick: 21,
            delta: 20.1 - controller.animationTimestamp.seconds,
            date: controller.date.addingTimeInterval(20.1),
            contentSize: CGSize(width: 420, height: 240),
            redraw: &redraw,
            withGC
        )
        XCTAssertEqual(probe.completions, [1])
    }

    @MainActor
    func testModalSpringCompletionWaitsForRegisteredAnimation() throws {
        let counter = LayoutSchedulingCounter()
        let probe = LayoutSchedulingAnimationProbe()
        let parent = WindowController(
            content: EmptyView(),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(EmptyView.self)
            )
        )
        let child = parent.viewGraph.data.withCurrent {
            let sourceGraph = parent.viewGraph.data.graph
            let contentAttr: Attribute<AnyView> = sourceGraph.makeInput(
                value: AnyView(
                    SheetContent(
                        content: AnyView(
                            LayoutSchedulingCompletionAnimationRoot(counter: counter, probe: probe)
                        )
                    )
                )
            )
            return ModalWindowController(
                crossGraphContent: contentAttr,
                sourceGraph: sourceGraph,
                scene: WindowKey(
                    namespace: .app,
                    sceneID: SceneID(LayoutSchedulingCompletionAnimationRoot.self)
                ),
                parentController: parent,
                usesPlatformWindow: false
            )
        }

        let withGC: WindowContext.WithGraphicsContext = { _, _ in
            XCTFail("Static animation scheduling test should not request graphics resources.")
        }

        var redraw = false
        child.updateView(
            tick: 0,
            delta: 0,
            date: child.date,
            contentSize: CGSize(width: 420, height: 240),
            redraw: &redraw,
            withGC
        )
        let runSpringMove = try XCTUnwrap(probe.toggle)

        try XCTUnwrap(child.gestureGraph).data.withCurrent {
            runSpringMove()
        }
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        XCTAssertEqual(probe.completions, [])

        for (index, sampleTime) in [0.0, 1.0 / 60.0, 2.0 / 60.0, 0.1, 1.0, 10.0].enumerated() {
            redraw = false
            child.updateView(
                tick: UInt64(index + 1),
                delta: sampleTime - child.animationTimestamp.seconds,
                date: child.date.addingTimeInterval(sampleTime),
                contentSize: CGSize(width: 420, height: 240),
                redraw: &redraw,
                withGC
            )
            _ = try displayList(in: child)
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
            XCTAssertEqual(probe.completions, [])
        }
    }

    @MainActor
    func testButtonSpringCompletionWaitsForRegisteredAnimation() throws {
        let counter = LayoutSchedulingCounter()
        let probe = LayoutSchedulingAnimationProbe()
        let controller = WindowController(
            content: LayoutSchedulingButtonCompletionRoot(counter: counter, probe: probe),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(LayoutSchedulingButtonCompletionRoot.self)
            )
        )

        let withGC: WindowContext.WithGraphicsContext = { _, _ in
            XCTFail("Static animation scheduling test should not request graphics resources.")
        }

        var redraw = false
        controller.updateView(
            tick: 0,
            delta: 0,
            date: controller.date,
            contentSize: CGSize(width: 420, height: 240),
            redraw: &redraw,
            withGC
        )

        XCTAssertTrue(controller.handleMouseEvent(event: MouseEvent(
            type: .buttonDown,
            device: .genericMouse,
            deviceID: 0,
            buttonID: 0,
            location: CGPoint(x: 210, y: 120),
            timestamp: 0
        )))
        XCTAssertTrue(controller.handleMouseEvent(event: MouseEvent(
            type: .buttonUp,
            device: .genericMouse,
            deviceID: 0,
            buttonID: 0,
            location: CGPoint(x: 210, y: 120),
            timestamp: 0
        )))
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        XCTAssertEqual(probe.completions, [])

        for (index, sampleTime) in [0.0, 1.0 / 60.0, 2.0 / 60.0, 0.1, 1.0, 10.0].enumerated() {
            redraw = false
            controller.updateView(
                tick: UInt64(index + 1),
                delta: sampleTime - controller.animationTimestamp.seconds,
                date: controller.date.addingTimeInterval(sampleTime),
                contentSize: CGSize(width: 420, height: 240),
                redraw: &redraw,
                withGC
            )
            _ = try displayList(in: controller)
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
            XCTAssertEqual(probe.completions, [])
        }
    }

    @MainActor
    func testRepeatedButtonSpringMoveDoesNotCompleteImmediately() throws {
        let counter = LayoutSchedulingCounter()
        let probe = LayoutSchedulingAnimationProbe()
        let controller = WindowController(
            content: LayoutSchedulingButtonCompletionRoot(counter: counter, probe: probe),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(LayoutSchedulingButtonCompletionRoot.self)
            )
        )

        let withGC: WindowContext.WithGraphicsContext = { _, _ in
            XCTFail("Static animation scheduling test should not request graphics resources.")
        }

        var redraw = false
        controller.updateView(
            tick: 0,
            delta: 0,
            date: controller.date,
            contentSize: CGSize(width: 420, height: 240),
            redraw: &redraw,
            withGC
        )

        var tick: UInt64 = 1
        for run in 1...6 {
            pressSpringMoveButton(in: controller)
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))

            let baseTime = Double(run - 1)
            for sampleOffset in [0.0, 1.0 / 60.0, 2.0 / 60.0, 0.1] {
                redraw = false
                controller.updateView(
                    tick: tick,
                    delta: (baseTime + sampleOffset) - controller.animationTimestamp.seconds,
                    date: controller.date.addingTimeInterval(baseTime + sampleOffset),
                    contentSize: CGSize(width: 420, height: 240),
                    redraw: &redraw,
                    withGC
                )
                tick += 1
                _ = try displayList(in: controller)
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
                XCTAssertEqual(
                    probe.completions,
                    [],
                    "Run \(run) should not complete during immediate retarget samples."
                )
            }
        }
    }

    @MainActor
    func testNonAnimatedSiblingStateDoesNotInheritSpringTransaction() throws {
        let counter = LayoutSchedulingCounter()
        let probe = LayoutSchedulingAnimationProbe()
        let controller = WindowController(
            content: LayoutSchedulingMixedTransactionRoot(counter: counter, probe: probe),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(LayoutSchedulingMixedTransactionRoot.self)
            )
        )

        let withGC: WindowContext.WithGraphicsContext = { _, _ in
            XCTFail("Static animation scheduling test should not request graphics resources.")
        }

        var redraw = false
        controller.updateView(
            tick: 0,
            delta: 0,
            date: controller.date,
            contentSize: CGSize(width: 420, height: 240),
            redraw: &redraw,
            withGC
        )
        let initialStatusBounds = try XCTUnwrap(statusMarkerBounds(in: try displayList(in: controller)))
        XCTAssertEqual(initialStatusBounds.width, 40, accuracy: 0.5)

        let run = try XCTUnwrap(probe.toggle)
        run()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))

        redraw = false
        controller.updateView(
            tick: 1,
            delta: 0,
            date: controller.date,
            contentSize: CGSize(width: 420, height: 240),
            redraw: &redraw,
            withGC
        )
        let immediateDisplayList = try displayList(in: controller)
        let immediateStatusBounds = try XCTUnwrap(statusMarkerBounds(in: immediateDisplayList))
        XCTAssertEqual(
            immediateStatusBounds.width,
            160,
            accuracy: 0.5,
            "shape bounds: \(shapeFillBounds(in: immediateDisplayList))"
        )

        redraw = false
        controller.updateView(
            tick: 2,
            delta: 30 - controller.animationTimestamp.seconds,
            date: controller.date.addingTimeInterval(30),
            contentSize: CGSize(width: 420, height: 240),
            redraw: &redraw,
            withGC
        )
        let finalStatusBounds = try XCTUnwrap(statusMarkerBounds(in: try displayList(in: controller)))
        XCTAssertEqual(
            immediateStatusBounds.origin.x,
            finalStatusBounds.origin.x,
            accuracy: 0.5,
            "Non-animated sibling placement should reach its final horizontal position immediately."
        )
        XCTAssertEqual(
            immediateStatusBounds.origin.y,
            finalStatusBounds.origin.y,
            accuracy: 0.5,
            "Non-animated sibling placement should reach its final position immediately."
        )
    }

    @MainActor
    func testNonAnimatedResourceRequestIsSampledBeforeAnimatedSiblingMutation() throws {
        let counter = LayoutSchedulingCounter()
        let probe = LayoutSchedulingAnimationProbe()
        let controller = WindowController(
            content: LayoutSchedulingMixedResourceTransactionRoot(counter: counter, probe: probe),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(LayoutSchedulingMixedResourceTransactionRoot.self)
            )
        )
        let withGC: WindowContext.WithGraphicsContext = { _, _ in
            probe.resourceEvents.append(.load)
        }

        var redraw = false
        controller.updateView(
            tick: 0,
            delta: 0,
            date: controller.date,
            contentSize: CGSize(width: 420, height: 240),
            redraw: &redraw,
            withGC
        )
        probe.resourceTransactions.removeAll()
        probe.resourceEvents.removeAll()

        try XCTUnwrap(probe.toggle)()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        redraw = false
        controller.updateView(
            tick: 1,
            delta: 0,
            date: controller.date,
            contentSize: CGSize(width: 420, height: 240),
            redraw: &redraw,
            withGC
        )

        let firstUpdatedRequest = try XCTUnwrap(
            probe.resourceTransactions.first { $0.value }
        )
        XCTAssertNil(firstUpdatedRequest.duration)
        let loadIndex = try XCTUnwrap(
            probe.resourceEvents.firstIndex(of: .load)
        )
        let animatedRequestIndex = try XCTUnwrap(
            probe.resourceEvents.firstIndex { event in
                guard case let .request(_, duration) = event else { return false }
                return duration == 5
            }
        )
        XCTAssertLessThan(loadIndex, animatedRequestIndex)
    }

    @MainActor
    func testSpringCompletionStatusSurfaceStaysRunningUntilAnimationCompletes() throws {
        let counter = LayoutSchedulingCounter()
        let probe = LayoutSchedulingAnimationProbe()
        let controller = WindowController(
            content: LayoutSchedulingCompletionStatusRoot(counter: counter, probe: probe),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(LayoutSchedulingCompletionStatusRoot.self)
            )
        )

        let withGC: WindowContext.WithGraphicsContext = { _, _ in
            XCTFail("Static animation scheduling test should not request graphics resources.")
        }

        var redraw = false
        controller.updateView(
            tick: 0,
            delta: 0,
            date: controller.date,
            contentSize: CGSize(width: 420, height: 240),
            redraw: &redraw,
            withGC
        )
        let initialDisplayList = try displayList(in: controller)
        XCTAssertEqual(try XCTUnwrap(statusMarkerBounds(in: initialDisplayList)).width, 40, accuracy: 0.5)

        let run = try XCTUnwrap(probe.toggle)
        run()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        XCTAssertEqual(probe.completions, [])

        for (index, sampleTime) in [1.0 / 60.0, 2.0 / 60.0, 0.1, 1.0, 10.0].enumerated() {
            redraw = false
            controller.updateView(
                tick: UInt64(index + 1),
                delta: sampleTime - controller.animationTimestamp.seconds,
                date: controller.date.addingTimeInterval(sampleTime),
                contentSize: CGSize(width: 420, height: 240),
                redraw: &redraw,
                withGC
            )
            let runningDisplayList = try displayList(in: controller)
            XCTAssertEqual(
                try XCTUnwrap(statusMarkerBounds(in: runningDisplayList)).width,
                100,
                accuracy: 0.5,
                "The nonanimated status write should be visible before the spring completion fires."
            )
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
            XCTAssertEqual(probe.completions, [])
        }

        redraw = false
        controller.updateView(
            tick: 20,
            delta: 20.1 - controller.animationTimestamp.seconds,
            date: controller.date.addingTimeInterval(20.1),
            contentSize: CGSize(width: 420, height: 240),
            redraw: &redraw,
            withGC
        )
        _ = try displayList(in: controller)
        redraw = false
        controller.updateView(
            tick: 21,
            delta: 20.1 - controller.animationTimestamp.seconds,
            date: controller.date.addingTimeInterval(20.1),
            contentSize: CGSize(width: 420, height: 240),
            redraw: &redraw,
            withGC
        )
        let completeDisplayList = try displayList(in: controller)
        XCTAssertEqual(probe.completions, [1])
        XCTAssertEqual(try XCTUnwrap(statusMarkerBounds(in: completeDisplayList)).width, 160, accuracy: 0.5)
    }

    // ASSERTIONS animationLabStatusTransactionIsolationRuntimeObserved
    @MainActor
    func testResolvedStatusCompletionSnapsOutsideRetainedRemovalTransaction() throws {
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
        appContext = LayoutSchedulingAppContext(
            graphicsDeviceContext: deviceContext
        )
        defer { appContext = previousAppContext }

        let probe = LayoutSchedulingAnimationProbe()
        let controller = WindowController(
            content: LayoutSchedulingResolvedRemovalStatusRoot(
                probe: probe,
                font: VUI.Font(textureFont)
            ),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(LayoutSchedulingResolvedRemovalStatusRoot.self)
            )
        )
        let withGC: WindowContext.WithGraphicsContext = { _, handler in
            guard let commandBuffer = renderQueue.makeCommandBuffer(),
                  let context = GraphicsContext(
                    sceneResources: controller.sceneResources,
                    environment: controller.environment,
                    viewport: CGRect(x: 0, y: 0, width: 420, height: 240),
                    contentOffset: .zero,
                    contentScaleFactor: 1,
                    resolution: CGSize(width: 420, height: 240),
                    commandBuffer: commandBuffer
                  ) else {
                return XCTFail("Unable to create the text resource graphics context.")
            }
            handler(context)
            XCTAssertTrue(commandBuffer.commit())
        }
        let startDate = controller.date
        var tick: UInt64 = 0

        func update(time: Double) throws -> (
            initial: [LayoutSchedulingResolvedTextSample],
            intermediate: [LayoutSchedulingResolvedTextSample],
            running: [LayoutSchedulingResolvedTextSample],
            completed: [LayoutSchedulingResolvedTextSample]
        ) {
            controller.updateFrame(
                tick: tick,
                delta: time - controller.animationTimestamp.seconds,
                date: startDate.addingTimeInterval(time),
                contentSize: CGSize(width: 420, height: 240),
                shouldDrawFrame: false,
                withGC
            )
            tick &+= 1
            let list = try displayList(in: controller)
            return (
                renderedResolvedTextSamples(
                    in: list,
                    matching: "Run 0: idle",
                    environment: controller.environment
                ),
                renderedResolvedTextSamples(
                    in: list,
                    matching: "Run 1: idle",
                    environment: controller.environment
                ),
                renderedResolvedTextSamples(
                    in: list,
                    matching: "Run 1: removal running",
                    environment: controller.environment
                ),
                renderedResolvedTextSamples(
                    in: list,
                    matching: "Run 1: removed completion 1",
                    environment: controller.environment
                )
            )
        }

        let initial = try update(time: 0)
        XCTAssertFalse(initial.initial.isEmpty)
        XCTAssertTrue(initial.intermediate.isEmpty)
        XCTAssertTrue(initial.running.isEmpty)
        XCTAssertTrue(initial.completed.isEmpty)

        try XCTUnwrap(probe.toggle)()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))

        for time in [0.001, 1.0 / 60.0, 0.1, 0.5, 1.25] {
            let sample = try update(time: time)
            XCTAssertTrue(
                sample.initial.allSatisfy { $0.opacity <= 0.001 },
                "The old status must not remain in presentation at \(time): \(sample.initial)"
            )
            XCTAssertTrue(
                sample.intermediate.allSatisfy { $0.opacity <= 0.001 },
                "The first of the two plain writes must not remain in presentation at \(time): \(sample.intermediate)"
            )
            XCTAssertFalse(sample.running.isEmpty, "Missing running status at \(time)")
            XCTAssertTrue(
                sample.running.allSatisfy { abs($0.opacity - 1) <= 0.001 },
                "The plain status write must reach full opacity immediately at \(time): \(sample.running)"
            )
            XCTAssertTrue(sample.completed.isEmpty)
        }

        _ = try update(time: 5.1)
        let completed = try update(time: 5.1)
        XCTAssertEqual(probe.completions, [1])
        XCTAssertTrue(
            completed.initial.allSatisfy { $0.opacity <= 0.001 }
        )
        XCTAssertTrue(
            completed.intermediate.allSatisfy { $0.opacity <= 0.001 }
        )
        XCTAssertTrue(
            completed.running.allSatisfy { $0.opacity <= 0.001 },
            "The running status must snap away at completion: \(completed.running)"
        )
        XCTAssertFalse(completed.completed.isEmpty)
        XCTAssertTrue(
            completed.completed.allSatisfy { abs($0.opacity - 1) <= 0.001 },
            "The completion status must be fully visible immediately: \(completed.completed)"
        )
    }

    @MainActor
    func testNestedOffsetScaleSurfaceSamplesOffsetDuringSpringMove() throws {
        let counter = LayoutSchedulingCounter()
        let probe = LayoutSchedulingAnimationProbe()
        let controller = WindowController(
            content: LayoutSchedulingNestedOffsetScaleRoot(counter: counter, probe: probe),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(LayoutSchedulingNestedOffsetScaleRoot.self)
            )
        )

        let withGC: WindowContext.WithGraphicsContext = { _, _ in
            XCTFail("Static animation scheduling test should not request graphics resources.")
        }

        var redraw = false
        controller.updateView(
            tick: 0,
            delta: 0,
            date: controller.date,
            contentSize: CGSize(width: 420, height: 240),
            redraw: &redraw,
            withGC
        )
        let initialDisplayList = try displayList(in: controller)
        XCTAssertEqual(try XCTUnwrap(statusMarkerBounds(in: initialDisplayList)).width, 40, accuracy: 0.5)
        let initialBounds = try XCTUnwrap(opaqueGreenShapeBounds(in: initialDisplayList).first)

        let run = try XCTUnwrap(probe.toggle)
        run()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))

        var samples: [(time: Double, bounds: CGRect, displayList: DisplayList)] = []
        for (index, sampleTime) in [0.0, 1.0 / 60.0, 2.0 / 60.0, 0.1, 1.0, 10.0, 30.0].enumerated() {
            redraw = false
            controller.updateView(
                tick: UInt64(index + 1),
                delta: sampleTime - controller.animationTimestamp.seconds,
                date: controller.date.addingTimeInterval(sampleTime),
                contentSize: CGSize(width: 420, height: 240),
                redraw: &redraw,
                withGC
            )
            let sampleDisplayList = try displayList(in: controller)
            samples.append((
                sampleTime,
                try XCTUnwrap(opaqueGreenShapeBounds(in: sampleDisplayList).first),
                sampleDisplayList
            ))
        }
        let finalDisplayList = try XCTUnwrap(samples.last?.displayList)
        let finalBounds = try XCTUnwrap(samples.last?.bounds)
        let sampledBounds = try XCTUnwrap(samples.dropFirst().dropLast().first { sample in
            sample.bounds.minY > finalBounds.minY &&
                sample.bounds.minY < initialBounds.minY
        }?.bounds)

        XCTAssertLessThan(
            finalBounds.minY,
            initialBounds.minY,
            """
            expected final marker to move upward:
            initial=\(initialBounds)
            samples=\(samples.map { ($0.time, $0.bounds) })
            final=\(finalBounds)
            initialShapes=\(shapeFillBounds(in: initialDisplayList))
            finalShapes=\(shapeFillBounds(in: finalDisplayList))
            """
        )
        XCTAssertGreaterThan(
            sampledBounds.minY,
            finalBounds.minY,
            "Expected the nested offset marker to stay above the final position during the spring."
        )
        XCTAssertLessThan(
            sampledBounds.minY,
            initialBounds.minY,
            "Expected the nested offset marker to leave its initial position during the spring."
        )
    }

    @MainActor
    func testDynamicChildOffsetScaleSurfaceSamplesOffsetDuringSpringMove() throws {
        let counter = LayoutSchedulingCounter()
        let probe = LayoutSchedulingAnimationProbe()
        let controller = WindowController(
            content: LayoutSchedulingDynamicChildOffsetScaleRoot(counter: counter, probe: probe),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(LayoutSchedulingDynamicChildOffsetScaleRoot.self)
            )
        )

        let withGC: WindowContext.WithGraphicsContext = { _, _ in
            XCTFail("Static animation scheduling test should not request graphics resources.")
        }

        var redraw = false
        controller.updateView(
            tick: 0,
            delta: 0,
            date: controller.date,
            contentSize: CGSize(width: 420, height: 240),
            redraw: &redraw,
            withGC
        )
        let initialDisplayList = try displayList(in: controller)
        let initialBounds = try XCTUnwrap(translucentShapeFillRecords(in: initialDisplayList).first?.bounds)

        let run = try XCTUnwrap(probe.toggle)
        run()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))

        var samples: [(time: Double, bounds: CGRect)] = []
        for (index, sampleTime) in [0.0, 1.0 / 60.0, 2.0 / 60.0, 0.1, 1.0, 10.0, 30.0].enumerated() {
            redraw = false
            controller.updateView(
                tick: UInt64(index + 1),
                delta: sampleTime - controller.animationTimestamp.seconds,
                date: controller.date.addingTimeInterval(sampleTime),
                contentSize: CGSize(width: 420, height: 240),
                redraw: &redraw,
                withGC
            )
            let sampleDisplayList = try displayList(in: controller)
            samples.append((sampleTime, try XCTUnwrap(translucentShapeFillRecords(in: sampleDisplayList).first?.bounds)))
        }

        let finalBounds = try XCTUnwrap(samples.last?.bounds)
        let sampledBounds = try XCTUnwrap(
            samples.dropFirst().dropLast().first { sample in
                sample.bounds.minY > finalBounds.minY &&
                    sample.bounds.minY < initialBounds.minY
            }?.bounds,
            """
            expected intermediate dynamic child offset:
            initial=\(initialBounds)
            final=\(finalBounds)
            samples=\(samples)
            """
        )

        XCTAssertLessThan(finalBounds.minY, initialBounds.minY)
        XCTAssertGreaterThan(sampledBounds.minY, finalBounds.minY)
        XCTAssertLessThan(sampledBounds.minY, initialBounds.minY)
    }

    @MainActor
    func testDynamicChildBackgroundShapeStartsGreenDuringSpringMove() throws {
        let counter = LayoutSchedulingCounter()
        let probe = LayoutSchedulingAnimationProbe()
        let controller = WindowController(
            content: LayoutSchedulingDynamicChildOffsetScaleRoot(counter: counter, probe: probe),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(LayoutSchedulingDynamicChildOffsetScaleRoot.self)
            )
        )

        let withGC: WindowContext.WithGraphicsContext = { _, _ in
            XCTFail("Static animation scheduling test should not request graphics resources.")
        }

        var redraw = false
        controller.updateView(
            tick: 0,
            delta: 0,
            date: controller.date,
            contentSize: CGSize(width: 420, height: 240),
            redraw: &redraw,
            withGC
        )
        let initialDisplayList = try displayList(in: controller)
        let initialColor = try XCTUnwrap(
            translucentShapeFillColors(in: initialDisplayList).first,
            """
            shape records: \(shapeFillDebugRecords(in: initialDisplayList))
            item records: \(initialDisplayList.itemRecords)
            """
        )
        XCTAssertLessThan(initialColor.provider.red, initialColor.provider.green)

        let run = try XCTUnwrap(probe.toggle)
        run()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))

        var samples: [(time: Double, color: VUI.Color)] = []
        for (index, sampleTime) in [0.0, 1.0 / 60.0, 2.0 / 60.0, 0.1, 1.0, 10.0, 30.0].enumerated() {
            redraw = false
            controller.updateView(
                tick: UInt64(index + 1),
                delta: sampleTime - controller.animationTimestamp.seconds,
                date: controller.date.addingTimeInterval(sampleTime),
                contentSize: CGSize(width: 420, height: 240),
                redraw: &redraw,
                withGC
            )
            let sampleDisplayList = try displayList(in: controller)
            samples.append((sampleTime, try XCTUnwrap(translucentShapeFillColors(in: sampleDisplayList).first)))
        }

        let finalColor = try XCTUnwrap(samples.last?.color)
        let sampledColor = try XCTUnwrap(
            samples.dropFirst().dropLast().first { sample in
                sample.color.provider.red > initialColor.provider.red &&
                    sample.color.provider.red < finalColor.provider.red
            }?.color,
            """
            expected intermediate dynamic child background color:
            initial=\(initialColor)
            final=\(finalColor)
            samples=\(samples.map { ($0.time, $0.color) })
            """
        )
        XCTAssertEqual(sampledColor.provider.alpha, 0.35, accuracy: 0.01)
    }

    @MainActor
    func testConditionalChildCombinedTransitionRetainsRemovalAndDelaysCompletion() throws {
        let counter = LayoutSchedulingCounter()
        let probe = LayoutSchedulingAnimationProbe()
        let controller = WindowController(
            content: LayoutSchedulingConditionalRemovalRoot(counter: counter, probe: probe),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(LayoutSchedulingConditionalRemovalRoot.self)
            )
        )

        try assertConditionalChildCombinedRemoval(in: controller, probe: probe)
    }

    @MainActor
    func testModalConditionalChildCombinedTransitionRetainsRemovalAndDelaysCompletion() throws {
        let counter = LayoutSchedulingCounter()
        let probe = LayoutSchedulingAnimationProbe()
        let parent = WindowController(
            content: EmptyView(),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(EmptyView.self)
            )
        )
        let child = parent.viewGraph.data.withCurrent {
            let sourceGraph = parent.viewGraph.data.graph
            let contentAttr: Attribute<AnyView> = sourceGraph.makeInput(
                value: AnyView(
                    SheetContent(
                        content: AnyView(
                            LayoutSchedulingConditionalRemovalRoot(counter: counter, probe: probe)
                        )
                    )
                )
            )
            return ModalWindowController(
                crossGraphContent: contentAttr,
                sourceGraph: sourceGraph,
                scene: WindowKey(
                    namespace: .app,
                    sceneID: SceneID(LayoutSchedulingConditionalRemovalRoot.self)
                ),
                parentController: parent,
                usesPlatformWindow: false
            )
        }

        try assertConditionalChildCombinedRemoval(in: child, probe: probe)
    }

    @MainActor
    private func assertConditionalChildCombinedRemoval(
        in controller: WindowController,
        probe: LayoutSchedulingAnimationProbe
    ) throws {

        let withGC: WindowContext.WithGraphicsContext = { _, _ in
            XCTFail("Static animation scheduling test should not request graphics resources.")
        }

        var redraw = false
        controller.updateView(
            tick: 0,
            delta: 0,
            date: controller.date,
            contentSize: CGSize(width: 420, height: 240),
            redraw: &redraw,
            withGC
        )
        let initialGreenBounds = try XCTUnwrap(
            opaqueGreenShapeBounds(in: try displayList(in: controller)).first
        )
        let initialBackgroundBounds = try XCTUnwrap(
            translucentGreenShapeBounds(in: try displayList(in: controller))
        )

        let removeChild = try XCTUnwrap(probe.toggle)
        removeChild()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        XCTAssertEqual(probe.completions, [])
        let immediateGreenBounds = try XCTUnwrap(
            opaqueGreenShapeBounds(in: try displayList(in: controller)).first
        )
        XCTAssertEqual(immediateGreenBounds.midX, initialGreenBounds.midX, accuracy: 0.5)
        XCTAssertEqual(immediateGreenBounds.midY, initialGreenBounds.midY, accuracy: 0.5)
        XCTAssertEqual(immediateGreenBounds.width, initialGreenBounds.width, accuracy: 0.5)
        XCTAssertEqual(immediateGreenBounds.height, initialGreenBounds.height, accuracy: 0.5)
        let immediateBackgroundBounds = try XCTUnwrap(
            translucentGreenShapeBounds(in: try displayList(in: controller))
        )
        XCTAssertEqual(immediateBackgroundBounds.midX, initialBackgroundBounds.midX, accuracy: 0.5)
        XCTAssertEqual(immediateBackgroundBounds.midY, initialBackgroundBounds.midY, accuracy: 0.5)
        XCTAssertEqual(immediateBackgroundBounds.width, initialBackgroundBounds.width, accuracy: 0.5)
        XCTAssertEqual(immediateBackgroundBounds.height, initialBackgroundBounds.height, accuracy: 0.5)

        var opacitySamples: [(time: Double, opacity: Double?)] = []
        var greenBoundsSamples: [(time: Double, bounds: CGRect)] = []
        for (index, sampleTime) in [0.0, 1.0 / 60.0, 2.0 / 60.0, 0.5, 2.5].enumerated() {
            redraw = false
            controller.updateView(
                tick: UInt64(index + 1),
                delta: sampleTime - controller.animationTimestamp.seconds,
                date: controller.date.addingTimeInterval(sampleTime),
                contentSize: CGSize(width: 420, height: 240),
                redraw: &redraw,
                withGC
            )
            let sample = try displayList(in: controller)
            opacitySamples.append((sampleTime, firstOpacity(in: sample)))
            if let bounds = opaqueGreenShapeBounds(in: sample).first {
                greenBoundsSamples.append((sampleTime, bounds))
            }
            XCTAssertEqual(probe.completions, [])
        }
        let firstGreenBounds = try XCTUnwrap(greenBoundsSamples.first?.bounds)
        XCTAssertEqual(firstGreenBounds.midX, initialGreenBounds.midX, accuracy: 0.5)
        XCTAssertEqual(firstGreenBounds.midY, initialGreenBounds.midY, accuracy: 0.5)
        XCTAssertEqual(firstGreenBounds.width, initialGreenBounds.width, accuracy: 0.5)
        XCTAssertEqual(firstGreenBounds.height, initialGreenBounds.height, accuracy: 0.5)

        let intermediateOpacity = try XCTUnwrap(opacitySamples.last?.opacity)
        XCTAssertGreaterThan(intermediateOpacity, 0)
        XCTAssertLessThan(intermediateOpacity, 1)
    }

    @MainActor
    func testSiblingPlacementSurfaceSamplesIntermediatePositionDuringSpringMove() throws {
        let counter = LayoutSchedulingCounter()
        let probe = LayoutSchedulingAnimationProbe()
        let controller = WindowController(
            content: LayoutSchedulingSiblingPlacementRoot(counter: counter, probe: probe),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(LayoutSchedulingSiblingPlacementRoot.self)
            )
        )

        let withGC: WindowContext.WithGraphicsContext = { _, _ in
            XCTFail("Static animation scheduling test should not request graphics resources.")
        }

        var redraw = false
        controller.updateView(
            tick: 0,
            delta: 0,
            date: controller.date,
            contentSize: CGSize(width: 420, height: 240),
            redraw: &redraw,
            withGC
        )
        let initialDisplayList = try displayList(in: controller)
        let initialBounds = try XCTUnwrap(siblingMarkerBounds(in: initialDisplayList))

        let run = try XCTUnwrap(probe.toggle)
        run()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))

        var samples: [(time: Double, bounds: CGRect)] = []
        for (index, sampleTime) in [0.0, 1.0 / 60.0, 2.0 / 60.0, 0.1, 1.0, 10.0, 30.0].enumerated() {
            redraw = false
            controller.updateView(
                tick: UInt64(index + 1),
                delta: sampleTime - controller.animationTimestamp.seconds,
                date: controller.date.addingTimeInterval(sampleTime),
                contentSize: CGSize(width: 420, height: 240),
                redraw: &redraw,
                withGC
            )
            let sampleDisplayList = try displayList(in: controller)
            samples.append((sampleTime, try XCTUnwrap(siblingMarkerBounds(in: sampleDisplayList))))
        }

        let finalBounds = try XCTUnwrap(samples.last?.bounds)
        let sampledBounds = try XCTUnwrap(
            samples.dropFirst().dropLast().first { sample in
                sample.bounds.minX > initialBounds.minX &&
                    sample.bounds.minX < finalBounds.minX
            }?.bounds,
            """
            expected intermediate sibling placement:
            initial=\(initialBounds)
            final=\(finalBounds)
            samples=\(samples)
            """
        )

        XCTAssertGreaterThan(finalBounds.minX, initialBounds.minX)
        XCTAssertGreaterThan(sampledBounds.minX, initialBounds.minX)
        XCTAssertLessThan(sampledBounds.minX, finalBounds.minX)
    }

    @MainActor
    func testTextLikeSiblingPlacementSurfaceSamplesIntermediatePositionDuringSpringMove() throws {
        let counter = LayoutSchedulingCounter()
        let probe = LayoutSchedulingAnimationProbe()
        let controller = WindowController(
            content: LayoutSchedulingTextSiblingPlacementRoot(counter: counter, probe: probe),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(LayoutSchedulingTextSiblingPlacementRoot.self)
            )
        )

        let withGC: WindowContext.WithGraphicsContext = { _, _ in
            XCTFail("Static animation scheduling test should not request graphics resources.")
        }

        var redraw = false
        controller.updateView(
            tick: 0,
            delta: 0,
            date: controller.date,
            contentSize: CGSize(width: 420, height: 240),
            redraw: &redraw,
            withGC
        )
        let initialDisplayList = try displayList(in: controller)
        let initialBounds = try XCTUnwrap(textBounds(in: initialDisplayList).first)

        let run = try XCTUnwrap(probe.toggle)
        run()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))

        var samples: [(time: Double, bounds: CGRect)] = []
        for (index, sampleTime) in [0.0, 1.0 / 60.0, 2.0 / 60.0, 0.1, 1.0, 10.0, 30.0].enumerated() {
            redraw = false
            controller.updateView(
                tick: UInt64(index + 1),
                delta: sampleTime - controller.animationTimestamp.seconds,
                date: controller.date.addingTimeInterval(sampleTime),
                contentSize: CGSize(width: 420, height: 240),
                redraw: &redraw,
                withGC
            )
            let sampleDisplayList = try displayList(in: controller)
            samples.append((sampleTime, try XCTUnwrap(textBounds(in: sampleDisplayList).first)))
        }

        let finalBounds = try XCTUnwrap(samples.last?.bounds)
        let sampledBounds = try XCTUnwrap(
            samples.dropFirst().dropLast().first { sample in
                sample.bounds.minX > initialBounds.minX &&
                    sample.bounds.minX < finalBounds.minX
            }?.bounds,
            """
            expected intermediate text placement:
            initial=\(initialBounds)
            final=\(finalBounds)
            samples=\(samples)
            """
        )

        XCTAssertGreaterThan(finalBounds.minX, initialBounds.minX)
        XCTAssertGreaterThan(sampledBounds.minX, initialBounds.minX)
        XCTAssertLessThan(sampledBounds.minX, finalBounds.minX)
    }

    @MainActor
    func testStaticButtonLabelSamplesIntermediatePositionWhenSiblingLabelWidthChanges() throws {
        let counter = LayoutSchedulingCounter()
        let probe = LayoutSchedulingAnimationProbe()
        let controller = WindowController(
            content: LayoutSchedulingButtonLabelPlacementRoot(counter: counter, probe: probe),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(LayoutSchedulingButtonLabelPlacementRoot.self)
            )
        )

        let withGC: WindowContext.WithGraphicsContext = { _, _ in
            XCTFail("Static button label scheduling test should not request graphics resources.")
        }

        var redraw = false
        controller.updateView(
            tick: 0,
            delta: 0,
            date: controller.date,
            contentSize: CGSize(width: 420, height: 240),
            redraw: &redraw,
            withGC
        )
        let initialDisplayList = try displayList(in: controller)
        let initialBounds = try XCTUnwrap(textBounds(in: initialDisplayList).min { $0.minX < $1.minX })

        let run = try XCTUnwrap(probe.toggle)
        run()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))

        var samples: [(time: Double, bounds: CGRect)] = []
        for (index, sampleTime) in [0.0, 1.0 / 60.0, 2.0 / 60.0, 0.1, 1.0, 10.0, 30.0].enumerated() {
            redraw = false
            controller.updateView(
                tick: UInt64(index + 1),
                delta: sampleTime - controller.animationTimestamp.seconds,
                date: controller.date.addingTimeInterval(sampleTime),
                contentSize: CGSize(width: 420, height: 240),
                redraw: &redraw,
                withGC
            )
            let sampleDisplayList = try displayList(in: controller)
            samples.append((
                sampleTime,
                try XCTUnwrap(textBounds(in: sampleDisplayList).min { $0.minX < $1.minX })
            ))
        }

        let finalBounds = try XCTUnwrap(samples.last?.bounds)
        let sampledBounds = try XCTUnwrap(
            samples.dropFirst().dropLast().first { sample in
                sample.bounds.minX < initialBounds.minX &&
                    sample.bounds.minX > finalBounds.minX
            }?.bounds,
            """
            expected intermediate static button label placement:
            initial=\(initialBounds)
            final=\(finalBounds)
            samples=\(samples)
            """
        )

        XCTAssertLessThan(finalBounds.minX, initialBounds.minX)
        XCTAssertLessThan(sampledBounds.minX, initialBounds.minX)
        XCTAssertGreaterThan(sampledBounds.minX, finalBounds.minX)
    }

    @MainActor
    func testAnimationLabConditionalButtonSamplesIntermediateWidthDuringRemoval() throws {
        let counter = LayoutSchedulingCounter()
        let probe = LayoutSchedulingAnimationProbe()
        let controller = WindowController(
            content: LayoutSchedulingAnimationLabButtonRowRoot(
                counter: counter,
                probe: probe
            ),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(LayoutSchedulingAnimationLabButtonRowRoot.self)
            )
        )
        let withGC: WindowContext.WithGraphicsContext = { _, _ in
            XCTFail("Animation Lab button scheduling test should not request graphics resources.")
        }
        let startDate = controller.date
        var redraw = false
        var tick: UInt64 = 0

        func update(time: Double) throws -> CGRect {
            redraw = false
            controller.updateView(
                tick: tick,
                delta: time - controller.animationTimestamp.seconds,
                date: startDate.addingTimeInterval(time),
                contentSize: CGSize(width: 560, height: 120),
                redraw: &redraw,
                withGC
            )
            tick += 1
            let buttons = shapeStrokeBounds(in: try displayList(in: controller))
                .filter { $0.width > 40 && $0.height > 15 && $0.height < 50 }
                .sorted { $0.minX < $1.minX }
            XCTAssertEqual(buttons.count, 4, "unexpected button strokes at \(time): \(buttons)")
            return try XCTUnwrap(buttons.dropFirst().first)
        }

        let initialBounds = try update(time: 0)
        try XCTUnwrap(probe.toggle)()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))

        var samples: [(time: Double, bounds: CGRect)] = []
        for time in [0.001, 1.0 / 60.0, 0.1, 1.0, 2.5, 4.0, 5.1] {
            samples.append((time, try update(time: time)))
        }

        let finalBounds = try XCTUnwrap(samples.last?.bounds)
        XCTAssertNotEqual(initialBounds.width, finalBounds.width, accuracy: 0.01)
        let lower = min(initialBounds.width, finalBounds.width)
        let upper = max(initialBounds.width, finalBounds.width)
        XCTAssertNotNil(
            samples.dropLast().first { sample in
                sample.bounds.width > lower + 0.01 && sample.bounds.width < upper - 0.01
            },
            "expected intermediate button width: initial=\(initialBounds) final=\(finalBounds) samples=\(samples)"
        )
    }

    // ASSERTIONS graphHostSeedMutationLifecycleObserved
    @MainActor
    func testResolvedTextButtonBorderSamplesIntermediateWidthWhenLabelChanges() throws {
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
        appContext = LayoutSchedulingAppContext(
            graphicsDeviceContext: deviceContext
        )
        defer { appContext = previousAppContext }

        let probe = LayoutSchedulingAnimationProbe()
        let controller = WindowController(
            content: LayoutSchedulingResolvedTextButtonRowRoot(
                probe: probe,
                font: VUI.Font(textureFont)
            ),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(LayoutSchedulingResolvedTextButtonRowRoot.self)
            )
        )
        let withGC: WindowContext.WithGraphicsContext = { _, handler in
            guard let commandBuffer = renderQueue.makeCommandBuffer(),
                  let context = GraphicsContext(
                    sceneResources: controller.sceneResources,
                    environment: controller.environment,
                    viewport: CGRect(x: 0, y: 0, width: 560, height: 120),
                    contentOffset: .zero,
                    contentScaleFactor: 1,
                    resolution: CGSize(width: 560, height: 120),
                    commandBuffer: commandBuffer
                  ) else {
                return XCTFail("Unable to create the text resource graphics context.")
            }
            handler(context)
            XCTAssertTrue(commandBuffer.commit())
        }
        let startDate = controller.date
        var tick: UInt64 = 0

        func update(time: Double) throws -> CGRect {
            controller.updateFrame(
                tick: tick,
                delta: time - controller.animationTimestamp.seconds,
                date: startDate.addingTimeInterval(time),
                contentSize: CGSize(width: 560, height: 120),
                shouldDrawFrame: false,
                withGC
            )
            tick &+= 1
            let buttons = shapeStrokeBounds(in: try displayList(in: controller))
                .filter { $0.width > 30 && $0.height > 15 && $0.height < 50 }
                .sorted { $0.minX < $1.minX }
            XCTAssertEqual(buttons.count, 4, "unexpected button strokes at \(time): \(buttons)")
            return try XCTUnwrap(buttons.dropFirst().first)
        }

        let initialBounds = try update(time: 0)
        try XCTUnwrap(probe.toggle)()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))

        var samples: [(time: Double, bounds: CGRect)] = []
        for time in [0.001, 1.0 / 60.0, 0.1, 1.0, 2.5, 4.0, 5.1] {
            samples.append((time, try update(time: time)))
        }

        let finalBounds = try XCTUnwrap(samples.last?.bounds)
        XCTAssertNotEqual(initialBounds.width, finalBounds.width, accuracy: 0.01)
        let lower = min(initialBounds.width, finalBounds.width)
        let upper = max(initialBounds.width, finalBounds.width)
        XCTAssertNotNil(
            samples.dropLast().first { sample in
                sample.bounds.width > lower + 0.01 && sample.bounds.width < upper - 0.01
            },
            "expected intermediate button width: initial=\(initialBounds) final=\(finalBounds) samples=\(samples)"
        )
    }

    // ASSERTIONS graphHostSeedMutationLifecycleObserved
    @MainActor
    func testResolvedTextContentChangeMovesRetainedHeadingAndButtonContinuously() throws {
        guard let deviceContext = makeGraphicsDeviceContext(api: .metal),
              let renderQueue = deviceContext.renderQueue() else {
            throw XCTSkip("Metal graphics device unavailable")
        }
        let previousAppContext = appContext
        appContext = LayoutSchedulingAppContext(
            graphicsDeviceContext: deviceContext
        )
        defer { appContext = previousAppContext }

        let probe = LayoutSchedulingAnimationProbe()
        let controller = WindowController(
            content: LayoutSchedulingResolvedContentGeometryRoot(probe: probe),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(LayoutSchedulingResolvedContentGeometryRoot.self)
            )
        )
        let withGC: WindowContext.WithGraphicsContext = { _, handler in
            guard let commandBuffer = renderQueue.makeCommandBuffer(),
                  let context = GraphicsContext(
                    sceneResources: controller.sceneResources,
                    environment: controller.environment,
                    viewport: CGRect(x: 0, y: 0, width: 320, height: 240),
                    contentOffset: .zero,
                    contentScaleFactor: 1,
                    resolution: CGSize(width: 320, height: 240),
                    commandBuffer: commandBuffer
                  ) else {
                return XCTFail("Unable to create the text resource graphics context.")
            }
            handler(context)
            XCTAssertTrue(commandBuffer.commit())
        }
        let startDate = controller.date
        var tick: UInt64 = 0

        func update(time: Double) throws -> (
            heading: CGRect,
            buttonLabel: CGRect,
            buttonBorder: CGRect,
            compact: [LayoutSchedulingResolvedTextSample],
            expanded: [LayoutSchedulingResolvedTextSample]
        ) {
            controller.updateFrame(
                tick: tick,
                delta: time - controller.animationTimestamp.seconds,
                date: startDate.addingTimeInterval(time),
                contentSize: CGSize(width: 320, height: 240),
                shouldDrawFrame: false,
                withGC
            )
            tick &+= 1
            let list = try displayList(in: controller)
            let heading = try XCTUnwrap(
                renderedResolvedTextSamples(
                    in: list,
                    matching: "Interpolate",
                    environment: controller.environment
                ).last?.frame
            )
            let buttonLabel = try XCTUnwrap(
                renderedResolvedTextSamples(
                    in: list,
                    matching: "Change Text",
                    environment: controller.environment
                ).last?.frame
            )
            let buttonBorder = try XCTUnwrap(
                shapeStrokeBounds(in: list).first {
                    $0.width > 40 && $0.height > 15 && $0.height < 50
                }
            )
            return (
                heading,
                buttonLabel,
                buttonBorder,
                renderedResolvedTextSamples(
                    in: list,
                    matching: "Compact",
                    environment: controller.environment
                ),
                renderedResolvedTextSamples(
                    in: list,
                    matching: "Expanded value",
                    environment: controller.environment
                )
            )
        }

        let initial = try update(time: 0)
        try XCTUnwrap(probe.toggle)()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))

        var samples: [(
            time: Double,
            heading: CGRect,
            buttonLabel: CGRect,
            buttonBorder: CGRect,
            compact: [LayoutSchedulingResolvedTextSample],
            expanded: [LayoutSchedulingResolvedTextSample]
        )] = []
        for time in [0.001, 1.0 / 60.0, 0.1, 0.7, 1.4, 2.5, 5.1] {
            let sample = try update(time: time)
            samples.append((
                time,
                sample.heading,
                sample.buttonLabel,
                sample.buttonBorder,
                sample.compact,
                sample.expanded
            ))
        }

        let final = try XCTUnwrap(samples.last)
        XCTAssertNotEqual(initial.heading.midY, final.heading.midY, accuracy: 0.01)
        XCTAssertNotEqual(initial.buttonLabel.midY, final.buttonLabel.midY, accuracy: 0.01)
        XCTAssertNotEqual(initial.buttonBorder.midY, final.buttonBorder.midY, accuracy: 0.01)

        func liesBetween(_ value: CGFloat, _ lhs: CGFloat, _ rhs: CGFloat) -> Bool {
            value > min(lhs, rhs) + 0.01 && value < max(lhs, rhs) - 0.01
        }

        XCTAssertNotNil(
            samples.dropLast().first {
                liesBetween($0.heading.midY, initial.heading.midY, final.heading.midY)
            },
            "expected intermediate heading position: initial=\(initial) final=\(final) samples=\(samples)"
        )
        XCTAssertNotNil(
            samples.dropLast().first {
                liesBetween($0.buttonLabel.midY, initial.buttonLabel.midY, final.buttonLabel.midY)
            },
            "expected intermediate button-label position: initial=\(initial) final=\(final) samples=\(samples)"
        )
        XCTAssertNotNil(
            samples.dropLast().first {
                liesBetween($0.buttonBorder.midY, initial.buttonBorder.midY, final.buttonBorder.midY)
            },
            "expected intermediate button-border position: initial=\(initial) final=\(final) samples=\(samples)"
        )
        for sample in samples {
            XCTAssertEqual(
                sample.buttonLabel.midX,
                sample.buttonBorder.midX,
                accuracy: 0.75,
                "button label moved horizontally inside its border: \(samples)"
            )
            for text in sample.compact + sample.expanded where text.opacity > 0.001 {
                XCTAssertEqual(
                    text.frame.midX,
                    160,
                    accuracy: 1.25,
                    "changed text moved horizontally at \(sample.time): \(samples)"
                )
            }
        }
    }

    // ASSERTIONS interpolatedDisplayListFinalTranslationObserved
    // ASSERTIONS shapeStyleUnchangedTextPresentationOffsetObserved
    @MainActor
    func testResolvedAnimationLabVariantTextStaysCenteredDuringSpringMove() throws {
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
        appContext = LayoutSchedulingAppContext(
            graphicsDeviceContext: deviceContext
        )
        defer { appContext = previousAppContext }

        let probe = LayoutSchedulingAnimationProbe()
        let controller = WindowController(
            content: LayoutSchedulingResolvedAnimationLabSpringRoot(
                probe: probe,
                font: VUI.Font(textureFont)
            ),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(LayoutSchedulingResolvedAnimationLabSpringRoot.self)
            )
        )
        let withGC: WindowContext.WithGraphicsContext = { _, handler in
            guard let commandBuffer = renderQueue.makeCommandBuffer(),
                  let context = GraphicsContext(
                    sceneResources: controller.sceneResources,
                    environment: controller.environment,
                    viewport: CGRect(x: 0, y: 0, width: 560, height: 360),
                    contentOffset: .zero,
                    contentScaleFactor: 1,
                    resolution: CGSize(width: 560, height: 360),
                    commandBuffer: commandBuffer
                  ) else {
                return XCTFail("Unable to create the text resource graphics context.")
            }
            handler(context)
            XCTAssertTrue(commandBuffer.commit())
        }
        let startDate = controller.date
        var tick: UInt64 = 0

        func update(time: Double) throws -> (
            background: CGRect,
            compact: [LayoutSchedulingResolvedTextSample],
            expanded: [LayoutSchedulingResolvedTextSample]
        ) {
            controller.updateFrame(
                tick: tick,
                delta: time - controller.animationTimestamp.seconds,
                date: startDate.addingTimeInterval(time),
                contentSize: CGSize(width: 560, height: 360),
                shouldDrawFrame: false,
                withGC
            )
            tick &+= 1
            let list = try displayList(in: controller)
            let background = try XCTUnwrap(
                translucentShapeFillRecords(in: list).first?.bounds
            )
            return (
                background,
                renderedResolvedTextSamples(
                    in: list,
                    matching: "compact",
                    environment: controller.environment
                ),
                renderedResolvedTextSamples(
                    in: list,
                    matching: "expanded",
                    environment: controller.environment
                )
            )
        }

        let initial = try update(time: 0)
        XCTAssertFalse(initial.compact.isEmpty)
        for text in initial.compact {
            XCTAssertEqual(text.frame.midX, initial.background.midX, accuracy: 1.1)
        }

        try XCTUnwrap(probe.toggle)()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        for time in [0.001, 1.0 / 60.0, 0.1, 0.5, 1.25, 2.5, 5.1] {
            let sample = try update(time: time)
            let texts = sample.compact + sample.expanded
            XCTAssertFalse(texts.isEmpty, "missing variant text at \(time)")
            for text in texts where text.opacity > 0.001 {
                XCTAssertEqual(
                    text.frame.midX,
                    sample.background.midX,
                    accuracy: 3,
                    "variant text left the child center at \(time): \(sample)"
                )
            }
        }
    }

    // ASSERTIONS dynamicLayoutRetainedGeometryPreservationObserved
    @MainActor
    func testAnimationLabRetainedChildKeepsLastPublishedGeometryDuringRemoval() throws {
        let counter = LayoutSchedulingCounter()
        let probe = LayoutSchedulingAnimationLabProbe()
        let controller = WindowController(
            content: LayoutSchedulingReinsertedAnimationLabChildRoot(
                counter: counter,
                probe: probe
            ),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(LayoutSchedulingReinsertedAnimationLabChildRoot.self)
            )
        )
        let withGC: WindowContext.WithGraphicsContext = { _, _ in
            XCTFail("Retained geometry test should not request graphics resources.")
        }
        let startDate = controller.date
        var redraw = false
        var tick: UInt64 = 0

        func update(time: Double) {
            redraw = false
            controller.updateView(
                tick: tick,
                delta: time - controller.animationTimestamp.seconds,
                date: startDate.addingTimeInterval(time),
                contentSize: CGSize(width: 560, height: 360),
                redraw: &redraw,
                withGC
            )
            tick += 1
        }

        func childGeometry() throws -> (CGPoint, CGSize) {
            try controller.viewGraph.data.withCurrent {
                let position = try XCTUnwrap(probe.text.insertionPosition)
                let size = try XCTUnwrap(probe.text.insertionSize)
                return (position.value, size.value.value)
            }
        }

        update(time: 0)
        let initial = try childGeometry()

        try XCTUnwrap(probe.removeChild)()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        for time in [0.001, 1.0, 2.5] {
            update(time: time)
            let retained = try childGeometry()
            XCTAssertEqual(retained.0.x, initial.0.x, accuracy: 0.001)
            XCTAssertEqual(retained.0.y, initial.0.y, accuracy: 0.001)
            XCTAssertEqual(retained.1.width, initial.1.width, accuracy: 0.001)
            XCTAssertEqual(retained.1.height, initial.1.height, accuracy: 0.001)
        }
    }

    @MainActor
    func testAnimationLabRemovalTitleSamplesIntermediateVerticalPosition() throws {
        let counter = LayoutSchedulingCounter()
        let probe = LayoutSchedulingAnimationLabProbe()
        let controller = WindowController(
            content: LayoutSchedulingReinsertedAnimationLabChildRoot(
                counter: counter,
                probe: probe
            ),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(LayoutSchedulingReinsertedAnimationLabChildRoot.self)
            )
        )
        let withGC: WindowContext.WithGraphicsContext = { _, _ in
            XCTFail("Animation Lab title scheduling test should not request graphics resources.")
        }
        let startDate = controller.date
        var redraw = false
        var tick: UInt64 = 0

        func update(time: Double) throws -> CGRect {
            redraw = false
            controller.updateView(
                tick: tick,
                delta: time - controller.animationTimestamp.seconds,
                date: startDate.addingTimeInterval(time),
                contentSize: CGSize(width: 560, height: 360),
                redraw: &redraw,
                withGC
            )
            tick += 1
            return try XCTUnwrap(
                textBounds(in: try displayList(in: controller)).first {
                    abs($0.width - 160) <= 0.5 && abs($0.height - 20) <= 0.5
                }
            )
        }

        let initialBounds = try update(time: 0)
        try XCTUnwrap(probe.removeChild)()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))

        var samples: [(time: Double, bounds: CGRect)] = []
        for time in [0.001, 1.0 / 60.0, 0.1, 1.0, 2.5, 4.0, 5.1] {
            samples.append((time, try update(time: time)))
        }

        let finalBounds = try XCTUnwrap(samples.last?.bounds)
        XCTAssertGreaterThan(finalBounds.minY, initialBounds.minY)
        XCTAssertNotNil(
            samples.dropLast().first { sample in
                sample.bounds.minY > initialBounds.minY + 0.01 &&
                    sample.bounds.minY < finalBounds.minY - 0.01
            },
            "expected intermediate title position: initial=\(initialBounds) final=\(finalBounds) samples=\(samples)"
        )
        for pair in zip(samples, samples.dropFirst()) {
            XCTAssertGreaterThanOrEqual(
                pair.1.bounds.minY + 0.01,
                pair.0.bounds.minY,
                "title reversed vertically: initial=\(initialBounds) final=\(finalBounds) samples=\(samples)"
            )
        }
    }

    // ASSERTIONS animationLabRemovalTitleVerticalMonotonicObserved
    @MainActor
    func testResolvedAnimationLabRemovalTitleSamplesIntermediateVerticalPosition() throws {
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
        appContext = LayoutSchedulingAppContext(
            graphicsDeviceContext: deviceContext
        )
        defer { appContext = previousAppContext }

        let probe = LayoutSchedulingAnimationLabProbe()
        let controller = WindowController(
            content: LayoutSchedulingResolvedAnimationLabRemovalTitleRoot(
                probe: probe,
                font: VUI.Font(textureFont)
            ),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(
                    LayoutSchedulingResolvedAnimationLabRemovalTitleRoot.self
                )
            )
        )
        let withGC: WindowContext.WithGraphicsContext = { _, handler in
            guard let commandBuffer = renderQueue.makeCommandBuffer(),
                  let context = GraphicsContext(
                    sceneResources: controller.sceneResources,
                    environment: controller.environment,
                    viewport: CGRect(x: 0, y: 0, width: 560, height: 360),
                    contentOffset: .zero,
                    contentScaleFactor: 1,
                    resolution: CGSize(width: 560, height: 360),
                    commandBuffer: commandBuffer
                  ) else {
                return XCTFail("Unable to create the text resource graphics context.")
            }
            handler(context)
            XCTAssertTrue(commandBuffer.commit())
        }
        let startDate = controller.date
        var tick: UInt64 = 0

        func update(time: Double) throws -> CGRect {
            controller.updateFrame(
                tick: tick,
                delta: time - controller.animationTimestamp.seconds,
                date: startDate.addingTimeInterval(time),
                contentSize: CGSize(width: 560, height: 360),
                shouldDrawFrame: false,
                withGC
            )
            tick &+= 1
            let samples = renderedResolvedTextSamples(
                in: try displayList(in: controller),
                matching: "Retained removal",
                environment: controller.environment
            )
            return try XCTUnwrap(
                samples.max { $0.opacity < $1.opacity }?.frame,
                "missing resolved retained-removal title at \(time)"
            )
        }

        let initialBounds = try update(time: 0)
        try XCTUnwrap(probe.removeChild)()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))

        var samples: [(time: Double, bounds: CGRect)] = []
        for time in [0.001, 1.0 / 60.0, 0.1, 0.5, 1.0, 2.5, 4.0, 5.1] {
            samples.append((time, try update(time: time)))
        }

        let finalBounds = try XCTUnwrap(samples.last?.bounds)
        XCTAssertNotEqual(initialBounds.midY, finalBounds.midY, accuracy: 0.01)
        XCTAssertNotNil(
            samples.dropLast().first { sample in
                sample.bounds.midY > min(initialBounds.midY, finalBounds.midY) + 0.01 &&
                    sample.bounds.midY < max(initialBounds.midY, finalBounds.midY) - 0.01
            },
            "expected intermediate resolved title position: initial=\(initialBounds) final=\(finalBounds) samples=\(samples)"
        )

        try XCTUnwrap(probe.insertChild)()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        var insertionSamples: [(time: Double, bounds: CGRect)] = []
        for offset in [0.001, 1.0 / 60.0, 0.1, 0.5, 1.0, 2.5, 4.0, 5.1] {
            insertionSamples.append((
                time: 5.1 + offset,
                bounds: try update(time: 5.1 + offset)
            ))
        }
        let insertionFinal = try XCTUnwrap(insertionSamples.last?.bounds)
        XCTAssertEqual(insertionFinal.midY, initialBounds.midY, accuracy: 0.01)
        XCTAssertNotNil(
            insertionSamples.dropLast().first { sample in
                sample.bounds.midY > min(finalBounds.midY, insertionFinal.midY) + 0.01 &&
                    sample.bounds.midY < max(finalBounds.midY, insertionFinal.midY) - 0.01
            },
            "expected existing insertion animation to remain continuous: start=\(finalBounds) final=\(insertionFinal) samples=\(insertionSamples)"
        )
    }

    @MainActor
    func testAnimationLabReplacementTextStaysAtInsertionPositionDuringRemoval() throws {
        guard let deviceContext = makeGraphicsDeviceContext(api: .metal),
              let renderQueue = deviceContext.renderQueue(),
              let fontURL = defaultFontURL,
              let textureFont = TextureFont(
                deviceContext: deviceContext,
                path: fontURL.path
              ) else {
            throw XCTSkip("Metal graphics device unavailable")
        }
        let textFont = VUI.Font(textureFont)
        let previousAppContext = appContext
        let testAppContext = LayoutSchedulingAppContext(
            graphicsDeviceContext: deviceContext
        )
        appContext = testAppContext
        defer { appContext = previousAppContext }
        let counter = LayoutSchedulingCounter()
        let probe = LayoutSchedulingAnimationLabProbe()
        let controller = WindowController(
            content: LayoutSchedulingAnimationLabReplacementRoot(
                counter: counter,
                probe: probe,
                font: textFont
            ),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(LayoutSchedulingAnimationLabReplacementRoot.self)
            )
        )
        let withGC: WindowContext.WithGraphicsContext = { _, handler in
            guard let commandBuffer = renderQueue.makeCommandBuffer(),
                  let context = GraphicsContext(
                    sceneResources: controller.sceneResources,
                    environment: controller.environment,
                    viewport: CGRect(x: 0, y: 0, width: 560, height: 360),
                    contentOffset: .zero,
                    contentScaleFactor: 1,
                    resolution: CGSize(width: 560, height: 360),
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

        func update(time: Double) throws -> LayoutSchedulingResolvedTextSample? {
            controller.updateFrame(
                tick: tick,
                delta: time - controller.animationTimestamp.seconds,
                date: startDate.addingTimeInterval(time),
                contentSize: CGSize(width: 560, height: 360),
                shouldDrawFrame: false,
                withGC
            )
            tick &+= 1
            let list = try displayList(in: controller)
            let samples = renderedResolvedTextSamples(
                in: list,
                matching: "child removed",
                environment: controller.environment
            )
            return samples.last
        }

        func renderedInsertionPixels(
            in list: DisplayList,
            titleFrame: CGRect,
            detailFrame: CGRect
        ) throws -> (
            titleBounds: CGRect?,
            titleSpread: Double?,
            detailDarkness: Double?,
            backgroundBounds: CGRect?
        ) {
            let width = 560
            let height = 360
            let commandBuffer = try XCTUnwrap(renderQueue.makeCommandBuffer())
            let context = try XCTUnwrap(GraphicsContext(
                sceneResources: controller.sceneResources,
                environment: controller.environment,
                viewport: CGRect(x: 0, y: 0, width: width, height: height),
                contentOffset: .zero,
                contentScaleFactor: 1,
                resolution: CGSize(width: width, height: height),
                commandBuffer: commandBuffer
            ))
            context.clear(with: .white)
            renderer.render(
                list: list,
                at: controller.animationTimestamp,
                in: context
            )
            let condition = NSCondition()
            var completed = false
            commandBuffer.addCompletedHandler { _ in
                condition.lock()
                completed = true
                condition.broadcast()
                condition.unlock()
            }
            condition.lock()
            XCTAssertTrue(commandBuffer.commit())
            let timeout = Date(timeIntervalSinceNow: 5)
            while !completed {
                if !condition.wait(until: timeout) {
                    XCTFail("GPU command buffer timed out")
                    break
                }
            }
            condition.unlock()

            let staging = try XCTUnwrap(
                deviceContext.makeCPUAccessible(texture: context.backdrop)
            )
            let pointer = try XCTUnwrap(staging.contents())
            let bytes = UnsafeRawBufferPointer(
                start: pointer,
                count: width * height * 4
            )

            func luminance(x: Int, y: Int) -> Double {
                let offset = (y * width + x) * 4
                return (
                    Double(bytes[offset]) +
                        Double(bytes[offset + 1]) +
                        Double(bytes[offset + 2])
                ) / 3
            }

            var backgroundMinX = width
            var backgroundMinY = height
            var backgroundMaxX = -1
            var backgroundMaxY = -1
            for y in 0..<height {
                for x in 0..<width {
                    let offset = (y * width + x) * 4
                    let red = Int(bytes[offset])
                    let green = Int(bytes[offset + 1])
                    let blue = Int(bytes[offset + 2])
                    if green > red + 8, green > blue + 8 {
                        backgroundMinX = min(backgroundMinX, x)
                        backgroundMinY = min(backgroundMinY, y)
                        backgroundMaxX = max(backgroundMaxX, x)
                        backgroundMaxY = max(backgroundMaxY, y)
                    }
                }
            }
            let backgroundBounds: CGRect? =
                if backgroundMaxX >= backgroundMinX,
                   backgroundMaxY >= backgroundMinY {
                    CGRect(
                        x: backgroundMinX,
                        y: backgroundMinY,
                        width: backgroundMaxX - backgroundMinX + 1,
                        height: backgroundMaxY - backgroundMinY + 1
                    )
                } else {
                    nil
                }

            var minX = width
            var minY = height
            var maxX = -1
            var maxY = -1
            let titleFrame = titleFrame.standardized
            let titleRegion = CGRect(
                x: titleFrame.minX - 6,
                y: titleFrame.minY,
                width: titleFrame.width + 12,
                height: max(
                    min(titleFrame.maxY, detailFrame.standardized.minY - 0.5) -
                        titleFrame.minY,
                    0
                )
            )
            let titleMinX = max(Int(floor(titleRegion.minX)), 0)
            let titleMaxX = min(Int(ceil(titleRegion.maxX)), width)
            let titleMinY = max(Int(floor(titleRegion.minY)), 0)
            let titleMaxY = min(Int(ceil(titleRegion.maxY)), height)
            var titleWeights: [(x: Int, y: Int, value: Double)] = []
            var maximumTitleWeight = 0.0
            for y in titleMinY..<titleMaxY {
                for x in titleMinX..<titleMaxX {
                    let offset = (y * width + x) * 4
                    let value = max(
                        255 - max(
                            Double(bytes[offset]),
                            Double(bytes[offset + 1]),
                            Double(bytes[offset + 2])
                        ),
                        0
                    )
                    maximumTitleWeight = max(maximumTitleWeight, value)
                    titleWeights.append((x, y, value))
                }
            }
            var totalTitleWeight = 0.0
            var weightedTitleX = 0.0
            var weightedTitleX2 = 0.0
            let titleWeightThreshold = maximumTitleWeight * 0.08
            for sample in titleWeights where sample.value > titleWeightThreshold {
                minX = min(minX, sample.x)
                minY = min(minY, sample.y)
                maxX = max(maxX, sample.x)
                maxY = max(maxY, sample.y)
                totalTitleWeight += sample.value
                weightedTitleX += Double(sample.x) * sample.value
                weightedTitleX2 += Double(sample.x * sample.x) * sample.value
            }
            let titleBounds: CGRect? = if maxX >= minX, maxY >= minY {
                CGRect(
                    x: minX,
                    y: minY,
                    width: maxX - minX + 1,
                    height: maxY - minY + 1
                )
            } else {
                nil
            }
            let titleSpread: Double? = if totalTitleWeight > 0 {
                sqrt(max(
                    weightedTitleX2 / totalTitleWeight -
                        pow(weightedTitleX / totalTitleWeight, 2),
                    0
                ))
            } else {
                nil
            }

            let detail = detailFrame.standardized
            let detailMinX = max(Int(floor(detail.minX)) - 1, 0)
            let detailMaxX = min(Int(ceil(detail.maxX)) + 1, width)
            let detailMinY = max(Int(floor(detail.minY)) - 1, 0)
            let detailMaxY = min(Int(ceil(detail.maxY)) + 1, height)
            let detailBackgroundMinY = min(detailMaxY + 2, height)
            let detailBackgroundMaxY = min(detailBackgroundMinY + 4, height)
            guard detailMinX < detailMaxX,
                  detailMinY < detailMaxY,
                  detailBackgroundMinY < detailBackgroundMaxY else {
                return (titleBounds, titleSpread, nil, backgroundBounds)
            }

            var backgroundSum = 0.0
            var backgroundCount = 0
            for y in detailBackgroundMinY..<detailBackgroundMaxY {
                for x in detailMinX..<detailMaxX {
                    backgroundSum += luminance(x: x, y: y)
                    backgroundCount += 1
                }
            }
            let background = backgroundSum / Double(backgroundCount)
            var darkness = 0.0
            for y in detailMinY..<detailMaxY {
                for x in detailMinX..<detailMaxX {
                    darkness += max(background - luminance(x: x, y: y), 0)
                }
            }
            return (titleBounds, titleSpread, darkness, backgroundBounds)
        }

        XCTAssertNil(try update(time: 0))
        try XCTUnwrap(probe.removeChild)()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))

        let samples = try [
            0.001,
            1.0 / 60.0,
            2.0 / 60.0,
            0.10,
            0.50,
            1.25,
            2.50,
            6.00,
        ].compactMap { time in
            try update(time: time)
        }
        let final = try XCTUnwrap(samples.last)
        XCTAssertFalse(samples.isEmpty)
        for sample in samples {
            XCTAssertEqual(sample.frame.midX, final.frame.midX, accuracy: 0.001, "\(samples)")
            XCTAssertEqual(sample.frame.midY, final.frame.midY, accuracy: 0.001, "\(samples)")
        }
        XCTAssertLessThan(try XCTUnwrap(samples.first).opacity, final.opacity)
        XCTAssertEqual(final.opacity, 1, accuracy: 0.001)

        try XCTUnwrap(probe.insertChild)()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))

        let insertionSamples: [LayoutSchedulingAnimationLabInsertionSample] = try [
            6.001,
            6.0 + 1.0 / 60.0,
            6.0 + 2.0 / 60.0,
            6.10,
            6.50,
            7.25,
            8.50,
            10.35,
            10.90,
            11.10,
        ].map { time in
            _ = try update(time: time)
            let list = try displayList(in: controller)
            let title = renderedResolvedTextSamples(
                in: list,
                matching: "Animated child",
                environment: controller.environment
            ).last
            let detail = renderedResolvedTextSamples(
                in: list,
                matching: "compact",
                environment: controller.environment
            ).last
            let pixels: (
                titleBounds: CGRect?,
                titleSpread: Double?,
                detailDarkness: Double?,
                backgroundBounds: CGRect?
            ) =
                if time >= 7.25, let title, let detail {
                try renderedInsertionPixels(
                    in: list,
                    titleFrame: title.frame,
                    detailFrame: detail.frame
                )
            } else {
                (
                    titleBounds: nil,
                    titleSpread: nil,
                    detailDarkness: nil,
                    backgroundBounds: nil
                )
            }
            return LayoutSchedulingAnimationLabInsertionSample(
                time: time,
                title: title,
                detail: detail,
                titlePixels: pixels.titleBounds,
                titlePixelSpread: pixels.titleSpread,
                detailPixelDarkness: pixels.detailDarkness,
                backgroundPixels: pixels.backgroundBounds
            )
        }
        let insertedFinal = try XCTUnwrap(insertionSamples.last?.title)
        let detailFinal = try XCTUnwrap(insertionSamples.last?.detail)
        let insertedIntermediate = try XCTUnwrap(
            insertionSamples.dropLast().compactMap { $0.title }.first {
                $0.opacity > 0.001 && $0.opacity < 0.999
            },
            "expected an intermediate insertion opacity: \(insertionSamples)"
        )
        XCTAssertLessThan(insertedIntermediate.opacity, insertedFinal.opacity)
        XCTAssertEqual(insertedFinal.opacity, 1, accuracy: 0.001)
        let scaledIntermediate = try XCTUnwrap(
            insertionSamples.first(where: { abs($0.time - 8.50) < 0.001 })?.title
        )
        let scaledDetailIntermediate = try XCTUnwrap(
            insertionSamples.first(where: { abs($0.time - 8.50) < 0.001 })?.detail
        )
        XCTAssertLessThan(
            scaledIntermediate.frame.width,
            insertedFinal.frame.width - 0.25,
            "Animated child must share the insertion scale: \(insertionSamples)"
        )
        XCTAssertLessThan(
            scaledDetailIntermediate.frame.width,
            detailFinal.frame.width - 0.25,
            "compact must share the insertion scale: \(insertionSamples)"
        )
        let insertionPreterminal = try XCTUnwrap(
            insertionSamples.first(where: { abs($0.time - 10.90) < 0.001 })
        )
        let titlePreterminal = try XCTUnwrap(insertionPreterminal.title)
        let detailPreterminal = try XCTUnwrap(insertionPreterminal.detail)
        XCTAssertGreaterThan(
            titlePreterminal.frame.width / insertedFinal.frame.width,
            0.94,
            "Animated child must approach its final scale before completion: \(insertionSamples)"
        )
        XCTAssertGreaterThan(
            detailPreterminal.frame.width / detailFinal.frame.width,
            0.90,
            "compact must approach its final scale before completion: \(insertionSamples)"
        )
        XCTAssertGreaterThan(
            detailPreterminal.opacity / detailFinal.opacity,
            0.94,
            "compact opacity must not jump at insertion completion: \(insertionSamples)"
        )
        XCTAssertEqual(
            titlePreterminal.frame.midY,
            insertedFinal.frame.midY,
            accuracy: 0.5,
            "Animated child must reach its terminal position continuously: \(insertionSamples)"
        )
        XCTAssertEqual(
            detailPreterminal.frame.midY,
            detailFinal.frame.midY,
            accuracy: 0.5,
            "compact must reach its terminal position continuously: \(insertionSamples)"
        )
        let preterminalPixels = try XCTUnwrap(insertionPreterminal.titlePixels)
        let finalPixels = try XCTUnwrap(insertionSamples.last?.titlePixels)
        let midpointSpread = try XCTUnwrap(
            insertionSamples.first(where: { abs($0.time - 8.50) < 0.001 })?
                .titlePixelSpread
        )
        let finalSpread = try XCTUnwrap(
            insertionSamples.last?.titlePixelSpread
        )
        XCTAssertLessThan(
            midpointSpread / finalSpread,
            0.94,
            "Rendered Animated child pixels must share the insertion scale"
        )
        let midpointBackgroundPixels = try XCTUnwrap(
            insertionSamples.first(where: { abs($0.time - 8.50) < 0.001 })?
                .backgroundPixels
        )
        let finalBackgroundPixels = try XCTUnwrap(
            insertionSamples.last?.backgroundPixels
        )
        XCTAssertEqual(
            midpointBackgroundPixels.width / finalBackgroundPixels.width,
            midpointSpread / finalSpread,
            accuracy: 0.12,
            "Animated child and its background must share one insertion scale"
        )
        XCTAssertEqual(
            preterminalPixels.midY,
            finalPixels.midY,
            accuracy: 2,
            "Rendered Animated child pixels must not jump at completion"
        )
        let preterminalDetailDarkness = try XCTUnwrap(
            insertionPreterminal.detailPixelDarkness
        )
        let finalDetailDarkness = try XCTUnwrap(
            insertionSamples.last?.detailPixelDarkness
        )
        XCTAssertGreaterThan(
            preterminalDetailDarkness / finalDetailDarkness,
            0.94,
            "Rendered compact opacity must not jump at completion"
        )

        for cycle in 0..<3 {
            let cycleStart = 11.1 + Double(cycle) * 10.2
            try XCTUnwrap(probe.removeChild)()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
            for offset in [0.001, 2.5, 5.1] {
                _ = try update(time: cycleStart + offset)
            }
            try XCTUnwrap(probe.insertChild)()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
            for offset in [5.101, 7.6, 10.2] {
                _ = try update(time: cycleStart + offset)
            }
        }

        var rapidTime = 41.7
        for _ in 0..<12 {
            try XCTUnwrap(probe.removeChild)()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.005))
            rapidTime += 0.05
            _ = try update(time: rapidTime)
            try XCTUnwrap(probe.insertChild)()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.005))
            rapidTime += 0.10
            _ = try update(time: rapidTime)
        }
    }

    @MainActor
    func testContentTransitionLabRetainsAnimatedTextAndNumericTransitions() throws {
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
        appContext = LayoutSchedulingAppContext(
            graphicsDeviceContext: deviceContext
        )
        defer { appContext = previousAppContext }

        let probe = LayoutSchedulingContentTransitionProbe()
        let controller = WindowController(
            content: LayoutSchedulingContentTransitionRoot(
                probe: probe,
                font: VUI.Font(textureFont)
            ),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(LayoutSchedulingContentTransitionRoot.self)
            )
        )
        let withGC: WindowContext.WithGraphicsContext = { _, handler in
            guard let commandBuffer = renderQueue.makeCommandBuffer(),
                  let context = GraphicsContext(
                    sceneResources: controller.sceneResources,
                    environment: controller.environment,
                    viewport: CGRect(x: 0, y: 0, width: 680, height: 300),
                    contentOffset: .zero,
                    contentScaleFactor: 1,
                    resolution: CGSize(width: 680, height: 300),
                    commandBuffer: commandBuffer
                  ) else {
                return XCTFail("Unable to create the text resource graphics context.")
            }
            handler(context)
            XCTAssertTrue(commandBuffer.commit())
        }
        let startDate = controller.date
        var tick: UInt64 = 0

        func update(_ time: Double) throws -> DisplayList {
            controller.updateFrame(
                tick: tick,
                delta: time - controller.animationTimestamp.seconds,
                date: startDate.addingTimeInterval(time),
                contentSize: CGSize(width: 680, height: 300),
                shouldDrawFrame: false,
                withGC
            )
            tick &+= 1
            return try displayList(in: controller)
        }

        let initial = try update(0)
        XCTAssertFalse(
            resolvedTextSamples(
                in: initial,
                matching: "Compact",
                environment: controller.environment
            ).isEmpty
        )

        try XCTUnwrap(probe.changeText)()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        let changedLists = try [
            0.001,
            0.01,
            0.02,
            0.03,
            0.05,
            0.10,
            0.50,
            1.00,
            2.53,
        ].map(update)
        let changed = try XCTUnwrap(changedLists.last)
        let compact = resolvedTextSamples(
            in: changed,
            matching: "Compact",
            environment: controller.environment
        )
        let expanded = resolvedTextSamples(
            in: changed,
            matching: "Expanded value",
            environment: controller.environment
        )
        XCTAssertFalse(compact.isEmpty, displayListTreeDescription(changed))
        XCTAssertFalse(expanded.isEmpty, displayListTreeDescription(changed))
        XCTAssertTrue(
            compact.contains { $0.opacity > 0 && $0.opacity < 1 },
            "\(compact)"
        )
        XCTAssertTrue(
            expanded.contains { $0.opacity > 0 && $0.opacity < 1 },
            "\(expanded)"
        )
        for list in changedLists {
            let compactSamples = renderedResolvedTextSamples(
                in: list,
                matching: "Compact",
                environment: controller.environment
            )
            let expandedSamples = renderedResolvedTextSamples(
                in: list,
                matching: "Expanded value",
                environment: controller.environment
            )
            for source in compactSamples where source.opacity > 0.001 {
                for target in expandedSamples where target.opacity > 0.001 {
                    XCTAssertEqual(
                        source.frame.midX,
                        target.frame.midX,
                        accuracy: 1,
                        "changed-text endpoints must share the presentation center: compact=\(compactSamples) expanded=\(expandedSamples)"
                    )
                }
            }
        }

        _ = try update(5.2)
        try XCTUnwrap(probe.increment)()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        _ = try update(5.21)
        _ = try update(5.22)
        _ = try update(5.23)
        let incremented = try update(5.24)
        XCTAssertTrue(
            incremented.effects.contains {
                if case .contentTransition = $0.effect {
                    return true
                }
                return false
            },
            displayListTreeDescription(incremented)
        )
    }

    @MainActor
    func testSystemFontNumericTransitionSurvivesRapidRepeatedRetargets() throws {
        guard let deviceContext = makeGraphicsDeviceContext(api: .metal),
              let renderQueue = deviceContext.renderQueue() else {
            throw XCTSkip("Metal graphics device unavailable")
        }
        let previousAppContext = appContext
        appContext = LayoutSchedulingAppContext(
            graphicsDeviceContext: deviceContext
        )
        defer { appContext = previousAppContext }

        let probe = LayoutSchedulingContentTransitionProbe()
        let controller = WindowController(
            content: LayoutSchedulingSystemNumericTransitionRoot(probe: probe),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(LayoutSchedulingSystemNumericTransitionRoot.self)
            )
        )
        let withGC: WindowContext.WithGraphicsContext = { _, handler in
            guard let commandBuffer = renderQueue.makeCommandBuffer(),
                  let context = GraphicsContext(
                    sceneResources: controller.sceneResources,
                    environment: controller.environment,
                    viewport: CGRect(x: 0, y: 0, width: 200, height: 180),
                    contentOffset: .zero,
                    contentScaleFactor: 1,
                    resolution: CGSize(width: 200, height: 180),
                    commandBuffer: commandBuffer
                  ) else {
                return XCTFail("Unable to create the numeric-text resource context.")
            }
            handler(context)
            XCTAssertTrue(commandBuffer.commit())
        }
        let startDate = controller.date
        var tick: UInt64 = 0
        var time = 0.0

        func update() throws -> DisplayList {
            controller.updateFrame(
                tick: tick,
                delta: time - controller.animationTimestamp.seconds,
                date: startDate.addingTimeInterval(time),
                contentSize: CGSize(width: 200, height: 180),
                shouldDrawFrame: false,
                withGC
            )
            tick &+= 1
            return try displayList(in: controller)
        }

        _ = try update()
        for _ in 0..<256 {
            try XCTUnwrap(probe.increment)()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.001))
            let list = try update()
            XCTAssertFalse(
                renderedTextBounds(in: list).isEmpty
            )
            let transitionContents = list.effects.first {
                    if case .contentTransition = $0.effect {
                        return true
                    }
                    return false
                }?.contents
            XCTAssertNotNil(transitionContents, displayListTreeDescription(list))
            XCTAssertFalse(
                transitionContents?.itemCommands.compactMap(\.bounds).contains {
                    $0.width >= 100
                } ?? true,
                "rapid numeric updates must retain glyph-bounded operations"
            )
        }
    }

    @MainActor
    func testSystemSymbolDrawTransitionAnimatesFreshInsertion() throws {
        guard let deviceContext = makeGraphicsDeviceContext(api: .metal),
              let renderQueue = deviceContext.renderQueue() else {
            throw XCTSkip("Metal graphics device unavailable")
        }
        let previousAppContext = appContext
        appContext = LayoutSchedulingAppContext(
            graphicsDeviceContext: deviceContext
        )
        defer { appContext = previousAppContext }

        let probe = LayoutSchedulingAnimationProbe()
        let controller = WindowController(
            content: LayoutSchedulingSymbolDrawTransitionRoot(probe: probe),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(LayoutSchedulingSymbolDrawTransitionRoot.self)
            )
        )
        let withGC: WindowContext.WithGraphicsContext = { _, handler in
            guard let commandBuffer = renderQueue.makeCommandBuffer(),
                  let context = GraphicsContext(
                    sceneResources: controller.sceneResources,
                    environment: controller.environment,
                    viewport: CGRect(x: 0, y: 0, width: 160, height: 120),
                    contentOffset: .zero,
                    contentScaleFactor: 1,
                    resolution: CGSize(width: 160, height: 120),
                    commandBuffer: commandBuffer
                  ) else {
                return XCTFail("Unable to create the symbol resource context.")
            }
            handler(context)
            XCTAssertTrue(commandBuffer.commit())
        }
        let startDate = controller.date
        var tick: UInt64 = 0

        func update(_ time: Double) throws -> DisplayList {
            controller.updateFrame(
                tick: tick,
                delta: time - controller.animationTimestamp.seconds,
                date: startDate.addingTimeInterval(time),
                contentSize: CGSize(width: 160, height: 120),
                shouldDrawFrame: false,
                withGC
            )
            tick &+= 1
            return try displayList(in: controller)
        }

        _ = try update(0)
        try XCTUnwrap(probe.toggle)()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        for time in [0.001, 0.05, 0.20, 0.50, 1.20] {
            _ = try update(time)
        }

        try XCTUnwrap(probe.toggle)()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        let insertion = try [1.201, 1.22, 1.28, 1.40, 1.70, 2.20]
            .map(update)
            .map(symbolDrawProgressSamples(in:))
        let insertionProgresses = insertion.flatMap {
            $0.compactMap { $0 }
        }

        XCTAssertEqual(
            insertionProgresses.first,
            [0, 0],
            "fresh symbol insertion consumed draw time before its first presentation: \(insertion)"
        )
        for motionGroup in 0..<2 {
            XCTAssertTrue(
                insertionProgresses.contains { progresses in
                    progresses.indices.contains(motionGroup) &&
                        progresses[motionGroup] > 0.001 &&
                        progresses[motionGroup] < 0.999
                },
                "fresh symbol insertion skipped motion group \(motionGroup): \(insertion)"
            )
        }
    }

    @MainActor
    func testRawPrimitiveReceivesEndpointModelPositionDuringSpringMove() throws {
        let counter = LayoutSchedulingCounter()
        let probe = LayoutSchedulingAnimationProbe()
        let controller = WindowController(
            content: LayoutSchedulingRawTextSiblingPlacementRoot(counter: counter, probe: probe),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(LayoutSchedulingRawTextSiblingPlacementRoot.self)
            )
        )

        let withGC: WindowContext.WithGraphicsContext = { _, _ in
            XCTFail("Static animation scheduling test should not request graphics resources.")
        }

        var redraw = false
        controller.updateView(
            tick: 0,
            delta: 0,
            date: controller.date,
            contentSize: CGSize(width: 420, height: 240),
            redraw: &redraw,
            withGC
        )
        let initialDisplayList = try displayList(in: controller)
        let initialBounds = try XCTUnwrap(textBounds(in: initialDisplayList).first)

        let run = try XCTUnwrap(probe.toggle)
        run()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))

        var samples: [(time: Double, bounds: CGRect)] = []
        for (index, sampleTime) in [0.0, 1.0 / 60.0, 2.0 / 60.0, 0.1, 1.0, 10.0, 30.0].enumerated() {
            redraw = false
            controller.updateView(
                tick: UInt64(index + 1),
                delta: sampleTime - controller.animationTimestamp.seconds,
                date: controller.date.addingTimeInterval(sampleTime),
                contentSize: CGSize(width: 420, height: 240),
                redraw: &redraw,
                withGC
            )
            let sampleDisplayList = try displayList(in: controller)
            samples.append((sampleTime, try XCTUnwrap(textBounds(in: sampleDisplayList).first)))
        }

        let finalBounds = try XCTUnwrap(samples.last?.bounds)
        XCTAssertGreaterThan(finalBounds.minX, initialBounds.minX)
        for sample in samples {
            XCTAssertEqual(sample.bounds.minX, finalBounds.minX, accuracy: 0.001)
        }
    }

    @MainActor
    func testBackgroundShapeColorSamplesIntermediateColorDuringSpringMove() throws {
        let counter = LayoutSchedulingCounter()
        let probe = LayoutSchedulingAnimationProbe()
        let controller = WindowController(
            content: LayoutSchedulingBackgroundShapeColorRoot(counter: counter, probe: probe),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(LayoutSchedulingBackgroundShapeColorRoot.self)
            )
        )

        let withGC: WindowContext.WithGraphicsContext = { _, _ in
            XCTFail("Static animation scheduling test should not request graphics resources.")
        }

        var redraw = false
        controller.updateView(
            tick: 0,
            delta: 0,
            date: controller.date,
            contentSize: CGSize(width: 420, height: 240),
            redraw: &redraw,
            withGC
        )
        let initialDisplayList = try displayList(in: controller)
        let initialColor = try XCTUnwrap(
            translucentShapeFillColors(in: initialDisplayList).first,
            "shape records: \(shapeFillDebugRecords(in: initialDisplayList))"
        )
        XCTAssertLessThan(initialColor.provider.red, initialColor.provider.green)

        let run = try XCTUnwrap(probe.toggle)
        run()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))

        var samples: [(time: Double, color: VUI.Color)] = []
        for (index, sampleTime) in [0.0, 1.0 / 60.0, 2.0 / 60.0, 0.1, 1.0, 10.0, 30.0].enumerated() {
            redraw = false
            controller.updateView(
                tick: UInt64(index + 1),
                delta: sampleTime - controller.animationTimestamp.seconds,
                date: controller.date.addingTimeInterval(sampleTime),
                contentSize: CGSize(width: 420, height: 240),
                redraw: &redraw,
                withGC
            )
            let sampleDisplayList = try displayList(in: controller)
            samples.append((sampleTime, try XCTUnwrap(translucentShapeFillColors(in: sampleDisplayList).first)))
        }

        let finalColor = try XCTUnwrap(samples.last?.color)
        XCTAssertGreaterThan(finalColor.provider.red, initialColor.provider.red)

        let sampledColor = try XCTUnwrap(
            samples.dropFirst().dropLast().first { sample in
                sample.color.provider.red > initialColor.provider.red &&
                    sample.color.provider.red < finalColor.provider.red
            }?.color,
            """
            expected intermediate background color:
            initial=\(initialColor)
            final=\(finalColor)
            samples=\(samples.map { ($0.time, $0.color) })
            """
        )
        XCTAssertEqual(sampledColor.provider.alpha, 0.35, accuracy: 0.01)
    }

    @MainActor
    func testBackgroundShapeContributesToGeometryEffectSurfaceDuringSpringMove() throws {
        let counter = LayoutSchedulingCounter()
        let probe = LayoutSchedulingAnimationProbe()
        let controller = WindowController(
            content: LayoutSchedulingBackgroundShapeGeometryRoot(counter: counter, probe: probe),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(LayoutSchedulingBackgroundShapeGeometryRoot.self)
            )
        )

        let withGC: WindowContext.WithGraphicsContext = { _, _ in
            XCTFail("Static animation scheduling test should not request graphics resources.")
        }

        var redraw = false
        controller.updateView(
            tick: 0,
            delta: 0,
            date: controller.date,
            contentSize: CGSize(width: 420, height: 240),
            redraw: &redraw,
            withGC
        )
        let initialBounds = try XCTUnwrap(
            translucentShapeFillRecords(in: try displayList(in: controller)).first?.bounds
        )
        XCTAssertGreaterThan(initialBounds.width, 120)
        XCTAssertGreaterThan(initialBounds.height, 35)

        let run = try XCTUnwrap(probe.toggle)
        run()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))

        redraw = false
        controller.updateView(
            tick: 1,
            delta: 0.1 - controller.animationTimestamp.seconds,
            date: controller.date.addingTimeInterval(0.1),
            contentSize: CGSize(width: 420, height: 240),
            redraw: &redraw,
            withGC
        )
        let sampledBounds = try XCTUnwrap(
            translucentShapeFillRecords(in: try displayList(in: controller)).first?.bounds
        )
        XCTAssertGreaterThan(sampledBounds.width, 120)
        XCTAssertGreaterThan(sampledBounds.height, 35)
    }

    @MainActor
    func testEnvironmentModifierPreservesAnimatedFrameForTextLikeSiblingPlacement() throws {
        let counter = LayoutSchedulingCounter()
        let probe = LayoutSchedulingAnimationProbe()
        let controller = WindowController(
            content: LayoutSchedulingEnvironmentTextSiblingPlacementRoot(counter: counter, probe: probe),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(LayoutSchedulingEnvironmentTextSiblingPlacementRoot.self)
            )
        )

        let withGC: WindowContext.WithGraphicsContext = { _, _ in
            XCTFail("Static animation scheduling test should not request graphics resources.")
        }

        var redraw = false
        controller.updateView(
            tick: 0,
            delta: 0,
            date: controller.date,
            contentSize: CGSize(width: 420, height: 240),
            redraw: &redraw,
            withGC
        )
        let initialDisplayList = try displayList(in: controller)
        let initialBounds = try XCTUnwrap(textBounds(in: initialDisplayList).first)

        let run = try XCTUnwrap(probe.toggle)
        run()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))

        var samples: [(time: Double, bounds: CGRect)] = []
        for (index, sampleTime) in [0.0, 1.0 / 60.0, 2.0 / 60.0, 0.1, 1.0, 10.0, 30.0].enumerated() {
            redraw = false
            controller.updateView(
                tick: UInt64(index + 1),
                delta: sampleTime - controller.animationTimestamp.seconds,
                date: controller.date.addingTimeInterval(sampleTime),
                contentSize: CGSize(width: 420, height: 240),
                redraw: &redraw,
                withGC
            )
            let sampleDisplayList = try displayList(in: controller)
            samples.append((sampleTime, try XCTUnwrap(textBounds(in: sampleDisplayList).first)))
        }

        let finalBounds = try XCTUnwrap(samples.last?.bounds)
        let sampledBounds = try XCTUnwrap(
            samples.dropFirst().dropLast().first { sample in
                sample.bounds.minX > initialBounds.minX &&
                    sample.bounds.minX < finalBounds.minX
            }?.bounds,
            """
            expected environment-modified text placement to keep animated frame:
            initial=\(initialBounds)
            final=\(finalBounds)
            samples=\(samples)
            """
        )

        XCTAssertGreaterThan(finalBounds.minX, initialBounds.minX)
        XCTAssertGreaterThan(sampledBounds.minX, initialBounds.minX)
        XCTAssertLessThan(sampledBounds.minX, finalBounds.minX)
    }

    @MainActor
    func testReinsertedAnimationLabChildTextMovesWithBackgroundDuringSpringMove() throws {
        let counter = LayoutSchedulingCounter()
        let probe = LayoutSchedulingAnimationLabProbe()
        let controller = WindowController(
            content: LayoutSchedulingReinsertedAnimationLabChildRoot(
                counter: counter,
                probe: probe
            ),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(LayoutSchedulingReinsertedAnimationLabChildRoot.self)
            )
        )
        let withGC: WindowContext.WithGraphicsContext = { _, _ in
            XCTFail("Static Animation Lab sequence test should not request graphics resources.")
        }
        let startDate = controller.date
        var redraw = false
        var tick: UInt64 = 0

        func update(time: Double) {
            redraw = false
            controller.updateView(
                tick: tick,
                delta: time - controller.animationTimestamp.seconds,
                date: startDate.addingTimeInterval(time),
                contentSize: CGSize(width: 560, height: 360),
                redraw: &redraw,
                withGC
            )
            tick += 1
        }

        update(time: 0)

        try XCTUnwrap(probe.removeChild)()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        for sampleTime in [0.001, 1.0 / 60.0, 2.0 / 60.0, 2.5, 5.1] {
            update(time: sampleTime)
        }

        try XCTUnwrap(probe.insertChild)()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        for sampleTime in [5.101, 5.1 + 1.0 / 60.0, 5.1 + 2.0 / 60.0, 7.6, 10.2] {
            update(time: sampleTime)
        }

        let inserted = try displayList(in: controller)
        let insertedText = try XCTUnwrap(
            textBounds(in: inserted).first {
                $0.width > 80 && $0.width < 140 && $0.height > 14
            }
        )
        let insertedBackground = try XCTUnwrap(
            translucentGreenShapeBounds(in: inserted)
        )
        try XCTUnwrap(probe.springMove)()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))

        var frames: [(time: Double, text: CGRect, background: CGRect)] = []
        for sampleTime in [10.2, 10.3, 10.7, 11.2, 12.2, 15.3] {
            update(time: sampleTime)
            let list = try displayList(in: controller)
            let text = try XCTUnwrap(
                textBounds(in: list).first {
                    $0.width > 80 && $0.width < 140 && $0.height > 14
                },
                "missing Animation Lab child text at \(sampleTime): \(textBounds(in: list))"
            )
            let background = try XCTUnwrap(
                translucentShapeFillRecords(in: list).first { record in
                    record.color.provider.alpha < 0.8 &&
                        record.bounds.width > 120 &&
                        record.bounds.height > 40
                }?.bounds,
                "missing Animation Lab child background at \(sampleTime): \(translucentShapeFillRecords(in: list))"
            )
            frames.append((sampleTime, text, background))
        }
        let activationFrame = try XCTUnwrap(frames.first)
        XCTAssertEqual(activationFrame.text.origin.x, insertedText.origin.x, accuracy: 0.001)
        XCTAssertEqual(activationFrame.text.origin.y, insertedText.origin.y, accuracy: 0.001)
        XCTAssertEqual(
            activationFrame.background.origin.x,
            insertedBackground.origin.x,
            accuracy: 0.001
        )
        XCTAssertEqual(
            activationFrame.background.origin.y,
            insertedBackground.origin.y,
            accuracy: 0.001
        )

        for sample in frames {
            let containingBounds = sample.background.insetBy(dx: -1, dy: -1)
            XCTAssertTrue(
                containingBounds.contains(sample.text),
                "reinserted child text left its background: \(frames)"
            )
        }
        let firstFrame = try XCTUnwrap(frames.first)
        let lastFrame = try XCTUnwrap(frames.last)
        XCTAssertGreaterThan(lastFrame.text.midX, firstFrame.text.midX)
        XCTAssertGreaterThan(lastFrame.background.midX, firstFrame.background.midX)
        XCTAssertGreaterThan(lastFrame.text.midX, insertedText.midX)
        XCTAssertGreaterThan(lastFrame.background.midX, insertedBackground.midX)
    }

    @MainActor
    func testRapidAnimationLabRetargetKeepsChildTextInsideBackground() throws {
        let counter = LayoutSchedulingCounter()
        let probe = LayoutSchedulingAnimationLabProbe()
        let controller = WindowController(
            content: LayoutSchedulingReinsertedAnimationLabChildRoot(
                counter: counter,
                probe: probe
            ),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(LayoutSchedulingReinsertedAnimationLabChildRoot.self)
            )
        )
        let withGC: WindowContext.WithGraphicsContext = { _, _ in
            XCTFail("Static Animation Lab retarget test should not request graphics resources.")
        }
        let startDate = controller.date
        var redraw = false
        var tick: UInt64 = 0

        func update(time: Double) throws {
            redraw = false
            controller.updateView(
                tick: tick,
                delta: time - controller.animationTimestamp.seconds,
                date: startDate.addingTimeInterval(time),
                contentSize: CGSize(width: 560, height: 360),
                redraw: &redraw,
                withGC
            )
            tick += 1

            let childFrameSize: CGSize? = controller.viewGraph.data.withCurrent {
                let graph = controller.viewGraph.data.graph
                guard let insertionSize = probe.text.insertionSize,
                      let weakSize = graph.weakAttributeIfValid(for: insertionSize.identifier),
                      weakSize.isValid(in: graph) else {
                    return nil
                }
                return Attribute<ViewSize>(weakSize.toStrong()).value.value
            }
            if let childFrameSize {
                XCTAssertEqual(
                    childFrameSize,
                    CGSize(width: 120, height: 20),
                    "child text layout frame changed at \(time)"
                )
            }

            let list = try displayList(in: controller)
            let childTexts = renderedTextBounds(in: list).filter {
                $0.width >= 50 && $0.width < 150 && $0.height >= 8 && $0.height < 25
            }
            let backgrounds: [CGRect] = renderedTranslucentShapeFillRecords(in: list).compactMap { record in
                guard record.bounds.width >= 60, record.bounds.height >= 25 else {
                    return nil
                }
                return record.bounds
            }

            XCTAssertLessThanOrEqual(
                backgrounds.count,
                1,
                "retained and inserted child backgrounds overlapped at \(time): \(backgrounds)"
            )

            if let firstBackground = backgrounds.first {
                for background in backgrounds.dropFirst() {
                    XCTAssertEqual(
                        background.midX,
                        firstBackground.midX,
                        accuracy: 0.75,
                        "retained and inserted child backgrounds split horizontally at \(time): \(backgrounds)"
                    )
                }
            }

            for text in childTexts {
                let containingBackground = backgrounds.first { background in
                    background.insetBy(dx: -0.75, dy: -0.75).contains(text)
                }
                if containingBackground == nil {
                    XCTFail(
                        "child text escaped its background at \(time): text=\(text) backgrounds=\(backgrounds) allText=\(renderedTextBounds(in: list)) tree=\(displayListTreeDescription(list))"
                    )
                }
            }
        }

        var currentTime = 0.0
        try update(time: currentTime)

        func advance(to targetTime: Double) throws {
            let interval = 1.0 / 30.0
            while currentTime + interval < targetTime {
                currentTime += interval
                try update(time: currentTime)
            }
            currentTime = targetTime
            try update(time: currentTime)
        }

        for cycle in 0..<8 {
            let base = Double(cycle) * 1.2

            try advance(to: base + 0.05)
            try XCTUnwrap(probe.springMove)()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))

            try advance(to: base + 0.10)
            try XCTUnwrap(probe.removeChild)()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))

            try advance(to: base + 0.15)
            try XCTUnwrap(probe.insertChild)()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))

            try advance(to: base + 0.20)
            try XCTUnwrap(probe.removeChild)()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))

            try advance(to: base + 0.25)
            try XCTUnwrap(probe.insertChild)()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))

            try advance(to: base + 0.30)
            try XCTUnwrap(probe.removeChild)()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))

            try advance(to: base + 0.35)
            try XCTUnwrap(probe.insertChild)()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
            try advance(to: base + 1.20)
        }

        try advance(to: 16.0)
    }

    @MainActor
    func testRepeatedAnimationLabRemovalKeepsTitleInsideBoxAndSettlesCentered() throws {
        let counter = LayoutSchedulingCounter()
        let probe = LayoutSchedulingAnimationLabProbe()
        let controller = WindowController(
            content: LayoutSchedulingReinsertedAnimationLabChildRoot(
                counter: counter,
                probe: probe
            ),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(LayoutSchedulingReinsertedAnimationLabChildRoot.self)
            )
        )
        let withGC: WindowContext.WithGraphicsContext = { _, _ in
            XCTFail("Static Animation Lab centering test should not request graphics resources.")
        }
        let startDate = controller.date
        var redraw = false
        var tick: UInt64 = 0

        func update(time: Double, expectsSettledCenter: Bool = false) throws {
            redraw = false
            controller.updateView(
                tick: tick,
                delta: time - controller.animationTimestamp.seconds,
                date: startDate.addingTimeInterval(time),
                contentSize: CGSize(width: 560, height: 360),
                redraw: &redraw,
                withGC
            )
            tick += 1

            let list = try displayList(in: controller)
            let titles = textBounds(in: list).filter {
                    abs($0.width - 160) <= 0.5 && abs($0.height - 20) <= 0.5
                }
            XCTAssertFalse(
                titles.isEmpty,
                "missing retained-removal title at \(time): \(textBounds(in: list))"
            )
            let box = try XCTUnwrap(
                shapeStrokeBounds(in: list).first {
                    abs($0.width - 190) <= 0.5 && abs($0.height - 150) <= 0.5
                },
                "missing retained-removal box at \(time): \(shapeStrokeBounds(in: list))"
            )
            for title in titles {
                XCTAssertGreaterThanOrEqual(
                    title.minX,
                    box.minX - 0.75,
                    "retained-removal title escaped the left edge at \(time): titles=\(titles) box=\(box) allText=\(textBounds(in: list)) allStrokes=\(shapeStrokeBounds(in: list)) tree=\(displayListTreeDescription(list))"
                )
                XCTAssertLessThanOrEqual(
                    title.maxX,
                    box.maxX + 0.75,
                    "retained-removal title escaped the right edge at \(time): titles=\(titles) box=\(box) allText=\(textBounds(in: list)) allStrokes=\(shapeStrokeBounds(in: list)) tree=\(displayListTreeDescription(list))"
                )
                if expectsSettledCenter {
                    XCTAssertEqual(
                        title.midX,
                        box.midX,
                        accuracy: 0.75,
                        "retained-removal title did not settle back to center at \(time): titles=\(titles) box=\(box)"
                    )
                }
            }
        }

        var currentTime = 0.0
        try update(time: currentTime)

        func advance(to targetTime: Double) throws {
            let interval = 1.0 / 30.0
            while currentTime + interval < targetTime {
                currentTime += interval
                try update(time: currentTime)
            }
            currentTime = targetTime
            try update(time: currentTime)
        }

        for cycle in 0..<20 {
            let base = Double(cycle) * 1.2

            try XCTUnwrap(probe.removeChild)()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.003))
            try advance(to: base + 0.10)

            try XCTUnwrap(probe.insertChild)()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.003))
            try advance(to: base + 0.40)

            try XCTUnwrap(probe.springMove)()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.003))
            try advance(to: base + 0.70)
            try advance(to: base + 1.20)
        }

        try advance(to: 30.0)
        try update(time: 30.0, expectsSettledCenter: true)
    }

    @MainActor
    func testModalTextLikeSiblingPlacementSurfaceSamplesIntermediatePositionDuringSpringMove() throws {
        let counter = LayoutSchedulingCounter()
        let probe = LayoutSchedulingAnimationProbe()
        let parent = WindowController(
            content: EmptyView(),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(EmptyView.self)
            )
        )
        let child = parent.viewGraph.data.withCurrent {
            let sourceGraph = parent.viewGraph.data.graph
            let contentAttr: Attribute<AnyView> = sourceGraph.makeInput(
                value: AnyView(
                    SheetContent(
                        content: AnyView(
                            LayoutSchedulingTextSiblingPlacementRoot(counter: counter, probe: probe)
                        )
                    )
                )
            )
            return ModalWindowController(
                crossGraphContent: contentAttr,
                sourceGraph: sourceGraph,
                scene: WindowKey(
                    namespace: .app,
                    sceneID: SceneID(LayoutSchedulingTextSiblingPlacementRoot.self)
                ),
                parentController: parent,
                usesPlatformWindow: false
            )
        }

        let withGC: WindowContext.WithGraphicsContext = { _, _ in
            XCTFail("Static animation scheduling test should not request graphics resources.")
        }

        var redraw = false
        child.updateView(
            tick: 0,
            delta: 0,
            date: child.date,
            contentSize: CGSize(width: 420, height: 240),
            redraw: &redraw,
            withGC
        )
        let initialDisplayList = try displayList(in: child)
        let initialBounds = try XCTUnwrap(textBounds(in: initialDisplayList).first)

        let run = try XCTUnwrap(probe.toggle)
        try XCTUnwrap(child.gestureGraph).data.withCurrent {
            run()
        }
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))

        var samples: [(time: Double, bounds: CGRect)] = []
        for (index, sampleTime) in [0.0, 1.0 / 60.0, 2.0 / 60.0, 0.1, 1.0, 10.0, 30.0].enumerated() {
            redraw = false
            child.updateView(
                tick: UInt64(index + 1),
                delta: sampleTime - child.animationTimestamp.seconds,
                date: child.date.addingTimeInterval(sampleTime),
                contentSize: CGSize(width: 420, height: 240),
                redraw: &redraw,
                withGC
            )
            let sampleDisplayList = try displayList(in: child)
            samples.append((sampleTime, try XCTUnwrap(textBounds(in: sampleDisplayList).first)))
        }

        let finalBounds = try XCTUnwrap(samples.last?.bounds)
        let sampledBounds = try XCTUnwrap(
            samples.dropFirst().dropLast().first { sample in
                sample.bounds.minX > initialBounds.minX &&
                    sample.bounds.minX < finalBounds.minX
            }?.bounds,
            """
            expected intermediate modal text placement:
            initial=\(initialBounds)
            final=\(finalBounds)
            samples=\(samples)
            """
        )

        XCTAssertGreaterThan(finalBounds.minX, initialBounds.minX)
        XCTAssertGreaterThan(sampledBounds.minX, initialBounds.minX)
        XCTAssertLessThan(sampledBounds.minX, finalBounds.minX)
    }

    @MainActor
    private func assertScheduledFullStackAnimationSamplesBoundsAndOpacity(
        animation: Animation,
        sampleTimes: [Double],
        finalTime: Double
    ) throws {
        let counter = LayoutSchedulingCounter()
        let probe = LayoutSchedulingAnimationProbe()
        let controller = WindowController(
            content: LayoutSchedulingFullStackAnimationRoot(counter: counter, probe: probe),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(LayoutSchedulingFullStackAnimationRoot.self)
            )
        )

        let withGC: WindowContext.WithGraphicsContext = { _, _ in
            XCTFail("Static animation scheduling test should not request graphics resources.")
        }

        var redraw = false
        controller.updateView(
            tick: 0,
            delta: 0,
            date: controller.date,
            contentSize: CGSize(width: 420, height: 240),
            redraw: &redraw,
            withGC
        )
        let initialDisplayList = try displayList(in: controller)
        let initialBounds = try XCTUnwrap(initialDisplayList.interpolationBounds)
        let initialOpacity = try XCTUnwrap(firstOpacity(in: initialDisplayList))
        let toggle = try XCTUnwrap(probe.toggle)

        withAnimation(animation) {
            toggle()
        }

        var samples: [(time: Double, bounds: CGRect, opacity: Double)] = []
        for (index, sampleTime) in sampleTimes.enumerated() {
            redraw = false
            controller.updateView(
                tick: UInt64(index + 1),
                delta: sampleTime - controller.animationTimestamp.seconds,
                date: controller.date.addingTimeInterval(sampleTime),
                contentSize: CGSize(width: 420, height: 240),
                redraw: &redraw,
                withGC
            )
            let displayList = try displayList(in: controller)
            samples.append((
                sampleTime,
                try XCTUnwrap(displayList.interpolationBounds),
                try XCTUnwrap(firstOpacity(in: displayList))
            ))
        }

        redraw = false
        controller.updateView(
            tick: 20,
            delta: finalTime - controller.animationTimestamp.seconds,
            date: controller.date.addingTimeInterval(finalTime),
            contentSize: CGSize(width: 420, height: 240),
            redraw: &redraw,
            withGC
        )
        let finalDisplayList = try displayList(in: controller)
        let finalBounds = try XCTUnwrap(finalDisplayList.interpolationBounds)
        let finalOpacity = try XCTUnwrap(firstOpacity(in: finalDisplayList))

        let movingSample = try XCTUnwrap(
            samples.dropFirst().dropLast().first { sample in
                sample.bounds.minX > initialBounds.minX &&
                    sample.bounds.minX < finalBounds.minX
            },
            """
            expected intermediate x movement:
            initial=\(initialBounds)
            final=\(finalBounds)
            samples=\(samples)
            """
        )
        let opacitySample = try XCTUnwrap(
            samples.dropFirst().dropLast().first { sample in
                sample.opacity > initialOpacity &&
                    sample.opacity < finalOpacity
            },
            """
            expected intermediate opacity:
            initial=\(initialOpacity)
            final=\(finalOpacity)
            samples=\(samples)
            """
        )

        XCTAssertGreaterThan(movingSample.bounds.minX, initialBounds.minX)
        XCTAssertLessThan(movingSample.bounds.minX, finalBounds.minX)
        XCTAssertGreaterThan(opacitySample.opacity, initialOpacity)
        XCTAssertLessThan(opacitySample.opacity, finalOpacity)
    }

    @MainActor
    func testInputOnlyUpdateDoesNotRepeatRootLayoutPlacement() {
        let counter = LayoutSchedulingCounter()
        let controller = WindowController(
            content: LayoutSchedulingRoot(counter: counter),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(LayoutSchedulingRoot.self)
            )
        )

        var redraw = false
        let withGC: WindowContext.WithGraphicsContext = { _, _ in
            XCTFail("Input-only layout scheduling test should not request graphics resources.")
        }

        controller.updateView(
            tick: 0,
            delta: 0,
            date: controller.date,
            contentSize: CGSize(width: 120, height: 80),
            redraw: &redraw,
            withGC
        )
        let initialPlacements = counter.placements
        XCTAssertGreaterThan(initialPlacements, 0)

        controller.enqueueInputAction {}
        controller.updateView(
            tick: 1,
            delta: (1.0 / 60.0) - controller.animationTimestamp.seconds,
            date: controller.date.addingTimeInterval(1.0 / 60.0),
            contentSize: CGSize(width: 120, height: 80),
            redraw: &redraw,
            withGC
        )

        XCTAssertEqual(counter.placements, initialPlacements)
    }

    @MainActor
    private func displayBounds(in controller: WindowController) throws -> CGRect {
        try controller.viewGraph.data.withCurrent {
            try XCTUnwrap(controller.viewGraph.rootDisplayList?.value.interpolationBounds)
        }
    }

    @MainActor
    private func displayList(in controller: WindowController) throws -> DisplayList {
        try controller.viewGraph.data.withCurrent {
            try XCTUnwrap(controller.viewGraph.rootDisplayList?.value)
        }
    }

    private func firstOpacity(in displayList: DisplayList) -> Double? {
        for record in displayList.itemRecords {
            if let opacity = record.opacity {
                return opacity
            }
        }
        for effect in displayList.effects {
            if let opacity = firstOpacity(in: effect.contents) {
                return opacity
            }
        }
        return nil
    }

    private func statusMarkerBounds(in displayList: DisplayList) -> CGRect? {
        shapeFillBounds(in: displayList)
            .filter { abs($0.height - 10) <= 0.5 }
            .min { $0.minY < $1.minY }
    }

    private func siblingMarkerBounds(in displayList: DisplayList) -> CGRect? {
        shapeFillBounds(in: displayList)
            .filter {
                abs($0.width - 40) <= 0.5 &&
                    abs($0.height - 10) <= 0.5
            }
            .max { $0.minX < $1.minX }
    }

    private func shapeFillBounds(in displayList: DisplayList) -> [CGRect] {
        var bounds = displayList.itemRecords.compactMap { record -> CGRect? in
            guard record.kind == .shapeFill else { return nil }
            return record.bounds
        }
        for effect in displayList.effects {
            bounds.append(contentsOf: shapeFillBounds(in: effect.contents))
        }
        return bounds
    }

    private func shapeStrokeBounds(in displayList: DisplayList) -> [CGRect] {
        var bounds = displayList.itemRecords.compactMap { record -> CGRect? in
            guard record.kind == .shapeStroke else { return nil }
            return record.bounds
        }
        for effect in displayList.effects {
            bounds.append(contentsOf: shapeStrokeBounds(in: effect.contents))
        }
        return bounds
    }

    private func opaqueGreenShapeBounds(in displayList: DisplayList) -> [CGRect] {
        var bounds = shapeFillRecords(in: displayList).compactMap { record -> CGRect? in
            guard record.color.provider.alpha >= 0.8,
                  record.color.provider.green > record.color.provider.red,
                  record.color.provider.green > record.color.provider.blue else {
                return nil
            }
            return record.bounds
        }
        for effect in displayList.effects {
            bounds.append(contentsOf: opaqueGreenShapeBounds(in: effect.contents))
        }
        return bounds
    }

    private func textBounds(in displayList: DisplayList) -> [CGRect] {
        var bounds = displayList.itemRecords.compactMap { record -> CGRect? in
            guard record.kind == .text else { return nil }
            return record.bounds
        }
        for effect in displayList.effects {
            bounds.append(contentsOf: textBounds(in: effect.contents))
        }
        return bounds
    }

    private func displayListTreeDescription(
        _ displayList: DisplayList,
        depth: Int = 0
    ) -> String {
        let prefix = String(repeating: "  ", count: depth)
        var lines = displayList.itemRecords.map { record in
            "\(prefix)item kind=\(record.kind) effect=\(String(describing: record.effectKind)) bounds=\(String(describing: record.bounds))"
        }
        for effect in displayList.effects {
            let label: String
            switch effect.effect {
            case .identity:
                label = "identity"
            case .archive:
                label = "archive"
            case .opacity:
                label = "opacity"
            case .transform:
                label = "transform"
            case .mask:
                label = "mask"
            case .animation:
                label = "animation"
            case .state:
                label = "state"
            case .contentTransition:
                label = "contentTransition"
            case .interpolatorRoot:
                label = "interpolatorRoot"
            case .interpolatorLayer:
                label = "interpolatorLayer"
            case .interpolatorAnimation:
                label = "interpolatorAnimation"
            case .shader:
                label = "shader"
            case .geometryGroup:
                label = "geometryGroup"
            }
            lines.append("\(prefix)effect \(label)")
            lines.append(displayListTreeDescription(effect.contents, depth: depth + 1))
        }
        return lines.joined(separator: " | ")
    }

    private func translucentShapeFillRecords(in displayList: DisplayList) -> [(bounds: CGRect, color: VUI.Color)] {
        var records = shapeFillRecords(in: displayList).filter { $0.color.provider.alpha < 0.8 }
        for effect in displayList.effects {
            records.append(contentsOf: translucentShapeFillRecords(in: effect.contents))
        }
        return records
    }

    private func renderedTranslucentShapeFillRecords(
        in displayList: DisplayList
    ) -> [(bounds: CGRect, color: VUI.Color)] {
        var records = translucentShapeFillRecords(in: displayList)
        for item in displayList.items {
            guard case let .content(content) = item.value,
                  case let .crossFade(crossFade) = content.value else {
                continue
            }
            if let source = crossFade.source {
                records.append(contentsOf: renderedTranslucentShapeFillRecords(in: source.contents))
            }
            if let target = crossFade.target {
                records.append(contentsOf: renderedTranslucentShapeFillRecords(in: target.contents))
            }
        }
        return records
    }

    private func renderedTextBounds(in displayList: DisplayList) -> [CGRect] {
        var bounds = textBounds(in: displayList)
        for item in displayList.items {
            guard case let .content(content) = item.value,
                  case let .crossFade(crossFade) = content.value else {
                continue
            }
            if let source = crossFade.source {
                bounds.append(contentsOf: renderedTextBounds(in: source.contents))
            }
            if let target = crossFade.target {
                bounds.append(contentsOf: renderedTextBounds(in: target.contents))
            }
        }
        return bounds
    }

    private func resolvedTextSamples(
        in displayList: DisplayList,
        matching string: String,
        environment: EnvironmentValues,
        inheritedOpacity: Double = 1
    ) -> [LayoutSchedulingResolvedTextSample] {
        displayList.items.reduce(into: []) { samples, item in
            let itemOpacity = inheritedOpacity * Double(item.opacity)
            switch item.value {
            case let .content(content):
                if case let .text(text) = content.value,
                   text.view.text.storage?.string == string {
                    let foregroundOpacity: Double
                    if case let .text(record, _) = content.command,
                       case let .color(color)? = record.foreground {
                        foregroundOpacity = Double(color.resolve(in: environment).opacity)
                    } else {
                        foregroundOpacity = 1
                    }
                    samples.append(LayoutSchedulingResolvedTextSample(
                        frame: text.frame.applying(text.transform).standardized,
                        opacity: itemOpacity * foregroundOpacity
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
                        matching: string,
                        environment: environment,
                        inheritedOpacity: itemOpacity * styleOpacity
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
                        samples.append(contentsOf: resolvedTextSamples(
                            in: source.contents,
                            matching: string,
                            environment: environment,
                            inheritedOpacity: itemOpacity * sourceOpacity
                        ))
                    }
                    if let target = crossFade.target {
                        samples.append(contentsOf: resolvedTextSamples(
                            in: target.contents,
                            matching: string,
                            environment: environment,
                            inheritedOpacity: itemOpacity * targetOpacity
                        ))
                    }
                case let .flattened(contents, _, _):
                    samples.append(contentsOf: resolvedTextSamples(
                        in: contents,
                        matching: string,
                        environment: environment,
                        inheritedOpacity: itemOpacity
                    ))
                case let .drawing(contents, _, _):
                    if let local = contents as? DisplayList.LocalContents {
                        samples.append(contentsOf: resolvedTextSamples(
                            in: local.list,
                            matching: string,
                            environment: environment,
                            inheritedOpacity: itemOpacity
                        ))
                    }
                case .backend, .color, .shape, .image, .text:
                    break
                }
            case let .effect(effect, contents):
                let effectOpacity: Double
                if case let .opacity(opacity) = effect {
                    effectOpacity = Double(opacity)
                } else {
                    effectOpacity = 1
                }
                samples.append(contentsOf: resolvedTextSamples(
                    in: contents,
                    matching: string,
                    environment: environment,
                    inheritedOpacity: itemOpacity * effectOpacity
                ))
            case let .states(states):
                if let contents = states.last?.1 {
                    samples.append(contentsOf: resolvedTextSamples(
                        in: contents,
                        matching: string,
                        environment: environment,
                        inheritedOpacity: itemOpacity
                    ))
                }
            case .empty:
                break
            }
        }
    }

    private func renderedResolvedTextSamples(
        in displayList: DisplayList,
        matching string: String,
        environment: EnvironmentValues,
        inheritedOpacity: Double = 1
    ) -> [LayoutSchedulingResolvedTextSample] {
        func applying(
            _ transform: CGAffineTransform,
            to samples: [LayoutSchedulingResolvedTextSample]
        ) -> [LayoutSchedulingResolvedTextSample] {
            guard !transform.isIdentity else { return samples }
            return samples.map { sample in
                var sample = sample
                sample.frame = sample.frame.applying(transform).standardized
                return sample
            }
        }

        func branchTransform(
            from sourceBounds: CGRect,
            to outputBounds: CGRect
        ) -> CGAffineTransform? {
            guard sourceBounds.width.magnitude > .ulpOfOne,
                  sourceBounds.height.magnitude > .ulpOfOne else {
                return nil
            }
            let scaleX = outputBounds.width / sourceBounds.width
            let scaleY = outputBounds.height / sourceBounds.height
            return CGAffineTransform(
                a: scaleX,
                b: 0,
                c: 0,
                d: scaleY,
                tx: outputBounds.minX - sourceBounds.minX * scaleX,
                ty: outputBounds.minY - sourceBounds.minY * scaleY
            )
        }

        return displayList.items.reduce(into: []) { samples, item in
            let itemOpacity = inheritedOpacity * Double(item.opacity)
            switch item.value {
            case let .content(content):
                if case let .text(text) = content.value,
                   text.view.text.storage?.string == string {
                    let foregroundOpacity: Double
                    if case let .text(record, _) = content.command,
                       case let .color(color)? = record.foreground {
                        foregroundOpacity = Double(color.resolve(in: environment).opacity)
                    } else {
                        foregroundOpacity = 1
                    }
                    samples.append(LayoutSchedulingResolvedTextSample(
                        frame: text.frame.applying(text.transform).standardized,
                        opacity: itemOpacity * foregroundOpacity
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
                    let nested = renderedResolvedTextSamples(
                        in: style.contents,
                        matching: string,
                        environment: environment,
                        inheritedOpacity: itemOpacity * styleOpacity
                    )
                    samples.append(contentsOf: applying(style.transform, to: nested))
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
                    if let source = crossFade.source,
                       let transform = branchTransform(
                        from: source.sourceBounds,
                        to: source.outputBounds
                       ) {
                        let nested = renderedResolvedTextSamples(
                            in: source.contents,
                            matching: string,
                            environment: environment,
                            inheritedOpacity: itemOpacity * sourceOpacity
                        )
                        samples.append(contentsOf: applying(
                            transform.concatenating(crossFade.transform),
                            to: nested
                        ))
                    }
                    if let target = crossFade.target,
                       let transform = branchTransform(
                        from: target.sourceBounds,
                        to: target.outputBounds
                       ) {
                        let nested = renderedResolvedTextSamples(
                            in: target.contents,
                            matching: string,
                            environment: environment,
                            inheritedOpacity: itemOpacity * targetOpacity
                        )
                        samples.append(contentsOf: applying(
                            transform.concatenating(crossFade.transform),
                            to: nested
                        ))
                    }
                case let .flattened(contents, origin, _):
                    let nested = renderedResolvedTextSamples(
                        in: contents,
                        matching: string,
                        environment: environment,
                        inheritedOpacity: itemOpacity
                    )
                    samples.append(contentsOf: applying(
                        CGAffineTransform(translationX: origin.x, y: origin.y),
                        to: nested
                    ))
                case let .drawing(contents, origin, _):
                    if let local = contents as? DisplayList.LocalContents {
                        let nested = renderedResolvedTextSamples(
                            in: local.list,
                            matching: string,
                            environment: environment,
                            inheritedOpacity: itemOpacity
                        )
                        samples.append(contentsOf: applying(
                            CGAffineTransform(translationX: origin.x, y: origin.y),
                            to: nested
                        ))
                    }
                case .backend, .color, .shape, .image, .text:
                    break
                }
            case let .effect(effect, contents):
                let effectOpacity: Double
                if case let .opacity(opacity) = effect {
                    effectOpacity = Double(opacity)
                } else {
                    effectOpacity = 1
                }
                let nested = renderedResolvedTextSamples(
                    in: contents,
                    matching: string,
                    environment: environment,
                    inheritedOpacity: itemOpacity * effectOpacity
                )
                if case let .transform(projection) = effect, projection.isAffine {
                    samples.append(contentsOf: applying(
                        CGAffineTransform(
                            a: projection.m11,
                            b: projection.m12,
                            c: projection.m21,
                            d: projection.m22,
                            tx: projection.m31,
                            ty: projection.m32
                        ),
                        to: nested
                    ))
                } else {
                    samples.append(contentsOf: nested)
                }
            case let .states(states):
                if let contents = states.last?.1 {
                    samples.append(contentsOf: renderedResolvedTextSamples(
                        in: contents,
                        matching: string,
                        environment: environment,
                        inheritedOpacity: itemOpacity
                    ))
                }
            case .empty:
                break
            }
        }
    }

    private func symbolDrawProgressSamples(
        in displayList: DisplayList
    ) -> [[Double]?] {
        var samples: [[Double]?] = []

        func collect(_ list: DisplayList) {
            for item in list.items {
                switch item.value {
                case let .content(content):
                    switch content.value {
                    case let .image(image):
                        samples.append(image.image.symbolDrawProgresses)
                    case let .style(style):
                        collect(style.contents)
                    case let .crossFade(crossFade):
                        if let source = crossFade.source {
                            collect(source.contents)
                        }
                        if let target = crossFade.target {
                            collect(target.contents)
                        }
                    case let .flattened(nested, _, _):
                        collect(nested)
                    case let .drawing(contents, _, _):
                        if let local = contents as? DisplayList.LocalContents {
                            collect(local.list)
                        }
                    case .backend,
                         .color,
                         .shape,
                         .text:
                        break
                    }
                case let .effect(_, contents):
                    collect(contents)
                case let .states(states):
                    for (_, contents) in states {
                        collect(contents)
                    }
                case .empty:
                    break
                }
            }
        }

        collect(displayList)
        return samples
    }

    private func translucentShapeFillColors(in displayList: DisplayList) -> [VUI.Color] {
        translucentShapeFillRecords(in: displayList).map(\.color)
    }

    private func translucentGreenShapeBounds(in displayList: DisplayList) -> CGRect? {
        translucentShapeFillRecords(in: displayList).first { record in
            record.color.provider.green > record.color.provider.red &&
                record.color.provider.green > record.color.provider.blue
        }?.bounds
    }

    private func shapeFillRecords(in displayList: DisplayList) -> [(bounds: CGRect, color: VUI.Color)] {
        displayList.itemRecords.compactMap { record -> (CGRect, VUI.Color)? in
            guard record.kind == .shapeFill,
                  let bounds = record.bounds,
                  case let .color(color)? = record.shapeStyle else {
                return nil
            }
            return (bounds, color)
        }
    }

    private func shapeFillDebugRecords(in displayList: DisplayList) -> [(CGRect, DisplayList.ItemRecord.ShapeStyleRecord?)] {
        var records = displayList.itemRecords.compactMap { record -> (CGRect, DisplayList.ItemRecord.ShapeStyleRecord?)? in
            guard record.kind == .shapeFill, let bounds = record.bounds else { return nil }
            return (bounds, record.shapeStyle)
        }
        for effect in displayList.effects {
            records.append(contentsOf: shapeFillDebugRecords(in: effect.contents))
        }
        return records
    }

    private func pressSpringMoveButton(in controller: WindowController) {
        XCTAssertTrue(controller.handleMouseEvent(event: MouseEvent(
            type: .buttonDown,
            device: .genericMouse,
            deviceID: 0,
            buttonID: 0,
            location: CGPoint(x: 210, y: 120),
            timestamp: 0
        )))
        XCTAssertTrue(controller.handleMouseEvent(event: MouseEvent(
            type: .buttonUp,
            device: .genericMouse,
            deviceID: 0,
            buttonID: 0,
            location: CGPoint(x: 210, y: 120),
            timestamp: 0
        )))
    }
}

private final class LayoutSchedulingCounter: @unchecked Sendable {
    var placements = 0
}

private struct LayoutSchedulingRoot: View {
    let counter: LayoutSchedulingCounter

    var body: some View {
        LayoutSchedulingProbeLayout(counter: counter) {
            Color.clear
                .frame(width: 10, height: 10)
        }
    }
}

private struct LayoutSchedulingProbeLayout: Layout {
    let counter: LayoutSchedulingCounter

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        CGSize(width: 10, height: 10)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        counter.placements += 1
        for subview in subviews {
            subview.place(
                at: CGPoint(x: bounds.midX, y: bounds.midY),
                anchor: .center,
                proposal: ProposedViewSize(width: 10, height: 10)
            )
        }
    }
}

private final class LayoutSchedulingAnimationProbe {
    var toggle: (() -> Void)?
    var completions: [Int] = []
    var insertionPosition: Attribute<CGPoint>?
    var insertionSize: Attribute<ViewSize>?
    var resourceTransactions: [(value: Bool, duration: Double?)] = []
    var resourceEvents: [LayoutSchedulingResourceEvent] = []
}

private final class LayoutSchedulingAnimationLabProbe {
    var removeChild: (() -> Void)?
    var insertChild: (() -> Void)?
    var springMove: (() -> Void)?
    let text = LayoutSchedulingAnimationProbe()
}

private final class LayoutSchedulingContentTransitionProbe {
    var increment: (() -> Void)?
    var changeText: (() -> Void)?
}

private enum LayoutSchedulingResourceEvent: Equatable {
    case request(value: Bool, duration: Double?)
    case load
}

private struct LayoutSchedulingAnimationRoot: View {
    let counter: LayoutSchedulingCounter
    let probe: LayoutSchedulingAnimationProbe

    var body: some View {
        LayoutSchedulingPassThroughLayout(counter: counter) {
            LayoutSchedulingAnimatedFrame(probe: probe)
        }
        .frame(width: 420, height: 240)
    }
}

private struct LayoutSchedulingFullStackAnimationRoot: View {
    let counter: LayoutSchedulingCounter
    let probe: LayoutSchedulingAnimationProbe

    var body: some View {
        LayoutSchedulingPassThroughLayout(counter: counter) {
            LayoutSchedulingFullStackAnimatedFrame(probe: probe)
        }
        .frame(width: 420, height: 240)
    }
}

private struct LayoutSchedulingCompletionAnimationRoot: View {
    let counter: LayoutSchedulingCounter
    let probe: LayoutSchedulingAnimationProbe
    @State private var expanded = false
    @State private var runCount = 0
    @State private var completionStatus = "idle"

    var body: some View {
        probe.toggle = {
            let nextRun = runCount + 1
            runCount = nextRun
            completionStatus = "spring running"
            withAnimation(
                .spring(duration: 20.0, bounce: 0.35),
                completionCriteria: .logicallyComplete
            ) {
                expanded.toggle()
            } completion: {
                completionStatus = "spring logical completion \(nextRun)"
                probe.completions.append(nextRun)
            }
        }
        let markerOffset = CGFloat(runCount + completionStatus.count) * 0
        return LayoutSchedulingPassThroughLayout(counter: counter) {
            RoundedRectangle(cornerRadius: expanded ? 28 : 10)
                .fill(expanded ? Color.purple : Color.blue)
                .frame(
                    width: expanded ? 180 : 72,
                    height: expanded ? 96 : 72
                )
                .scaleEffect(expanded ? 1.08 : 0.78)
                .rotationEffect(.degrees(expanded ? 8 : -8))
                .offset(
                    x: (expanded ? 42 : -42) + markerOffset,
                    y: expanded ? 8 : -8
                )
                .opacity(expanded ? 0.92 : 0.55)
        }
        .frame(width: 420, height: 240)
    }
}

private struct LayoutSchedulingButtonCompletionRoot: View {
    let counter: LayoutSchedulingCounter
    let probe: LayoutSchedulingAnimationProbe
    @State private var expanded = false
    @State private var runCount = 0
    @State private var completionStatus = "idle"

    var body: some View {
        LayoutSchedulingPassThroughLayout(counter: counter) {
            Button(action: runSpringMove) {
                RoundedRectangle(cornerRadius: expanded ? 28 : 10)
                    .fill(expanded ? Color.purple : Color.blue)
                    .frame(
                        width: expanded ? 180 : 72,
                        height: expanded ? 96 : 72
                    )
                    .scaleEffect(expanded ? 1.08 : 0.78)
                    .rotationEffect(.degrees(expanded ? 8 : -8))
                    .offset(
                        x: expanded ? 42 : -42,
                        y: expanded ? 8 : -8
                    )
                    .opacity(expanded ? 0.92 : 0.55)
            }
            .frame(width: 420, height: 240)
        }
        .frame(width: 420, height: 240)
    }

    private func runSpringMove() {
        let nextRun = runCount + 1
        runCount = nextRun
        completionStatus = "spring running"
        withAnimation(
            .spring(duration: 20.0, bounce: 0.35),
            completionCriteria: .logicallyComplete
        ) {
            expanded.toggle()
        } completion: {
            completionStatus = "spring logical completion \(nextRun)"
            probe.completions.append(nextRun)
        }
    }
}

private struct LayoutSchedulingMixedTransactionRoot: View {
    let counter: LayoutSchedulingCounter
    let probe: LayoutSchedulingAnimationProbe
    @State private var statusWide = false
    @State private var expanded = false

    var body: some View {
        probe.toggle = {
            statusWide.toggle()
            withAnimation(.spring(duration: 20.0, bounce: 0.35)) {
                expanded.toggle()
            }
        }
        return LayoutSchedulingPassThroughLayout(counter: counter) {
            VStack(spacing: 20) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.red)
                    .frame(width: statusWide ? 160 : 40, height: 10)

                RoundedRectangle(cornerRadius: expanded ? 28 : 10)
                    .fill(expanded ? Color.purple : Color.blue)
                    .frame(
                        width: expanded ? 180 : 72,
                        height: expanded ? 96 : 72
                    )
                    .scaleEffect(expanded ? 1.08 : 0.78)
                    .rotationEffect(.degrees(expanded ? 8 : -8))
                    .offset(
                        x: expanded ? 42 : -42,
                        y: expanded ? 8 : -8
                    )
                    .opacity(expanded ? 0.92 : 0.55)
            }
        }
        .frame(width: 420, height: 240)
    }
}

private struct LayoutSchedulingMixedResourceTransactionRoot: View {
    let counter: LayoutSchedulingCounter
    let probe: LayoutSchedulingAnimationProbe
    @State private var resourceValue = false
    @State private var expanded = false

    var body: some View {
        probe.toggle = {
            resourceValue.toggle()
            withAnimation(.linear(duration: 5)) {
                expanded.toggle()
            }
        }
        return LayoutSchedulingPassThroughLayout(counter: counter) {
            VStack {
                LayoutSchedulingResourceTransactionProbe(
                    value: resourceValue,
                    animatedMarker: expanded,
                    probe: probe
                )
                RoundedRectangle(cornerRadius: 2)
                    .fill(expanded ? Color.purple : Color.blue)
                    .frame(width: expanded ? 180 : 72, height: 72)
            }
        }
        .frame(width: 420, height: 240)
    }
}

private struct LayoutSchedulingResourceTransactionProbe: View {
    let value: Bool
    let animatedMarker: Bool
    let probe: LayoutSchedulingAnimationProbe

    static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("LayoutSchedulingResourceTransactionProbe requires an active graph.")
        }
        let resource = graph.makeRule {
            let value = view._attribute.value
            let transaction = _AGGraph.currentRuleContextAttribute
                .flatMap { graph.transaction(for: $0) }
            value.probe.resourceTransactions.append(
                (value.value, transaction?.effectiveAnimation?.box.duration)
            )
            value.probe.resourceEvents.append(
                .request(
                    value: value.value,
                    duration: transaction?.effectiveAnimation?.box.duration
                )
            )
            var list = ResourceList()
            list.items.append(ResourceList.Task(transaction: Transaction()) { _ in })
            return list
        }
        let layoutComputer = graph.makeInput(
            value: LayoutComputer(sizeThatFits: { _ in .zero })
        )
        var outputs = _ViewOutputs()
        outputs._layoutComputer = OptionalAttribute(layoutComputer)
        outputs.preferences.append(ResourceList.Key.self, node: resource.identifier)
        return outputs
    }

    typealias Body = Never
}

extension LayoutSchedulingResourceTransactionProbe: TestPrimitiveView {
}

private struct LayoutSchedulingCompletionStatusRoot: View {
    let counter: LayoutSchedulingCounter
    let probe: LayoutSchedulingAnimationProbe
    @State private var expanded = false
    @State private var runCount = 0
    @State private var statusPhase = 0

    var body: some View {
        probe.toggle = {
            let nextRun = runCount + 1
            runCount = nextRun
            statusPhase = 1
            withAnimation(
                .spring(duration: 20.0, bounce: 0.35),
                completionCriteria: .logicallyComplete
            ) {
                expanded.toggle()
            } completion: {
                statusPhase = 2
                probe.completions.append(nextRun)
            }
        }
        return LayoutSchedulingPassThroughLayout(counter: counter) {
            VStack(spacing: 20) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.red)
                    .frame(width: statusMarkerWidth, height: 10)

                RoundedRectangle(cornerRadius: expanded ? 28 : 10)
                    .fill(expanded ? Color.purple : Color.blue)
                    .frame(
                        width: expanded ? 180 : 72,
                        height: expanded ? 96 : 72
                    )
                    .scaleEffect(expanded ? 1.08 : 0.78)
                    .rotationEffect(.degrees(expanded ? 8 : -8))
                    .offset(
                        x: expanded ? 42 : -42,
                        y: expanded ? 8 : -8
                    )
                    .opacity(expanded ? 0.92 : 0.55)
            }
        }
        .frame(width: 420, height: 240)
    }

    private var statusMarkerWidth: CGFloat {
        switch statusPhase {
        case 1: 100
        case 2: 160
        default: 40
        }
    }
}

private struct LayoutSchedulingResolvedRemovalStatusRoot: View {
    let probe: LayoutSchedulingAnimationProbe
    let font: VUI.Font
    @State private var showChild = true
    @State private var runCount = 0
    @State private var completionStatus = "idle"

    var body: some View {
        probe.toggle = {
            let nextRun = runCount + 1
            let wasVisible = showChild
            runCount = nextRun
            completionStatus = "removal running"
            withAnimation(
                .easeInOut(duration: 5.0),
                completionCriteria: .removed
            ) {
                showChild.toggle()
            } completion: {
                completionStatus = wasVisible
                    ? "removed completion \(nextRun)"
                    : "unexpected removal state"
                probe.completions.append(nextRun)
            }
        }
        return VStack(spacing: 20) {
            Text("Run \(runCount): \(completionStatus)")
                .font(font)

            VStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.blue)
                    .frame(width: 120, height: 10)
                if showChild {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.green)
                        .frame(width: 72, height: 48)
                        .transition(
                            .opacity.combined(with: .scale(scale: 0.82))
                        )
                }
            }
            .frame(width: 190, height: 150)
        }
        .frame(width: 420, height: 240)
    }
}

private struct LayoutSchedulingNestedOffsetScaleRoot: View {
    let counter: LayoutSchedulingCounter
    let probe: LayoutSchedulingAnimationProbe
    @State private var expanded = false

    var body: some View {
        probe.toggle = {
            withAnimation(.spring(duration: 20.0, bounce: 0.35)) {
                expanded.toggle()
            }
        }
        return VStack(spacing: 20) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.red)
                .frame(width: expanded ? 160 : 40, height: 10)

            VStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.green)
                    .frame(width: 40, height: 10)
            }
            .scaleEffect(expanded ? 1.0 : 0.82)
            .offset(y: expanded ? -80 : 80)
        }
        .frame(width: 420, height: 240)
    }
}

private struct LayoutSchedulingSiblingPlacementRoot: View {
    let counter: LayoutSchedulingCounter
    let probe: LayoutSchedulingAnimationProbe
    @State private var expanded = false

    var body: some View {
        probe.toggle = {
            withAnimation(.spring(duration: 20.0, bounce: 0.35)) {
                expanded.toggle()
            }
        }
        return LayoutSchedulingPassThroughLayout(counter: counter) {
            HStack(spacing: 28) {
                RoundedRectangle(cornerRadius: expanded ? 28 : 10)
                    .fill(expanded ? Color.purple : Color.blue)
                    .frame(width: expanded ? 180 : 72, height: 72)

                VStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.green)
                        .frame(width: 40, height: 10)
                }
                .frame(width: 190, height: 150)
            }
        }
        .frame(width: 420, height: 240)
    }
}

private struct LayoutSchedulingDynamicChildOffsetScaleRoot: View {
    let counter: LayoutSchedulingCounter
    let probe: LayoutSchedulingAnimationProbe
    @State private var expanded = false
    @State private var showChild = true

    var body: some View {
        probe.toggle = {
            withAnimation(.spring(duration: 20.0, bounce: 0.35)) {
                expanded.toggle()
            }
        }
        return LayoutSchedulingPassThroughLayout(counter: counter) {
            VStack(spacing: 8) {
                if showChild {
                    VStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.green)
                            .frame(width: 40, height: 10)
                    }
                    .padding(18)
                    .background {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(expanded ? Color.orange.opacity(0.35) : Color.green.opacity(0.35))
                    }
                    .scaleEffect(expanded ? 1.0 : 0.82)
                    .offset(y: expanded ? -80 : 80)
                }
            }
        }
        .frame(width: 420, height: 240)
    }
}

private struct LayoutSchedulingConditionalRemovalRoot: View {
    let counter: LayoutSchedulingCounter
    let probe: LayoutSchedulingAnimationProbe
    @State private var showChild = true
    @State private var runCount = 0
    @State private var completionStatus = "idle"

    var body: some View {
        probe.toggle = toggleChild
        let markerOffset = CGFloat(runCount + completionStatus.count) * 0
        return LayoutSchedulingPassThroughLayout(counter: counter) {
            VStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.red)
                    .frame(width: showChild ? 120 : 80, height: 10)

                VStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.blue)
                        .frame(width: 120 + markerOffset, height: 10)
                    if showChild {
                        VStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.green)
                                .frame(width: 48, height: 24)
                        }
                        .padding(18)
                        .background {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.green.opacity(0.35))
                        }
                        .scaleEffect(0.82)
                        .offset(y: 8)
                        .transition(
                            .scale(scale: 0.72)
                                .combined(with: .opacity)
                                .animation(.easeInOut(duration: 5.0))
                        )
                    } else {
                        LayoutSchedulingDeferredIntrinsicSizeMarker(
                            resolvedSize: CGSize(width: 48, height: 10)
                        )
                            .padding(18)
                    }
                }
                .frame(width: 190, height: 150)
            }
        }
        .frame(width: 420, height: 240)
    }

    private func toggleChild() {
        let nextRun = runCount + 1
        let wasVisible = showChild
        runCount = nextRun
        completionStatus = wasVisible ? "removal running" : "insertion running"
        withAnimation(
            .easeInOut(duration: 5.0),
            completionCriteria: wasVisible ? .removed : .logicallyComplete
        ) {
            showChild.toggle()
        } completion: {
            completionStatus = wasVisible ? "removed" : "inserted"
            probe.completions.append(nextRun)
        }
    }
}

private struct LayoutSchedulingTextSiblingPlacementRoot: View {
    let counter: LayoutSchedulingCounter
    let probe: LayoutSchedulingAnimationProbe
    @State private var expanded = false

    var body: some View {
        probe.toggle = {
            withAnimation(.spring(duration: 20.0, bounce: 0.35)) {
                expanded.toggle()
            }
        }
        return LayoutSchedulingPassThroughLayout(counter: counter) {
            HStack(spacing: 28) {
                RoundedRectangle(cornerRadius: expanded ? 28 : 10)
                    .fill(expanded ? Color.purple : Color.blue)
                    .frame(width: expanded ? 180 : 72, height: 72)

                VStack(spacing: 8) {
                    LayoutSchedulingTextMarker(
                        content: LayoutSchedulingTextContent(value: "Retained removal"),
                        size: CGSize(width: 160, height: 20)
                    )
                }
                .frame(width: 190, height: 150)
            }
        }
        .frame(width: 420, height: 240)
    }
}

private struct LayoutSchedulingButtonLabelPlacementRoot: View {
    let counter: LayoutSchedulingCounter
    let probe: LayoutSchedulingAnimationProbe
    @State private var expanded = false

    var body: some View {
        probe.toggle = {
            withAnimation(.easeInOut(duration: 20.0)) {
                expanded.toggle()
            }
        }
        return LayoutSchedulingPassThroughLayout(counter: counter) {
            HStack(spacing: 10) {
                Button(action: {}) {
                    LayoutSchedulingTextMarker(
                        content: LayoutSchedulingTextContent(value: "static-leading"),
                        size: CGSize(width: 40, height: 20)
                    )
                }
                Button(action: {}) {
                    LayoutSchedulingTextMarker(
                        content: LayoutSchedulingTextContent(value: expanded ? "wide" : "narrow"),
                        size: CGSize(width: expanded ? 120 : 60, height: 20)
                    )
                }
                Button(action: {}) {
                    LayoutSchedulingTextMarker(
                        content: LayoutSchedulingTextContent(value: "static-trailing"),
                        size: CGSize(width: 40, height: 20)
                    )
                }
            }
        }
        .frame(width: 420, height: 240)
    }
}

private struct LayoutSchedulingAnimationLabButtonRowRoot: View {
    let counter: LayoutSchedulingCounter
    let probe: LayoutSchedulingAnimationProbe
    @State private var showChild = true

    var body: some View {
        probe.toggle = {
            withAnimation(.easeInOut(duration: 5)) {
                showChild.toggle()
            }
        }
        return LayoutSchedulingPassThroughLayout(counter: counter) {
            HStack(spacing: 10) {
                Button(action: {}) {
                    LayoutSchedulingTextMarker(
                        content: LayoutSchedulingTextContent(value: "Spring Move"),
                        size: CGSize(width: 84, height: 20)
                    )
                }
                Button(action: {}) {
                    LayoutSchedulingTextMarker(
                        content: LayoutSchedulingTextContent(
                            value: showChild ? "Remove Child" : "Insert Child"
                        ),
                        size: CGSize(width: showChild ? 96 : 84, height: 20)
                    )
                }
                Button(action: {}) {
                    LayoutSchedulingTextMarker(
                        content: LayoutSchedulingTextContent(value: "Sequence"),
                        size: CGSize(width: 68, height: 20)
                    )
                }
                Button(action: {}) {
                    LayoutSchedulingTextMarker(
                        content: LayoutSchedulingTextContent(value: "Close"),
                        size: CGSize(width: 40, height: 20)
                    )
                }
            }
        }
        .frame(width: 560, height: 120)
    }
}

private struct LayoutSchedulingResolvedTextButtonRowRoot: View {
    let probe: LayoutSchedulingAnimationProbe
    let font: VUI.Font
    @State private var showChild = true

    var body: some View {
        probe.toggle = {
            withAnimation(.easeInOut(duration: 5)) {
                showChild.toggle()
            }
        }
        return HStack(spacing: 10) {
            Button(action: {}) {
                Text(verbatim: "Spring Move")
                    .font(font)
            }
            Button(action: {}) {
                Text(verbatim: showChild ? "Remove Child" : "Insert Child")
                    .font(font)
            }
            Button(action: {}) {
                Text(verbatim: "Sequence")
                    .font(font)
            }
            Button(action: {}) {
                Text(verbatim: "Close")
                    .font(font)
            }
        }
        .frame(width: 560, height: 120)
    }
}

private struct LayoutSchedulingResolvedContentGeometryRoot: View {
    let probe: LayoutSchedulingAnimationProbe
    @State private var alternateText = false

    var body: some View {
        probe.toggle = {
            withAnimation(.easeInOut(duration: 5)) {
                alternateText.toggle()
            }
        }
        return VStack(spacing: 12) {
            Text(verbatim: "Interpolate")
                .font(.system(.headline))
            Text(verbatim: alternateText ? "Expanded value" : "Compact")
                .font(
                    .system(
                        size: alternateText ? 30 : 20,
                        weight: .semibold
                    )
                )
                .foregroundColor(alternateText ? .purple : .blue)
                .contentTransition(.interpolate)
            Button(action: {}) {
                Text(verbatim: "Change Text")
                    .font(.system(.body))
            }
        }
        .frame(width: 240)
        .frame(width: 320, height: 240)
    }
}

private struct LayoutSchedulingResolvedAnimationLabSpringRoot: View {
    let probe: LayoutSchedulingAnimationProbe
    let font: VUI.Font
    @State private var expanded = false

    var body: some View {
        probe.toggle = {
            withAnimation(.spring(duration: 5, bounce: 0.35)) {
                expanded.toggle()
            }
        }
        return HStack(spacing: 28) {
            RoundedRectangle(cornerRadius: expanded ? 28 : 10)
                .fill(expanded ? Color.purple : Color.blue)
                .frame(
                    width: expanded ? 180 : 72,
                    height: expanded ? 96 : 72
                )

            VStack(spacing: 8) {
                Text(verbatim: "Retained removal")
                    .font(font)
                VStack(spacing: 6) {
                    Text(verbatim: "Animated child")
                        .font(font)
                    Text(verbatim: expanded ? "expanded" : "compact")
                        .font(font)
                }
                .padding(18)
                .background {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(
                            expanded
                                ? Color.orange.opacity(0.35)
                                : Color.green.opacity(0.35)
                        )
                }
                .scaleEffect(expanded ? 1.0 : 0.82)
                .offset(y: expanded ? -8 : 8)
            }
            .frame(width: 190, height: 150)
            .border(.gray, width: 1)
        }
        .frame(width: 560, height: 360)
    }
}

private struct LayoutSchedulingResolvedAnimationLabRemovalTitleRoot: View {
    let probe: LayoutSchedulingAnimationLabProbe
    let font: VUI.Font
    @State private var expanded = false
    @State private var showRetainedChild = true

    var body: some View {
        probe.removeChild = {
            withAnimation(
                .easeInOut(duration: 5),
                completionCriteria: .removed
            ) {
                showRetainedChild = false
            } completion: {
            }
        }
        probe.insertChild = {
            withAnimation(
                .easeInOut(duration: 5),
                completionCriteria: .logicallyComplete
            ) {
                showRetainedChild = true
            } completion: {
            }
        }
        return HStack(spacing: 28) {
            RoundedRectangle(cornerRadius: expanded ? 28 : 10)
                .fill(expanded ? Color.purple : Color.blue)
                .frame(
                    width: expanded ? 180 : 72,
                    height: expanded ? 96 : 72
                )
                .scaleEffect(expanded ? 1.08 : 0.78)
                .rotationEffect(.degrees(expanded ? 8 : -8))
                .offset(
                    x: expanded ? 42 : -42,
                    y: expanded ? 8 : -8
                )
                .opacity(expanded ? 0.92 : 0.55)

            VStack(spacing: 8) {
                Text(verbatim: "Retained removal")
                    .font(font)
                if showRetainedChild {
                    VStack(spacing: 6) {
                        Text(verbatim: "Animated child")
                            .font(font)
                        Text(verbatim: expanded ? "expanded" : "compact")
                            .font(font)
                            .foregroundColor(.secondary)
                    }
                    .padding(18)
                    .background {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(
                                expanded
                                    ? Color.orange.opacity(0.35)
                                    : Color.green.opacity(0.35)
                            )
                    }
                    .scaleEffect(expanded ? 1.0 : 0.82)
                    .offset(y: expanded ? -8 : 8)
                    .transition(
                        .scale(scale: 0.72)
                            .combined(with: .opacity)
                            .animation(.easeInOut(duration: 5))
                    )
                } else {
                    Text(verbatim: "child removed")
                        .font(font)
                        .foregroundColor(.secondary)
                        .padding(18)
                }
            }
            .frame(width: 190, height: 150)
            .border(.gray, width: 1)
        }
        .frame(width: 560, height: 360)
    }
}

private struct LayoutSchedulingEnvironmentTextSiblingPlacementRoot: View {
    let counter: LayoutSchedulingCounter
    let probe: LayoutSchedulingAnimationProbe
    @State private var expanded = false

    var body: some View {
        probe.toggle = {
            withAnimation(.spring(duration: 20.0, bounce: 0.35)) {
                expanded.toggle()
            }
        }
        return LayoutSchedulingPassThroughLayout(counter: counter) {
            HStack(spacing: 28) {
                RoundedRectangle(cornerRadius: expanded ? 28 : 10)
                    .fill(expanded ? Color.purple : Color.blue)
                    .frame(width: expanded ? 180 : 72, height: 72)

                VStack(spacing: 8) {
                    LayoutSchedulingEnvironmentTextMarker(
                        content: LayoutSchedulingTextContent(value: "Retained removal"),
                        size: CGSize(width: 160, height: 20)
                    )
                    .font(.system(.headline))
                }
                .frame(width: 190, height: 150)
            }
        }
        .frame(width: 420, height: 240)
    }
}

private struct LayoutSchedulingReinsertedAnimationLabChildRoot: View {
    let counter: LayoutSchedulingCounter
    let probe: LayoutSchedulingAnimationLabProbe
    @State private var expanded = false
    @State private var showRetainedChild = true

    var body: some View {
        probe.removeChild = {
            withAnimation(
                .easeInOut(duration: 5),
                completionCriteria: .removed
            ) {
                showRetainedChild = false
            } completion: {
            }
        }
        probe.insertChild = {
            withAnimation(
                .easeInOut(duration: 5),
                completionCriteria: .logicallyComplete
            ) {
                showRetainedChild = true
            } completion: {
            }
        }
        probe.springMove = {
            withAnimation(.spring(duration: 5, bounce: 0.35)) {
                expanded.toggle()
            }
        }
        return LayoutSchedulingPassThroughLayout(counter: counter) {
            HStack(spacing: 28) {
                RoundedRectangle(cornerRadius: expanded ? 28 : 10)
                    .fill(expanded ? Color.purple : Color.blue)
                    .frame(
                        width: expanded ? 180 : 72,
                        height: expanded ? 96 : 72
                    )

                VStack(spacing: 8) {
                    LayoutSchedulingEnvironmentTextMarker(
                        content: LayoutSchedulingTextContent(value: "Retained removal"),
                        size: CGSize(width: 160, height: 20)
                    )
                    .font(.system(.headline))
                    if showRetainedChild {
                        VStack(spacing: 6) {
                            LayoutSchedulingTransitionTextMarker(
                                content: LayoutSchedulingTextContent(value: "Animated child"),
                                size: CGSize(width: 120, height: 20),
                                probe: probe.text
                            )
                            LayoutSchedulingEnvironmentTextMarker(
                                content: LayoutSchedulingTextContent(
                                    value: expanded ? "expanded" : "compact"
                                ),
                                size: CGSize(width: expanded ? 35 : 31, height: 10)
                            )
                        }
                        .padding(18)
                        .background {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(
                                    expanded
                                        ? Color.orange.opacity(0.35)
                                        : Color.green.opacity(0.35)
                                )
                        }
                        .scaleEffect(expanded ? 1.0 : 0.82)
                        .offset(y: expanded ? -8 : 8)
                        .transition(
                            .scale(scale: 0.72)
                                .combined(with: .opacity)
                                .animation(.easeInOut(duration: 5))
                        )
                    } else {
                        LayoutSchedulingRawTextMarker(size: CGSize(width: 80, height: 10))
                            .padding(18)
                    }
                }
                .frame(width: 190, height: 150)
                .border(.gray, width: 1)
            }
        }
        .frame(width: 560, height: 360)
    }
}

private struct LayoutSchedulingAnimationLabReplacementRoot: View {
    let counter: LayoutSchedulingCounter
    let probe: LayoutSchedulingAnimationLabProbe
    let font: VUI.Font
    @State private var showRetainedChild = true

    var body: some View {
        probe.removeChild = {
            withAnimation(
                .easeInOut(duration: 5),
                completionCriteria: .removed
            ) {
                showRetainedChild = false
            } completion: {
            }
        }
        probe.insertChild = {
            withAnimation(
                .easeInOut(duration: 5),
                completionCriteria: .logicallyComplete
            ) {
                showRetainedChild = true
            } completion: {
            }
        }
        return LayoutSchedulingPassThroughLayout(counter: counter) {
            HStack(spacing: 28) {
                Rectangle()
                    .fill(Color.blue)
                    .frame(width: 72, height: 72)

                VStack(spacing: 8) {
                    LayoutSchedulingRawTextMarker(size: CGSize(width: 160, height: 20))
                    if showRetainedChild {
                        VStack(spacing: 6) {
                            Text("Animated child")
                                .font(.system(.subheadline))
                            Text("compact")
                                .font(.system(.caption))
                                .foregroundColor(.secondary)
                        }
                        .padding(18)
                        .background {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.green.opacity(0.35))
                        }
                        .scaleEffect(0.82)
                        .offset(y: 8)
                        .transition(
                            .scale(scale: 0.72)
                                .combined(with: .opacity)
                                .animation(.easeInOut(duration: 5))
                        )
                    } else {
                        Text("child removed")
                            .font(.system(.caption))
                            .foregroundColor(Color(red: 1, green: 0, blue: 1))
                            .padding(18)
                    }
                }
                .frame(width: 190, height: 150)
                .border(.gray, width: 1)
            }
        }
        .frame(width: 560, height: 360)
    }
}

private struct LayoutSchedulingContentTransitionRoot: View {
    let probe: LayoutSchedulingContentTransitionProbe
    let font: VUI.Font

    @State private var count = 0
    @State private var alternateText = false

    var body: some View {
        probe.increment = {
            withAnimation(.linear(duration: 5)) {
                count += 17
            }
        }
        probe.changeText = {
            withAnimation(.linear(duration: 5)) {
                alternateText.toggle()
            }
        }
        return HStack(spacing: 70) {
            Text("\(count)")
                .font(font)
                .contentTransition(.numericText(value: Double(count)))
                .frame(width: 200, height: 80)

            Text(alternateText ? "Expanded value" : "Compact")
                .font(font)
                .foregroundColor(alternateText ? .purple : .blue)
                .contentTransition(.interpolate)
                .frame(width: 240, height: 80)
        }
        .frame(width: 680, height: 300)
    }
}

private struct LayoutSchedulingSystemNumericTransitionRoot: View {
    let probe: LayoutSchedulingContentTransitionProbe
    @State private var count = 0

    var body: some View {
        probe.increment = {
            withAnimation(.spring(duration: 1.2, bounce: 0.2)) {
                count += 17
            }
        }
        return VStack(spacing: 12) {
            Text("\(count)")
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .contentTransition(.numericText(value: Double(count)))
            Button("Increment", action: {})
        }
        .frame(width: 200, height: 180)
    }
}

private struct LayoutSchedulingSymbolDrawTransitionRoot: View {
    let probe: LayoutSchedulingAnimationProbe
    @State private var visible = true

    var body: some View {
        probe.toggle = {
            withAnimation {
                visible.toggle()
            }
        }
        return ZStack {
            if visible {
                Image(systemName: "draw")
                    .frame(width: 48, height: 48)
                    .foregroundStyle(Color.blue)
                    .transition(.symbolEffect(.drawOn.individually))
            }
        }
        .frame(width: 160, height: 120)
    }
}

private struct LayoutSchedulingRawTextSiblingPlacementRoot: View {
    let counter: LayoutSchedulingCounter
    let probe: LayoutSchedulingAnimationProbe
    @State private var expanded = false

    var body: some View {
        probe.toggle = {
            withAnimation(.spring(duration: 20.0, bounce: 0.35)) {
                expanded.toggle()
            }
        }
        return LayoutSchedulingPassThroughLayout(counter: counter) {
            HStack(spacing: 28) {
                RoundedRectangle(cornerRadius: expanded ? 28 : 10)
                    .fill(expanded ? Color.purple : Color.blue)
                    .frame(width: expanded ? 180 : 72, height: 72)

                VStack(spacing: 8) {
                    LayoutSchedulingRawTextMarker(size: CGSize(width: 160, height: 20))
                }
                .frame(width: 190, height: 150)
            }
        }
        .frame(width: 420, height: 240)
    }
}

private struct LayoutSchedulingBackgroundShapeColorRoot: View {
    let counter: LayoutSchedulingCounter
    let probe: LayoutSchedulingAnimationProbe
    @State private var expanded = false

    var body: some View {
        probe.toggle = {
            withAnimation(.spring(duration: 20.0, bounce: 0.35)) {
                expanded.toggle()
            }
        }
        return LayoutSchedulingPassThroughLayout(counter: counter) {
            VStack(spacing: 6) {
                LayoutSchedulingRawTextMarker(size: CGSize(width: 120, height: 20))
            }
            .padding(18)
            .background {
                RoundedRectangle(cornerRadius: 16)
                    .fill(expanded ? Color.orange.opacity(0.35) : Color.green.opacity(0.35))
            }
        }
        .frame(width: 420, height: 240)
    }
}

private struct LayoutSchedulingBackgroundShapeGeometryRoot: View {
    let counter: LayoutSchedulingCounter
    let probe: LayoutSchedulingAnimationProbe
    @State private var expanded = false

    var body: some View {
        probe.toggle = {
            withAnimation(.spring(duration: 20.0, bounce: 0.35)) {
                expanded.toggle()
            }
        }
        return LayoutSchedulingPassThroughLayout(counter: counter) {
            VStack(spacing: 6) {
                LayoutSchedulingRawTextMarker(size: CGSize(width: 120, height: 20))
            }
            .padding(18)
            .background {
                RoundedRectangle(cornerRadius: 16)
                    .fill(expanded ? Color.orange.opacity(0.35) : Color.green.opacity(0.35))
            }
            .scaleEffect(expanded ? 1.0 : 0.82)
            .offset(y: expanded ? -8 : 8)
        }
        .frame(width: 420, height: 240)
    }
}

private struct LayoutSchedulingTextContent: Equatable, InterpolatableContent {
    var value: String
}

private struct LayoutSchedulingResolvedTextSample {
    var frame: CGRect
    var opacity: Double
}

private struct LayoutSchedulingAnimationLabInsertionSample {
    var time: Double
    var title: LayoutSchedulingResolvedTextSample?
    var detail: LayoutSchedulingResolvedTextSample?
    var titlePixels: CGRect?
    var titlePixelSpread: Double?
    var detailPixelDarkness: Double?
    var backgroundPixels: CGRect?
}

private final class LayoutSchedulingAppContext: AppContext {
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

    func checkWindowActivities() {
    }
}

private struct LayoutSchedulingTransitionTextMarker: View {
    var content: LayoutSchedulingTextContent
    var size: CGSize
    var probe: LayoutSchedulingAnimationProbe

    typealias Body = Never

    static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("\(self)._makeView called outside an active _AGGraph context.")
        }

        let cachedEnvironmentAttribute = inputs.base.cachedEnvironment
        var cachedEnvironment = cachedEnvironmentAttribute.value
        let inputSize = cachedEnvironment.animatedSize(for: inputs)
        let position = cachedEnvironment.animatedPosition(for: inputs)
        cachedEnvironmentAttribute.value = cachedEnvironment
        view[\.probe]._attribute.value.insertionPosition = position
        view[\.probe]._attribute.value.insertionSize = inputSize
        let resolvedSize = graph.makeInput(value: CGSize.zero)
        let boxedSize = UnsafeBox(view._attribute.value.size)
        let transaction = graph.transaction(
            for: view._attribute.identifier
        ) ?? Transaction()
        let boxedTransaction = UnsafeBox(transaction)
        graph.inbox.enqueue(transaction: transaction) {
            resolvedSize.setValue(boxedSize.value, transaction: boxedTransaction.value)
        }
        let layoutComputer: Attribute<LayoutComputer> = graph.makeRule {
            LayoutComputer.fixed(resolvedSize.value)
        }
        let displayList: Attribute<DisplayList> = graph.makeRule {
            let bounds = CGRect(origin: position.value, size: inputSize.value.value)
            var list = DisplayList()
            list.appendTextItem(foreground: .color(.red), bounds: bounds) { _ in }
            list.appendDebugItem(bounds: bounds) { _ in }
            return list
        }

        var outputs = _ViewOutputs(layoutComputer: OptionalAttribute(layoutComputer))
        outputs.preferences.append(DisplayList.Key.self, node: displayList.identifier)
        outputs.applyInterpolatorGroup(
            DisplayList.UnaryInterpolatorGroup(),
            content: view[\.content]._attribute,
            inputs: inputs,
            animatesSize: false,
            defersRender: false
        )
        return outputs
    }
}

extension LayoutSchedulingTransitionTextMarker: TestPrimitiveView {
}

private struct LayoutSchedulingDeferredIntrinsicSizeMarker: View {
    let resolvedSize: CGSize

    typealias Body = Never

    static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("\(self)._makeView called outside an active _AGGraph context.")
        }

        let size = view._attribute.value.resolvedSize
        let resolvedSize = graph.makeInput(value: CGSize.zero)
        let boxedSize = UnsafeBox(size)
        graph.inbox.enqueue {
            resolvedSize.setValue(boxedSize.value)
        }
        let layoutComputer: Attribute<LayoutComputer> = graph.makeRule {
            LayoutComputer.fixed(resolvedSize.value)
        }
        return _ViewOutputs(layoutComputer: OptionalAttribute(layoutComputer))
    }
}

extension LayoutSchedulingDeferredIntrinsicSizeMarker: TestPrimitiveView {
}

private struct LayoutSchedulingTextMarker: View {
    var content: LayoutSchedulingTextContent
    var size: CGSize

    typealias Body = Never

    static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("\(self)._makeView called outside an active _AGGraph context.")
        }

        let cachedEnvironmentAttribute = inputs.base.cachedEnvironment
        var cachedEnvironment = cachedEnvironmentAttribute.value
        let sizeAttr = cachedEnvironment.animatedSize(for: inputs)
        let positionAttr = cachedEnvironment.animatedPosition(for: inputs)
        cachedEnvironmentAttribute.value = cachedEnvironment
        let lcAttr: Attribute<LayoutComputer> = graph.makeRule {
            LayoutComputer.fixed(view._attribute.value.size)
        }
        let displayListAttr: Attribute<DisplayList> = graph.makeRule {
            let position = positionAttr.value
            let size = sizeAttr.value.value
            var list = DisplayList()
            list.appendTextItem(
                foreground: .color(.red),
                bounds: CGRect(origin: position, size: size)
            ) { _ in }
            return list
        }

        var outputs = _ViewOutputs()
        outputs._layoutComputer = OptionalAttribute(lcAttr)
        outputs.preferences.append(DisplayList.Key.self, node: displayListAttr.identifier)
        outputs.applyInterpolatorGroup(
            DisplayList.InterpolatorGroup(),
            content: view[\.content]._attribute,
            inputs: inputs,
            animatesSize: false,
            defersRender: false
        )
        return outputs
    }
}

extension LayoutSchedulingTextMarker: TestPrimitiveView {
}

private struct LayoutSchedulingRawTextMarker: View {
    var size: CGSize

    typealias Body = Never

    static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("\(self)._makeView called outside an active _AGGraph context.")
        }

        let positionAttr = inputs.position
        let sizeAttr = inputs.size
        let lcAttr: Attribute<LayoutComputer> = graph.makeRule {
            LayoutComputer.fixed(view._attribute.value.size)
        }
        let displayListAttr: Attribute<DisplayList> = graph.makeRule {
            let position = positionAttr.value
            let size = sizeAttr.value.value
            var list = DisplayList()
            list.appendTextItem(
                foreground: .color(.red),
                bounds: CGRect(origin: position, size: size)
            ) { _ in }
            return list
        }

        var outputs = _ViewOutputs()
        outputs._layoutComputer = OptionalAttribute(lcAttr)
        outputs.preferences.append(DisplayList.Key.self, node: displayListAttr.identifier)
        return outputs
    }
}

extension LayoutSchedulingRawTextMarker: TestPrimitiveView {
}

private struct LayoutSchedulingEnvironmentTextMarker: View {
    var content: LayoutSchedulingTextContent
    var size: CGSize

    typealias Body = Never

    static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("\(self)._makeView called outside an active _AGGraph context.")
        }

        let cachedEnvironmentAttr = inputs.base.cachedEnvironment
        var cachedEnvironment = cachedEnvironmentAttr.value
        let sizeAttr = cachedEnvironment.animatedSize(for: inputs)
        let positionAttr = cachedEnvironment.animatedPosition(for: inputs)
        cachedEnvironmentAttr.value = cachedEnvironment
        let lcAttr: Attribute<LayoutComputer> = graph.makeRule {
            _ = cachedEnvironmentAttr.value.environment.value.font
            return LayoutComputer.fixed(view._attribute.value.size)
        }
        let displayListAttr: Attribute<DisplayList> = graph.makeRule {
            let position = positionAttr.value
            let size = sizeAttr.value.value
            var list = DisplayList()
            list.appendTextItem(
                foreground: .color(.red),
                bounds: CGRect(origin: position, size: size)
            ) { _ in }
            return list
        }

        var outputs = _ViewOutputs()
        outputs._layoutComputer = OptionalAttribute(lcAttr)
        outputs.preferences.append(DisplayList.Key.self, node: displayListAttr.identifier)
        outputs.applyInterpolatorGroup(
            DisplayList.InterpolatorGroup(),
            content: view[\.content]._attribute,
            inputs: inputs,
            animatesSize: false,
            defersRender: false
        )
        return outputs
    }
}

extension LayoutSchedulingEnvironmentTextMarker: TestPrimitiveView {
}

private struct LayoutSchedulingAnimatedFrame: View {
    let probe: LayoutSchedulingAnimationProbe
    @State private var expanded = false

    var body: some View {
        probe.toggle = {
            expanded.toggle()
        }
        return RoundedRectangle(cornerRadius: expanded ? 28 : 10)
            .fill(expanded ? Color.purple : Color.blue)
            .frame(
                width: expanded ? 180 : 72,
                height: expanded ? 96 : 72
            )
            .offset(
                x: expanded ? 42 : -42,
                y: expanded ? 8 : -8
            )
    }
}

private struct LayoutSchedulingFullStackAnimatedFrame: View {
    let probe: LayoutSchedulingAnimationProbe
    @State private var expanded = false

    var body: some View {
        probe.toggle = {
            expanded.toggle()
        }
        return RoundedRectangle(cornerRadius: expanded ? 28 : 10)
            .fill(expanded ? Color.purple : Color.blue)
            .frame(
                width: expanded ? 180 : 72,
                height: expanded ? 96 : 72
            )
            .scaleEffect(expanded ? 1.08 : 0.78)
            .rotationEffect(.degrees(expanded ? 8 : -8))
            .offset(
                x: expanded ? 42 : -42,
                y: expanded ? 8 : -8
            )
            .opacity(expanded ? 0.92 : 0.55)
    }
}

private struct LayoutSchedulingPassThroughLayout: Layout {
    let counter: LayoutSchedulingCounter

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        proposal.replacingUnspecifiedDimensions(by: CGSize(width: 420, height: 240))
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        counter.placements += 1
        for subview in subviews {
            subview.place(
                at: CGPoint(x: bounds.midX, y: bounds.midY),
                anchor: .center,
                proposal: ProposedViewSize(bounds.size)
            )
        }
    }
}
