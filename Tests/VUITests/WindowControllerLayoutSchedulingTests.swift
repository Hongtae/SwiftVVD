import XCTest
@testable import VVD
@testable import VUI

final class WindowControllerLayoutSchedulingTests: XCTestCase {
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
            delta: 1.0 / 60.0,
            date: controller.date,
            contentSize: CGSize(width: 120, height: 80),
            redraw: &redraw,
            withGC
        )
        let initialPlacements = counter.placements
        XCTAssertGreaterThan(initialPlacements, 0)

        controller.updateView(
            tick: 1,
            delta: 1.0 / 60.0,
            date: controller.date.addingTimeInterval(1.0 / 60.0),
            contentSize: CGSize(width: 120, height: 80),
            redraw: &redraw,
            withGC
        )
        XCTAssertEqual(counter.placements, initialPlacements)

        controller.updateView(
            tick: 2,
            delta: 1.0 / 60.0,
            date: controller.date.addingTimeInterval(2.0 / 60.0),
            contentSize: CGSize(width: 140, height: 80),
            redraw: &redraw,
            withGC
        )
        XCTAssertGreaterThan(counter.placements, initialPlacements)
    }

    @MainActor
    func testScheduledAnimationUpdateDoesNotRepeatRootLayoutPlacement() throws {
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
            delta: 1.0 / 60.0,
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
            delta: 1.0 / 60.0,
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
            delta: 1.0 / 60.0,
            date: controller.date.addingTimeInterval(0.25),
            contentSize: CGSize(width: 420, height: 240),
            redraw: &redraw,
            withGC
        )

        let sampledBounds = try displayBounds(in: controller)
        XCTAssertEqual(counter.placements, targetPlacements)
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
            delta: 1.0 / 60.0,
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
                delta: 1.0 / 60.0,
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
            delta: 1.0 / 60.0,
            date: controller.date.addingTimeInterval(20.1),
            contentSize: CGSize(width: 420, height: 240),
            redraw: &redraw,
            withGC
        )
        _ = try displayList(in: controller)
        redraw = false
        controller.updateView(
            tick: 21,
            delta: 1.0 / 60.0,
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
            delta: 1.0 / 60.0,
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
                delta: 1.0 / 60.0,
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
            delta: 1.0 / 60.0,
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
            location: CGPoint(x: 210, y: 120)
        )))
        XCTAssertTrue(controller.handleMouseEvent(event: MouseEvent(
            type: .buttonUp,
            device: .genericMouse,
            deviceID: 0,
            buttonID: 0,
            location: CGPoint(x: 210, y: 120)
        )))
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        XCTAssertEqual(probe.completions, [])

        for (index, sampleTime) in [0.0, 1.0 / 60.0, 2.0 / 60.0, 0.1, 1.0, 10.0].enumerated() {
            redraw = false
            controller.updateView(
                tick: UInt64(index + 1),
                delta: 1.0 / 60.0,
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
            delta: 1.0 / 60.0,
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
                    delta: 1.0 / 60.0,
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
            delta: 1.0 / 60.0,
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
            delta: 1.0 / 60.0,
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
            delta: 1.0 / 60.0,
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
                delta: 1.0 / 60.0,
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
            delta: 1.0 / 60.0,
            date: controller.date.addingTimeInterval(20.1),
            contentSize: CGSize(width: 420, height: 240),
            redraw: &redraw,
            withGC
        )
        _ = try displayList(in: controller)
        redraw = false
        controller.updateView(
            tick: 21,
            delta: 1.0 / 60.0,
            date: controller.date.addingTimeInterval(20.1),
            contentSize: CGSize(width: 420, height: 240),
            redraw: &redraw,
            withGC
        )
        let completeDisplayList = try displayList(in: controller)
        XCTAssertEqual(probe.completions, [1])
        XCTAssertEqual(try XCTUnwrap(statusMarkerBounds(in: completeDisplayList)).width, 160, accuracy: 0.5)
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
            delta: 1.0 / 60.0,
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
                delta: 1.0 / 60.0,
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
            delta: 1.0 / 60.0,
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
                delta: 1.0 / 60.0,
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
            delta: 1.0 / 60.0,
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
                delta: 1.0 / 60.0,
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
            delta: 1.0 / 60.0,
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
                delta: 1.0 / 60.0,
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
            delta: 1.0 / 60.0,
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
                delta: 1.0 / 60.0,
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
    func testRawTextLikeSiblingPlacementSurfaceSamplesIntermediatePositionDuringSpringMove() throws {
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
            delta: 1.0 / 60.0,
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
                delta: 1.0 / 60.0,
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
            expected raw text-like placement to animate through frame attributes:
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
            delta: 1.0 / 60.0,
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
                delta: 1.0 / 60.0,
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
            delta: 1.0 / 60.0,
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
            delta: 1.0 / 60.0,
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
            delta: 1.0 / 60.0,
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
                delta: 1.0 / 60.0,
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
            delta: 1.0 / 60.0,
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
                delta: 1.0 / 60.0,
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
            delta: 1.0 / 60.0,
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
                delta: 1.0 / 60.0,
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
            delta: 1.0 / 60.0,
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
            delta: 1.0 / 60.0,
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
            delta: 1.0 / 60.0,
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

    private func translucentShapeFillRecords(in displayList: DisplayList) -> [(bounds: CGRect, color: VUI.Color)] {
        var records = shapeFillRecords(in: displayList).filter { $0.color.provider.alpha < 0.8 }
        for effect in displayList.effects {
            records.append(contentsOf: translucentShapeFillRecords(in: effect.contents))
        }
        return records
    }

    private func translucentShapeFillColors(in displayList: DisplayList) -> [VUI.Color] {
        translucentShapeFillRecords(in: displayList).map(\.color)
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
            location: CGPoint(x: 210, y: 120)
        )))
        XCTAssertTrue(controller.handleMouseEvent(event: MouseEvent(
            type: .buttonUp,
            device: .genericMouse,
            deviceID: 0,
            buttonID: 0,
            location: CGPoint(x: 210, y: 120)
        )))
    }
}

private final class LayoutSchedulingCounter {
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

private struct LayoutSchedulingTextMarker: View {
    var content: LayoutSchedulingTextContent
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

extension LayoutSchedulingTextMarker: _PrimitiveView {
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

extension LayoutSchedulingRawTextMarker: _PrimitiveView {
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
        let animatedFrame = cachedEnvironmentAttr.value.animatedFrame
        let positionAttr = animatedFrame?._animatedPosition ?? inputs.position
        let sizeAttr = animatedFrame?._animatedSize ?? inputs.size
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

extension LayoutSchedulingEnvironmentTextMarker: _PrimitiveView {
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
