import XCTest
@testable import VVD
@testable import VUI

final class WindowControllerLayoutSchedulingTests: XCTestCase {
    // ASSERTIONS updateRenderPhaseAnimatorOrderObserved
    func testPendingHostTransactionsFlushBeforeNextUpdateSeedAdvances() {
        let controller = WindowController(
            content: EmptyView(),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(
                    WindowControllerLayoutSchedulingTests.self
                )
            )
        )
        let withGC: WindowContext.WithGraphicsContext = { _, _ in }

        controller.updateFrame(
            tick: 0,
            delta: 0,
            date: controller.date,
            contentSize: CGSize(width: 220, height: 220),
            shouldDrawFrame: false,
            withGC
        )
        let seedBeforeNextFrame = controller.viewGraph.data.updateSeed
        var appliedSeed: UInt32?
        controller.viewGraph.asyncTransaction {
            appliedSeed = controller.viewGraph.data.updateSeed
        }

        controller.updateFrame(
            tick: 1,
            delta: 1.0 / 60.0,
            date: controller.date.addingTimeInterval(1.0 / 60.0),
            contentSize: CGSize(width: 220, height: 220),
            shouldDrawFrame: false,
            withGC
        )

        XCTAssertEqual(appliedSeed, seedBeforeNextFrame)
        XCTAssertEqual(
            controller.viewGraph.data.updateSeed,
            seedBeforeNextFrame &+ 1
        )
    }

    func testViewGraphActionOutboxDrainsWithoutGraphBinding() {
        let controller = WindowController(
            content: EmptyView(),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(
                    WindowControllerLayoutSchedulingTests.self
                )
            )
        )
        var actionRan = false
        var observedGraphBinding = true
        var observedUpdateScope = false

        controller.viewGraph.data.withCurrent {
            controller.viewGraph.data.graph.actionOutbox.append {
                actionRan = true
                observedGraphBinding = _AGGraph.current != nil
                observedUpdateScope = Update.isActive
            }
        }

        let withGC: WindowContext.WithGraphicsContext = { _, _ in }
        controller.updateFrame(
            tick: 0,
            delta: 0,
            date: controller.date,
            contentSize: CGSize(width: 220, height: 220),
            shouldDrawFrame: false,
            withGC
        )

        XCTAssertTrue(actionRan)
        XCTAssertFalse(observedGraphBinding)
        XCTAssertTrue(observedUpdateScope)
    }

    func testViewGraphActionOutboxDefersWorkProducedDuringCurrentHostTurn() {
        // ASSERTIONS lazyScrollTargetGraphUpdateOrderObserved
        let controller = WindowController(
            content: EmptyView(),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(
                    WindowControllerLayoutSchedulingTests.self
                )
            )
        )
        let counter = LayoutSchedulingCounter()
        controller.enqueueInputAction {
            controller.viewGraph.data.graph.actionOutbox.append {
                counter.placements += 1
            }
        }

        let withGC: WindowContext.WithGraphicsContext = { _, _ in }
        controller.updateFrame(
            tick: 0,
            delta: 0,
            date: controller.date,
            contentSize: CGSize(width: 220, height: 220),
            shouldDrawFrame: false,
            withGC
        )

        XCTAssertEqual(counter.placements, 0)
        XCTAssertEqual(controller.viewGraph.data.graph.actionOutbox.count, 1)

        controller.updateFrame(
            tick: 1,
            delta: 1.0 / 60.0,
            date: controller.date.addingTimeInterval(1.0 / 60.0),
            contentSize: CGSize(width: 220, height: 220),
            shouldDrawFrame: false,
            withGC
        )

        XCTAssertEqual(counter.placements, 1)
        XCTAssertTrue(controller.viewGraph.data.graph.actionOutbox.isEmpty)
    }

    @MainActor
    func testScrollViewRootDisplayListMountsContentOnlyInsidePlatformGroup() throws {
        let controller = WindowController(
            content: LayoutSchedulingScrollViewAttachmentRoot(),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(LayoutSchedulingScrollViewAttachmentRoot.self)
            )
        )
        let withGC: WindowContext.WithGraphicsContext = { _, _ in
            XCTFail("Scroll-view display-list test should not request graphics resources.")
        }
        var redraw = false
        controller.updateView(
            tick: 0,
            delta: 0,
            date: controller.date,
            contentSize: CGSize(width: 220, height: 220),
            redraw: &redraw,
            withGC
        )
        let list = try displayList(in: controller)
        XCTAssertEqual(list.items.count, 1, displayListTreeDescription(list))
        let item = try XCTUnwrap(list.items.first)
        let effect = try XCTUnwrap(item.effectItem)
        guard case .platformGroup = effect.effect else {
            return XCTFail("expected platform group: \(displayListTreeDescription(list))")
        }
        XCTAssertEqual(item.frame, CGRect(x: 70, y: 60, width: 80, height: 100))
        XCTAssertEqual(effect.contents.items.count, 8)
        XCTAssertEqual(
            effect.contents.interpolationBounds,
            CGRect(x: 0, y: 0, width: 80, height: 320)
        )
    }

    @MainActor
    func testScrollViewReaderRealizesMountedLazyNonVisibleTarget() throws {
        let probe = LayoutSchedulingScrollViewReaderProbe()
        let controller = WindowController(
            content: LayoutSchedulingScrollViewReaderRoot(probe: probe),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(LayoutSchedulingScrollViewReaderRoot.self)
            )
        )
        let withGC: WindowContext.WithGraphicsContext = { _, _ in
            XCTFail("Scroll-view reader test should not request graphics resources.")
        }
        var redraw = false
        controller.updateView(
            tick: 0,
            delta: 0,
            date: controller.date,
            contentSize: CGSize(width: 220, height: 220),
            redraw: &redraw,
            withGC
        )

        let root = try XCTUnwrap(
            controller.responderNode
                as? MultiViewResponder
        )
        let responder = try XCTUnwrap(firstHostingScrollViewResponder(in: root))
        let host = try XCTUnwrap(responder.hostContainer?.scrollView)
        XCTAssertEqual(try XCTUnwrap(host.pendingContext).contentOffset, .zero)
        XCTAssertFalse(
            shapeFillRecords(in: try displayList(in: controller)).contains {
                $0.color.provider.red > $0.color.provider.green &&
                    $0.color.provider.red > $0.color.provider.blue
            }
        )

        try controller.viewGraph.data.withCurrent {
            try XCTUnwrap(probe.proxy).scrollTo(150, anchor: .top)
        }
        controller.updateView(
            tick: 1,
            delta: 1.0 / 60.0,
            date: controller.date.addingTimeInterval(1.0 / 60.0),
            contentSize: CGSize(width: 220, height: 220),
            redraw: &redraw,
            withGC
        )
        controller.updateView(
            tick: 2,
            delta: 1.0 / 60.0,
            date: controller.date.addingTimeInterval(2.0 / 60.0),
            contentSize: CGSize(width: 220, height: 220),
            redraw: &redraw,
            withGC
        )

        XCTAssertEqual(
            try XCTUnwrap(host.pendingContext).contentOffset.y,
            3_000,
            accuracy: 0.001
        )
        let refreshedRoot = try XCTUnwrap(
            controller.responderNode
                as? MultiViewResponder
        )
        let refreshedHost = try XCTUnwrap(
            firstHostingScrollViewResponder(in: refreshedRoot)
                .flatMap { $0.hostContainer?.scrollView }
        )
        XCTAssertTrue(refreshedHost === host)

        let lazyState = try controller.viewGraph.data.withCurrent {
            let proxy = try XCTUnwrap(probe.proxy)
            let scrollables = proxy._values.toStrong().value
            let lazy = try XCTUnwrap(
                scrollables.first?.mapFirstChild(
                    ofType: LazyScrollable<LazyVStackLayout>.self
                ) { $0 }
            )
            let cache = try XCTUnwrap(lazy.cache)
            return (
                ids: lazy.visibleCollectionViewIDs,
                itemCount: cache.items.count
            )
        }
        XCTAssertTrue(
            lazyState.ids.first { id in
                id.explicitID == AnyHashable(150) ||
                    id.explicitID == AnyHashable(Optional(150))
            } != nil
        )
        XCTAssertLessThan(lazyState.itemCount, 20)

        let records = shapeFillRecords(in: try displayList(in: controller))
        XCTAssertTrue(
            records.contains {
                $0.color.provider.red > $0.color.provider.green &&
                    $0.color.provider.red > $0.color.provider.blue
            },
            "records: " + records.map {
                "\(String(reflecting: $0.color)):\($0.bounds)"
            }.joined(separator: ", ")
        )
    }

    @MainActor
    func testScrollViewReaderRealizesMountedTextLazyNonVisibleTarget() async throws {
        let probe = LayoutSchedulingScrollViewReaderProbe()
        let controller = WindowController(
            content: LayoutSchedulingTextScrollViewReaderRoot(probe: probe),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(LayoutSchedulingTextScrollViewReaderRoot.self)
            )
        )
        let withGC: WindowContext.WithGraphicsContext = { _, _ in }
        var redraw = false
        controller.updateView(
            tick: 0,
            delta: 0,
            date: controller.date,
            contentSize: CGSize(width: 520, height: 470),
            redraw: &redraw,
            withGC
        )

        let root = try XCTUnwrap(
            controller.responderNode
                as? MultiViewResponder
        )
        let responder = try XCTUnwrap(firstHostingScrollViewResponder(in: root))
        let host = try XCTUnwrap(responder.hostContainer?.scrollView)
        XCTAssertEqual(try XCTUnwrap(host.pendingContext).contentOffset, .zero)

        for tick in 1...3 {
            controller.updateView(
                tick: UInt64(tick),
                delta: 1.0 / 60.0,
                date: controller.date.addingTimeInterval(Double(tick) / 60.0),
                contentSize: CGSize(width: 520, height: 470),
                redraw: &redraw,
                withGC
            )
        }
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }

        let estimateSnapshot = try controller.viewGraph.data.withCurrent {
            let proxy = try XCTUnwrap(probe.proxy)
            let scrollables = proxy._values.toStrong().value
            let lazy = try XCTUnwrap(
                scrollables.first?.mapFirstChild(
                    ofType: LazyScrollable<LazyVStackLayout>.self
                ) { $0 }
            )
            let cache = try XCTUnwrap(lazy.cache).cacheState
            return (
                average: cache.estimations.average,
                spacings: cache.estimations.spacingToCount
            )
        }
        XCTAssertEqual(estimateSnapshot.average.length, 30, accuracy: 0.001)
        XCTAssertEqual(
            try XCTUnwrap(estimateSnapshot.average.spacing),
            4,
            accuracy: 0.001
        )
        XCTAssertNil(estimateSnapshot.spacings[0])

        try controller.viewGraph.data.withCurrent {
            try XCTUnwrap(probe.proxy).scrollTo(150, anchor: .top)
        }
        var observedOffsets = [try XCTUnwrap(host.pendingContext).contentOffset.y]
        controller.updateView(
            tick: 4,
            delta: 1.0 / 60.0,
            date: controller.date.addingTimeInterval(4.0 / 60.0),
            contentSize: CGSize(width: 520, height: 470),
            redraw: &redraw,
            withGC
        )
        observedOffsets.append(
            try XCTUnwrap(host.pendingContext).contentOffset.y
        )
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }
        for tick in 5...6 {
            controller.updateView(
                tick: UInt64(tick),
                delta: 1.0 / 60.0,
                date: controller.date.addingTimeInterval(Double(tick) / 60.0),
                contentSize: CGSize(width: 520, height: 470),
                redraw: &redraw,
                withGC
            )
            observedOffsets.append(
                try XCTUnwrap(host.pendingContext).contentOffset.y
            )
        }

        for offset in observedOffsets.dropFirst() {
            XCTAssertEqual(offset, 5_104, accuracy: 0.001)
        }

        XCTAssertEqual(
            try XCTUnwrap(host.pendingContext).contentOffset.y,
            5_104,
            accuracy: 0.001,
            "offsets: \(observedOffsets)"
        )
        let refreshedRoot = try XCTUnwrap(
            controller.responderNode
                as? MultiViewResponder
        )
        let refreshedHost = try XCTUnwrap(
            firstHostingScrollViewResponder(in: refreshedRoot)
                .flatMap { $0.hostContainer?.scrollView }
        )
        XCTAssertTrue(refreshedHost === host)
    }

    // ASSERTIONS appKitEventActionUpdateBoundaryObserved buttonPressedDragBoundaryBindingObserved
    @MainActor
    func testScrollViewReaderButtonActionResolvesOwningGraph() throws {
        let probe = LayoutSchedulingButtonScrollViewReaderProbe()
        let controller = WindowController(
            content: LayoutSchedulingButtonScrollViewReaderRoot(probe: probe),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(
                    LayoutSchedulingButtonScrollViewReaderRoot.self
                )
            )
        )
        let withGC: WindowContext.WithGraphicsContext = { _, _ in }
        var redraw = false
        for tick in 0...3 {
            controller.updateView(
                tick: UInt64(tick),
                delta: tick == 0 ? 0 : 1.0 / 60.0,
                date: controller.date.addingTimeInterval(
                    Double(tick) / 60.0
                ),
                contentSize: CGSize(width: 520, height: 470),
                redraw: &redraw,
                withGC
            )
        }

        let root = try XCTUnwrap(
            controller.responderNode
                as? MultiViewResponder
        )
        let responder = try XCTUnwrap(firstHostingScrollViewResponder(in: root))
        let host = try XCTUnwrap(responder.hostContainer?.scrollView)
        XCTAssertEqual(try XCTUnwrap(host.pendingContext).contentOffset, .zero)
        XCTAssertNil(_AGGraph.current)

        let location = CGPoint(x: 260, y: 235)
        XCTAssertTrue(controller.handleMouseEvent(event: MouseEvent(
            type: .buttonDown,
            device: .genericMouse,
            deviceID: 0,
            buttonID: 0,
            location: location,
            timestamp: 0
        )))
        XCTAssertTrue(controller.handleMouseEvent(event: MouseEvent(
            type: .buttonUp,
            device: .genericMouse,
            deviceID: 0,
            buttonID: 0,
            location: location,
            timestamp: 0
        )))
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))

        XCTAssertEqual(probe.actionCount, 1)
        XCTAssertTrue(probe.actionHadNoGraphContext)
        XCTAssertNil(_AGGraph.current)

        for tick in 4...6 {
            controller.updateView(
                tick: UInt64(tick),
                delta: 1.0 / 60.0,
                date: controller.date.addingTimeInterval(
                    Double(tick) / 60.0
                ),
                contentSize: CGSize(width: 520, height: 470),
                redraw: &redraw,
                withGC
            )
        }

        XCTAssertEqual(
            try XCTUnwrap(host.pendingContext).contentOffset.y,
            5_104,
            accuracy: 0.001
        )
    }

    // ASSERTIONS systemScrollViewDeferredTargetInvocationContextObserved
    @MainActor
    func testModalScrollViewReaderButtonActionRealizesMountedTarget() throws {
        guard let deviceContext = makeGraphicsDeviceContext(api: .metal),
              let renderQueue = deviceContext.renderQueue() else {
            throw XCTSkip("Metal graphics device unavailable")
        }
        let previousAppContext = appContext
        appContext = LayoutSchedulingAppContext(
            graphicsDeviceContext: deviceContext
        )
        defer { appContext = previousAppContext }

        let probe = LayoutSchedulingStatefulScrollViewReaderProbe()
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
                            LayoutSchedulingStatefulScrollViewReaderRoot(
                                probe: probe
                            )
                        )
                    )
                )
            )
            return ModalWindowController(
                crossGraphContent: contentAttr,
                sourceGraph: sourceGraph,
                scene: WindowKey(
                    namespace: .app,
                    sceneID: SceneID(
                        LayoutSchedulingStatefulScrollViewReaderRoot.self
                    )
                ),
                parentController: parent,
                usesPlatformWindow: true
            )
        }
        let withGC: WindowContext.WithGraphicsContext = { _, handler in
            guard let commandBuffer = renderQueue.makeCommandBuffer(),
                  let context = GraphicsContext(
                    sceneResources: child.sceneResources,
                    environment: child.environment,
                    viewport: CGRect(x: 0, y: 0, width: 520, height: 470),
                    contentOffset: .zero,
                    contentScaleFactor: 1,
                    resolution: CGSize(width: 520, height: 470),
                    commandBuffer: commandBuffer
                  ) else {
                return XCTFail("Unable to create the scroll-view resource graphics context.")
            }
            handler(context)
            XCTAssertTrue(commandBuffer.commit())
        }
        var redraw = false
        for tick in 0...3 {
            child.updateView(
                tick: UInt64(tick),
                delta: tick == 0 ? 0 : 1.0 / 60.0,
                date: child.date.addingTimeInterval(Double(tick) / 60.0),
                contentSize: CGSize(width: 520, height: 470),
                redraw: &redraw,
                withGC
            )
        }

        let root = try XCTUnwrap(
            child.responderNode
                as? MultiViewResponder
        )
        let responder = try XCTUnwrap(firstHostingScrollViewResponder(in: root))
        let host = try XCTUnwrap(responder.hostContainer?.scrollView)
        XCTAssertEqual(try XCTUnwrap(host.pendingContext).contentOffset, .zero)

        let renderer = DisplayList.GraphicsRenderer()
        let initialCommandBuffer = try XCTUnwrap(renderQueue.makeCommandBuffer())
        let initialContext = try XCTUnwrap(GraphicsContext(
            sceneResources: child.sceneResources,
            environment: child.environment,
            viewport: CGRect(x: 0, y: 0, width: 520, height: 470),
            contentOffset: .zero,
            contentScaleFactor: 1,
            resolution: CGSize(width: 520, height: 470),
            commandBuffer: initialCommandBuffer
        ))
        initialContext.clear(with: .white)
        renderer.render(
            list: try displayList(in: child),
            at: child.animationTimestamp,
            in: initialContext
        )
        let initialCondition = NSCondition()
        var initialCompleted = false
        initialCommandBuffer.addCompletedHandler { _ in
            initialCondition.lock()
            initialCompleted = true
            initialCondition.broadcast()
            initialCondition.unlock()
        }
        initialCondition.lock()
        XCTAssertTrue(initialCommandBuffer.commit())
        let initialTimeout = Date(timeIntervalSinceNow: 5)
        while !initialCompleted {
            if !initialCondition.wait(until: initialTimeout) {
                XCTFail("GPU command buffer timed out")
                break
            }
        }
        initialCondition.unlock()

        try XCTUnwrap(probe.action)()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))

        for tick in 4...6 {
            child.updateView(
                tick: UInt64(tick),
                delta: 1.0 / 60.0,
                date: child.date.addingTimeInterval(Double(tick) / 60.0),
                contentSize: CGSize(width: 520, height: 470),
                redraw: &redraw,
                withGC
            )
        }

        XCTAssertEqual(
            try XCTUnwrap(host.pendingContext).contentOffset.y,
            5_104,
            accuracy: 0.001
        )
        let list = try displayList(in: child)
        XCTAssertFalse(list.items.isEmpty)

        let commandBuffer = try XCTUnwrap(renderQueue.makeCommandBuffer())
        let context = try XCTUnwrap(GraphicsContext(
            sceneResources: child.sceneResources,
            environment: child.environment,
            viewport: CGRect(x: 0, y: 0, width: 520, height: 470),
            contentOffset: .zero,
            contentScaleFactor: 1,
            resolution: CGSize(width: 520, height: 470),
            commandBuffer: commandBuffer
        ))
        context.clear(with: .white)
        renderer.render(
            list: list,
            at: child.animationTimestamp,
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
            count: 520 * 470 * 4
        )
        let viewport = CGRect(x: 114, y: 131, width: 300, height: 260)
            .insetBy(dx: 2, dy: 2)
            .integral
        var nonWhitePixelCount = 0
        for y in Int(viewport.minY)..<Int(viewport.maxY) {
            for x in Int(viewport.minX)..<Int(viewport.maxX) {
                let index = ((y * 520) + x) * 4
                if bytes[index] < 250 ||
                    bytes[index + 1] < 250 ||
                    bytes[index + 2] < 250 {
                    nonWhitePixelCount += 1
                }
            }
        }
        XCTAssertGreaterThan(
            nonWhitePixelCount,
            100,
            displayListTreeDescription(list)
        )
    }

    @MainActor
    func testSiblingGridReadersPreserveIndependentColdSectionEstimate() throws {
        // ASSERTIONS: lazySiblingGridSectionPlacementLifecycleObserved
        let probe = LayoutSchedulingSiblingGridReaderProbe()
        let controller = WindowController(
            content: LayoutSchedulingSiblingGridReaderRoot(probe: probe),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(LayoutSchedulingSiblingGridReaderRoot.self)
            )
        )
        let withGC: WindowContext.WithGraphicsContext = { _, _ in
            XCTFail("Sibling grid reader test should not request graphics resources.")
        }
        var redraw = false
        controller.updateView(
            tick: 0,
            delta: 0,
            date: controller.date,
            contentSize: CGSize(width: 140, height: 260),
            redraw: &redraw,
            withGC
        )

        let root = try XCTUnwrap(
            controller.responderNode
                as? MultiViewResponder
        )
        let responders = allHostingScrollViewResponders(in: root)
        XCTAssertEqual(responders.count, 2)
        let hosts = try responders.map {
            try XCTUnwrap($0.hostContainer?.scrollView)
        }
        XCTAssertTrue(hosts.allSatisfy {
            $0.pendingContext?.contentOffset == .zero
        })

        try controller.viewGraph.data.withCurrent {
            try XCTUnwrap(probe.sectionProxy).scrollTo(
                LayoutSchedulingSectionGridTargetID(section: 7, row: 10),
                anchor: .top
            )
            try XCTUnwrap(probe.plainProxy).scrollTo(150, anchor: .top)
        }
        for tick in 1...2 {
            controller.updateView(
                tick: UInt64(tick),
                delta: 1.0 / 60.0,
                date: controller.date.addingTimeInterval(
                    Double(tick) / 60.0
                ),
                contentSize: CGSize(width: 140, height: 260),
                redraw: &redraw,
                withGC
            )
        }

        let offsets = try hosts.map {
            try XCTUnwrap($0.pendingContext).contentOffset.y
        }.sorted()
        XCTAssertEqual(offsets[0], 1_500, accuracy: 0.001)
        XCTAssertEqual(offsets[1], 1_529, accuracy: 0.001)
    }

    @MainActor
    func testSiblingGridReadersPreserveParameterizedSectionEstimates() async throws {
        // ASSERTIONS: lazyScrollViewReaderGridSectionParameterizedOffsetObserved
        // ASSERTIONS: lazyIndexPositionCachedVisibleStartObserved
        let cases: [(LayoutSchedulingSiblingGridReaderConfiguration, [CGFloat])] = [
            (
                LayoutSchedulingSiblingGridReaderConfiguration(
                    columnCount: 1,
                    viewportWidth: 60
                ),
                [2_919.5, 3_000]
            ),
            (
                LayoutSchedulingSiblingGridReaderConfiguration(
                    columnCount: 3,
                    viewportWidth: 140
                ),
                [1_000, 1_105.5]
            ),
            (
                LayoutSchedulingSiblingGridReaderConfiguration(
                    rowsPerSection: 21
                ),
                [1_500, 1_658]
            ),
            (
                LayoutSchedulingSiblingGridReaderConfiguration(
                    rowHeight: 30,
                    headerHeight: 15
                ),
                [1_500, 2_193.5]
            ),
        ]

        for (configuration, expected) in cases {
            let offsets = try await siblingGridReaderOffsets(configuration: configuration)
            XCTAssertEqual(offsets.count, expected.count)
            for (actual, expected) in zip(offsets, expected) {
                XCTAssertEqual(actual, expected, accuracy: 0.001)
            }
        }
    }

    @MainActor
    private func siblingGridReaderOffsets(
        configuration: LayoutSchedulingSiblingGridReaderConfiguration
    ) async throws -> [CGFloat] {
        let probe = LayoutSchedulingSiblingGridReaderProbe()
        let controller = WindowController(
            content: LayoutSchedulingSiblingGridReaderRoot(
                probe: probe,
                configuration: configuration
            ),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(LayoutSchedulingSiblingGridReaderRoot.self)
            )
        )
        controller.contentScaleFactorOverride = 2
        let withGC: WindowContext.WithGraphicsContext = { _, _ in
            XCTFail("Sibling grid reader test should not request graphics resources.")
        }
        let contentSize = CGSize(
            width: configuration.viewportWidth + 40,
            height: configuration.viewportHeight * 2 + 60
        )
        var redraw = false
        Update.ensure {
            controller.updateView(
                tick: 0,
                delta: 0,
                date: controller.date,
                contentSize: contentSize,
                redraw: &redraw,
                withGC
            )
        }

        Update.ensure {
            controller.updateView(
                tick: 1,
                delta: 1.0 / 60.0,
                date: controller.date.addingTimeInterval(1.0 / 60.0),
                contentSize: contentSize,
                redraw: &redraw,
                withGC
            )
        }

        let root = try XCTUnwrap(
            controller.responderNode
                as? MultiViewResponder
        )
        let responders = allHostingScrollViewResponders(in: root)
        XCTAssertEqual(responders.count, 2)
        let hosts = try responders.map {
            try XCTUnwrap($0.hostContainer?.scrollView)
        }
        XCTAssertTrue(hosts.allSatisfy {
            $0.pendingContext?.contentOffset == .zero
        })
        try controller.viewGraph.data.withCurrent {
            try XCTUnwrap(probe.sectionProxy).scrollTo(
                LayoutSchedulingSectionGridTargetID(section: 7, row: 10),
                anchor: .top
            )
            try XCTUnwrap(probe.plainProxy).scrollTo(150, anchor: .top)
        }
        for tick in 2...3 {
            Update.ensure {
                controller.updateView(
                    tick: UInt64(tick),
                    delta: 1.0 / 60.0,
                    date: controller.date.addingTimeInterval(Double(tick) / 60.0),
                    contentSize: contentSize,
                    redraw: &redraw,
                    withGC
                )
            }
        }
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }

        return try hosts.map {
            try XCTUnwrap($0.pendingContext).contentOffset.y
        }.sorted()
    }

    // ASSERTIONS systemScrollViewWheelOffsetSignObserved
    @MainActor
    func testScrollViewHostConsumesDiscreteWheelAtMountedResponderBoundary() throws {
        let controller = WindowController(
            content: LayoutSchedulingScrollViewAttachmentRoot(),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(LayoutSchedulingScrollViewAttachmentRoot.self)
            )
        )
        let withGC: WindowContext.WithGraphicsContext = { _, _ in
            XCTFail("Scroll-view input test should not request graphics resources.")
        }
        var redraw = false
        controller.updateView(
            tick: 0,
            delta: 0,
            date: controller.date,
            contentSize: CGSize(width: 220, height: 220),
            redraw: &redraw,
            withGC
        )

        let root = try XCTUnwrap(
            controller.responderNode
                as? MultiViewResponder
        )
        let responder = try XCTUnwrap(
            firstHostingScrollViewResponder(in: root)
        )
        let host = try XCTUnwrap(responder.hostContainer?.scrollView)
        XCTAssertTrue(responder.acceptsEventType(SystemWheelEvent.self))
        let responderHit = responder.containsGlobalPoints(
            [CGPoint(x: 110, y: 110)],
            cacheKey: nil,
            options: .platformDefault
        )
        XCTAssertTrue(responderHit.mask[0])
        let binding = try XCTUnwrap(controller.gestureEnvironment.eventBinding(
            at: CGPoint(x: 110, y: 110),
            accepting: SystemWheelEvent.self
        ))
        XCTAssertTrue(binding.responder === responder)

        XCTAssertTrue(controller.handleMouseWheel(
            at: CGPoint(x: 110, y: 110),
            delta: CGPoint(x: 0, y: -40)
        ))
        controller.updateView(
            tick: 1,
            delta: 1.0 / 60.0,
            date: controller.date,
            contentSize: CGSize(width: 220, height: 220),
            redraw: &redraw,
            withGC
        )

        XCTAssertEqual(
            try XCTUnwrap(host.pendingContext).contentOffset.y,
            40,
            accuracy: 0.001
        )
    }

    // ASSERTIONS scrollGeometryObserverPullPathObserved
    // ASSERTIONS scrollObserverStateCadenceObserved
    // ASSERTIONS scrollActionDispatcherTransactionalSchedulingObserved
    @MainActor
    func testLazyScrollPublishesEachDiscreteWheelOffset() throws {
        let probe = LayoutSchedulingLazyScrollObserverProbe()
        let controller = WindowController(
            content: LayoutSchedulingLazyScrollObserverRoot(probe: probe),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(LayoutSchedulingLazyScrollObserverRoot.self)
            )
        )
        let contentSize = CGSize(width: 820, height: 680)
        let withGC: WindowContext.WithGraphicsContext = { _, _ in }
        let startDate = controller.date

        func updateHost(tick: Int, delta: Double = 1.0 / 60.0) {
            controller.updateFrame(
                tick: UInt64(tick),
                delta: delta,
                date: startDate.addingTimeInterval(Double(tick) / 60.0),
                contentSize: contentSize,
                shouldDrawFrame: false,
                withGC
            )
        }

        for tick in 0...1 {
            updateHost(tick: tick, delta: tick == 0 ? 0 : 1.0 / 60.0)
        }

        let root = try XCTUnwrap(
            controller.responderNode
                as? MultiViewResponder
        )
        let responder = try XCTUnwrap(firstHostingScrollViewResponder(in: root))
        let host = try XCTUnwrap(responder.hostContainer?.scrollView)
        XCTAssertEqual(try XCTUnwrap(host.pendingContext).containingSize.height, 360)

        let wheelPoint = CGPoint(x: contentSize.width / 2, y: contentSize.height / 2)
        var publishedOffsets: [CGPoint] = []
        var observedOffsets: [CGPoint] = []
        for sample in 0..<6 {
            controller.enqueueInputAction { [weak controller] in
                _ = controller?.handleMouseWheel(
                    at: wheelPoint,
                    delta: CGPoint(x: 0, y: -688)
                )
            }
            let tick = sample + 2
            updateHost(tick: tick)
            publishedOffsets.append(try XCTUnwrap(host.pendingContext).contentOffset)
            observedOffsets.append(try XCTUnwrap(probe.geometryActions.last).contentOffset)
            let currentRoot = try XCTUnwrap(
                controller.responderNode
                    as? MultiViewResponder
            )
            let currentResponder = try XCTUnwrap(
                firstHostingScrollViewResponder(in: currentRoot)
            )
            let currentHost = try XCTUnwrap(currentResponder.hostContainer?.scrollView)
            XCTAssertTrue(currentHost === host, "sample \(sample)")
        }

        for (sample, pair) in zip(publishedOffsets, observedOffsets).enumerated() {
            XCTAssertEqual(pair.0.y, CGFloat(sample + 1) * 688, accuracy: 0.001)
            XCTAssertEqual(pair.1.y, pair.0.y, accuracy: 0.001, "sample \(sample)")
        }
    }

    // ASSERTIONS lazyChildInputCacheOwnershipObserved
    @MainActor
    func testLazyScrollTerminalSettleKeepsRetainedInputsValid() throws {
        let environment = ProcessInfo.processInfo.environment
        let itemCount = Int(
            environment["VUI_LAZY_LIFETIME_ITEM_COUNT"] ?? "32"
        ) ?? 32
        let wheelSampleCount = Int(
            environment["VUI_LAZY_LIFETIME_WHEEL_SAMPLES"] ?? "8"
        ) ?? 8
        let settleSampleCount = Int(
            environment["VUI_LAZY_LIFETIME_SETTLE_SAMPLES"] ?? "40"
        ) ?? 40
        let probe = LayoutSchedulingLazyScrollObserverProbe()
        let controller = WindowController(
            content: LayoutSchedulingLazyScrollObserverRoot(
                probe: probe,
                itemCount: itemCount
            ),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(LayoutSchedulingLazyScrollObserverRoot.self)
            )
        )
        let contentSize = CGSize(width: 820, height: 680)
        let withGC: WindowContext.WithGraphicsContext = { _, _ in }
        let startDate = controller.date

        func updateHost(tick: Int, delta: Double = 1.0 / 60.0) {
            controller.updateFrame(
                tick: UInt64(tick),
                delta: delta,
                date: startDate.addingTimeInterval(Double(tick) / 60.0),
                contentSize: contentSize,
                shouldDrawFrame: false,
                withGC
            )
        }

        for tick in 0...1 {
            updateHost(tick: tick, delta: tick == 0 ? 0 : 1.0 / 60.0)
        }

        let root = try XCTUnwrap(
            controller.responderNode
                as? MultiViewResponder
        )
        let responder = try XCTUnwrap(firstHostingScrollViewResponder(in: root))
        let host = try XCTUnwrap(responder.hostContainer?.scrollView)
        let wheelPoint = CGPoint(x: contentSize.width / 2, y: contentSize.height / 2)

        for sample in 0..<wheelSampleCount {
            controller.enqueueInputAction { [weak controller] in
                _ = controller?.handleMouseWheel(
                    at: wheelPoint,
                    delta: CGPoint(x: 0, y: -688)
                )
            }
            updateHost(tick: sample + 2)
        }

        let settleStartTick = wheelSampleCount + 2
        for sample in 0..<settleSampleCount {
            updateHost(tick: settleStartTick + sample)
        }

        let currentRoot = try XCTUnwrap(
            controller.responderNode
                as? MultiViewResponder
        )
        let currentResponder = try XCTUnwrap(firstHostingScrollViewResponder(in: currentRoot))
        let currentHost = try XCTUnwrap(currentResponder.hostContainer?.scrollView)
        XCTAssertTrue(currentHost === host)
        XCTAssertEqual(
            try XCTUnwrap(probe.geometryActions.last).contentOffset.y,
            try XCTUnwrap(host.pendingContext).contentOffset.y,
            accuracy: 0.001
        )
    }

    // ASSERTIONS systemScrollViewWheelOffsetSignObserved
    @MainActor
    func testScrollViewHostConsumesPhasedWheelWithoutPanThreshold() throws {
        let phaseProbe = LayoutSchedulingScrollPhaseProbe()
        let controller = WindowController(
            content: LayoutSchedulingPhasedWheelRoot(probe: phaseProbe),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(LayoutSchedulingPhasedWheelRoot.self)
            )
        )
        let withGC: WindowContext.WithGraphicsContext = { _, _ in
            XCTFail("Scroll-view input test should not request graphics resources.")
        }
        var redraw = false
        controller.updateView(
            tick: 0,
            delta: 0,
            date: controller.date,
            contentSize: CGSize(width: 220, height: 220),
            redraw: &redraw,
            withGC
        )

        let root = try XCTUnwrap(
            controller.responderNode
                as? MultiViewResponder
        )
        let responder = try XCTUnwrap(firstHostingScrollViewResponder(in: root))
        let host = try XCTUnwrap(responder.hostContainer?.scrollView)
        let location = CGPoint(x: 110, y: 110)

        controller.onMouseEvent(
            event: MouseEvent(
                type: .wheel,
                device: .genericMouse,
                deviceID: 0,
                buttonID: 0,
                location: location,
                delta: .zero,
                timestamp: 0,
                scrollData: ScrollEventData(
                    phase: .began,
                    source: .continuous,
                    isPrecise: true
                )
            ),
            at: Time(seconds: 0)
        )
        controller.updateView(
            tick: 1,
            delta: 0,
            date: controller.date,
            contentSize: CGSize(width: 220, height: 220),
            redraw: &redraw,
            withGC
        )
        XCTAssertEqual(phaseProbe.changes.map(\.new), [.interacting])

        controller.onMouseEvent(
            event: MouseEvent(
                type: .wheel,
                device: .genericMouse,
                deviceID: 0,
                buttonID: 0,
                location: location,
                delta: CGPoint(x: 0, y: -4),
                timestamp: 0.1,
                scrollData: ScrollEventData(
                    phase: .changed,
                    source: .continuous,
                    isPrecise: true
                )
            ),
            at: Time(seconds: 0.1)
        )
        controller.updateView(
            tick: 2,
            delta: 0.1,
            date: controller.date,
            contentSize: CGSize(width: 220, height: 220),
            redraw: &redraw,
            withGC
        )
        XCTAssertEqual(
            try XCTUnwrap(host.pendingContext).contentOffset.y,
            4,
            accuracy: 0.001
        )
        XCTAssertEqual(
            phaseProbe.changes.map(\.new),
            [.interacting],
            "Changed samples in one direct-scroll phase must not republish phase velocity."
        )

        controller.onMouseEvent(
            event: MouseEvent(
                type: .wheel,
                device: .genericMouse,
                deviceID: 0,
                buttonID: 0,
                location: location,
                delta: CGPoint(x: 0, y: -20),
                timestamp: 0.2,
                scrollData: ScrollEventData(
                    phase: .ended,
                    nativeMomentumPhase: .began,
                    source: .continuous,
                    isPrecise: true
                )
            ),
            at: Time(seconds: 0.2)
        )

        XCTAssertTrue(host.isDecelerating)
        XCTAssertEqual(
            host.currentMotionVelocity.valuePerSecond.height,
            40,
            accuracy: 0.001
        )

        let offsetBeforeMotion = try XCTUnwrap(host.pendingContext).contentOffset.y
        XCTAssertTrue(controller.viewGraph.hasScheduledViewUpdate)

        redraw = false
        Update.ensure {
            controller.updateView(
                tick: 3,
                delta: 1.0 / 60.0,
                date: controller.date.addingTimeInterval(1.0 / 60.0),
                contentSize: CGSize(width: 220, height: 220),
                redraw: &redraw,
                withGC
            )
        }
        let firstMotionOffset = try XCTUnwrap(host.pendingContext).contentOffset.y
        XCTAssertNotEqual(firstMotionOffset, offsetBeforeMotion, accuracy: 0.001)
        XCTAssertTrue(controller.viewGraph.hasScheduledViewUpdate)
        XCTAssertEqual(phaseProbe.changes.map(\.new), [.interacting, .decelerating])
        XCTAssertEqual(phaseProbe.changes.last?.velocity, CGVector(dx: 0, dy: 40))

        redraw = false
        Update.ensure {
            controller.updateView(
                tick: 4,
                delta: 1.0 / 60.0,
                date: controller.date.addingTimeInterval(2.0 / 60.0),
                contentSize: CGSize(width: 220, height: 220),
                redraw: &redraw,
                withGC
            )
        }
        XCTAssertNotEqual(
            try XCTUnwrap(host.pendingContext).contentOffset.y,
            firstMotionOffset,
            accuracy: 0.001
        )
        XCTAssertEqual(
            phaseProbe.changes.map(\.new),
            [.interacting, .decelerating],
            "Motion samples in one deceleration phase must not republish phase velocity."
        )

        redraw = false
        Update.ensure {
            controller.updateView(
                tick: 5,
                delta: 3,
                date: controller.date.addingTimeInterval(3),
                contentSize: CGSize(width: 220, height: 220),
                redraw: &redraw,
                withGC
            )
        }
        XCTAssertFalse(host.isDecelerating)
        XCTAssertEqual(host.currentPhaseState.phase, .idle)

        redraw = false
        Update.ensure {
            controller.updateView(
                tick: 6,
                delta: 1.0 / 60.0,
                date: controller.date.addingTimeInterval(3 + 1.0 / 60.0),
                contentSize: CGSize(width: 220, height: 220),
                redraw: &redraw,
                withGC
            )
        }
        XCTAssertEqual(
            phaseProbe.changes.map(\.new),
            [.interacting, .decelerating, .idle]
        )
    }

    @MainActor
    func testScrollViewHostCapturesPointerPanAfterAxisThreshold() throws {
        let controller = WindowController(
            content: LayoutSchedulingScrollViewAttachmentRoot(),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(LayoutSchedulingScrollViewAttachmentRoot.self)
            )
        )
        let withGC: WindowContext.WithGraphicsContext = { _, _ in
            XCTFail("Scroll-view input test should not request graphics resources.")
        }
        var redraw = false
        controller.updateView(
            tick: 0,
            delta: 0,
            date: controller.date,
            contentSize: CGSize(width: 220, height: 220),
            redraw: &redraw,
            withGC
        )

        let root = try XCTUnwrap(
            controller.responderNode
                as? MultiViewResponder
        )
        let responder = try XCTUnwrap(firstHostingScrollViewResponder(in: root))
        let host = try XCTUnwrap(responder.hostContainer?.scrollView)
        let binding = try XCTUnwrap(controller.gestureEnvironment.eventBinding(
            at: CGPoint(x: 110, y: 110),
            accepting: ScrollEvent.self
        ))
        XCTAssertTrue(binding.responder === responder)

        XCTAssertFalse(controller.handleMouseEvent(
            event: MouseEvent(
                type: .buttonDown,
                device: .genericMouse,
                deviceID: 0,
                buttonID: 0,
                location: CGPoint(x: 110, y: 110),
                timestamp: 0
            ),
            at: Time(seconds: 0)
        ))
        XCTAssertFalse(controller.handleMouseEvent(
            event: MouseEvent(
                type: .move,
                device: .genericMouse,
                deviceID: 0,
                buttonID: 0,
                location: CGPoint(x: 110, y: 104),
                timestamp: 0.01
            ),
            at: Time(seconds: 0.01)
        ))
        controller.updateView(
            tick: 1,
            delta: 0.01,
            date: controller.date,
            contentSize: CGSize(width: 220, height: 220),
            redraw: &redraw,
            withGC
        )
        XCTAssertEqual(
            try XCTUnwrap(host.pendingContext).contentOffset.y,
            0,
            accuracy: 0.001
        )

        XCTAssertTrue(controller.handleMouseEvent(
            event: MouseEvent(
                type: .move,
                device: .genericMouse,
                deviceID: 0,
                buttonID: 0,
                location: CGPoint(x: 110, y: 94),
                timestamp: 0.02
            ),
            at: Time(seconds: 0.02)
        ))
        controller.updateView(
            tick: 2,
            delta: 0.01,
            date: controller.date,
            contentSize: CGSize(width: 220, height: 220),
            redraw: &redraw,
            withGC
        )
        XCTAssertEqual(
            try XCTUnwrap(host.pendingContext).contentOffset.y,
            16,
            accuracy: 0.001
        )

        XCTAssertTrue(controller.handleMouseEvent(
            event: MouseEvent(
                type: .buttonUp,
                device: .genericMouse,
                deviceID: 0,
                buttonID: 0,
                location: CGPoint(x: 110, y: 94),
                timestamp: 0.03
            ),
            at: Time(seconds: 0.03)
        ))
        XCTAssertFalse(
            controller.eventBindingManager.eventBindings.values
                .contains { $0.responder === responder }
        )
        XCTAssertTrue(host.isDecelerating)
        let offsetBeforeMotion = try XCTUnwrap(host.pendingContext).contentOffset.y
        XCTAssertTrue(controller.viewGraph.hasScheduledViewUpdate)

        redraw = false
        Update.ensure {
            controller.updateView(
                tick: 3,
                delta: 1.0 / 60.0,
                date: controller.date.addingTimeInterval(1.0 / 60.0),
                contentSize: CGSize(width: 220, height: 220),
                redraw: &redraw,
                withGC
            )
        }
        let firstMotionOffset = try XCTUnwrap(host.pendingContext).contentOffset.y
        XCTAssertNotEqual(firstMotionOffset, offsetBeforeMotion, accuracy: 0.001)
        XCTAssertTrue(controller.viewGraph.hasScheduledViewUpdate)

        redraw = false
        Update.ensure {
            controller.updateView(
                tick: 4,
                delta: 1.0 / 60.0,
                date: controller.date.addingTimeInterval(2.0 / 60.0),
                contentSize: CGSize(width: 220, height: 220),
                redraw: &redraw,
                withGC
            )
        }
        XCTAssertNotEqual(
            try XCTUnwrap(host.pendingContext).contentOffset.y,
            firstMotionOffset,
            accuracy: 0.001
        )
    }

    @MainActor
    func testScrollPanCancelsActiveDescendantButtonWithoutTriggeringAction() throws {
        let probe = LayoutSchedulingScrollGestureArbitrationProbe()
        let controller = WindowController(
            content: LayoutSchedulingScrollButtonArbitrationRoot(probe: probe),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(LayoutSchedulingScrollButtonArbitrationRoot.self)
            )
        )
        let withGC: WindowContext.WithGraphicsContext = { _, _ in
            XCTFail("Scroll-view arbitration test should not request graphics resources.")
        }
        var redraw = false
        controller.updateView(
            tick: 0,
            delta: 0,
            date: controller.date,
            contentSize: CGSize(width: 220, height: 220),
            redraw: &redraw,
            withGC
        )
        let root = try XCTUnwrap(
            controller.responderNode
                as? MultiViewResponder
        )
        let responder = try XCTUnwrap(firstHostingScrollViewResponder(in: root))
        let host = try XCTUnwrap(responder.hostContainer?.scrollView)
        let movement = CGSize(width: 0, height: -20)
        let start = try XCTUnwrap(firstGesturePanStart(
            in: root,
            descendantOf: responder,
            movement: movement,
            size: CGSize(width: 220, height: 220)
        ))
        let moved = CGPoint(
            x: start.x + movement.width,
            y: start.y + movement.height
        )

        XCTAssertTrue(controller.handleMouseEvent(
            event: MouseEvent(
                type: .buttonDown,
                device: .genericMouse,
                deviceID: 0,
                buttonID: 0,
                location: start,
                timestamp: 0
            ),
            at: Time(seconds: 0)
        ))
        XCTAssertEqual(probe.pressing, [true])

        XCTAssertTrue(controller.handleMouseEvent(
            event: MouseEvent(
                type: .move,
                device: .genericMouse,
                deviceID: 0,
                buttonID: 0,
                location: moved,
                timestamp: 0.02
            ),
            at: Time(seconds: 0.02)
        ))
        XCTAssertEqual(probe.pressing, [true, false])
        XCTAssertEqual(probe.actions, 0)

        controller.updateView(
            tick: 1,
            delta: 0.02,
            date: controller.date,
            contentSize: CGSize(width: 220, height: 220),
            redraw: &redraw,
            withGC
        )
        XCTAssertGreaterThan(
            try XCTUnwrap(host.pendingContext).contentOffset.y,
            0
        )

        XCTAssertTrue(controller.handleMouseEvent(
            event: MouseEvent(
                type: .buttonUp,
                device: .genericMouse,
                deviceID: 0,
                buttonID: 0,
                location: moved,
                timestamp: 0.03
            ),
            at: Time(seconds: 0.03)
        ))
        XCTAssertEqual(probe.pressing, [true, false])
        XCTAssertEqual(probe.actions, 0)
    }

    @MainActor
    func testActiveDescendantDragPreventsScrollPan() throws {
        let probe = LayoutSchedulingScrollGestureArbitrationProbe()
        let controller = WindowController(
            content: LayoutSchedulingScrollDragArbitrationRoot(probe: probe),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(LayoutSchedulingScrollDragArbitrationRoot.self)
            )
        )
        let withGC: WindowContext.WithGraphicsContext = { _, _ in
            XCTFail("Scroll-view arbitration test should not request graphics resources.")
        }
        var redraw = false
        controller.updateView(
            tick: 0,
            delta: 0,
            date: controller.date,
            contentSize: CGSize(width: 220, height: 220),
            redraw: &redraw,
            withGC
        )
        let root = try XCTUnwrap(
            controller.responderNode
                as? MultiViewResponder
        )
        let responder = try XCTUnwrap(firstHostingScrollViewResponder(in: root))
        let host = try XCTUnwrap(responder.hostContainer?.scrollView)
        let movement = CGSize(width: 0, height: -24)
        let start = try XCTUnwrap(firstGesturePanStart(
            in: root,
            descendantOf: responder,
            movement: movement,
            size: CGSize(width: 220, height: 220)
        ))
        let moved = CGPoint(
            x: start.x + movement.width,
            y: start.y + movement.height
        )

        XCTAssertTrue(controller.handleMouseEvent(
            event: MouseEvent(
                type: .buttonDown,
                device: .genericMouse,
                deviceID: 0,
                buttonID: 0,
                location: start,
                timestamp: 0
            ),
            at: Time(seconds: 0)
        ))
        XCTAssertTrue(controller.handleMouseEvent(
            event: MouseEvent(
                type: .move,
                device: .genericMouse,
                deviceID: 0,
                buttonID: 0,
                location: moved,
                timestamp: 0.02
            ),
            at: Time(seconds: 0.02)
        ))
        controller.updateView(
            tick: 1,
            delta: 0.02,
            date: controller.date,
            contentSize: CGSize(width: 220, height: 220),
            redraw: &redraw,
            withGC
        )

        XCTAssertGreaterThan(probe.dragChanges, 0)
        XCTAssertEqual(
            try XCTUnwrap(host.pendingContext).contentOffset.y,
            0,
            accuracy: 0.001
        )
        XCTAssertTrue(controller.handleMouseEvent(
            event: MouseEvent(
                type: .buttonUp,
                device: .genericMouse,
                deviceID: 0,
                buttonID: 0,
                location: moved,
                timestamp: 0.03
            ),
            at: Time(seconds: 0.03)
        ))
    }

    @MainActor
    func testActiveSimultaneousDescendantDragStillPreventsScrollPan() throws {
        let probe = LayoutSchedulingScrollGestureArbitrationProbe()
        let controller = WindowController(
            content: LayoutSchedulingScrollSimultaneousDragArbitrationRoot(
                probe: probe
            ),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(
                    LayoutSchedulingScrollSimultaneousDragArbitrationRoot.self
                )
            )
        )
        let withGC: WindowContext.WithGraphicsContext = { _, _ in
            XCTFail("Scroll-view arbitration test should not request graphics resources.")
        }
        var redraw = false
        controller.updateView(
            tick: 0,
            delta: 0,
            date: controller.date,
            contentSize: CGSize(width: 220, height: 220),
            redraw: &redraw,
            withGC
        )
        let root = try XCTUnwrap(
            controller.responderNode
                as? MultiViewResponder
        )
        let responder = try XCTUnwrap(firstHostingScrollViewResponder(in: root))
        let host = try XCTUnwrap(responder.hostContainer?.scrollView)
        let movement = CGSize(width: 0, height: -24)
        let start = try XCTUnwrap(firstGesturePanStart(
            in: root,
            descendantOf: responder,
            movement: movement,
            size: CGSize(width: 220, height: 220)
        ))
        let moved = CGPoint(
            x: start.x + movement.width,
            y: start.y + movement.height
        )

        XCTAssertTrue(controller.handleMouseEvent(
            event: MouseEvent(
                type: .buttonDown,
                device: .genericMouse,
                deviceID: 0,
                buttonID: 0,
                location: start,
                timestamp: 0
            ),
            at: Time(seconds: 0)
        ))
        XCTAssertTrue(controller.handleMouseEvent(
            event: MouseEvent(
                type: .move,
                device: .genericMouse,
                deviceID: 0,
                buttonID: 0,
                location: moved,
                timestamp: 0.02
            ),
            at: Time(seconds: 0.02)
        ))
        controller.updateView(
            tick: 1,
            delta: 0.02,
            date: controller.date,
            contentSize: CGSize(width: 220, height: 220),
            redraw: &redraw,
            withGC
        )

        XCTAssertGreaterThan(probe.dragChanges, 0)
        XCTAssertEqual(
            try XCTUnwrap(host.pendingContext).contentOffset.y,
            0,
            accuracy: 0.001
        )
        XCTAssertTrue(controller.handleMouseEvent(
            event: MouseEvent(
                type: .buttonUp,
                device: .genericMouse,
                deviceID: 0,
                buttonID: 0,
                location: moved,
                timestamp: 0.03
            ),
            at: Time(seconds: 0.03)
        ))
    }

    @MainActor
    func testTransformedScrollViewHostInverseMapsWheelHitTesting() throws {
        let baselineController = WindowController(
            content: LayoutSchedulingScrollViewAttachmentRoot(),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(LayoutSchedulingScrollViewAttachmentRoot.self)
            )
        )
        let controller = WindowController(
            content: LayoutSchedulingTransformedScrollViewAttachmentRoot(),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(LayoutSchedulingTransformedScrollViewAttachmentRoot.self)
            )
        )
        let withGC: WindowContext.WithGraphicsContext = { _, _ in
            XCTFail("Scroll-view input test should not request graphics resources.")
        }
        var redraw = false
        baselineController.updateView(
            tick: 0,
            delta: 0,
            date: baselineController.date,
            contentSize: CGSize(width: 220, height: 220),
            redraw: &redraw,
            withGC
        )
        controller.updateView(
            tick: 0,
            delta: 0,
            date: controller.date,
            contentSize: CGSize(width: 220, height: 220),
            redraw: &redraw,
            withGC
        )

        let baselineRoot = try XCTUnwrap(
            baselineController.responderNode
                as? MultiViewResponder
        )
        let baselineResponder = try XCTUnwrap(
            firstHostingScrollViewResponder(in: baselineRoot)
        )
        let baselineBounds = try XCTUnwrap(sampledHitBounds(
            of: baselineResponder,
            in: CGSize(width: 220, height: 220)
        ))
        let root = try XCTUnwrap(
            controller.responderNode
                as? MultiViewResponder
        )
        let responder = try XCTUnwrap(firstHostingScrollViewResponder(in: root))
        let bounds = try XCTUnwrap(sampledHitBounds(
            of: responder,
            in: CGSize(width: 220, height: 220)
        ))
        XCTAssertEqual(bounds.width, baselineBounds.width * 1.5, accuracy: 3)
        XCTAssertEqual(bounds.height, baselineBounds.height * 1.5, accuracy: 3)

        let location = try XCTUnwrap(firstExclusiveHitPoint(
            in: responder,
            excluding: baselineResponder,
            size: CGSize(width: 220, height: 220)
        ))
        let binding = try XCTUnwrap(controller.gestureEnvironment.eventBinding(
            at: location,
            accepting: SystemWheelEvent.self
        ))
        XCTAssertTrue(binding.responder === responder)
    }

    @MainActor
    func testNestedScrollViewWheelSelectsInnermostMountedHost() throws {
        let controller = WindowController(
            content: LayoutSchedulingNestedScrollViewAttachmentRoot(),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(LayoutSchedulingNestedScrollViewAttachmentRoot.self)
            )
        )
        let withGC: WindowContext.WithGraphicsContext = { _, _ in
            XCTFail("Scroll-view input test should not request graphics resources.")
        }
        var redraw = false
        controller.updateView(
            tick: 0,
            delta: 0,
            date: controller.date,
            contentSize: CGSize(width: 260, height: 260),
            redraw: &redraw,
            withGC
        )

        let root = try XCTUnwrap(
            controller.responderNode
                as? MultiViewResponder
        )
        let responders = allHostingScrollViewResponders(in: root)
        XCTAssertEqual(responders.count, 2)
        let inner = try XCTUnwrap(responders.first { candidate in
            responders.contains { ancestor in
                ancestor !== candidate && candidate.isDescendant(of: ancestor)
            }
        })
        let outer = try XCTUnwrap(responders.first { candidate in
            candidate !== inner && inner.isDescendant(of: candidate)
        })
        let innerHost = try XCTUnwrap(inner.hostContainer?.scrollView)
        let outerHost = try XCTUnwrap(outer.hostContainer?.scrollView)
        XCTAssertEqual(innerHost.ancestorScrollableAxes, .vertical)
        XCTAssertEqual(innerHost.descendantScrollableAxes, Axis.Set())
        XCTAssertEqual(outerHost.ancestorScrollableAxes, Axis.Set())
        XCTAssertEqual(outerHost.descendantScrollableAxes, .vertical)
        let location = try XCTUnwrap(firstCommonHitPoint(
            for: [outer, inner],
            in: CGSize(width: 260, height: 260)
        ))
        let binding = try XCTUnwrap(controller.gestureEnvironment.eventBinding(
            at: location,
            accepting: SystemWheelEvent.self
        ))
        XCTAssertTrue(binding.responder === inner)

        XCTAssertTrue(controller.handleMouseWheel(
            at: location,
            delta: CGPoint(x: 0, y: -40)
        ))
        controller.updateView(
            tick: 1,
            delta: 1.0 / 60.0,
            date: controller.date,
            contentSize: CGSize(width: 260, height: 260),
            redraw: &redraw,
            withGC
        )
        XCTAssertEqual(
            try XCTUnwrap(inner.hostContainer?.scrollView.pendingContext)
                .contentOffset.y,
            40,
            accuracy: 0.001
        )
        XCTAssertEqual(
            try XCTUnwrap(outer.hostContainer?.scrollView.pendingContext)
                .contentOffset.y,
            0,
            accuracy: 0.001
        )
    }

    // ASSERTIONS platformViewResponderFeatureHitTestPruningObserved
    func testPlatformEventConsumerHitTestSkipsBranchesWithoutPlatformViews() throws {
        let ignored = LayoutSchedulingNonPlatformHitTestProbe()
        let consumer = LayoutSchedulingPlatformEventConsumerProbe()
        consumer.children = [ignored]
        let root = MultiViewResponder()
        root.children = [consumer]
        let manager = EventBindingManager()
        let environment = WindowGestureEnvironment(
            rootResponder: root,
            eventBindingManager: manager
        )

        let binding = try XCTUnwrap(environment.eventBinding(
            at: CGPoint(x: 10, y: 10),
            accepting: SystemWheelEvent.self
        ))

        XCTAssertTrue(binding.responder === consumer)
        XCTAssertEqual(consumer.containsCallCount, 1)
        XCTAssertEqual(ignored.containsCallCount, 0)
    }

    // ASSERTIONS menuPlatformControlLifecycleObserved
    func testExclusivePlatformControlOwnsEntirePointerSerial() {
        let control = LayoutSchedulingExclusiveEventConsumerProbe()
        let scroll = LayoutSchedulingScrollEventConsumerProbe()
        scroll.children = [control]
        let root = MultiViewResponder()
        root.children = [scroll]
        let manager = EventBindingManager()
        let environment = WindowGestureEnvironment(
            rootResponder: root,
            eventBindingManager: manager
        )
        let mouseID = EventID(type: VUI.MouseEvent.self, serial: 61)
        let scrollID = EventID(type: ScrollEvent.self, serial: 61)

        let result = environment.send(
            [
                mouseID: VUI.MouseEvent(
                    timestamp: .zero,
                    binding: nil,
                    button: .primary,
                    phase: .began,
                    location: CGPoint(x: 10, y: 10),
                    globalLocation: CGPoint(x: 10, y: 10),
                    modifiers: []
                ),
                scrollID: ScrollEvent(
                    timestamp: .zero,
                    phase: .began,
                    binding: nil,
                    translation: .zero,
                    modifiers: [],
                    hitTestLocation: CGPoint(x: 10, y: 10)
                ),
            ],
            at: .zero
        )

        XCTAssertTrue(result.phase.isActive)
        XCTAssertEqual(control.receivedEventIDs, [mouseID])
        XCTAssertEqual(scroll.consumeCallCount, 0)
        XCTAssertTrue(manager.eventBindings[mouseID]?.responder === control)
        XCTAssertNil(manager.eventBindings[scrollID])
    }

    @MainActor
    func testOrthogonalNestedScrollViewRoutesPhasedWheelAfterSignedThreshold() throws {
        let controller = WindowController(
            content: LayoutSchedulingOrthogonalNestedScrollViewAttachmentRoot(),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(
                    LayoutSchedulingOrthogonalNestedScrollViewAttachmentRoot.self
                )
            )
        )
        let withGC: WindowContext.WithGraphicsContext = { _, _ in
            XCTFail("Scroll-view input test should not request graphics resources.")
        }
        var redraw = false
        var tick: UInt64 = 0
        func update() {
            tick += 1
            controller.updateView(
                tick: tick,
                delta: 0,
                date: controller.date,
                contentSize: CGSize(width: 260, height: 260),
                redraw: &redraw,
                withGC
            )
        }
        update()

        let root = try XCTUnwrap(
            controller.responderNode
                as? MultiViewResponder
        )
        let responders = allHostingScrollViewResponders(in: root)
        XCTAssertEqual(responders.count, 2)
        let inner = try XCTUnwrap(responders.first { candidate in
            responders.contains { ancestor in
                ancestor !== candidate && candidate.isDescendant(of: ancestor)
            }
        })
        let outer = try XCTUnwrap(responders.first { candidate in
            candidate !== inner && inner.isDescendant(of: candidate)
        })
        let innerHost = try XCTUnwrap(inner.hostContainer?.scrollView)
        let outerHost = try XCTUnwrap(outer.hostContainer?.scrollView)
        XCTAssertEqual(innerHost.configuration.axes, .horizontal)
        XCTAssertEqual(innerHost.ancestorScrollableAxes, .vertical)
        XCTAssertEqual(innerHost.descendantScrollableAxes, Axis.Set())
        XCTAssertEqual(outerHost.configuration.axes, .vertical)
        XCTAssertEqual(outerHost.ancestorScrollableAxes, Axis.Set())
        XCTAssertEqual(outerHost.descendantScrollableAxes, .horizontal)
        XCTAssertTrue(innerHost.wantsForwardedScrollEvents(for: .horizontal))
        XCTAssertTrue(innerHost.wantsForwardedScrollEvents(for: .vertical))
        XCTAssertFalse(outerHost.wantsForwardedScrollEvents(for: .horizontal))
        XCTAssertFalse(outerHost.wantsForwardedScrollEvents(for: .vertical))

        innerHost.publishSystemContentOffset(CGPoint(x: 100, y: 0))
        outerHost.publishSystemContentOffset(CGPoint(x: 0, y: 20))
        update()
        XCTAssertEqual(
            try XCTUnwrap(innerHost.pendingContext).contentOffset.x,
            100,
            accuracy: 0.001
        )
        XCTAssertEqual(
            try XCTUnwrap(outerHost.pendingContext).contentOffset.y,
            20,
            accuracy: 0.001
        )

        let location = try XCTUnwrap(firstCommonHitPoint(
            for: [outer, inner],
            in: CGSize(width: 260, height: 260)
        ))
        func send(
            _ phase: ScrollEventPhase,
            delta: CGPoint,
            timestamp: Double
        ) {
            controller.onMouseEvent(
                event: MouseEvent(
                    type: .wheel,
                    device: .genericMouse,
                    deviceID: 0,
                    buttonID: 0,
                    location: location,
                    delta: delta,
                    timestamp: timestamp,
                    scrollData: ScrollEventData(
                        phase: phase,
                        source: .continuous,
                        isPrecise: true
                    )
                ),
                at: Time(seconds: timestamp)
            )
            update()
        }

        send(.began, delta: CGPoint(x: 20, y: 0), timestamp: 0)
        send(.changed, delta: CGPoint(x: 8, y: 0), timestamp: 0.1)
        send(.changed, delta: CGPoint(x: 0, y: 6), timestamp: 0.2)
        XCTAssertEqual(
            try XCTUnwrap(outerHost.pendingContext).contentOffset.y,
            20,
            accuracy: 0.001
        )

        send(.changed, delta: CGPoint(x: 0, y: 6), timestamp: 0.3)
        XCTAssertEqual(
            try XCTUnwrap(innerHost.pendingContext).contentOffset.x,
            72,
            accuracy: 0.001
        )
        XCTAssertEqual(
            try XCTUnwrap(outerHost.pendingContext).contentOffset.y,
            14,
            accuracy: 0.001
        )

        func routingEvent(
            _ phase: EventPhase,
            delta: CGSize,
            kind: SystemWheelEvent.Kind = .continuous
        ) -> SystemWheelEvent {
            SystemWheelEvent(
                timestamp: .zero,
                phase: phase,
                binding: nil,
                scrollingDelta: delta,
                kind: kind
            )
        }
        func assertRouting(
            _ event: SystemWheelEvent,
            self expectedSelf: Bool,
            next expectedNext: Bool,
            file: StaticString = #filePath,
            line: UInt = #line
        ) {
            let routing = innerHost.scrollWheelRouting(for: event)
            XCTAssertEqual(
                routing.sendToSelf,
                expectedSelf,
                file: file,
                line: line
            )
            XCTAssertEqual(
                routing.sendToNextResponder,
                expectedNext,
                file: file,
                line: line
            )
        }
        _ = innerHost.scrollWheelRouting(for: routingEvent(.ended, delta: .zero))
        assertRouting(
            routingEvent(
                .began,
                delta: CGSize(width: 20, height: 0)
            ),
            self: true,
            next: true
        )
        assertRouting(
            routingEvent(
                .active,
                delta: CGSize(width: 0, height: -6)
            ),
            self: true,
            next: false
        )
        assertRouting(
            routingEvent(
                .active,
                delta: CGSize(width: 0, height: -6)
            ),
            self: true,
            next: false
        )
        assertRouting(
            routingEvent(
                .ended,
                delta: .zero
            ),
            self: true,
            next: true
        )
        assertRouting(
            routingEvent(
                .began,
                delta: CGSize(width: 8, height: 9),
                kind: .discrete
            ),
            self: true,
            next: true
        )
    }

    @MainActor
    func testScrollViewRootDisplayListMountsInitiallyPlacedLazyContent() throws {
        let controller = WindowController(
            content: LayoutSchedulingLazyScrollViewAttachmentRoot(),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(LayoutSchedulingLazyScrollViewAttachmentRoot.self)
            )
        )
        let withGC: WindowContext.WithGraphicsContext = { _, _ in
            XCTFail("Lazy scroll-view display-list test should not request graphics resources.")
        }
        var redraw = false
        controller.updateView(
            tick: 0,
            delta: 0,
            date: controller.date,
            contentSize: CGSize(width: 220, height: 220),
            redraw: &redraw,
            withGC
        )

        let list = try displayList(in: controller)
        XCTAssertEqual(list.items.count, 1, displayListTreeDescription(list))
        let item = try XCTUnwrap(list.items.first)
        let effect = try XCTUnwrap(item.effectItem)
        guard case .platformGroup = effect.effect else {
            return XCTFail("expected platform group: \(displayListTreeDescription(list))")
        }
        XCTAssertEqual(item.frame, CGRect(x: 60, y: 60, width: 100, height: 100))
        XCTAssertEqual(
            shapeFillBounds(in: effect.contents),
            [
                CGRect(x: 10, y: 0, width: 80, height: 40),
                CGRect(x: 10, y: 40, width: 80, height: 40),
                CGRect(x: 10, y: 80, width: 80, height: 40),
            ],
            displayListTreeDescription(list)
        )
        XCTAssertEqual(
            effect.contents.effects.map(\.frame),
            [
                CGRect(x: 10, y: 0, width: 80, height: 40),
                CGRect(x: 10, y: 40, width: 80, height: 40),
                CGRect(x: 10, y: 80, width: 80, height: 40),
            ],
            displayListTreeDescription(list)
        )
        XCTAssertEqual(
            effect.contents.effects.flatMap { shapeFillBounds(in: $0.contents) },
            [
                CGRect(x: 0, y: 0, width: 80, height: 40),
                CGRect(x: 0, y: 0, width: 80, height: 40),
                CGRect(x: 0, y: 0, width: 80, height: 40),
            ],
            displayListTreeDescription(list)
        )
    }

    @MainActor
    func testScrollViewRootDisplayListReplacesEagerContentWithPlacedLazyContent() throws {
        let probe = LayoutSchedulingLazyScrollReplacementProbe()
        let controller = WindowController(
            content: LayoutSchedulingLazyScrollReplacementRoot(probe: probe),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(LayoutSchedulingLazyScrollReplacementRoot.self)
            )
        )
        let withGC: WindowContext.WithGraphicsContext = { _, _ in
            XCTFail("Lazy scroll-view replacement test should not request graphics resources.")
        }
        var redraw = false

        controller.updateView(
            tick: 0,
            delta: 0,
            date: controller.date,
            contentSize: CGSize(width: 220, height: 220),
            redraw: &redraw,
            withGC
        )
        var list = try displayList(in: controller)
        var effect = try XCTUnwrap(try XCTUnwrap(list.items.first).effectItem)
        XCTAssertEqual(
            shapeFillBounds(in: effect.contents),
            (0..<8).map {
                CGRect(x: 0, y: CGFloat($0) * 40, width: 80, height: 40)
            },
            displayListTreeDescription(list)
        )

        try XCTUnwrap(probe.toggle)()
        for tick in 1...2 {
            redraw = false
            controller.updateView(
                tick: UInt64(tick),
                delta: 1.0 / 60.0,
                date: controller.date.addingTimeInterval(Double(tick) / 60.0),
                contentSize: CGSize(width: 220, height: 220),
                redraw: &redraw,
                withGC
            )
        }

        list = try displayList(in: controller)
        effect = try XCTUnwrap(try XCTUnwrap(list.items.first).effectItem)
        XCTAssertEqual(
            shapeFillBounds(in: effect.contents),
            [
                CGRect(x: 10, y: 0, width: 80, height: 40),
                CGRect(x: 10, y: 40, width: 80, height: 40),
                CGRect(x: 10, y: 80, width: 80, height: 40),
            ],
            displayListTreeDescription(list)
        )
    }

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
    func testConsecutiveNoOpInboxWritesDoNotRepeatRootLayoutPlacement() {
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

        XCTAssertEqual(counter.placements, initialPlacements)
    }

    @MainActor
    func testSettledLayoutSkipsMeasurementAndResizeReusesChildSizes() throws {
        let counter = LayoutMeasurementCounter()
        let probe = LayoutMeasurementProbe()
        let controller = WindowController(
            content: LayoutMeasurementRoot(counter: counter, probe: probe),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(LayoutMeasurementRoot.self)
            )
        )
        let withGC: WindowContext.WithGraphicsContext = { _, _ in
            XCTFail("Layout measurement should not request graphics resources.")
        }

        func sample() -> LayoutMeasurementCounts {
            counter.snapshot()
        }

        let constructed = sample()
        var redraw = false
        controller.updateView(
            tick: 0,
            delta: 0,
            date: controller.date,
            contentSize: CGSize(width: 320, height: 180),
            redraw: &redraw,
            withGC
        )
        let cold = sample()

        redraw = false
        controller.updateView(
            tick: 1,
            delta: 1.0 / 60.0,
            date: controller.date.addingTimeInterval(1.0 / 60.0),
            contentSize: CGSize(width: 320, height: 180),
            redraw: &redraw,
            withGC
        )
        let warm = sample()

        try XCTUnwrap(probe.changeLayoutValue)()
        redraw = false
        controller.updateView(
            tick: 2,
            delta: 1.0 / 60.0,
            date: controller.date.addingTimeInterval(2.0 / 60.0),
            contentSize: CGSize(width: 320, height: 180),
            redraw: &redraw,
            withGC
        )
        let layoutValue = sample()

        try XCTUnwrap(probe.toggleVisual)()
        redraw = false
        controller.updateView(
            tick: 3,
            delta: 1.0 / 60.0,
            date: controller.date.addingTimeInterval(3.0 / 60.0),
            contentSize: CGSize(width: 320, height: 180),
            redraw: &redraw,
            withGC
        )
        let visual = sample()

        redraw = false
        controller.updateView(
            tick: 4,
            delta: 1.0 / 60.0,
            date: controller.date.addingTimeInterval(4.0 / 60.0),
            contentSize: CGSize(width: 360, height: 180),
            redraw: &redraw,
            withGC
        )
        let resized = sample()

        XCTAssertEqual(constructed, .zero)
        // Default explicit-alignment propagation owns a zero-origin placement
        // pass. Translated child geometry is resolved by the ordinary pass.
        XCTAssertEqual(
            cold - constructed,
            LayoutMeasurementCounts(
                makeCache: 1,
                updateCache: 0,
                sizeThatFits: 1,
                placeSubviews: 2,
                leafSizeThatFits: 4,
                leafPlaceSubviews: 3
            )
        )
        XCTAssertEqual(warm - cold, .zero)
        XCTAssertEqual(
            layoutValue - warm,
            LayoutMeasurementCounts(
                makeCache: 0,
                updateCache: 1,
                sizeThatFits: 1,
                placeSubviews: 2,
                leafSizeThatFits: 0,
                leafPlaceSubviews: 0
            )
        )
        XCTAssertEqual(visual - layoutValue, .zero)
        XCTAssertEqual(
            resized - visual,
            LayoutMeasurementCounts(
                makeCache: 0,
                updateCache: 0,
                sizeThatFits: 0,
                placeSubviews: 2,
                leafSizeThatFits: 0,
                leafPlaceSubviews: 2
            )
        )
    }

    // ASSERTIONS scrollHostPresentationDoesNotRelayoutEagerContentObserved
    // ASSERTIONS scrollUpdateRetainedDisplaySubtreeObserved
    // ASSERTIONS interpolatedDisplayListConditionalTransactionReadObserved
    // ASSERTIONS scrollGeometryObserverPullPathObserved
    // ASSERTIONS scrollShapeDisplayTransformCarrierUntrackedObserved
    // ASSERTIONS scrollShapeDisplayRetainedAcrossHostUpdatesObserved
    @MainActor
    func testSystemScrollHostOffsetDoesNotRelayoutEagerContent() throws {
        let counter = LayoutMeasurementCounter()
        let geometryProbe = LayoutMeasurementScrollGeometryProbe()
        let controller = WindowController(
            content: LayoutMeasurementScrollRoot(
                counter: counter,
                geometryProbe: geometryProbe
            ),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(LayoutMeasurementScrollRoot.self)
            )
        )
        let withGC: WindowContext.WithGraphicsContext = { _, _ in }
        var redraw = false
        for tick in 0...1 {
            controller.updateView(
                tick: UInt64(tick),
                delta: tick == 0 ? 0 : 1.0 / 60.0,
                date: controller.date.addingTimeInterval(Double(tick) / 60.0),
                contentSize: CGSize(width: 220, height: 180),
                redraw: &redraw,
                withGC
            )
        }

        let root = try XCTUnwrap(
            controller.responderNode
                as? MultiViewResponder
        )
        let responder = try XCTUnwrap(firstHostingScrollViewResponder(in: root))
        let host = try XCTUnwrap(responder.hostContainer?.scrollView)
        let settled = counter.snapshot()
        let graph = controller.viewGraph.data.graph
        let settledDisplayVersions = graph.slots.enumerated().reduce(
            into: [UInt32: UInt64]()
        ) { versions, element in
            guard let node = element.element.node else { return }
            let bodyType: Any.Type?
            switch node.pointee.kind {
            case .ruleBody(let box):
                bodyType = box.bodyType
            case .stateful(let box):
                bodyType = box.bodyType
            case .lowLevelBody(let box):
                bodyType = box.bodyType
            default:
                bodyType = nil
            }
            guard let bodyType else { return }
            let name = String(reflecting: bodyType)
            if name.contains("ScrollViewDisplayList")
                || name.contains("InterpolatedDisplayList<VUI.ResolvedStyledText>") {
                versions[UInt32(element.offset)] = node.pointee.valueVersion
            }
        }
        XCTAssertGreaterThan(
            settledDisplayVersions.count,
            1,
            "expected the scroll display node and settled text interpolators"
        )
        var childTransformIDs = Set<UInt32>()
        var styledTextShapeInputs: [UInt32: [UInt32]] = [:]
        for (index, slot) in graph.slots.enumerated() {
            guard let node = slot.node else { continue }
            let bodyType: Any.Type?
            switch node.pointee.kind {
            case .ruleBody(let box):
                bodyType = box.bodyType
            case .stateful(let box):
                bodyType = box.bodyType
            case .lowLevelBody(let box):
                bodyType = box.bodyType
            default:
                bodyType = nil
            }
            guard let bodyType else { continue }
            let name = String(reflecting: bodyType)
            if name.contains("ScrollViewChildTransform") {
                childTransformIDs.insert(UInt32(index))
            } else if name.contains(
                "ShapeStyledDisplayList<VUI.StyledTextContentView>"
            ) {
                styledTextShapeInputs[UInt32(index)] = node.pointee.inputs.map(\.attribute)
            }
        }
        XCTAssertFalse(childTransformIDs.isEmpty)
        XCTAssertFalse(styledTextShapeInputs.isEmpty)
        for (id, inputs) in styledTextShapeInputs {
            XCTAssertTrue(
                childTransformIDs.isDisjoint(with: inputs),
                "styled-text display node @\(id) tracked a scroll child transform"
            )
        }
        let offsets = [40.0, 80.0, 120.0].map {
            CGPoint(x: 0, y: $0)
        }
        for (index, offset) in offsets.enumerated() {
            Update.ensure {
                host.publishSystemContentOffset(offset)
            }
            redraw = false
            let tick = index + 2
            controller.updateView(
                tick: UInt64(tick),
                delta: 1.0 / 60.0,
                date: controller.date.addingTimeInterval(Double(tick) / 60.0),
                contentSize: CGSize(width: 220, height: 180),
                redraw: &redraw,
                withGC
            )

            XCTAssertEqual(host.host.bounds.origin, offset)
            XCTAssertEqual(counter.snapshot() - settled, .zero)
            for (id, version) in settledDisplayVersions {
                XCTAssertEqual(
                    graph.slots[Int(id)].node?.pointee.valueVersion,
                    version,
                    "host-only viewport motion republished display node @\(id)"
                )
            }
        }
        XCTAssertEqual(geometryProbe.offsets, offsets)
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
        XCTAssertEqual(targetPlacements - initialPlacements, 1)

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
        XCTAssertEqual(counter.placements - targetPlacements, 1)
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
        redraw = false
        controller.updateView(
            tick: 1,
            delta: -controller.animationTimestamp.seconds,
            date: controller.date,
            contentSize: CGSize(width: 420, height: 240),
            redraw: &redraw,
            withGC
        )
        _ = try displayList(in: controller)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        XCTAssertEqual(probe.completions, [])

        for (index, sampleTime) in [1.0 / 60.0, 2.0 / 60.0, 0.1, 1.0, 10.0].enumerated() {
            redraw = false
            controller.updateView(
                tick: UInt64(index + 2),
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

        child.viewGraph.data.withCurrent {
            runSpringMove()
        }
        redraw = false
        child.updateView(
            tick: 1,
            delta: -child.animationTimestamp.seconds,
            date: child.date,
            contentSize: CGSize(width: 420, height: 240),
            redraw: &redraw,
            withGC
        )
        _ = try displayList(in: child)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        XCTAssertEqual(probe.completions, [])

        for (index, sampleTime) in [1.0 / 60.0, 2.0 / 60.0, 0.1, 1.0, 10.0].enumerated() {
            redraw = false
            child.updateView(
                tick: UInt64(index + 2),
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
        redraw = false
        controller.updateView(
            tick: 1,
            delta: -controller.animationTimestamp.seconds,
            date: controller.date,
            contentSize: CGSize(width: 420, height: 240),
            redraw: &redraw,
            withGC
        )
        _ = try displayList(in: controller)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        XCTAssertEqual(probe.completions, [])

        for (index, sampleTime) in [1.0 / 60.0, 2.0 / 60.0, 0.1, 1.0, 10.0].enumerated() {
            redraw = false
            controller.updateView(
                tick: UInt64(index + 2),
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
            let baseTime = Double(run - 1)
            redraw = false
            controller.updateView(
                tick: tick,
                delta: baseTime - controller.animationTimestamp.seconds,
                date: controller.date.addingTimeInterval(baseTime),
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
                "Run \(run) should not complete before its registered animation."
            )

            for sampleOffset in [1.0 / 60.0, 2.0 / 60.0, 0.1] {
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

    // ASSERTIONS customAnimationStatusLayoutContinuityObserved
    @MainActor
    func testCustomAnimationCompletionStatusKeepsMovingWithReversedLayout() throws {
        let counter = LayoutSchedulingCounter()
        let probe = LayoutSchedulingAnimationProbe()
        let controller = WindowController(
            content: LayoutSchedulingCustomCompletionStatusRoot(
                counter: counter,
                probe: probe
            ),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(LayoutSchedulingCustomCompletionStatusRoot.self)
            )
        )
        let withGC: WindowContext.WithGraphicsContext = { _, _ in }
        let startDate = controller.date
        var tick: UInt64 = 0

        func update(time: Double) throws -> CGRect {
            controller.updateFrame(
                tick: tick,
                delta: time - controller.animationTimestamp.seconds,
                date: startDate.addingTimeInterval(time),
                contentSize: CGSize(width: 420, height: 240),
                shouldDrawFrame: false,
                withGC
            )
            tick &+= 1
            return try XCTUnwrap(
                renderedTextBounds(in: try displayList(in: controller)).first {
                    $0.height < 30
                }
            )
        }

        _ = try update(time: 0)
        try XCTUnwrap(probe.toggle)()
        _ = try update(time: 0.001)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        _ = try update(time: 0.25)
        _ = try update(time: 0.60)

        try XCTUnwrap(probe.toggle)()
        _ = try update(time: 0.60)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))

        var beforeCompletion: (time: Double, bounds: CGRect)?
        var boundary: (time: Double, bounds: CGRect)?
        for step in 37...180 {
            let time = Double(step) / 60.0
            let bounds = try update(time: time)
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.001))
            if probe.completions.isEmpty {
                beforeCompletion = (time, bounds)
                continue
            }
            boundary = (time + 0.000_1, try update(time: time + 0.000_1))
            break
        }

        let before = try XCTUnwrap(
            beforeCompletion,
            "The first custom-animation completion did not leave a pre-boundary sample."
        )
        let after = try XCTUnwrap(
            boundary,
            "The first custom-animation completion did not fire while the reverse route was active."
        )
        let continuing = try update(time: after.time + 0.25)

        XCTAssertEqual(probe.completions, [1])
        XCTAssertEqual(
            after.bounds.midY,
            before.bounds.midY,
            accuracy: 1.0,
            "Changing the status payload must not discard the active layout presentation."
        )
        XCTAssertGreaterThan(
            abs(continuing.midY - after.bounds.midY),
            0.5,
            "The completion status must continue moving with the reversed layout."
        )
    }

    // ASSERTIONS appKitEventActionUpdateBoundaryObserved animationListenerLifecycleObserved
    @MainActor
    func testInputQueuedCustomAnimationRegistersBeforePendingListenerFallback() throws {
        Transaction.dispatchPendingListeners()

        let counter = LayoutSchedulingCounter()
        let probe = LayoutSchedulingAnimationProbe()
        let controller = WindowController(
            content: LayoutSchedulingCustomCompletionStatusRoot(
                counter: counter,
                probe: probe
            ),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(
                    LayoutSchedulingCustomCompletionStatusRoot.self
                )
            )
        )
        let withGC: WindowContext.WithGraphicsContext = { _, _ in }
        let startDate = controller.date
        var tick: UInt64 = 0

        func update(time: Double) {
            controller.updateFrame(
                tick: tick,
                delta: time - controller.animationTimestamp.seconds,
                date: startDate.addingTimeInterval(time),
                contentSize: CGSize(width: 420, height: 240),
                shouldDrawFrame: false,
                withGC
            )
            tick &+= 1
        }

        update(time: 0)
        _ = try XCTUnwrap(probe.toggle)
        controller.enqueueInputAction {
            Update.enqueueAction {
                probe.toggle?()
            }
        }
        update(time: 0.001)

        XCTAssertTrue(probe.completions.isEmpty)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        XCTAssertTrue(
            probe.completions.isEmpty,
            "The event action must register its animator before the 10 ms "
                + "pending-listener fallback."
        )

        update(time: 1.0 / 60.0)
        update(time: 2.0 / 60.0)
        update(time: 2.2)
        XCTAssertEqual(probe.completions, [1])
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
        redraw = false
        Update.ensure {
            controller.updateView(
                tick: 1,
                delta: -controller.animationTimestamp.seconds,
                date: controller.date,
                contentSize: CGSize(width: 420, height: 240),
                redraw: &redraw,
                withGC
            )
        }
        let immediateDisplayList = try displayList(in: controller)
        XCTAssertEqual(
            try XCTUnwrap(statusMarkerBounds(in: immediateDisplayList)).width,
            100,
            accuracy: 0.5
        )
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        XCTAssertEqual(probe.completions, [])

        for (index, sampleTime) in [1.0 / 60.0, 2.0 / 60.0, 0.1, 1.0, 10.0].enumerated() {
            redraw = false
            Update.ensure {
                controller.updateView(
                    tick: UInt64(index + 2),
                    delta: sampleTime - controller.animationTimestamp.seconds,
                    date: controller.date.addingTimeInterval(sampleTime),
                    contentSize: CGSize(width: 420, height: 240),
                    redraw: &redraw,
                    withGC
                )
            }
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
        Update.ensure {
            controller.updateView(
                tick: 20,
                delta: 20.1 - controller.animationTimestamp.seconds,
                date: controller.date.addingTimeInterval(20.1),
                contentSize: CGSize(width: 420, height: 240),
                redraw: &redraw,
                withGC
            )
        }
        _ = try displayList(in: controller)
        redraw = false
        Update.ensure {
            controller.updateView(
                tick: 21,
                delta: 20.1 - controller.animationTimestamp.seconds,
                date: controller.date.addingTimeInterval(20.1),
                contentSize: CGSize(width: 420, height: 240),
                redraw: &redraw,
                withGC
            )
        }
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
        GraphHost.flushGlobalTransactions()

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

    // ASSERTIONS animationLabAnimatedThenPlainStatusRetargetObserved
    @MainActor
    func testPlainResolvedTextWritePreservesItsOwnActiveInterpolation() throws {
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
            content: LayoutSchedulingAnimatedThenPlainStatusRoot(
                probe: probe,
                font: VUI.Font(textureFont)
            ),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(LayoutSchedulingAnimatedThenPlainStatusRoot.self)
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
            idle: [LayoutSchedulingResolvedTextSample],
            animated: [LayoutSchedulingResolvedTextSample],
            plain: [LayoutSchedulingResolvedTextSample]
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
                    matching: "idle",
                    environment: controller.environment
                ),
                renderedResolvedTextSamples(
                    in: list,
                    matching: "explicitly animated status",
                    environment: controller.environment
                ),
                renderedResolvedTextSamples(
                    in: list,
                    matching: "plain status after explicit animation",
                    environment: controller.environment
                )
            )
        }

        let initial = try update(time: 0)
        XCTAssertFalse(initial.idle.isEmpty)
        XCTAssertTrue(initial.animated.isEmpty)
        XCTAssertTrue(initial.plain.isEmpty)

        try XCTUnwrap(probe.toggle)()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        _ = try update(time: 0.001)
        _ = try update(time: 0.25)
        let beforePlain = try update(time: 0.75)
        XCTAssertFalse(beforePlain.animated.isEmpty)

        try XCTUnwrap(probe.plainTextChange)()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))

        let retargeted = try [0.751, 0.8, 1.0, 1.5].map(update(time:))
        XCTAssertNotNil(
            retargeted.first { sample in
                let source = sample.idle + sample.animated
                return source.contains { $0.opacity > 0.001 }
                    && sample.plain.contains {
                        $0.opacity > 0.001 && $0.opacity < 0.999
                    }
            },
            "The plain write should retarget the Text's existing presentation animation instead of snapping."
        )

        let settled = try update(time: 4.0)
        XCTAssertTrue(
            (settled.idle + settled.animated).allSatisfy {
                $0.opacity <= 0.001
            }
        )
        XCTAssertFalse(settled.plain.isEmpty)
        XCTAssertTrue(
            settled.plain.allSatisfy { abs($0.opacity - 1) <= 0.001 }
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
        redraw = false
        Update.ensure {
            controller.updateView(
                tick: 1,
                delta: -controller.animationTimestamp.seconds,
                date: controller.date,
                contentSize: CGSize(width: 420, height: 240),
                redraw: &redraw,
                withGC
            )
        }
        let immediateDisplayList = try displayList(in: controller)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        XCTAssertEqual(probe.completions, [])
        let immediateGreenBounds = try XCTUnwrap(
            opaqueGreenShapeBounds(in: immediateDisplayList).first
        )
        XCTAssertEqual(immediateGreenBounds.midX, initialGreenBounds.midX, accuracy: 0.5)
        XCTAssertEqual(immediateGreenBounds.midY, initialGreenBounds.midY, accuracy: 0.5)
        XCTAssertEqual(immediateGreenBounds.width, initialGreenBounds.width, accuracy: 0.5)
        XCTAssertEqual(immediateGreenBounds.height, initialGreenBounds.height, accuracy: 0.5)
        let immediateBackgroundBounds = try XCTUnwrap(
            translucentGreenShapeBounds(in: immediateDisplayList)
        )
        XCTAssertEqual(immediateBackgroundBounds.midX, initialBackgroundBounds.midX, accuracy: 0.5)
        XCTAssertEqual(immediateBackgroundBounds.midY, initialBackgroundBounds.midY, accuracy: 0.5)
        XCTAssertEqual(immediateBackgroundBounds.width, initialBackgroundBounds.width, accuracy: 0.5)
        XCTAssertEqual(immediateBackgroundBounds.height, initialBackgroundBounds.height, accuracy: 0.5)

        var opacitySamples: [(time: Double, opacity: Double?)] = []
        var greenBoundsSamples: [(time: Double, bounds: CGRect)] = [
            (time: 0, bounds: immediateGreenBounds)
        ]
        for (index, sampleTime) in [1.0 / 60.0, 2.0 / 60.0, 0.5, 2.5].enumerated() {
            redraw = false
            Update.ensure {
                controller.updateView(
                    tick: UInt64(index + 2),
                    delta: sampleTime - controller.animationTimestamp.seconds,
                    date: controller.date.addingTimeInterval(sampleTime),
                    contentSize: CGSize(width: 420, height: 240),
                    redraw: &redraw,
                    withGC
                )
            }
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
        let initialBounds = try XCTUnwrap(renderedTextBounds(in: initialDisplayList).first)

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
            samples.append((sampleTime, try XCTUnwrap(renderedTextBounds(in: sampleDisplayList).first)))
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
        let initialBounds = try XCTUnwrap(
            renderedTextBounds(in: initialDisplayList).min {
                $0.minX < $1.minX
            }
        )

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
                try XCTUnwrap(
                    renderedTextBounds(in: sampleDisplayList).min {
                        $0.minX < $1.minX
                    }
                )
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
    func testStaticButtonLabelsRemainCenteredInsideBorders() throws {
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
            XCTFail("Static button centering test should not request graphics resources.")
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

        let list = try displayList(in: controller)
        let borders = shapeStrokeBounds(in: list).sorted { $0.minX < $1.minX }
        let labels = renderedTextBounds(in: list).sorted {
            $0.minX < $1.minX
        }
        XCTAssertEqual(borders.count, 3)
        XCTAssertEqual(labels.count, 3)
        for (border, label) in zip(borders, labels) {
            XCTAssertEqual(label.midX, border.midX, accuracy: 0.001)
            XCTAssertEqual(label.midY, border.midY, accuracy: 0.001)
        }
    }

    @MainActor
    // ASSERTIONS buttonLabelNestedLayoutInheritsContainerPositionObserved
    func testLabButtonGlyphPixelsRemainCenteredAcrossNestedAndDirectLayouts() throws {
        guard let deviceContext = makeGraphicsDeviceContext(api: .metal),
              let renderQueue = deviceContext.renderQueue() else {
            throw XCTSkip("Metal graphics device unavailable")
        }
        let previousAppContext = appContext
        appContext = LayoutSchedulingAppContext(
            graphicsDeviceContext: deviceContext
        )
        defer { appContext = previousAppContext }

        let controller = WindowController(
            content: LayoutSchedulingLabButtonGlyphAlignmentRoot(),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(LayoutSchedulingLabButtonGlyphAlignmentRoot.self)
            )
        )
        let width = 1400
        let height = 760
        let scale: CGFloat = 1
        let resolutionWidth = Int(CGFloat(width) * scale)
        let resolutionHeight = Int(CGFloat(height) * scale)
        let withGC: WindowContext.WithGraphicsContext = { _, handler in
            guard let commandBuffer = renderQueue.makeCommandBuffer(),
                  let context = GraphicsContext(
                    sceneResources: controller.sceneResources,
                    environment: controller.environment,
                    viewport: CGRect(x: 0, y: 0, width: width, height: height),
                    contentOffset: .zero,
                    contentScaleFactor: scale,
                    resolution: CGSize(
                        width: resolutionWidth,
                        height: resolutionHeight
                    ),
                    commandBuffer: commandBuffer
                  ) else {
                return XCTFail("Unable to create the text resource graphics context.")
            }
            handler(context)
            XCTAssertTrue(commandBuffer.commit())
        }

        controller.updateFrame(
            tick: 0,
            delta: 0,
            date: controller.date,
            contentSize: CGSize(width: width, height: height),
            shouldDrawFrame: false,
            withGC
        )
        let list = try displayList(in: controller)
        let buttonBorders = shapeStrokeBounds(in: list)
            .filter { abs($0.height - 25) <= 0.5 }
            .sorted {
                abs($0.minY - $1.minY) > 0.5
                    ? $0.minY < $1.minY
                    : $0.minX < $1.minX
            }
        XCTAssertEqual(buttonBorders.count, 21)

        let commandBuffer = try XCTUnwrap(renderQueue.makeCommandBuffer())
        let context = try XCTUnwrap(GraphicsContext(
            sceneResources: controller.sceneResources,
            environment: controller.environment,
            viewport: CGRect(x: 0, y: 0, width: width, height: height),
            contentOffset: .zero,
            contentScaleFactor: scale,
            resolution: CGSize(
                width: resolutionWidth,
                height: resolutionHeight
            ),
            commandBuffer: commandBuffer
        ))
        XCTAssertEqual(context.backdrop.width, resolutionWidth)
        XCTAssertEqual(context.backdrop.height, resolutionHeight)
        context.clear(with: .white)
        DisplayList.GraphicsRenderer().render(
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
            count: resolutionWidth * resolutionHeight * 4
        )

        func glyphBounds(in frame: CGRect) -> CGRect? {
            let region = frame.standardized
                .insetBy(dx: 3, dy: 3)
                .applying(CGAffineTransform(scaleX: scale, y: scale))
            let minRegionX = max(Int(floor(region.minX)), 0)
            let maxRegionX = min(Int(ceil(region.maxX)), resolutionWidth)
            let minRegionY = max(Int(floor(region.minY)), 0)
            let maxRegionY = min(Int(ceil(region.maxY)), resolutionHeight)
            var minX = resolutionWidth
            var minY = resolutionHeight
            var maxX = -1
            var maxY = -1
            for y in minRegionY..<maxRegionY {
                for x in minRegionX..<maxRegionX {
                    let offset = (y * resolutionWidth + x) * 4
                    let darkness = 255 - max(
                        Int(bytes[offset]),
                        Int(bytes[offset + 1]),
                        Int(bytes[offset + 2])
                    )
                    if darkness > 20 {
                        minX = min(minX, x)
                        minY = min(minY, y)
                        maxX = max(maxX, x)
                        maxY = max(maxY, y)
                    }
                }
            }
            guard maxX >= minX, maxY >= minY else {
                return nil
            }
            return CGRect(
                x: minX,
                y: minY,
                width: maxX - minX + 1,
                height: maxY - minY + 1
            )
        }

        for (index, border) in buttonBorders.enumerated() {
            let glyph = try XCTUnwrap(
                glyphBounds(in: border),
                "button \(index) has no glyph pixels inside \(border)"
            )
            XCTAssertGreaterThan(
                glyph.width,
                2,
                "button \(index) contains only a pixel artifact"
            )
            XCTAssertLessThanOrEqual(
                abs(glyph.midX / scale - border.midX),
                1,
                "button \(index) glyph pixels are not horizontally centered in \(border)"
            )
            XCTAssertLessThanOrEqual(
                abs(glyph.midY / scale - border.midY),
                2,
                "button \(index) glyph pixels are not vertically centered in \(border)"
            )
        }
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
            let list = try displayList(in: controller)
            let buttons = shapeStrokeBounds(in: list)
                .filter { $0.width > 40 && $0.height > 15 && $0.height < 50 }
                .sorted { $0.minX < $1.minX }
            XCTAssertEqual(
                buttons.count,
                4,
                "unexpected button strokes at \(time): \(buttons)"
            )
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
        XCTAssertEqual(
            initial.buttonLabel.midX,
            initial.buttonBorder.midX,
            accuracy: 0.001,
            "Change Text label must remain centered inside its button border"
        )
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
        XCTAssertEqual(
            final.buttonLabel.midX,
            final.buttonBorder.midX,
            accuracy: 0.001,
            "Change Text label must remain centered inside its button border"
        )
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
        _ = try update(time: 0)
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

    // ASSERTIONS animationLabSpringReversalCompositionObserved
    @MainActor
    func testResolvedAnimationLabVariantTextStaysCenteredDuringRapidSpringReversal() throws {
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

        _ = try update(time: 0)
        try XCTUnwrap(probe.toggle)()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        for time in [0.001, 1.0 / 60.0, 0.05, 0.10, 0.15] {
            _ = try update(time: time)
        }

        try XCTUnwrap(probe.toggle)()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))

        var sawComposedEndpoints = false
        for time in [0.151, 1.0 / 6.0, 0.20, 0.30, 0.50, 0.90, 1.50, 2.50, 5.20] {
            let sample = try update(time: time)
            let visibleCompact = sample.compact.filter { $0.opacity > 0.001 }
            let visibleExpanded = sample.expanded.filter { $0.opacity > 0.001 }
            sawComposedEndpoints = sawComposedEndpoints ||
                (!visibleCompact.isEmpty && !visibleExpanded.isEmpty)

            let visibleTexts = visibleCompact + visibleExpanded
            XCTAssertFalse(
                visibleTexts.isEmpty,
                "missing rapid-reversal variant text at \(time)"
            )
            for text in visibleTexts {
                XCTAssertEqual(
                    text.frame.midX,
                    sample.background.midX,
                    accuracy: 3,
                    "rapid-reversal text split from the child center at \(time): \(sample)"
                )
            }
        }
        XCTAssertTrue(
            sawComposedEndpoints,
            "rapid reversal never exposed the native two-endpoint composition"
        )
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
                renderedTextBounds(
                    in: try displayList(in: controller)
                ).first {
                    abs($0.width - 160) <= 0.5 && abs($0.height - 20) <= 0.5
                }
            )
        }

        let initialBounds = try update(time: 0)
        try XCTUnwrap(probe.removeChild)()
        _ = try update(time: 0)
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
        _ = try update(time: 0)
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
        _ = try update(time: 5.1)
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

    // ASSERTIONS animationLabActiveSpringRemovalTitleContinuityObserved
    // ASSERTIONS animationLabActiveSpringInsertionTitleContinuityObserved
    // ASSERTIONS animationLabActiveSpringInsertionTrajectoryObserved
    @MainActor
    func testResolvedAnimationLabActiveSpringRetainedTitleKeepsActionBoundaryContinuity() throws {
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

        var currentTime = 0.0
        let initial = try update(time: currentTime)

        @discardableResult
        func advance(to targetTime: Double) throws -> CGRect {
            let interval = 1.0 / 30.0
            var sample = try update(time: currentTime)
            while currentTime + interval < targetTime {
                currentTime += interval
                sample = try update(time: currentTime)
            }
            currentTime = targetTime
            return try update(time: currentTime)
        }

        try XCTUnwrap(probe.springMove)()
        _ = try update(time: currentTime)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        let beforeRemoval = try advance(to: 1.0)

        try XCTUnwrap(probe.removeChild)()
        _ = try update(time: currentTime)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        let immediateRemoval = try update(time: currentTime)
        XCTAssertEqual(
            immediateRemoval.midX,
            beforeRemoval.midX,
            accuracy: 0.01,
            "Active-spring removal must preserve the title's current horizontal presentation."
        )
        XCTAssertEqual(
            immediateRemoval.midY,
            beforeRemoval.midY,
            accuracy: 0.01,
            "Active-spring removal must preserve the title's current vertical presentation."
        )
        let earlyRemoval = try advance(to: 1.1)
        XCTAssertLessThanOrEqual(
            abs(earlyRemoval.midY - immediateRemoval.midY),
            1.5,
            "Active-spring removal must begin from the current title position instead of snapping."
        )

        _ = try advance(to: 6.2)
        try XCTUnwrap(probe.springMove)()
        _ = try update(time: currentTime)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        let beforeInsertion = try advance(to: 7.2)

        try XCTUnwrap(probe.insertChild)()
        _ = try update(time: currentTime)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        let immediateInsertion = try update(time: currentTime)
        XCTAssertEqual(
            immediateInsertion.midX,
            beforeInsertion.midX,
            accuracy: 0.01,
            "Active-spring insertion must preserve the title's current horizontal presentation."
        )
        XCTAssertEqual(
            immediateInsertion.midY,
            beforeInsertion.midY,
            accuracy: 0.01,
            "Active-spring insertion must preserve the title's current vertical presentation."
        )
        let earlyInsertion = try advance(to: 7.3)
        XCTAssertLessThanOrEqual(
            abs(earlyInsertion.midY - immediateInsertion.midY),
            1.5,
            "Active-spring insertion must begin from the current title position instead of snapping."
        )

        var insertionSamples: [(time: Double, bounds: CGRect)] = []
        for sampleTime in [7.5, 8.0, 9.0, 10.0, 11.0, 12.0, 12.15] {
            insertionSamples.append((
                time: sampleTime,
                bounds: try advance(to: sampleTime)
            ))
        }
        XCTAssertTrue(
            insertionSamples.allSatisfy {
                $0.bounds.midY <= immediateInsertion.midY + 0.05
            },
            "Active-spring insertion must not move away from its upward target: start=\(immediateInsertion) samples=\(insertionSamples)"
        )
        XCTAssertNotNil(
            insertionSamples.first {
                $0.bounds.midY < immediateInsertion.midY - 0.25
            },
            "Active-spring insertion must sample upward motion before settling: start=\(immediateInsertion) samples=\(insertionSamples)"
        )
        let preTerminalInsertion = try XCTUnwrap(insertionSamples.last?.bounds)
        XCTAssertEqual(
            preTerminalInsertion.midY,
            initial.midY,
            accuracy: 0.75,
            "Active-spring insertion must approach its target before completion instead of jumping at the terminal sample."
        )
        let settled = try advance(to: 12.4)
        XCTAssertEqual(settled.midY, initial.midY, accuracy: 0.5)
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
                    let red = Double(bytes[offset])
                    let green = Double(bytes[offset + 1])
                    let blue = Double(bytes[offset + 2])
                    // The outgoing replacement is deliberately magenta so its
                    // antialiased edge must not contribute to the black title.
                    let value = if red > green && blue > green {
                        0.0
                    } else {
                        max(255.0 - max(red, green, blue), 0.0)
                    }
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
            midpointSpread,
            finalSpread,
            "Rendered Animated child pixels must shrink during insertion"
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
        let numericGlyphOperations = closureBounds(in: incremented)
        XCTAssertFalse(
            numericGlyphOperations.isEmpty,
            displayListTreeDescription(incremented)
        )
    }

    // ASSERTIONS contentTransitionRapidTextPublicRetargetContinuityObserved
    @MainActor
    func testContentTransitionRapidTextRetargetPreservesPresentationTrajectory() throws {
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
            content: LayoutSchedulingRapidContentTextRoot(probe: probe),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(LayoutSchedulingRapidContentTextRoot.self)
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
                return XCTFail("Unable to create the rapid text graphics context.")
            }
            handler(context)
            XCTAssertTrue(commandBuffer.commit())
        }
        let startDate = controller.date
        var tick: UInt64 = 0

        struct Sample {
            var buttonMidY: CGFloat
            var compactOpacity: Double
            var expandedOpacity: Double
        }

        func compositeOpacity(
            _ samples: [LayoutSchedulingResolvedTextSample]
        ) -> Double {
            1 - samples.reduce(1) {
                $0 * (1 - $1.opacity)
            }
        }

        func update(time: Double) throws -> Sample {
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
            let buttonMidY = try XCTUnwrap(
                renderedResolvedTextSamples(
                    in: list,
                    matching: "Change Text",
                    environment: controller.environment
                ).last?.frame.midY
            )
            let compact = renderedResolvedTextSamples(
                in: list,
                matching: "Compact",
                environment: controller.environment
            )
            let expanded = renderedResolvedTextSamples(
                in: list,
                matching: "Expanded value",
                environment: controller.environment
            )
            return Sample(
                buttonMidY: buttonMidY,
                compactOpacity: compositeOpacity(compact),
                expandedOpacity: compositeOpacity(expanded)
            )
        }

        let initial = try update(time: 0)
        try XCTUnwrap(probe.toggle)()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        _ = try update(time: 0.001)
        _ = try update(time: 0.017)
        _ = try update(time: 0.034)
        let beforeRetarget = try update(time: 0.12)

        try XCTUnwrap(probe.toggle)()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        let afterRetarget = try update(time: 0.121)
        _ = try update(time: 0.137)
        _ = try update(time: 0.154)
        let continued = try update(time: 0.24)
        let later = try update(time: 0.72)
        let settled = try update(time: 1.70)

        XCTAssertEqual(
            afterRetarget.buttonMidY,
            beforeRetarget.buttonMidY,
            accuracy: 0.5
        )
        XCTAssertGreaterThan(beforeRetarget.expandedOpacity, 0)
        XCTAssertGreaterThan(afterRetarget.expandedOpacity, 0)
        XCTAssertGreaterThanOrEqual(
            continued.expandedOpacity,
            beforeRetarget.expandedOpacity
        )
        XCTAssertGreaterThan(
            abs(continued.buttonMidY - initial.buttonMidY),
            abs(beforeRetarget.buttonMidY - initial.buttonMidY)
        )
        XCTAssertGreaterThan(
            abs(later.buttonMidY - initial.buttonMidY),
            abs(continued.buttonMidY - initial.buttonMidY)
        )
        XCTAssertEqual(settled.buttonMidY, initial.buttonMidY, accuracy: 0.5)
        XCTAssertEqual(settled.compactOpacity, 1, accuracy: 0.01)
        XCTAssertEqual(settled.expandedOpacity, 0, accuracy: 0.01)

        var repeatedBoundaries: [Sample] = []
        for action in 0..<16 {
            let actionTime = 2.0 + Double(action) * 0.12
            let boundary = try update(time: actionTime)
            repeatedBoundaries.append(boundary)
            try XCTUnwrap(probe.toggle)()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
            let immediate = try update(time: actionTime + 0.001)
            XCTAssertEqual(
                immediate.buttonMidY,
                boundary.buttonMidY,
                accuracy: 0.5,
                "repeated retarget restarted at action \(action + 1)"
            )
            _ = try update(time: actionTime + 0.017)
            _ = try update(time: actionTime + 0.034)
        }

        for (index, sample) in repeatedBoundaries.enumerated().dropFirst(2) {
            XCTAssertGreaterThan(
                sample.compactOpacity,
                0.001,
                "Compact presentation disappeared at action \(index + 1)"
            )
            XCTAssertGreaterThan(
                sample.expandedOpacity,
                0.001,
                "Expanded presentation disappeared at action \(index + 1)"
            )
        }

        _ = try update(time: 3.92)
        _ = try update(time: 4.04)
        let repeatedSettled = try update(time: 5.55)
        XCTAssertEqual(
            repeatedSettled.buttonMidY,
            initial.buttonMidY,
            accuracy: 0.5
        )
        XCTAssertEqual(repeatedSettled.compactOpacity, 1, accuracy: 0.01)
        XCTAssertEqual(repeatedSettled.expandedOpacity, 0, accuracy: 0.01)
    }

    // ASSERTIONS asymmetricTransitionRapidViewRetargetContinuityObserved
    @MainActor
    func testRapidAsymmetricViewTransitionRetargetKeepsPresentationBoundaryContinuous() throws {
        guard let deviceContext = makeGraphicsDeviceContext(api: .metal),
              let renderQueue = deviceContext.renderQueue() else {
            throw XCTSkip("Metal graphics device unavailable")
        }
        let previousAppContext = appContext
        appContext = LayoutSchedulingAppContext(
            graphicsDeviceContext: deviceContext
        )
        defer { appContext = previousAppContext }
        let pipelineStates = try XCTUnwrap(
            GraphicsPipelineStates.sharedInstance(commandQueue: renderQueue)
        )

        let probe = LayoutSchedulingAnimationProbe()
        let controller = WindowController(
            content: LayoutSchedulingRapidAsymmetricViewTransitionRoot(
                probe: probe
            ),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(
                    LayoutSchedulingRapidAsymmetricViewTransitionRoot.self
                )
            )
        )
        let withGC: WindowContext.WithGraphicsContext = { _, handler in
            _ = pipelineStates
            guard let commandBuffer = renderQueue.makeCommandBuffer(),
                  let context = GraphicsContext(
                    sceneResources: controller.sceneResources,
                    environment: controller.environment,
                    viewport: CGRect(x: 0, y: 0, width: 500, height: 220),
                    contentOffset: .zero,
                    contentScaleFactor: 1,
                    resolution: CGSize(width: 500, height: 220),
                    commandBuffer: commandBuffer
                  ) else {
                return XCTFail(
                    "Unable to create asymmetric-transition graphics context."
                )
            }
            handler(context)
            XCTAssertTrue(commandBuffer.commit())
        }
        let startDate = controller.date
        var tick: UInt64 = 0
        var redraw = false
        var frameTrajectory: [(time: Double, bounds: CGRect)] = []

        func greenCardBounds(
            in list: DisplayList
        ) throws -> CGRect {
            let candidates = renderedShapePresentationSamples(in: list)
                .compactMap { sample -> CGRect? in
                guard sample.role == .fill,
                      !sample.isStroke,
                      sample.opacity > 0.0001,
                      let color = sample.color,
                      color.provider.green > color.provider.red,
                      color.provider.green > color.provider.blue else {
                    return nil
                }
                return sample.bounds
            }
            return try XCTUnwrap(
                candidates.max {
                    $0.width * $0.height < $1.width * $1.height
                },
                "missing transitioned green card: \(displayListTreeDescription(list))"
            )
        }

        func update(
            time: Double
        ) throws -> CGRect {
            redraw = false
            controller.updateView(
                tick: tick,
                delta: time - controller.animationTimestamp.seconds,
                date: startDate.addingTimeInterval(time),
                contentSize: CGSize(width: 500, height: 220),
                redraw: &redraw,
                withGC
            )
            tick &+= 1
            let bounds = try greenCardBounds(
                in: try displayList(in: controller)
            )
            frameTrajectory.append((time, bounds))
            return bounds
        }

        var currentTime = 0.0
        let initial = try update(time: currentTime)
        let buttonBounds = try XCTUnwrap(
            shapeStrokeBounds(in: try displayList(in: controller)).first {
                $0.width > 70 &&
                    $0.width < 160 &&
                    $0.height > 18 &&
                    $0.height < 40
            }
        )
        let buttonPoint = CGPoint(
            x: buttonBounds.midX,
            y: buttonBounds.midY
        )

        func advance(
            to targetTime: Double
        ) throws -> CGRect {
            let interval = 1.0 / 60.0
            while currentTime + interval < targetTime {
                currentTime += interval
                _ = try update(time: currentTime)
            }
            currentTime = targetTime
            return try update(time: currentTime)
        }

        let actionTimes = [
            0.20,
            0.65,
            1.05,
            1.75,
            2.20,
            2.95,
            3.30,
            4.05,
            4.50,
            5.15,
        ]
        for (action, actionTime) in actionTimes.enumerated() {
            let boundary = try advance(to: actionTime)
            controller.enqueueInputAction {
                _ = controller.handleMouseEvent(event: MouseEvent(
                    type: .buttonDown,
                    device: .genericMouse,
                    deviceID: 0,
                    buttonID: 0,
                    location: buttonPoint,
                    timestamp: actionTime
                ))
                _ = controller.handleMouseEvent(event: MouseEvent(
                    type: .buttonUp,
                    device: .genericMouse,
                    deviceID: 0,
                    buttonID: 0,
                    location: buttonPoint,
                    timestamp: actionTime + 0.0001
                ))
            }
            let immediate = try advance(to: actionTime + 0.001)

            XCTAssertEqual(
                immediate.origin.x,
                boundary.origin.x,
                accuracy: 0.75,
                "asymmetric transition restarted horizontally at action \(action + 1)"
            )
            XCTAssertEqual(
                immediate.origin.y,
                boundary.origin.y,
                accuracy: 0.75,
                "asymmetric transition restarted vertically at action \(action + 1)"
            )
            XCTAssertEqual(
                immediate.size.width,
                boundary.size.width,
                accuracy: 0.75,
                "asymmetric transition restarted its scale at action \(action + 1)"
            )
            XCTAssertEqual(
                immediate.size.height,
                boundary.size.height,
                accuracy: 0.75,
                "asymmetric transition restarted its scale at action \(action + 1)"
            )
        }

        _ = try advance(to: currentTime + 2.2)
        let settled = try advance(to: currentTime + 0.1)
        XCTAssertEqual(settled, initial)

        for (previous, next) in zip(
            frameTrajectory,
            frameTrajectory.dropFirst()
        ) {
            XCTAssertLessThanOrEqual(
                abs(
                    next.bounds.midX -
                        previous.bounds.midX
                ),
                8,
                "horizontal presentation jump from \(previous) to \(next)"
            )
            XCTAssertLessThanOrEqual(
                abs(
                    next.bounds.midY -
                        previous.bounds.midY
                ),
                2,
                "vertical presentation jump from \(previous) to \(next)"
            )
            XCTAssertLessThanOrEqual(
                abs(
                    next.bounds.width -
                        previous.bounds.width
                ),
                3,
                "presentation width jump from \(previous) to \(next)"
            )
            XCTAssertLessThanOrEqual(
                abs(
                    next.bounds.height -
                        previous.bounds.height
                ),
                3,
                "presentation height jump from \(previous) to \(next)"
            )
        }
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
            let transitionContents = drawingContents(in: list)
            XCTAssertFalse(
                transitionContents.isEmpty,
                displayListTreeDescription(list)
            )
            let transitionCommandBounds = transitionContents.flatMap(
                recursiveTextCommandBounds(in:)
            )
            XCTAssertFalse(transitionCommandBounds.isEmpty)
            XCTAssertFalse(
                transitionCommandBounds.contains {
                    $0.width >= 100
                },
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
        let insertionLists = try [
            1.201, 1.22, 1.28, 1.40, 1.70, 1.80, 1.90, 2.20,
        ]
            .map(update)
        let insertion = insertionLists.map(symbolDrawProgressSamples(in:))
        let fallbackInsertion = insertionLists.map(
            symbolDrawFallbackProgressSamples(in:)
        )
        let insertionProgresses = insertion.flatMap {
            $0.compactMap { $0 }
        }
        let fallbackProgresses = fallbackInsertion.flatMap {
            $0.compactMap { $0 }
        }

        let firstInsertionProgresses = try XCTUnwrap(
            insertionProgresses.first
        )
        XCTAssertTrue(
            firstInsertionProgresses.allSatisfy {
                $0 >= 0 && $0 < 0.10
            },
            "fresh symbol insertion did not begin at the hidden boundary: \(insertion)"
        )
        XCTAssertTrue(
            insertionProgresses.contains { progresses in
                progresses.indices.contains(0) &&
                    progresses[0] > 0.001 &&
                    progresses[0] < 0.999
            },
            "fresh symbol insertion skipped stroke motion group: \(insertion)"
        )
        XCTAssertTrue(
            fallbackProgresses.contains { progresses in
                progresses.indices.contains(1) &&
                    progresses[1] > 0.001 &&
                    progresses[1] < 0.999
            },
            "fresh symbol insertion skipped pencil opacity group: \(fallbackInsertion)"
        )
    }

    // ASSERTIONS symbolEffectLayoutMotionObserved
    // ASSERTIONS symbolEffectLayoutDrawRestoreObserved
    @MainActor
    func testSystemSymbolDrawHideKeepsRenderedPositionDuringButtonRelayout() throws {
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
            content: LayoutSchedulingSymbolDrawLayoutRoot(probe: probe),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(LayoutSchedulingSymbolDrawLayoutRoot.self)
            )
        )
        let withGC: WindowContext.WithGraphicsContext = { _, handler in
            guard let commandBuffer = renderQueue.makeCommandBuffer(),
                  let context = GraphicsContext(
                    sceneResources: controller.sceneResources,
                    environment: controller.environment,
                    viewport: CGRect(x: 0, y: 0, width: 500, height: 150),
                    contentOffset: .zero,
                    contentScaleFactor: 1,
                    resolution: CGSize(width: 500, height: 150),
                    commandBuffer: commandBuffer
                  ) else {
                return XCTFail("Unable to create the symbol layout context.")
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
                contentSize: CGSize(width: 500, height: 150),
                shouldDrawFrame: false,
                withGC
            )
            tick &+= 1
            return try displayList(in: controller)
        }

        func drawSample(
            in list: DisplayList
        ) throws -> LayoutSchedulingSymbolPresentationSample {
            try XCTUnwrap(
                symbolPresentationSamples(in: list).first {
                    $0.name == "draw" && $0.opacity > 0.001
                },
                "missing draw symbol: \(displayListTreeDescription(list))"
            )
        }

        func labelFrame(in list: DisplayList) throws -> CGRect {
            try XCTUnwrap(
                renderedResolvedTextSamples(
                    in: list,
                    matching: "by layer",
                    environment: controller.environment
                )
                .filter { $0.opacity > 0.001 }
                .max { $0.opacity < $1.opacity }?
                .frame,
                "missing symbol caption: \(displayListTreeDescription(list))"
            )
        }

        let initialList = try update(0)
        let initialSymbol = try drawSample(in: initialList)
        let initialLabel = try labelFrame(in: initialList)

        try XCTUnwrap(probe.toggle)()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        _ = try update(0.001)
        let hidingList = try update(0.15)
        let hidingSymbol = try drawSample(in: hidingList)
        let hidingLabel = try labelFrame(in: hidingList)

        XCTAssertGreaterThan(
            abs(hidingLabel.midX - initialLabel.midX),
            5,
            "the caption must follow the widened-button HStack layout"
        )
        XCTAssertEqual(
            hidingSymbol.bounds.midX,
            initialSymbol.bounds.midX,
            accuracy: 0.75,
            """
            draw-to-hidden presentation must retain its preceding position
            initialSymbol=\(initialSymbol)
            hidingSymbol=\(hidingSymbol)
            initialLabel=\(initialLabel)
            hidingLabel=\(hidingLabel)
            initialList:
            \(displayListTreeDescription(initialList))
            hidingList:
            \(displayListTreeDescription(hidingList))
            """
        )

        _ = try update(1.40)
        try XCTUnwrap(probe.toggle)()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        _ = try update(1.401)
        let restoringList = try update(1.55)
        let restoringSymbol = try drawSample(in: restoringList)
        let restoringLabel = try labelFrame(in: restoringList)

        XCTAssertEqual(restoringLabel.midX, initialLabel.midX, accuracy: 0.75)
        XCTAssertEqual(
            restoringSymbol.bounds.midX,
            initialSymbol.bounds.midX,
            accuracy: 0.75,
            "restore presentation must follow the current layout position"
        )
    }

    @MainActor
    func testSystemSymbolReplacementKeepsStyleSpecificHostTimeline() throws {
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
            content: LayoutSchedulingSymbolReplaceRoot(probe: probe),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(LayoutSchedulingSymbolReplaceRoot.self)
            )
        )
        let withGC: WindowContext.WithGraphicsContext = { _, handler in
            guard let commandBuffer = renderQueue.makeCommandBuffer(),
                  let context = GraphicsContext(
                    sceneResources: controller.sceneResources,
                    environment: controller.environment,
                    viewport: CGRect(x: 0, y: 0, width: 400, height: 120),
                    contentOffset: .zero,
                    contentScaleFactor: 1,
                    resolution: CGSize(width: 400, height: 120),
                    commandBuffer: commandBuffer
                  ) else {
                return XCTFail("Unable to create the replacement resource context.")
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
                contentSize: CGSize(width: 400, height: 120),
                shouldDrawFrame: false,
                withGC
            )
            tick &+= 1
            return try displayList(in: controller)
        }

        _ = try update(0)
        try XCTUnwrap(probe.toggle)()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))

        let timeline = try [0.001, 0.01, 0.02, 0.10, 0.20, 0.30, 0.50, 0.80]
            .map { time in
                let list = try update(time)
                return (
                    time,
                    symbolPresentationSamples(in: list)
                        .filter { $0.opacity > 0.001 }
                )
            }
        let early = timeline.first { abs($0.0 - 0.10) < 0.001 }?.1 ?? []
        let earlyNames = early.map(\.name)

        XCTAssertEqual(
            earlyNames.filter { $0 == "photo.fill" }.count,
            4,
            "default/downUp/upUp/whole must still present the source at 0.1s: \(timeline)"
        )
        XCTAssertEqual(
            earlyNames.filter { $0 == "draw" }.count,
            2,
            "only offUp's two incoming groups must present the target at 0.1s: \(timeline)"
        )

        let middle = timeline.first { abs($0.0 - 0.30) < 0.001 }?.1 ?? []
        XCTAssertTrue(
            middle.contains {
                $0.name == "draw" &&
                    $0.drawProgresses?.contains(where: { $0 > 0 && $0 < 1 }) == true
            },
            "automatic replacement must retain its partial incoming draw tail: \(timeline)"
        )

        let settled = timeline.last?.1 ?? []
        XCTAssertEqual(
            settled.filter { $0.name == "draw" }.count,
            5,
            "every style must settle on the target independently: \(timeline)"
        )
        XCTAssertFalse(
            settled.contains { $0.name == "photo.fill" },
            "the outgoing source must be absent after the longest checked timeline: \(timeline)"
        )

        try XCTUnwrap(probe.plainTextChange)()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        let plainReplacement = symbolPresentationSamples(in: try update(0.801))
            .filter { $0.opacity > 0.001 }
        XCTAssertEqual(
            plainReplacement.filter { $0.name == "photo.fill" }.count,
            5,
            "a later plain image change must not reuse the completed animation transaction"
        )
        XCTAssertFalse(
            plainReplacement.contains { $0.name == "draw" },
            "a later plain image change must publish its target immediately"
        )

        // ASSERTIONS imageViewChildInputTransactionWiringObserved
        // ASSERTIONS symbolEffectReplaceTimelineRuntimeObserved
        // ASSERTIONS symbolEffectReplaceSpatialRuntimeObserved
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
        let initialBounds = try XCTUnwrap(
            renderedTextBounds(in: initialDisplayList).first
        )

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
                try XCTUnwrap(
                    renderedTextBounds(in: sampleDisplayList).first
                )
            ))
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
        let initialBounds = try XCTUnwrap(
            renderedTextBounds(in: initialDisplayList).first
        )

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
                try XCTUnwrap(
                    renderedTextBounds(in: sampleDisplayList).first
                )
            ))
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
            renderedTextBounds(in: inserted).first {
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
                renderedTextBounds(in: list).first {
                    $0.width > 80 && $0.width < 140 && $0.height > 14
                },
                "missing Animation Lab child text at \(sampleTime): \(renderedTextBounds(in: list))"
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
                ($0.width > 60 && $0.width < 150 &&
                    $0.height > 11 && $0.height < 25) ||
                    ($0.width > 20 && $0.width < 45 &&
                        $0.height > 5 && $0.height <= 12)
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
            let titles = renderedTextBounds(in: list).filter {
                    abs($0.width - 160) <= 0.5 && abs($0.height - 20) <= 0.5
                }
            XCTAssertFalse(
                titles.isEmpty,
                "missing retained-removal title at \(time): \(renderedTextBounds(in: list))"
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
                    "retained-removal title escaped the left edge at \(time): titles=\(titles) box=\(box) allText=\(renderedTextBounds(in: list)) allStrokes=\(shapeStrokeBounds(in: list)) tree=\(displayListTreeDescription(list))"
                )
                XCTAssertLessThanOrEqual(
                    title.maxX,
                    box.maxX + 0.75,
                    "retained-removal title escaped the right edge at \(time): titles=\(titles) box=\(box) allText=\(renderedTextBounds(in: list)) allStrokes=\(shapeStrokeBounds(in: list)) tree=\(displayListTreeDescription(list))"
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
        let initialBounds = try XCTUnwrap(
            renderedTextBounds(in: initialDisplayList).first
        )

        let run = try XCTUnwrap(probe.toggle)
        child.viewGraph.data.withCurrent {
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
            samples.append((
                sampleTime,
                try XCTUnwrap(
                    renderedTextBounds(in: sampleDisplayList).first
                )
            ))
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

    private func renderedShapeRecords(
        in displayList: DisplayList
    ) -> [(
        bounds: CGRect,
        role: ShapeRole,
        color: VUI.Color?,
        isStroke: Bool
    )] {
        typealias Record = (
            bounds: CGRect,
            role: ShapeRole,
            color: VUI.Color?,
            isStroke: Bool
        )

        func applying(
            _ transform: CGAffineTransform,
            to records: [Record]
        ) -> [Record] {
            guard !transform.isIdentity else { return records }
            return records.map { record in
                (
                    record.bounds.applying(transform).standardized,
                    record.role,
                    record.color,
                    record.isStroke
                )
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

        func presentationTransform(
            for item: DisplayList.Item
        ) -> CGAffineTransform {
            let recordedBounds: CGRect?
            switch item.value {
            case let .content(content):
                recordedBounds = content.command.bounds
            case .effect:
                return CGAffineTransform(
                    translationX: item.frame.minX,
                    y: item.frame.minY
                )
            case let .states(states):
                recordedBounds = states.last?.1.interpolationBounds
            case .empty:
                recordedBounds = nil
            }
            guard let recordedBounds, !recordedBounds.isNull else {
                return .identity
            }
            return CGAffineTransform(
                translationX: item.frame.minX - recordedBounds.minX,
                y: item.frame.minY - recordedBounds.minY
            )
        }

        return displayList.items.reduce(into: []) { records, item in
            let itemTransform = presentationTransform(for: item)
            switch item.value {
            case let .content(content):
                if case let .shape(shape) = content.value,
                   case let .shape(
                    role,
                    style,
                    _,
                    _,
                    commandBounds
                   ) = shape.command,
                   let commandBounds {
                    let transformedPath = shape.path.applying(shape.transform)
                    let center = CGPoint(
                        x: commandBounds.midX,
                        y: commandBounds.midY
                    )
                    let isStroke: Bool
                    switch role {
                    case .stroke:
                        isStroke = true
                    case .fill:
                        isStroke = !transformedPath.contains(
                            center,
                            eoFill: shape.fillStyle.isEOFilled
                        )
                    case .separator:
                        isStroke = false
                    }
                    let color: VUI.Color?
                    if case let .color(value)? = style {
                        color = value
                    } else {
                        color = nil
                    }
                    records.append((
                        commandBounds
                            .applying(itemTransform)
                            .standardized,
                        role,
                        color,
                        isStroke
                    ))
                }
                switch content.value {
                case let .style(style):
                    let nested = renderedShapeRecords(in: style.contents)
                    records.append(contentsOf: applying(
                        style.transform.concatenating(itemTransform),
                        to: nested
                    ))
                case let .crossFade(crossFade):
                    if let source = crossFade.source,
                       let transform = branchTransform(
                        from: source.sourceBounds,
                        to: source.outputBounds
                       ) {
                        records.append(contentsOf: applying(
                            transform
                                .concatenating(crossFade.transform)
                                .concatenating(itemTransform),
                            to: renderedShapeRecords(in: source.contents)
                        ))
                    }
                    if let target = crossFade.target,
                       let transform = branchTransform(
                        from: target.sourceBounds,
                        to: target.outputBounds
                       ) {
                        records.append(contentsOf: applying(
                            transform
                                .concatenating(crossFade.transform)
                                .concatenating(itemTransform),
                            to: renderedShapeRecords(in: target.contents)
                        ))
                    }
                case let .flattened(contents, origin, _):
                    records.append(contentsOf: applying(
                        CGAffineTransform(
                            translationX: origin.x,
                            y: origin.y
                        ).concatenating(itemTransform),
                        to: renderedShapeRecords(in: contents)
                    ))
                case let .drawing(contents, origin, _):
                    if let local = contents as? DisplayList.LocalContents {
                        records.append(contentsOf: applying(
                            CGAffineTransform(
                                translationX: origin.x,
                                y: origin.y
                            ).concatenating(itemTransform),
                            to: renderedShapeRecords(in: local.list)
                        ))
                    }
                case .backend, .color, .shape, .image, .text:
                    break
                }
            case let .effect(effect, contents):
                let nested = renderedShapeRecords(in: contents)
                if case let .transform(projection) = effect,
                   projection.isAffine {
                    records.append(contentsOf: applying(
                        CGAffineTransform(
                            a: projection.m11,
                            b: projection.m12,
                            c: projection.m21,
                            d: projection.m22,
                            tx: projection.m31,
                            ty: projection.m32
                        ).concatenating(itemTransform),
                        to: nested
                    ))
                } else {
                    records.append(contentsOf: applying(
                        itemTransform,
                        to: nested
                    ))
                }
            case let .states(states):
                if let contents = states.last?.1 {
                    records.append(contentsOf: applying(
                        itemTransform,
                        to: renderedShapeRecords(in: contents)
                    ))
                }
            case .empty:
                break
            }
        }
    }

    private func renderedShapePresentationSamples(
        in displayList: DisplayList,
        inheritedOpacity: Double = 1
    ) -> [LayoutSchedulingShapePresentationSample] {
        func applying(
            _ transform: CGAffineTransform,
            to samples: [LayoutSchedulingShapePresentationSample]
        ) -> [LayoutSchedulingShapePresentationSample] {
            guard !transform.isIdentity else { return samples }
            return samples.map { sample in
                var sample = sample
                sample.bounds = sample.bounds
                    .applying(transform)
                    .standardized
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

        func presentationTransform(
            for item: DisplayList.Item
        ) -> CGAffineTransform {
            let recordedBounds: CGRect?
            switch item.value {
            case let .content(content):
                recordedBounds = content.command.bounds
            case .effect:
                return CGAffineTransform(
                    translationX: item.frame.minX,
                    y: item.frame.minY
                )
            case let .states(states):
                recordedBounds = states.last?.1.interpolationBounds
            case .empty:
                recordedBounds = nil
            }
            guard let recordedBounds, !recordedBounds.isNull else {
                return .identity
            }
            return CGAffineTransform(
                translationX: item.frame.minX - recordedBounds.minX,
                y: item.frame.minY - recordedBounds.minY
            )
        }

        return displayList.items.reduce(into: []) { samples, item in
            let itemOpacity = inheritedOpacity * Double(item.opacity)
            let itemTransform = presentationTransform(for: item)
            switch item.value {
            case let .content(content):
                if case let .shape(shape) = content.value,
                   case let .shape(
                    role,
                    style,
                    _,
                    _,
                    commandBounds
                   ) = shape.command,
                   let commandBounds {
                    let transformedPath = shape.path.applying(shape.transform)
                    let center = CGPoint(
                        x: commandBounds.midX,
                        y: commandBounds.midY
                    )
                    let isStroke: Bool
                    switch role {
                    case .stroke:
                        isStroke = true
                    case .fill:
                        isStroke = !transformedPath.contains(
                            center,
                            eoFill: shape.fillStyle.isEOFilled
                        )
                    case .separator:
                        isStroke = false
                    }
                    let color: VUI.Color?
                    if case let .color(value)? = style {
                        color = value
                    } else {
                        color = nil
                    }
                    samples.append(LayoutSchedulingShapePresentationSample(
                        bounds: commandBounds
                            .applying(itemTransform)
                            .standardized,
                        role: role,
                        color: color,
                        isStroke: isStroke,
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
                    let nested = renderedShapePresentationSamples(
                        in: style.contents,
                        inheritedOpacity: itemOpacity * styleOpacity
                    )
                    samples.append(contentsOf: applying(
                        style.transform.concatenating(itemTransform),
                        to: nested
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
                    if let source = crossFade.source,
                       let transform = branchTransform(
                        from: source.sourceBounds,
                        to: source.outputBounds
                       ) {
                        let nested = renderedShapePresentationSamples(
                            in: source.contents,
                            inheritedOpacity: itemOpacity * sourceOpacity
                        )
                        samples.append(contentsOf: applying(
                            transform
                                .concatenating(crossFade.transform)
                                .concatenating(itemTransform),
                            to: nested
                        ))
                    }
                    if let target = crossFade.target,
                       let transform = branchTransform(
                        from: target.sourceBounds,
                        to: target.outputBounds
                       ) {
                        let nested = renderedShapePresentationSamples(
                            in: target.contents,
                            inheritedOpacity: itemOpacity * targetOpacity
                        )
                        samples.append(contentsOf: applying(
                            transform
                                .concatenating(crossFade.transform)
                                .concatenating(itemTransform),
                            to: nested
                        ))
                    }
                case let .flattened(contents, origin, _):
                    let nested = renderedShapePresentationSamples(
                        in: contents,
                        inheritedOpacity: itemOpacity
                    )
                    samples.append(contentsOf: applying(
                        CGAffineTransform(
                            translationX: origin.x,
                            y: origin.y
                        ).concatenating(itemTransform),
                        to: nested
                    ))
                case let .drawing(contents, origin, _):
                    if let local = contents as? DisplayList.LocalContents {
                        let nested = renderedShapePresentationSamples(
                            in: local.list,
                            inheritedOpacity: itemOpacity
                        )
                        samples.append(contentsOf: applying(
                            CGAffineTransform(
                                translationX: origin.x,
                                y: origin.y
                            ).concatenating(itemTransform),
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
                let nested = renderedShapePresentationSamples(
                    in: contents,
                    inheritedOpacity: itemOpacity * effectOpacity
                )
                if case let .transform(projection) = effect,
                   projection.isAffine {
                    samples.append(contentsOf: applying(
                        CGAffineTransform(
                            a: projection.m11,
                            b: projection.m12,
                            c: projection.m21,
                            d: projection.m22,
                            tx: projection.m31,
                            ty: projection.m32
                        ).concatenating(itemTransform),
                        to: nested
                    ))
                } else {
                    samples.append(contentsOf: applying(
                        itemTransform,
                        to: nested
                    ))
                }
            case let .states(states):
                if let contents = states.last?.1 {
                    let nested = renderedShapePresentationSamples(
                        in: contents,
                        inheritedOpacity: itemOpacity
                    )
                    samples.append(contentsOf: applying(
                        itemTransform,
                        to: nested
                    ))
                }
            case .empty:
                break
            }
        }
    }

    private func shapeFillBounds(in displayList: DisplayList) -> [CGRect] {
        renderedShapeRecords(in: displayList).compactMap { record in
            guard record.role == .fill else { return nil }
            return record.bounds
        }
    }

    private func shapeStrokeBounds(in displayList: DisplayList) -> [CGRect] {
        renderedShapeRecords(in: displayList).compactMap { record in
            record.isStroke ? record.bounds : nil
        }
    }

    private func opaqueGreenShapeBounds(in displayList: DisplayList) -> [CGRect] {
        shapeFillRecords(in: displayList).compactMap { record -> CGRect? in
            guard record.color.provider.alpha >= 0.8,
                  record.color.provider.green > record.color.provider.red,
                  record.color.provider.green > record.color.provider.blue else {
                return nil
            }
            return record.bounds
        }
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

    private func closureBounds(in displayList: DisplayList) -> [CGRect] {
        var bounds = displayList.itemRecords.compactMap { record -> CGRect? in
            guard record.kind == .closure else { return nil }
            return record.bounds
        }
        for effect in displayList.effects {
            bounds.append(contentsOf: closureBounds(in: effect.contents))
        }
        return bounds
    }

    private func displayListTreeDescription(
        _ displayList: DisplayList,
        depth: Int = 0
    ) -> String {
        let prefix = String(repeating: "  ", count: depth)
        var lines: [String] = []
        for item in displayList.items {
            switch item.value {
            case let .content(content):
                let record = item.record
                let text: String? = if case let .text(text) = content.value {
                    text.view.text.storage?.string
                } else {
                    nil
                }
                lines.append(
                    "\(prefix)item kind=\(record.kind) effect=\(String(describing: record.effectKind)) text=\(String(describing: text)) frame=\(item.frame) bounds=\(String(describing: record.bounds))"
                )
            case let .effect(effect, contents):
                let label: String
                switch effect {
                case .identity:
                    label = "identity"
                case .archive:
                    label = "archive"
                case .platformGroup:
                    label = "platformGroup"
                case .opacity:
                    label = "opacity"
                case let .transform(transform):
                    label = "transform \(transform)"
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
                lines.append(
                    "\(prefix)effect \(label) frame=\(item.frame) contentsBounds=\(String(describing: contents.interpolationBounds))"
                )
                lines.append(displayListTreeDescription(
                    contents,
                    depth: depth + 1
                ))
            case let .states(states):
                lines.append("\(prefix)states frame=\(item.frame)")
                for (_, contents) in states {
                    lines.append(displayListTreeDescription(
                        contents,
                        depth: depth + 1
                    ))
                }
            case .empty:
                lines.append("\(prefix)empty frame=\(item.frame)")
            }
        }
        for debugItem in displayList.debugItems {
            lines.append(
                "\(prefix)debug frame=\(debugItem.frame) bounds=\(String(describing: debugItem.record.bounds))"
            )
        }
        return lines.joined(separator: " | ")
    }

    private func drawingContents(
        in displayList: DisplayList
    ) -> [DisplayList] {
        displayList.items.reduce(into: []) { result, item in
            switch item.value {
            case let .content(content):
                switch content.value {
                case let .style(style):
                    result.append(contentsOf: drawingContents(
                        in: style.contents
                    ))
                case let .crossFade(crossFade):
                    if let source = crossFade.source {
                        result.append(contentsOf: drawingContents(
                            in: source.contents
                        ))
                    }
                    if let target = crossFade.target {
                        result.append(contentsOf: drawingContents(
                            in: target.contents
                        ))
                    }
                case let .flattened(contents, _, _):
                    result.append(contentsOf: drawingContents(
                        in: contents
                    ))
                case let .drawing(contents, _, _):
                    if let local = contents as? DisplayList.LocalContents {
                        result.append(local.list)
                        result.append(contentsOf: drawingContents(in: local.list))
                    }
                case .backend, .color, .shape, .image, .text:
                    break
                }
            case let .effect(_, contents):
                result.append(contentsOf: drawingContents(in: contents))
            case let .states(states):
                for (_, contents) in states {
                    result.append(contentsOf: drawingContents(
                        in: contents
                    ))
                }
            case .empty:
                break
            }
        }
    }

    private func recursiveTextCommandBounds(
        in displayList: DisplayList
    ) -> [CGRect] {
        displayList.items.reduce(into: []) { result, item in
            switch item.value {
            case let .content(content):
                if case .text = content.command,
                   let bounds = content.command.bounds {
                    result.append(bounds)
                }
                switch content.value {
                case let .style(style):
                    result.append(contentsOf: recursiveTextCommandBounds(
                        in: style.contents
                    ))
                case let .crossFade(crossFade):
                    if let source = crossFade.source {
                        result.append(contentsOf: recursiveTextCommandBounds(
                            in: source.contents
                        ))
                    }
                    if let target = crossFade.target {
                        result.append(contentsOf: recursiveTextCommandBounds(
                            in: target.contents
                        ))
                    }
                case let .flattened(contents, _, _):
                    result.append(contentsOf: recursiveTextCommandBounds(
                        in: contents
                    ))
                case let .drawing(contents, _, _):
                    if let local = contents as? DisplayList.LocalContents {
                        result.append(contentsOf: recursiveTextCommandBounds(
                            in: local.list
                        ))
                    }
                case .backend, .color, .shape, .image, .text:
                    break
                }
            case let .effect(_, contents):
                result.append(contentsOf: recursiveTextCommandBounds(in: contents))
            case let .states(states):
                for (_, contents) in states {
                    result.append(contentsOf: recursiveTextCommandBounds(
                        in: contents
                    ))
                }
            case .empty:
                break
            }
        }
    }

    private func translucentShapeFillRecords(in displayList: DisplayList) -> [(bounds: CGRect, color: VUI.Color)] {
        shapeFillRecords(in: displayList).filter {
            $0.color.provider.alpha < 0.8
        }
    }

    private func renderedTranslucentShapeFillRecords(
        in displayList: DisplayList
    ) -> [(bounds: CGRect, color: VUI.Color)] {
        translucentShapeFillRecords(in: displayList)
    }

    private func renderedTextBounds(
        in displayList: DisplayList,
        matching string: String? = nil
    ) -> [CGRect] {
        func applying(
            _ transform: CGAffineTransform,
            to bounds: [CGRect]
        ) -> [CGRect] {
            guard !transform.isIdentity else { return bounds }
            return bounds.map {
                $0.applying(transform).standardized
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

        func presentationTransform(
            for item: DisplayList.Item
        ) -> CGAffineTransform {
            let recordedBounds: CGRect?
            switch item.value {
            case let .content(content):
                recordedBounds = content.command.bounds
            case .effect:
                return CGAffineTransform(
                    translationX: item.frame.minX,
                    y: item.frame.minY
                )
            case let .states(states):
                recordedBounds = states.last?.1.interpolationBounds
            case .empty:
                recordedBounds = nil
            }
            guard let recordedBounds, !recordedBounds.isNull else {
                return .identity
            }
            return CGAffineTransform(
                translationX: item.frame.minX - recordedBounds.minX,
                y: item.frame.minY - recordedBounds.minY
            )
        }

        return displayList.items.reduce(into: []) { bounds, item in
            let itemTransform = presentationTransform(for: item)
            switch item.value {
            case let .content(content):
                let matchesString: Bool
                if let string,
                   case let .text(text) = content.value {
                    matchesString = text.view.text.storage?.string == string
                } else {
                    matchesString = string == nil
                }
                if matchesString,
                   case let .text(_, commandBounds) = content.command,
                   let commandBounds {
                    bounds.append(
                        commandBounds
                            .applying(itemTransform)
                            .standardized
                    )
                }
                switch content.value {
                case let .style(style):
                    bounds.append(contentsOf: applying(
                        style.transform.concatenating(itemTransform),
                        to: renderedTextBounds(
                            in: style.contents,
                            matching: string
                        )
                    ))
                case let .crossFade(crossFade):
                    if let source = crossFade.source,
                       let transform = branchTransform(
                        from: source.sourceBounds,
                        to: source.outputBounds
                       ) {
                        bounds.append(contentsOf: applying(
                            transform
                                .concatenating(crossFade.transform)
                                .concatenating(itemTransform),
                            to: renderedTextBounds(
                                in: source.contents,
                                matching: string
                            )
                        ))
                    }
                    if let target = crossFade.target,
                       let transform = branchTransform(
                        from: target.sourceBounds,
                        to: target.outputBounds
                       ) {
                        bounds.append(contentsOf: applying(
                            transform
                                .concatenating(crossFade.transform)
                                .concatenating(itemTransform),
                            to: renderedTextBounds(
                                in: target.contents,
                                matching: string
                            )
                        ))
                    }
                case let .flattened(contents, origin, _):
                    bounds.append(contentsOf: applying(
                        CGAffineTransform(
                            translationX: origin.x,
                            y: origin.y
                        ).concatenating(itemTransform),
                        to: renderedTextBounds(
                            in: contents,
                            matching: string
                        )
                    ))
                case let .drawing(contents, origin, _):
                    if let local = contents as? DisplayList.LocalContents {
                        bounds.append(contentsOf: applying(
                            CGAffineTransform(
                                translationX: origin.x,
                                y: origin.y
                            ).concatenating(itemTransform),
                            to: renderedTextBounds(
                                in: local.list,
                                matching: string
                            )
                        ))
                    }
                case .backend, .color, .shape, .image, .text:
                    break
                }
            case let .effect(effect, contents):
                let nested = renderedTextBounds(
                    in: contents,
                    matching: string
                )
                if case let .transform(projection) = effect,
                   projection.isAffine {
                    bounds.append(contentsOf: applying(
                        CGAffineTransform(
                            a: projection.m11,
                            b: projection.m12,
                            c: projection.m21,
                            d: projection.m22,
                            tx: projection.m31,
                            ty: projection.m32
                        ).concatenating(itemTransform),
                        to: nested
                    ))
                } else {
                    bounds.append(contentsOf: applying(
                        itemTransform,
                        to: nested
                    ))
                }
            case let .states(states):
                if let contents = states.last?.1 {
                    bounds.append(contentsOf: applying(
                        itemTransform,
                        to: renderedTextBounds(
                            in: contents,
                            matching: string
                        )
                    ))
                }
            case .empty:
                break
            }
        }
    }

    private func resolvedTextSamples(
        in displayList: DisplayList,
        matching string: String,
        environment: EnvironmentValues,
        inheritedOpacity: Double = 1
    ) -> [LayoutSchedulingResolvedTextSample] {
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

        func presentationTransform(
            for item: DisplayList.Item
        ) -> CGAffineTransform {
            let recordedBounds: CGRect?
            switch item.value {
            case let .content(content):
                recordedBounds = content.command.bounds
            case .effect:
                return CGAffineTransform(
                    translationX: item.frame.minX,
                    y: item.frame.minY
                )
            case let .states(states):
                recordedBounds = states.last?.1.interpolationBounds
            case .empty:
                recordedBounds = nil
            }
            guard let recordedBounds, !recordedBounds.isNull else {
                return .identity
            }
            return CGAffineTransform(
                translationX: item.frame.minX - recordedBounds.minX,
                y: item.frame.minY - recordedBounds.minY
            )
        }

        return displayList.items.reduce(into: []) { samples, item in
            let itemOpacity = inheritedOpacity * Double(item.opacity)
            let itemTransform = presentationTransform(for: item)
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
                        frame: text.frame
                            .applying(text.transform)
                            .applying(itemTransform)
                            .standardized,
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
                    samples.append(contentsOf: applying(
                        style.transform.concatenating(itemTransform),
                        to: nested
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
                            transform
                                .concatenating(crossFade.transform)
                                .concatenating(itemTransform),
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
                            transform
                                .concatenating(crossFade.transform)
                                .concatenating(itemTransform),
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
                        CGAffineTransform(
                            translationX: origin.x,
                            y: origin.y
                        ).concatenating(itemTransform),
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
                            CGAffineTransform(
                                translationX: origin.x,
                                y: origin.y
                            ).concatenating(itemTransform),
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
                        ).concatenating(itemTransform),
                        to: nested
                    ))
                } else {
                    samples.append(contentsOf: applying(
                        itemTransform,
                        to: nested
                    ))
                }
            case let .states(states):
                if let contents = states.last?.1 {
                    let nested = renderedResolvedTextSamples(
                        in: contents,
                        matching: string,
                        environment: environment,
                        inheritedOpacity: itemOpacity
                    )
                    samples.append(contentsOf: applying(
                        itemTransform,
                        to: nested
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

    private func symbolDrawFallbackProgressSamples(
        in displayList: DisplayList
    ) -> [[Double]?] {
        var samples: [[Double]?] = []

        func collect(_ list: DisplayList) {
            for item in list.items {
                switch item.value {
                case let .content(content):
                    switch content.value {
                    case let .image(image):
                        samples.append(
                            image.image.symbolDrawFallbackProgresses
                        )
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

    private func symbolPresentationSamples(
        in displayList: DisplayList,
        inheritedOpacity: Double = 1
    ) -> [LayoutSchedulingSymbolPresentationSample] {
        func applying(
            _ transform: CGAffineTransform,
            to samples: [LayoutSchedulingSymbolPresentationSample]
        ) -> [LayoutSchedulingSymbolPresentationSample] {
            guard !transform.isIdentity else { return samples }
            return samples.map { sample in
                var sample = sample
                sample.bounds = sample.bounds
                    .applying(transform)
                    .standardized
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

        func presentationTransform(
            for item: DisplayList.Item
        ) -> CGAffineTransform {
            let recordedBounds: CGRect?
            switch item.value {
            case let .content(content):
                recordedBounds = content.command.bounds
            case .effect:
                return CGAffineTransform(
                    translationX: item.frame.minX,
                    y: item.frame.minY
                )
            case let .states(states):
                recordedBounds = states.last?.1.interpolationBounds
            case .empty:
                recordedBounds = nil
            }
            guard let recordedBounds, !recordedBounds.isNull else {
                return .identity
            }
            return CGAffineTransform(
                translationX: item.frame.minX - recordedBounds.minX,
                y: item.frame.minY - recordedBounds.minY
            )
        }

        return displayList.items.reduce(into: []) { samples, item in
            let itemOpacity = inheritedOpacity * Double(item.opacity)
            let itemTransform = presentationTransform(for: item)
            switch item.value {
            case let .content(content):
                switch content.value {
                case let .image(image):
                    let bounds = image.frame
                        .applying(image.transform)
                        .applying(itemTransform)
                        .standardized
                    if let symbol = image.image.symbol {
                        if let replacement =
                            image.image.symbolReplacementPresentation {
                            for symbolPresentation in replacement.symbols {
                                guard let symbol =
                                    symbolPresentation.image.symbol else {
                                    continue
                                }
                                for values in symbolPresentation.levels
                                    where values.opacity > 0 {
                                    samples.append(
                                        LayoutSchedulingSymbolPresentationSample(
                                            name: symbol.identity.name,
                                            opacity: itemOpacity *
                                                values.opacity,
                                            drawProgresses: symbolPresentation
                                                .drawProgresses,
                                            bounds: bounds
                                        )
                                    )
                                }
                            }
                        } else {
                            samples.append(
                                LayoutSchedulingSymbolPresentationSample(
                                    name: symbol.identity.name,
                                    opacity: itemOpacity,
                                    drawProgresses:
                                        image.image.symbolDrawProgresses,
                                    bounds: bounds
                                )
                            )
                        }
                    }
                case let .style(style):
                    let styleOpacity: Double
                    if case let .opacity(opacity) = style.style {
                        styleOpacity = opacity
                    } else {
                        styleOpacity = 1
                    }
                    let nested = symbolPresentationSamples(
                        in: style.contents,
                        inheritedOpacity: itemOpacity * styleOpacity
                    )
                    samples.append(contentsOf: applying(
                        style.transform.concatenating(itemTransform),
                        to: nested
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
                    if let source = crossFade.source,
                       let transform = branchTransform(
                        from: source.sourceBounds,
                        to: source.outputBounds
                       ) {
                        let nested = symbolPresentationSamples(
                            in: source.contents,
                            inheritedOpacity: itemOpacity * sourceOpacity
                        )
                        samples.append(contentsOf: applying(
                            transform
                                .concatenating(crossFade.transform)
                                .concatenating(itemTransform),
                            to: nested
                        ))
                    }
                    if let target = crossFade.target,
                       let transform = branchTransform(
                        from: target.sourceBounds,
                        to: target.outputBounds
                       ) {
                        let nested = symbolPresentationSamples(
                            in: target.contents,
                            inheritedOpacity: itemOpacity * targetOpacity
                        )
                        samples.append(contentsOf: applying(
                            transform
                                .concatenating(crossFade.transform)
                                .concatenating(itemTransform),
                            to: nested
                        ))
                    }
                case let .flattened(contents, origin, _):
                    let nested = symbolPresentationSamples(
                        in: contents,
                        inheritedOpacity: itemOpacity
                    )
                    samples.append(contentsOf: applying(
                        CGAffineTransform(
                            translationX: origin.x,
                            y: origin.y
                        ).concatenating(itemTransform),
                        to: nested
                    ))
                case let .drawing(contents, origin, _):
                    if let local = contents as? DisplayList.LocalContents {
                        let nested = symbolPresentationSamples(
                            in: local.list,
                            inheritedOpacity: itemOpacity
                        )
                        samples.append(contentsOf: applying(
                            CGAffineTransform(
                                translationX: origin.x,
                                y: origin.y
                            ).concatenating(itemTransform),
                            to: nested
                        ))
                    }
                case .backend,
                     .color,
                     .shape,
                     .text:
                    break
                }
            case let .effect(effect, contents):
                let effectOpacity: Double
                if case let .opacity(opacity) = effect {
                    effectOpacity = Double(opacity)
                } else {
                    effectOpacity = 1
                }
                let nested = symbolPresentationSamples(
                    in: contents,
                    inheritedOpacity: itemOpacity * effectOpacity
                )
                if case let .transform(projection) = effect,
                   projection.isAffine {
                    samples.append(contentsOf: applying(
                        CGAffineTransform(
                            a: projection.m11,
                            b: projection.m12,
                            c: projection.m21,
                            d: projection.m22,
                            tx: projection.m31,
                            ty: projection.m32
                        ).concatenating(itemTransform),
                        to: nested
                    ))
                } else {
                    samples.append(contentsOf: applying(
                        itemTransform,
                        to: nested
                    ))
                }
            case let .states(states):
                if let contents = states.last?.1 {
                    let nested = symbolPresentationSamples(
                        in: contents,
                        inheritedOpacity: itemOpacity
                    )
                    samples.append(contentsOf: applying(
                        itemTransform,
                        to: nested
                    ))
                }
            case .empty:
                break
            }
        }
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
        renderedShapeRecords(in: displayList).compactMap { record in
            guard record.role == .fill,
                  let color = record.color else {
                return nil
            }
            return (record.bounds, color)
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

private struct LayoutMeasurementCounts: Equatable, AdditiveArithmetic {
    var makeCache = 0
    var updateCache = 0
    var sizeThatFits = 0
    var placeSubviews = 0
    var leafSizeThatFits = 0
    var leafPlaceSubviews = 0

    static func + (
        lhs: LayoutMeasurementCounts,
        rhs: LayoutMeasurementCounts
    ) -> LayoutMeasurementCounts {
        LayoutMeasurementCounts(
            makeCache: lhs.makeCache + rhs.makeCache,
            updateCache: lhs.updateCache + rhs.updateCache,
            sizeThatFits: lhs.sizeThatFits + rhs.sizeThatFits,
            placeSubviews: lhs.placeSubviews + rhs.placeSubviews,
            leafSizeThatFits: lhs.leafSizeThatFits + rhs.leafSizeThatFits,
            leafPlaceSubviews: lhs.leafPlaceSubviews + rhs.leafPlaceSubviews
        )
    }

    static func - (
        lhs: LayoutMeasurementCounts,
        rhs: LayoutMeasurementCounts
    ) -> LayoutMeasurementCounts {
        LayoutMeasurementCounts(
            makeCache: lhs.makeCache - rhs.makeCache,
            updateCache: lhs.updateCache - rhs.updateCache,
            sizeThatFits: lhs.sizeThatFits - rhs.sizeThatFits,
            placeSubviews: lhs.placeSubviews - rhs.placeSubviews,
            leafSizeThatFits: lhs.leafSizeThatFits - rhs.leafSizeThatFits,
            leafPlaceSubviews: lhs.leafPlaceSubviews - rhs.leafPlaceSubviews
        )
    }

    static let zero = LayoutMeasurementCounts()
}

private final class LayoutMeasurementCounter: @unchecked Sendable {
    var counts = LayoutMeasurementCounts()

    func snapshot() -> LayoutMeasurementCounts {
        counts
    }
}

private final class LayoutMeasurementScrollGeometryProbe: @unchecked Sendable {
    var offsets: [CGPoint] = []
}

private final class LayoutMeasurementProbe {
    var toggleVisual: (() -> Void)?
    var changeLayoutValue: (() -> Void)?
}

private final class LayoutMeasurementCache: @unchecked Sendable {}

private struct LayoutMeasurementContainer: Layout {
    let counter: LayoutMeasurementCounter
    var revision: Int

    func makeCache(subviews: Subviews) -> LayoutMeasurementCache {
        counter.counts.makeCache += 1
        return LayoutMeasurementCache()
    }

    func updateCache(
        _ cache: inout LayoutMeasurementCache,
        subviews: Subviews
    ) {
        counter.counts.updateCache += 1
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout LayoutMeasurementCache
    ) -> CGSize {
        counter.counts.sizeThatFits += 1
        var result = CGSize.zero
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            result.width = max(result.width, size.width)
            result.height += size.height
        }
        return result
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout LayoutMeasurementCache
    ) {
        counter.counts.placeSubviews += 1
        var y = bounds.minY
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            subview.place(
                at: CGPoint(x: bounds.minX, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(size)
            )
            y += size.height
        }
    }
}

private struct LayoutMeasurementLeaf: Layout {
    let counter: LayoutMeasurementCounter
    let size: CGSize

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        counter.counts.leafSizeThatFits += 1
        return size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        counter.counts.leafPlaceSubviews += 1
    }
}

private struct LayoutMeasurementRoot: View {
    let counter: LayoutMeasurementCounter
    let probe: LayoutMeasurementProbe
    @State private var visualToggle = false
    @State private var revision = 0

    var body: some View {
        probe.toggleVisual = {
            visualToggle.toggle()
        }
        probe.changeLayoutValue = {
            revision += 1
        }
        return LayoutMeasurementContainer(
            counter: counter,
            revision: revision
        ) {
            LayoutMeasurementLeaf(
                counter: counter,
                size: CGSize(width: 44, height: 18)
            ) {
                Color.clear
            }
            LayoutMeasurementLeaf(
                counter: counter,
                size: CGSize(width: 52, height: 20)
            ) {
                Color.clear
            }
        }
        .frame(width: 120, height: 120, alignment: .topLeading)
        .background(visualToggle ? Color.blue.opacity(0.08) : Color.clear)
        .frame(width: 320, height: 180, alignment: .topLeading)
    }
}

private struct LayoutMeasurementScrollRoot: View {
    let counter: LayoutMeasurementCounter
    let geometryProbe: LayoutMeasurementScrollGeometryProbe

    var body: some View {
        ScrollView(.vertical) {
            LayoutMeasurementContainer(counter: counter, revision: 0) {
                ForEach(0..<36, id: \.self) { _ in
                    LayoutMeasurementLeaf(
                        counter: counter,
                        size: CGSize(width: 160, height: 30)
                    ) {
                        Text(verbatim: "Row")
                    }
                }
            }
        }
        .frame(width: 180, height: 140)
        .onScrollGeometryChange(for: CGPoint.self) { geometry in
            geometry.contentOffset
        } action: { _, newValue in
            geometryProbe.offsets.append(newValue)
        }
    }
}

private struct LayoutSchedulingLazyScrollGeometry: Equatable {
    var contentOffset = CGPoint.zero
    var contentSize = CGSize.zero
    var containerSize = CGSize.zero
    var visibleRect = CGRect.zero

    init() {}

    init(_ geometry: ScrollGeometry) {
        contentOffset = geometry.contentOffset
        contentSize = geometry.contentSize
        containerSize = geometry.containerSize
        visibleRect = geometry.visibleRect
    }
}

private final class LayoutSchedulingLazyScrollObserverProbe: @unchecked Sendable {
    var geometryActions: [LayoutSchedulingLazyScrollGeometry] = []
    var phases: [ScrollPhase] = []
    var phaseGeometries: [LayoutSchedulingLazyScrollGeometry] = []
    var renderedGeometry = LayoutSchedulingLazyScrollGeometry()
}

private struct LayoutSchedulingLazyScrollObserverRoot: View {
    let probe: LayoutSchedulingLazyScrollObserverProbe
    var itemCount = 120
    @State private var geometry = LayoutSchedulingLazyScrollGeometry()
    @State private var phase = ScrollPhase.idle

    var body: some View {
        probe.renderedGeometry = geometry
        return VStack(spacing: 8) {
            Text(
                verbatim: "phase \(phase.debugDescription) offset \(geometry.contentOffset.y) "
                    + "content \(geometry.contentSize.height)"
            )
            ScrollView(.vertical) {
                LazyVStack(spacing: 7) {
                    ForEach(0..<itemCount, id: \.self) { row in
                        VStack(spacing: 5) {
                            Text(verbatim: "row \(row)")
                            if row == 4 {
                                ScrollView(.horizontal) {
                                    HStack(spacing: 6) {
                                        ForEach(0..<24, id: \.self) { column in
                                            Text(verbatim: "nested \(column)")
                                                .frame(width: 88, height: 32)
                                        }
                                    }
                                }
                                .frame(width: 520, height: 52)
                            }
                        }
                            .frame(
                                width: 640,
                                height: row == 4 ? 108 : (row.isMultiple(of: 9) ? 58 : 38),
                                alignment: .leading
                            )
                            .id(row)
                    }
                }
            }
            .frame(width: 700, height: 360)
            .onScrollGeometryChange(for: LayoutSchedulingLazyScrollGeometry.self) { geometry in
                LayoutSchedulingLazyScrollGeometry(geometry)
            } action: { _, newValue in
                geometry = newValue
                probe.geometryActions.append(newValue)
            }
            .onScrollPhaseChange { _, newPhase, context in
                phase = newPhase
                geometry = LayoutSchedulingLazyScrollGeometry(context.geometry)
                probe.phases.append(newPhase)
                probe.phaseGeometries.append(LayoutSchedulingLazyScrollGeometry(context.geometry))
            }
        }
    }
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

private struct LayoutSchedulingScrollViewAttachmentRoot: View {
    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 0) {
                ForEach(0..<8, id: \.self) { _ in
                    Color.green
                        .frame(width: 80, height: 40)
                }
            }
        }
        .frame(width: 100, height: 100)
    }
}

private final class LayoutSchedulingScrollViewReaderProbe {
    var proxy: ScrollViewProxy?
}

private struct LayoutSchedulingScrollViewReaderRoot: View {
    let probe: LayoutSchedulingScrollViewReaderProbe

    var body: some View {
        ScrollViewReader { proxy in
            LayoutSchedulingScrollViewReaderContent(
                proxy: proxy,
                probe: probe
            )
        }
    }
}

private struct LayoutSchedulingScrollViewReaderContent: View {
    let proxy: ScrollViewProxy
    let probe: LayoutSchedulingScrollViewReaderProbe

    var body: some View {
        probe.proxy = proxy
        return ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(0..<200, id: \.self) { row in
                    (row == 150 ? Color.red : Color.green)
                        .frame(width: 80, height: 20)
                        .id(row)
                }
            }
        }
        .frame(width: 100, height: 100)
    }
}

private struct LayoutSchedulingTextScrollViewReaderRoot: View {
    let probe: LayoutSchedulingScrollViewReaderProbe

    var body: some View {
        ScrollViewReader { proxy in
            LayoutSchedulingTextScrollViewReaderContent(
                proxy: proxy,
                probe: probe
            )
        }
    }
}

private struct LayoutSchedulingTextScrollViewReaderContent: View {
    let proxy: ScrollViewProxy
    let probe: LayoutSchedulingScrollViewReaderProbe

    var body: some View {
        probe.proxy = proxy
        return ScrollView(.vertical) {
            LazyVStack(spacing: 4) {
                ForEach(0..<200, id: \.self) { row in
                    Text("Row \(row)")
                        .frame(width: 280, height: 30, alignment: .leading)
                        .id(row)
                }
            }
        }
        .frame(width: 300, height: 260)
    }
}

private final class LayoutSchedulingButtonScrollViewReaderProbe {
    var actionCount = 0
    var actionHadNoGraphContext = false
    var proxy: ScrollViewProxy?
}

private struct LayoutSchedulingButtonScrollViewReaderRoot: View {
    let probe: LayoutSchedulingButtonScrollViewReaderProbe

    var body: some View {
        ScrollViewReader { proxy in
            probe.proxy = proxy
            return ZStack {
                ScrollView(.vertical) {
                    LazyVStack(spacing: 4) {
                        ForEach(0..<200, id: \.self) { row in
                            Text("Row \(row)")
                                .frame(
                                    width: 280,
                                    height: 30,
                                    alignment: .leading
                                )
                                .id(row)
                        }
                    }
                }
                .frame(width: 300, height: 260)

                Button("Scroll to row 150") {
                    probe.actionCount += 1
                    probe.actionHadNoGraphContext = _AGGraph.current == nil
                    proxy.scrollTo(150, anchor: .top)
                }
                .frame(width: 520, height: 470)
            }
        }
    }
}

private final class LayoutSchedulingStatefulScrollViewReaderProbe {
    var action: (() -> Void)?
}

private struct LayoutSchedulingStatefulScrollViewReaderRoot: View {
    let probe: LayoutSchedulingStatefulScrollViewReaderProbe

    var body: some View {
        ScrollViewReader { proxy in
            LayoutSchedulingStatefulScrollViewReaderContent(
                proxy: proxy,
                probe: probe
            )
        }
    }
}

private struct LayoutSchedulingStatefulScrollViewReaderContent: View {
    let proxy: ScrollViewProxy
    let probe: LayoutSchedulingStatefulScrollViewReaderProbe

    @State private var lastRequest = "none"
    @State private var contentOffset = CGPoint.zero

    var body: some View {
        probe.action = {
            lastRequest = "150 / top"
            proxy.scrollTo(150, anchor: .top)
        }
        return VStack(spacing: 12) {
            Text("ScrollView Reader")
                .font(.system(size: 22, weight: .semibold))
            HStack(spacing: 10) {
                Button("Row 0") {
                    lastRequest = "0 / top"
                    proxy.scrollTo(0, anchor: .top)
                }
                Button("Row 75") {
                    lastRequest = "75 / center"
                    proxy.scrollTo(75, anchor: .center)
                }
                Button("Row 150") {
                    lastRequest = "150 / top"
                    proxy.scrollTo(150, anchor: .top)
                }
            }
            Text("Request: \(lastRequest), offset: \(Int(contentOffset.y))")
                .font(.system(.caption))
                .foregroundColor(.secondary)
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(0..<200, id: \.self) { row in
                        Text("Row \(row)")
                            .frame(
                                width: 280,
                                height: 30,
                                alignment: .leading
                            )
                            .border(row == 150 ? .blue : .gray, width: 1)
                            .id(row)
                    }
                }
            }
            .frame(width: 300, height: 260)
            .onScrollGeometryChange(for: CGPoint.self) { geometry in
                geometry.contentOffset
            } action: { _, newValue in
                contentOffset = newValue
            }
        }
        .padding(20)
        .frame(width: 520, height: 470)
    }
}

private final class LayoutSchedulingSiblingGridReaderProbe {
    var plainProxy: ScrollViewProxy?
    var sectionProxy: ScrollViewProxy?
}

private struct LayoutSchedulingSectionGridTargetID: Hashable {
    var section: Int
    var row: Int
}

private struct LayoutSchedulingSiblingGridReaderConfiguration {
    var columnCount: Int = 2
    var sectionCount: Int = 10
    var rowsPerSection: Int = 20
    var rowHeight: CGFloat = 20
    var headerHeight: CGFloat = 10
    var viewportWidth: CGFloat = 100
    var viewportHeight: CGFloat = 100
}

private struct LayoutSchedulingSiblingGridReaderRoot: View {
    let probe: LayoutSchedulingSiblingGridReaderProbe
    var configuration = LayoutSchedulingSiblingGridReaderConfiguration()

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.fixed(40), spacing: 0),
            count: configuration.columnCount
        )
    }

    var body: some View {
        VStack(spacing: 20) {
            ScrollViewReader { proxy in
                probe.plainProxy = proxy
                return ScrollView(.vertical) {
                    LazyVGrid(columns: columns, spacing: 0) {
                        ForEach(0..<200, id: \.self) { row in
                            Color.green
                                .frame(width: 40, height: 20)
                                .id(row)
                        }
                    }
                }
                .frame(
                    width: configuration.viewportWidth,
                    height: configuration.viewportHeight
                )
            }
            ScrollViewReader { proxy in
                probe.sectionProxy = proxy
                return ScrollView(.vertical) {
                    LazyVGrid(columns: columns, spacing: 0) {
                        ForEach(0..<configuration.sectionCount, id: \.self) { section in
                            Section {
                                ForEach(0..<configuration.rowsPerSection, id: \.self) { row in
                                    Color.green
                                        .frame(width: 40, height: configuration.rowHeight)
                                        .id(LayoutSchedulingSectionGridTargetID(
                                            section: section,
                                            row: row
                                        ))
                                }
                            } header: {
                                Color.blue
                                    .frame(
                                        width: 40 * CGFloat(configuration.columnCount),
                                        height: configuration.headerHeight
                                    )
                            }
                        }
                    }
                }
                .frame(
                    width: configuration.viewportWidth,
                    height: configuration.viewportHeight
                )
            }
        }
        .padding(20)
    }
}

private final class LayoutSchedulingScrollPhaseProbe: @unchecked Sendable {
    var changes: [(old: ScrollPhase, new: ScrollPhase, velocity: CGVector?)] = []
}

private struct LayoutSchedulingPhasedWheelRoot: View {
    let probe: LayoutSchedulingScrollPhaseProbe

    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 0) {
                ForEach(0..<8, id: \.self) { _ in
                    Color.green
                        .frame(width: 80, height: 40)
                }
            }
        }
        .onScrollPhaseChange { oldPhase, newPhase, context in
            probe.changes.append((oldPhase, newPhase, context.velocity))
        }
        .frame(width: 100, height: 100)
    }
}

private final class LayoutSchedulingScrollGestureArbitrationProbe:
    @unchecked Sendable {
    var pressing: [Bool] = []
    var actions = 0
    var dragChanges = 0
}

private struct LayoutSchedulingScrollButtonArbitrationRoot: View {
    let probe: LayoutSchedulingScrollGestureArbitrationProbe

    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 0) {
                Color.green
                    .frame(width: 80, height: 80)
                    ._onButtonGesture(
                        pressing: { probe.pressing.append($0) },
                        perform: { probe.actions += 1 }
                    )
                Color.blue
                    .frame(width: 80, height: 240)
            }
        }
        .frame(width: 100, height: 100)
    }
}

private struct LayoutSchedulingScrollDragArbitrationRoot: View {
    let probe: LayoutSchedulingScrollGestureArbitrationProbe

    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 0) {
                Color.green
                    .frame(width: 80, height: 80)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { _ in probe.dragChanges += 1 }
                    )
                Color.blue
                    .frame(width: 80, height: 240)
            }
        }
        .frame(width: 100, height: 100)
    }
}

private struct LayoutSchedulingScrollSimultaneousDragArbitrationRoot: View {
    let probe: LayoutSchedulingScrollGestureArbitrationProbe

    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 0) {
                Color.green
                    .frame(width: 80, height: 80)
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { _ in probe.dragChanges += 1 }
                    )
                Color.blue
                    .frame(width: 80, height: 240)
            }
        }
        .frame(width: 100, height: 100)
    }
}

private struct LayoutSchedulingTransformedScrollViewAttachmentRoot: View {
    var body: some View {
        LayoutSchedulingScrollViewAttachmentRoot()
            .scaleEffect(
                CGSize(width: 1.5, height: 1.5),
                anchor: .topLeading
            )
    }
}

private struct LayoutSchedulingNestedScrollViewAttachmentRoot: View {
    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 0) {
                ScrollView(.vertical) {
                    VStack(spacing: 0) {
                        ForEach(0..<8, id: \.self) { _ in
                            Color.green
                                .frame(width: 80, height: 30)
                        }
                    }
                }
                .frame(width: 100, height: 100)

                Color.blue
                    .frame(width: 100, height: 220)
            }
        }
        .frame(width: 120, height: 140)
    }
}

private struct LayoutSchedulingOrthogonalNestedScrollViewAttachmentRoot: View {
    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 0) {
                ScrollView(.horizontal) {
                    HStack(spacing: 0) {
                        ForEach(0..<8, id: \.self) { _ in
                            Color.green
                                .frame(width: 30, height: 80)
                        }
                    }
                }
                .frame(width: 100, height: 100)

                Color.blue
                    .frame(width: 100, height: 220)
            }
        }
        .frame(width: 120, height: 140)
    }
}

private func firstHostingScrollViewResponder(
    in responder: ViewResponder
) -> HostingScrollViewResponder? {
    if let responder = responder as? HostingScrollViewResponder {
        return responder
    }
    for child in responder.children {
        if let match = firstHostingScrollViewResponder(in: child) {
            return match
        }
    }
    return nil
}

private final class LayoutSchedulingNonPlatformHitTestProbe: ViewResponder {
    private(set) var containsCallCount = 0

    override func containsGlobalPoints(
        _ points: [CGPoint],
        cacheKey: UInt32?,
        options: ViewResponder.ContainsPointsOptions
    ) -> ViewResponder.ContainsPointsResult {
        containsCallCount += 1
        return .stop
    }
}

private final class LayoutSchedulingPlatformEventConsumerProbe:
    MultiViewResponder,
    ResponderEventConsumer {
    private(set) var containsCallCount = 0

    override var features: ViewResponder.Features {
        super.features.union(.platformViews)
    }

    override func containsGlobalPoints(
        _ points: [CGPoint],
        cacheKey: UInt32?,
        options: ViewResponder.ContainsPointsOptions
    ) -> ViewResponder.ContainsPointsResult {
        containsCallCount += 1
        var mask = BitVector64()
        if !points.isEmpty {
            mask[0] = true
        }
        return ViewResponder.ContainsPointsResult(
            mask: mask,
            priority: 1,
            children: children
        )
    }

    func acceptsEventType(_ eventType: Any.Type) -> Bool {
        eventType == SystemWheelEvent.self
    }

    func consumeEvents(
        _ events: [EventID: any EventType],
        at time: Time
    ) -> GesturePhase<Void> {
        .possible(nil)
    }
}

private final class LayoutSchedulingScrollEventConsumerProbe:
    MultiViewResponder,
    ResponderEventConsumer {
    private(set) var consumeCallCount = 0

    override var features: ViewResponder.Features {
        super.features.union(.platformViews)
    }

    override func containsGlobalPoints(
        _ points: [CGPoint],
        cacheKey: UInt32?,
        options: ViewResponder.ContainsPointsOptions
    ) -> ViewResponder.ContainsPointsResult {
        var mask = BitVector64()
        if !points.isEmpty {
            mask[0] = true
        }
        return ViewResponder.ContainsPointsResult(
            mask: mask,
            priority: 1,
            children: children
        )
    }

    func acceptsEventType(_ eventType: Any.Type) -> Bool {
        eventType == ScrollEvent.self
    }

    func consumeEvents(
        _ events: [EventID: any EventType],
        at time: Time
    ) -> GesturePhase<Void> {
        consumeCallCount += 1
        return .active(())
    }
}

private final class LayoutSchedulingExclusiveEventConsumerProbe:
    MultiViewResponder,
    ExclusiveResponderEventConsumer {
    private(set) var receivedEventIDs: [EventID] = []

    override var features: ViewResponder.Features {
        super.features.union(.platformViews)
    }

    override func containsGlobalPoints(
        _ points: [CGPoint],
        cacheKey: UInt32?,
        options: ViewResponder.ContainsPointsOptions
    ) -> ViewResponder.ContainsPointsResult {
        var mask = BitVector64()
        if !points.isEmpty {
            mask[0] = true
        }
        return ViewResponder.ContainsPointsResult(
            mask: mask,
            priority: 1,
            children: children
        )
    }

    func acceptsEventType(_ eventType: Any.Type) -> Bool {
        eventType == VUI.MouseEvent.self
    }

    func exclusivelyConsumes(_ event: any EventType) -> Bool {
        guard let event = event as? VUI.MouseEvent else { return false }
        return event.button == .primary
    }

    func consumeEvents(
        _ events: [EventID: any EventType],
        at time: Time
    ) -> GesturePhase<Void> {
        receivedEventIDs.append(contentsOf: events.keys)
        receivedEventIDs.sort { $0.serial < $1.serial }
        return .active(())
    }
}

private func allHostingScrollViewResponders(
    in responder: ViewResponder
) -> [HostingScrollViewResponder] {
    var result: [HostingScrollViewResponder] = []
    if let responder = responder as? HostingScrollViewResponder {
        result.append(responder)
    }
    for child in responder.children {
        result.append(contentsOf: allHostingScrollViewResponders(in: child))
    }
    return result
}

private func firstGesturePanStart(
    in root: MultiViewResponder,
    descendantOf host: HostingScrollViewResponder,
    movement: CGSize,
    size: CGSize
) -> CGPoint? {
    func descendantGestureIDs(at point: CGPoint) -> Set<ObjectIdentifier> {
        Set(root.respondersContaining(point: point).compactMap { responder in
            guard responder is any AnyGestureResponder,
                  responder.isDescendant(of: host) else {
                return nil
            }
            return ObjectIdentifier(responder)
        })
    }

    for y in stride(from: CGFloat(2), to: size.height - 2, by: 2) {
        for x in stride(from: CGFloat(2), to: size.width - 2, by: 2) {
            let start = CGPoint(x: x, y: y)
            let moved = CGPoint(
                x: x + movement.width,
                y: y + movement.height
            )
            guard moved.x >= 0, moved.y >= 0,
                  moved.x < size.width, moved.y < size.height else {
                continue
            }
            let startIDs = descendantGestureIDs(at: start)
            guard !startIDs.isEmpty else { continue }
            if !startIDs.isDisjoint(with: descendantGestureIDs(at: moved)) {
                return start
            }
        }
    }
    return nil
}

private func sampledHitBounds(
    of responder: HostingScrollViewResponder,
    in size: CGSize
) -> CGRect? {
    var points: [CGPoint] = []
    for y in stride(from: CGFloat(1), to: size.height, by: 2) {
        for x in stride(from: CGFloat(1), to: size.width, by: 2) {
            let point = CGPoint(x: x, y: y)
            let result = responder.containsGlobalPoints(
                [point],
                cacheKey: nil,
                options: .platformDefault
            )
            if result.mask[0] {
                points.append(point)
            }
        }
    }
    guard let first = points.first else { return nil }
    return points.dropFirst().reduce(
        CGRect(origin: first, size: .zero)
    ) { bounds, point in
        bounds.union(CGRect(origin: point, size: .zero))
    }
}

private func firstCommonHitPoint(
    for responders: [HostingScrollViewResponder],
    in size: CGSize
) -> CGPoint? {
    for y in stride(from: CGFloat(2), to: size.height, by: 4) {
        for x in stride(from: CGFloat(2), to: size.width, by: 4) {
            let point = CGPoint(x: x, y: y)
            if responders.allSatisfy({ responder in
                responder.containsGlobalPoints(
                    [point],
                    cacheKey: nil,
                    options: .platformDefault
                ).mask[0]
            }) {
                return point
            }
        }
    }
    return nil
}

private func firstExclusiveHitPoint(
    in responder: HostingScrollViewResponder,
    excluding other: HostingScrollViewResponder,
    size: CGSize
) -> CGPoint? {
    for y in stride(from: CGFloat(1), to: size.height, by: 2) {
        for x in stride(from: CGFloat(1), to: size.width, by: 2) {
            let point = CGPoint(x: x, y: y)
            let responderHit = responder.containsGlobalPoints(
                [point],
                cacheKey: nil,
                options: .platformDefault
            ).mask[0]
            let otherHit = other.containsGlobalPoints(
                [point],
                cacheKey: nil,
                options: .platformDefault
            ).mask[0]
            if responderHit && !otherHit {
                return point
            }
        }
    }
    return nil
}

private struct LayoutSchedulingLazyScrollViewAttachmentRoot: View {
    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(0..<120, id: \.self) { _ in
                    Color.green
                        .frame(width: 80, height: 40)
                }
            }
        }
        .frame(width: 100, height: 100)
    }
}

private final class LayoutSchedulingLazyScrollReplacementProbe {
    var toggle: (() -> Void)?
}

private struct LayoutSchedulingLazyScrollReplacementRoot: View {
    let probe: LayoutSchedulingLazyScrollReplacementProbe
    @State private var usesLazyContent = false

    var body: some View {
        probe.toggle = {
            usesLazyContent.toggle()
        }
        return ScrollView(.vertical) {
            if usesLazyContent {
                LazyVStack(spacing: 0) {
                    ForEach(0..<120, id: \.self) { _ in
                        Color.green
                            .frame(width: 80, height: 40)
                    }
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(0..<8, id: \.self) { _ in
                        Color.blue
                            .frame(width: 80, height: 40)
                    }
                }
            }
        }
        .frame(width: 100, height: 100)
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

private final class LayoutSchedulingAnimationProbe: @unchecked Sendable {
    var toggle: (() -> Void)?
    var plainTextChange: (() -> Void)?
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

private struct LayoutSchedulingSymbolPresentationSample: CustomStringConvertible {
    var name: String
    var opacity: Double
    var drawProgresses: [Double]?
    var bounds: CGRect

    var description: String {
        "\(name)(opacity: \(opacity), draw: \(String(describing: drawProgresses)), bounds: \(bounds))"
    }
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
            value: testLayoutComputer(sizeThatFits: { _ in .zero })
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

private struct LayoutSchedulingCustomCompletionStatusRoot: View {
    let counter: LayoutSchedulingCounter
    let probe: LayoutSchedulingAnimationProbe
    @State private var expanded = false
    @State private var runCount = 0
    @State private var status = "idle"

    var body: some View {
        probe.toggle = {
            let nextRun = runCount + 1
            runCount = nextRun
            status = "running"
            withAnimation(
                Animation(UnitLinearAnimation(duration: 2)),
                completionCriteria: .logicallyComplete
            ) {
                expanded.toggle()
            } completion: {
                status = "logical completion"
                probe.completions.append(nextRun)
            }
        }
        return LayoutSchedulingPassThroughLayout(counter: counter) {
            VStack(spacing: 12) {
                LayoutSchedulingRawTextMarker(
                    size: CGSize(
                        width: expanded ? 190 : 85,
                        height: expanded ? 105 : 70
                    )
                )

                LayoutSchedulingEnvironmentTextMarker(
                    content: LayoutSchedulingTextContent(value: status),
                    size: CGSize(
                        width: status == "logical completion" ? 112 : 48,
                        height: 12
                    )
                )
            }
            .frame(width: 240, height: 210)
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

private struct LayoutSchedulingAnimatedThenPlainStatusRoot: View {
    let probe: LayoutSchedulingAnimationProbe
    let font: VUI.Font
    @State private var status = "idle"

    var body: some View {
        probe.toggle = {
            withAnimation(.easeInOut(duration: 3.0)) {
                status = "explicitly animated status"
            }
        }
        probe.plainTextChange = {
            status = "plain status after explicit animation"
        }
        return Text(status)
            .font(font)
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

private struct LayoutSchedulingLabButtonGlyphAlignmentRoot: View {
    @State private var enabled = true

    var body: some View {
        HStack(spacing: 20) {
            contentViewSurface
            contentTransitionSurface
        }
        .frame(width: 1400, height: 760)
    }

    private var contentViewSurface: some View {
        VStack(spacing: 14) {
            Text(verbatim: "TestApp1 Labs")
                .font(.system(size: 24, weight: .semibold))
            Text(verbatim: "Open a focused smoke surface. New parity work can add another category here.")
                .font(.system(.callout))
                .foregroundColor(.secondary)

            VStack(spacing: 10) {
                Toggle(
                    "Open Labs in Platform Windows",
                    isOn: $enabled
                )
                Text(verbatim: "Animation Comparison")
                    .font(.system(.headline))
                HStack(spacing: 10) {
                    categoryButton("Animation Lab")
                    categoryButton("Symbol Effects")
                    categoryButton("Keyframe & Phase")
                    categoryButton("Matched Geometry")
                }
                HStack(spacing: 10) {
                    categoryButton("Content Transition")
                    categoryButton("Timeline")
                    categoryButton("Visual Effect & Mesh")
                    categoryButton("Custom Animation")
                }
                Text(verbatim: "Other Labs")
                    .font(.system(.headline))
                HStack(spacing: 10) {
                    categoryButton("Context Menus")
                    categoryButton("Modals & Popups")
                    categoryButton("Images")
                    categoryButton("Text Variants")
                }
                categoryButton("ScrollView Reader")
            }

            Divider()
            Text(verbatim: "Top-Level Presentation Tests")
                .font(.system(.headline))
            Button("Open Top-Level Sheet", action: {})
            HStack(spacing: 10) {
                Button("Top-Level Alert", action: {})
                Button("Top-Level Data Alert", action: {})
                Button("Top-Level Error Alert", action: {})
            }
            Text(verbatim: "Result: none")
                .font(.system(.caption))
                .foregroundColor(.secondary)
        }
        .padding(24)
        .frame(width: 680, height: 650)
    }

    private var contentTransitionSurface: some View {
        VStack(spacing: 24) {
            Text(verbatim: "Content & View Transition Lab")
                .font(.system(size: 22, weight: .semibold))
            HStack(spacing: 70) {
                VStack(spacing: 12) {
                    Text(verbatim: "Numeric Text")
                        .font(.system(.headline))
                    Text(verbatim: "0")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                    Button("Increment", action: {})
                }
                .frame(width: 200)
                VStack(spacing: 12) {
                    Text(verbatim: "Interpolate")
                        .font(.system(.headline))
                    Text(verbatim: "Compact")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.blue)
                    Button("Change Text", action: {})
                }
                .frame(width: 240)
            }
            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.secondary.opacity(0.35), lineWidth: 1)
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.green)
                    .frame(width: 180, height: 82)
                    .overlay {
                        Text(verbatim: "Transitioned view")
                            .font(.system(.headline))
                            .foregroundColor(.white)
                    }
            }
            .frame(width: 430, height: 125)
            Button("Remove View", action: {})
            Text(verbatim: "Compare numeric direction, interpolated glyph/style changes, retained removal, asymmetric motion, and final layout.")
                .font(.system(.caption))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button("Close", action: {})
        }
        .padding(24)
        .frame(width: 680, height: 540)
    }

    private func categoryButton(_ title: String) -> some View {
        Button(title, action: {})
            .frame(width: 145)
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

private struct LayoutSchedulingRapidContentTextRoot: View {
    let probe: LayoutSchedulingAnimationProbe
    @State private var alternateText = false

    var body: some View {
        probe.toggle = {
            withAnimation(.easeInOut(duration: 1.4)) {
                alternateText.toggle()
            }
        }
        return VStack(spacing: 12) {
            Text("Interpolate")
                .font(.system(.headline))
            Text(alternateText ? "Expanded value" : "Compact")
                .font(
                    .system(
                        size: alternateText ? 30 : 20,
                        weight: .semibold
                    )
                )
                .foregroundColor(alternateText ? .purple : .blue)
                .contentTransition(.interpolate)
            Button("Change Text", action: {})
        }
        .frame(width: 240)
        .frame(width: 320, height: 240)
    }
}

private struct LayoutSchedulingRapidAsymmetricViewTransitionRoot: View {
    let probe: LayoutSchedulingAnimationProbe
    @State private var cardVisible = true

    var body: some View {
        probe.toggle = {
            withAnimation(.easeInOut(duration: 2)) {
                cardVisible.toggle()
            }
        }
        return VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.secondary.opacity(0.35), lineWidth: 1)
                if cardVisible {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.green)
                        .frame(width: 180, height: 82)
                        .transition(
                            .asymmetric(
                                insertion: .scale(scale: 0.65)
                                    .combined(with: .opacity),
                                removal: .move(edge: .trailing)
                                    .combined(with: .opacity)
                            )
                        )
                }
            }
            .frame(width: 430, height: 125)

            Button(cardVisible ? "Remove View" : "Insert View") {
                withAnimation(.easeInOut(duration: 2)) {
                    cardVisible.toggle()
                }
            }
        }
        .frame(width: 500, height: 220)
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
        probe.springMove = {
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

private struct LayoutSchedulingSymbolDrawLayoutRoot: View {
    let probe: LayoutSchedulingAnimationProbe
    @State private var hidden = false

    var body: some View {
        probe.toggle = {
            hidden.toggle()
        }
        return HStack(spacing: 14) {
            Button(hidden ? "Restore Draw" : "Hide Draw") {
                hidden.toggle()
            }

            VStack(spacing: 4) {
                Image(systemName: "draw")
                    .font(.system(size: 40))
                    .frame(width: 56, height: 56)
                    .foregroundStyle(Color.blue)
                    .symbolEffect(
                        DrawOnSymbolEffect.drawOn.byLayer,
                        options: .speed(0.25),
                        isActive: hidden
                    )
                Text("by layer")
                    .font(.system(.caption))
            }
        }
        .frame(width: 500, height: 150)
    }
}

private struct LayoutSchedulingSymbolReplaceRoot: View {
    let probe: LayoutSchedulingAnimationProbe
    @State private var usesDraw = false

    var body: some View {
        probe.toggle = {
            withAnimation(.linear(duration: 3)) {
                usesDraw.toggle()
            }
        }
        probe.plainTextChange = {
            usesDraw.toggle()
        }
        return HStack(spacing: 10) {
            replacement(ReplaceSymbolEffect.replace)
            replacement(ReplaceSymbolEffect.replace.downUp)
            replacement(ReplaceSymbolEffect.replace.upUp)
            replacement(ReplaceSymbolEffect.replace.offUp)
            replacement(ReplaceSymbolEffect.replace.wholeSymbol)
        }
        .frame(width: 400, height: 120)
    }

    private func replacement<Effect>(_ effect: Effect) -> some View
    where Effect: VUI.SymbolEffect & VUI.ContentTransitionSymbolEffect {
        Image(systemName: usesDraw ? "draw" : "photo.fill")
            .font(.system(size: 40))
            .frame(width: 56, height: 56)
            .foregroundStyle(Color.blue, Color.orange)
            .contentTransition(.symbolEffect(effect))
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

private struct LayoutSchedulingShapePresentationSample {
    var bounds: CGRect
    var role: ShapeRole
    var color: VUI.Color?
    var isStroke: Bool
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
            let bounds = CGRect(
                origin: .zero,
                size: inputSize.value.value
            )
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
        cachedEnvironmentAttribute.value = cachedEnvironment
        let lcAttr: Attribute<LayoutComputer> = graph.makeRule {
            LayoutComputer.fixed(view._attribute.value.size)
        }
        let displayListAttr: Attribute<DisplayList> = graph.makeRule {
            let size = sizeAttr.value.value
            var list = DisplayList()
            list.appendTextItem(
                foreground: .color(.red),
                bounds: CGRect(origin: .zero, size: size)
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
        cachedEnvironmentAttr.value = cachedEnvironment
        let lcAttr: Attribute<LayoutComputer> = graph.makeRule {
            _ = cachedEnvironmentAttr.value.environment.value.font
            return LayoutComputer.fixed(view._attribute.value.size)
        }
        let displayListAttr: Attribute<DisplayList> = graph.makeRule {
            let size = sizeAttr.value.value
            var list = DisplayList()
            list.appendTextItem(
                foreground: .color(.red),
                bounds: CGRect(origin: .zero, size: size)
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
