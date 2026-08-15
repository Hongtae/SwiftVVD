import XCTest
@testable import VVD
@testable import VUI

final class MenuResponderLayoutTests: XCTestCase {
    // ASSERTIONS responderGeometryRuleOwnershipObserved menuPlatformResponderGeometryOwnershipObserved
    @MainActor
    func testConditionalPrimaryActionMenuBuildsWithoutParentLayoutCycle() throws {
        let controller = WindowController(
            content: ConditionalPrimaryActionMenuRoot(),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(ConditionalPrimaryActionMenuRoot.self)
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

        XCTAssertNotNil(controller.viewGraph.rootLayoutComputer)
        let rootResponder = try XCTUnwrap(
            controller.viewGraph.responderNode as? MultiViewResponder
        )
        let menuResponders = responderTree(rootResponder)
            .compactMap { $0 as? MenuDropdownResponder }
        XCTAssertEqual(menuResponders.count, 2)
        var menuCenters: [CGPoint] = []
        for responder in menuResponders {
            XCTAssertGreaterThan(responder.helper.size.width, 0)
            XCTAssertGreaterThan(responder.helper.size.height, 0)
            var points = [CGPoint(
                x: responder.helper.size.width / 2,
                y: responder.helper.size.height / 2
            )]
            responder.helper.transform.convertGlobal(
                from: .local,
                points: &points
            )
            let center = try XCTUnwrap(points.first)
            menuCenters.append(center)
            XCTAssertTrue(
                rootResponder.respondersContaining(point: center).contains {
                    $0 === responder
                }
            )
        }
        XCTAssertNotEqual(menuCenters[0], menuCenters[1])
        XCTAssertTrue(menuCenters.allSatisfy { $0.x > 20 && $0.y > 20 })
        let hoverResponders = responderTree(rootResponder)
            .compactMap { $0 as? HoverResponder }
        XCTAssertFalse(hoverResponders.isEmpty)
        for responder in hoverResponders {
            guard case .nonSpatial = responder.callback else {
                XCTFail("Menu hover responder must use the non-spatial callback")
                continue
            }
            XCTAssertGreaterThan(responder.size.width, 0)
            XCTAssertGreaterThan(responder.size.height, 0)
        }
    }

    // ASSERTIONS menuPlatformResponderGeometryOwnershipObserved
    @MainActor
    func testMenuResponderGeometryRoutesPointerToPresentationTrigger() throws {
        let controller = WindowController(
            content: ConditionalPrimaryActionMenuRoot(),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(ConditionalPrimaryActionMenuRoot.self)
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
        let rootResponder = try XCTUnwrap(
            controller.viewGraph.responderNode as? MultiViewResponder
        )
        let responder = try XCTUnwrap(
            responderTree(rootResponder).compactMap {
                $0 as? MenuDropdownResponder
            }.last
        )
        var points = [CGPoint(
            x: responder.helper.size.width / 2,
            y: responder.helper.size.height / 2
        )]
        responder.helper.transform.convertGlobal(
            from: .local,
            points: &points
        )
        let center = try XCTUnwrap(points.first)

        XCTAssertTrue(controller.handleMouseEvent(event: MouseEvent(
            type: .buttonDown,
            device: .genericMouse,
            deviceID: 0,
            buttonID: 0,
            location: center,
            timestamp: 0
        )))
        XCTAssertTrue(responder.menuIsOpen)
        XCTAssertTrue(controller.handleMouseEvent(event: MouseEvent(
            type: .buttonUp,
            device: .genericMouse,
            deviceID: 0,
            buttonID: 0,
            location: center,
            timestamp: 0
        )))
        responder.dismissMenu()
    }

    // ASSERTIONS resolvedMenuStyleReentryObserved nestedMenuSourcePrecedenceObserved
    func testStandaloneMenuCollectsNestedMenuLabelAndChildren() throws {
        let controller = WindowController(
            content: NestedMenuItemCollectionRoot(),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(NestedMenuItemCollectionRoot.self)
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

        let rootResponder = try XCTUnwrap(
            controller.viewGraph.responderNode as? MultiViewResponder
        )
        let responder = try XCTUnwrap(
            responderTree(rootResponder).compactMap {
                $0 as? MenuDropdownResponder
            }.first
        )
        controller.viewGraph.data.withCurrent {
            let items = responder.itemList.value.items
            XCTAssertEqual(
                items.map { ($0.label ?? $0.text)?.string },
                ["First", "Submenu", "Submenu2"]
            )
            XCTAssertEqual(items[1].children?.items.count, 2)
            XCTAssertEqual(items[2].children?.items.count, 2)
            guard case .menu? = items[1].systemItem,
                  case .menu? = items[2].systemItem else {
                return XCTFail("Nested Menu items must retain their menu role")
            }
            XCTAssertEqual(
                items[1].children?.items.map { ($0.label ?? $0.text)?.string },
                ["Submenu Child 1", "Submenu Child 2"]
            )
        }
    }

    // ASSERTIONS resolvedMenuStyleReentryObserved nestedMenuSourcePrecedenceObserved
    func testContextMenuCollectsNestedMenuLabelAndChildren() throws {
        let controller = WindowController(
            content: NestedContextMenuItemCollectionRoot(),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(NestedContextMenuItemCollectionRoot.self)
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

        let rootResponder = try XCTUnwrap(
            controller.viewGraph.responderNode as? MultiViewResponder
        )
        let responder = try XCTUnwrap(
            responderTree(rootResponder).compactMap {
                $0 as? ContextMenuResponder
            }.first
        )
        var itemList: PlatformItemList?
        controller.viewGraph.data.withCurrent {
            itemList = responder.itemList.value
        }
        let items = try XCTUnwrap(itemList).items
        XCTAssertEqual(
            items.map { ($0.label ?? $0.text)?.string },
            ["First", "Submenu", "Plain Submenu"]
        )
        XCTAssertEqual(
            items[1].children?.items.map { ($0.label ?? $0.text)?.string },
            ["Submenu Child 1", "Submenu Child 2"]
        )
        guard case .menu? = items[1].systemItem else {
            return XCTFail("The context-menu child must retain its menu role")
        }
        XCTAssertEqual(
            items[2].children?.items.map { ($0.label ?? $0.text)?.string },
            ["Plain Child 1", "Plain Child 2"]
        )
        guard case .menu? = items[2].systemItem else {
            return XCTFail("The plain context-menu child must retain its menu role")
        }
    }

    // ASSERTIONS resolvedMenuStyleReentryObserved nestedMenuSourcePrecedenceObserved propertyListBidirectionalTailMergeObserved
    func testCompositeContextMenuRetainsNestedMenuRolesAndChildren() throws {
        let controller = WindowController(
            content: CompositeContextMenuItemCollectionRoot(),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(CompositeContextMenuItemCollectionRoot.self)
            )
        )

        var redraw = false
        controller.updateView(
            tick: 0,
            delta: 0,
            date: controller.date,
            contentSize: CGSize(width: 680, height: 360),
            redraw: &redraw
        ) { _, _ in }

        let rootResponder = try XCTUnwrap(
            controller.viewGraph.responderNode as? MultiViewResponder
        )
        let responder = try XCTUnwrap(
            responderTree(rootResponder).compactMap {
                $0 as? ContextMenuResponder
            }.first
        )
        var itemList: PlatformItemList?
        controller.viewGraph.data.withCurrent {
            itemList = responder.itemList.value
        }
        let items = try XCTUnwrap(itemList).items
        let disabledMore = try XCTUnwrap(items.first {
            ($0.label ?? $0.text)?.string == "Disabled More"
        })
        let more = try XCTUnwrap(items.first {
            ($0.label ?? $0.text)?.string == "More"
        })

        guard case .menu? = disabledMore.systemItem else {
            return XCTFail("Disabled More must retain its menu role")
        }
        XCTAssertEqual(
            disabledMore.children?.items.map { ($0.label ?? $0.text)?.string },
            ["Disabled Nested"]
        )
        guard case .menu? = more.systemItem else {
            return XCTFail("More must retain its menu role")
        }
        XCTAssertEqual(
            more.children?.items.map { ($0.label ?? $0.text)?.string },
            ["Nested Live 0", "Rename", "Developer Mode"]
        )
    }

    // ASSERTIONS responderGeometryRuleOwnershipObserved
    @MainActor
    func testConditionalContinuousHoverPublishesItsInitialResponderState() throws {
        let controller = WindowController(
            content: ConditionalContinuousHoverRoot(),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(ConditionalContinuousHoverRoot.self)
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

        let rootResponder = try XCTUnwrap(
            controller.viewGraph.responderNode as? ViewResponder
        )
        let hoverResponder = try XCTUnwrap(
            responderTree(rootResponder).compactMap { $0 as? HoverResponder }.first
        )
        guard case .spatial = hoverResponder.callback else {
            return XCTFail("Continuous hover must publish a spatial callback")
        }
        XCTAssertGreaterThan(hoverResponder.size.width, 0)
        XCTAssertGreaterThan(hoverResponder.size.height, 0)
    }

    // ASSERTIONS contextMenuEventBindingRouteObserved contextMenuResponderFilterOwnershipObserved contextMenuLongPressDriverThresholdsObserved
    @MainActor
    func testContextMenuEventBindsPositionedResponderAndLongPressTarget() throws {
        let controller = WindowController(
            content: PositionedContextMenuRoot(),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(PositionedContextMenuRoot.self)
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
        let rootResponder = try XCTUnwrap(
            controller.viewGraph.responderNode as? MultiViewResponder
        )
        try controller.viewGraph.data.withCurrent {
            let contextResponders = responderTree(rootResponder).compactMap {
                $0 as? ContextMenuResponder
            }
            XCTAssertEqual(contextResponders.count, 2)
            var hitPoints: [ObjectIdentifier: [CGPoint]] = [:]
            for y in stride(from: CGFloat(10), through: 230, by: 10) {
                for x in stride(from: CGFloat(10), through: 410, by: 10) {
                    let point = CGPoint(x: x, y: y)
                    let event = ContextMenuEvent(
                        timestamp: .zero,
                        binding: nil,
                        location: .zero,
                        globalLocation: point
                    )
                    if let responder = rootResponder
                        .bindEvent(event)?
                        .firstAncestor(ofType: ContextMenuResponder.self) {
                        hitPoints[ObjectIdentifier(responder), default: []]
                            .append(point)
                    }
                }
            }

            XCTAssertEqual(hitPoints.count, 2)
            for responder in contextResponders {
                XCTAssertFalse(
                    hitPoints[ObjectIdentifier(responder), default: []].isEmpty
                )
            }

            let policies = contextResponders.map {
                $0.resolvedTriggerPolicy(for: .genericMouse, buttonID: 0)
            }
            XCTAssertEqual(policies.filter { $0 == .secondaryDown }.count, 1)
            XCTAssertEqual(policies.filter { $0 == .longPress }.count, 1)

            let longPressResponder = try XCTUnwrap(contextResponders.first {
                $0.resolvedTriggerPolicy(for: .genericMouse, buttonID: 0)
                    == .longPress
            })
            let longPressPoint = try XCTUnwrap(
                hitPoints[ObjectIdentifier(longPressResponder)]?.first
            )
            var recognizer = ContextMenuRecognizer()
            var scheduledSession: UInt64?
            var scheduledDelay: TimeInterval?
            var openedResponder: ContextMenuResponder?
            XCTAssertTrue(recognizer.handleMouseEvent(
                MouseEvent(
                    type: .buttonDown,
                    device: .genericMouse,
                    deviceID: 3,
                    buttonID: 0,
                    location: longPressPoint,
                    timestamp: 1
                ),
                viewGraph: controller.viewGraph,
                rootResponder: rootResponder,
                scheduleLongPress: { sessionID, delay in
                    scheduledSession = sessionID
                    scheduledDelay = delay
                },
                open: { responder, _ in
                    openedResponder = responder
                }
            ))
            XCTAssertNil(openedResponder)
            XCTAssertEqual(scheduledDelay, 0.15)
            let withinPointerTolerance = CGPoint(
                x: longPressPoint.x + 3,
                y: longPressPoint.y
            )
            XCTAssertTrue(recognizer.handleMouseEvent(
                MouseEvent(
                    type: .move,
                    device: .genericMouse,
                    deviceID: 3,
                    buttonID: 0,
                    location: withinPointerTolerance,
                    timestamp: 1.1
                ),
                viewGraph: controller.viewGraph,
                rootResponder: rootResponder,
                scheduleLongPress: { _, _ in
                    XCTFail("An active long press must not schedule twice")
                },
                open: { _, _ in
                    XCTFail("Movement inside the tolerance must not open early")
                }
            ))
            XCTAssertTrue(recognizer.fireLongPress(
                sessionID: try XCTUnwrap(scheduledSession),
                viewGraph: controller.viewGraph,
                rootResponder: rootResponder,
                open: { responder, _ in
                    openedResponder = responder
                }
            ))
            XCTAssertTrue(openedResponder === longPressResponder)

            XCTAssertTrue(recognizer.handleMouseEvent(
                MouseEvent(
                    type: .buttonUp,
                    device: .genericMouse,
                    deviceID: 3,
                    buttonID: 0,
                    location: withinPointerTolerance,
                    timestamp: 1.2
                ),
                viewGraph: controller.viewGraph,
                rootResponder: rootResponder,
                scheduleLongPress: { _, _ in },
                open: { _, _ in }
            ))

            var cancelledSession: UInt64?
            openedResponder = nil
            XCTAssertTrue(recognizer.handleMouseEvent(
                MouseEvent(
                    type: .buttonDown,
                    device: .genericMouse,
                    deviceID: 3,
                    buttonID: 0,
                    location: longPressPoint,
                    timestamp: 2
                ),
                viewGraph: controller.viewGraph,
                rootResponder: rootResponder,
                scheduleLongPress: { sessionID, _ in
                    cancelledSession = sessionID
                },
                open: { responder, _ in
                    openedResponder = responder
                }
            ))
            XCTAssertTrue(recognizer.handleMouseEvent(
                MouseEvent(
                    type: .move,
                    device: .genericMouse,
                    deviceID: 3,
                    buttonID: 0,
                    location: CGPoint(
                        x: longPressPoint.x + 4,
                        y: longPressPoint.y
                    ),
                    timestamp: 2.1
                ),
                viewGraph: controller.viewGraph,
                rootResponder: rootResponder,
                scheduleLongPress: { _, _ in },
                open: { responder, _ in
                    openedResponder = responder
                }
            ))
            XCTAssertFalse(recognizer.fireLongPress(
                sessionID: try XCTUnwrap(cancelledSession),
                viewGraph: controller.viewGraph,
                rootResponder: rootResponder,
                open: { responder, _ in
                    openedResponder = responder
                }
            ))
            XCTAssertNil(openedResponder)
        }
    }

    // ASSERTIONS contextMenuEventBindingRouteObserved contextMenuLongPressDriverThresholdsObserved
    @MainActor
    func testWindowControllerLongPressDeadlineOpensPresentationChild() async throws {
        let controller = WindowController(
            content: PositionedContextMenuRoot(),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(PositionedContextMenuRoot.self)
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

        let rootResponder = try XCTUnwrap(
            controller.viewGraph.responderNode as? MultiViewResponder
        )
        var sampledLongPressResponder: ContextMenuResponder?
        controller.viewGraph.data.withCurrent {
            sampledLongPressResponder = responderTree(rootResponder).compactMap {
                $0 as? ContextMenuResponder
            }.first {
                $0.resolvedTriggerPolicy(for: .genericMouse, buttonID: 0)
                    == .longPress
            }
        }
        let longPressResponder = try XCTUnwrap(sampledLongPressResponder)
        var sampledLongPressPoint: CGPoint?
        controller.viewGraph.data.withCurrent {
            for y in stride(from: CGFloat(10), through: 230, by: 10) {
                for x in stride(from: CGFloat(10), through: 410, by: 10) {
                    let point = CGPoint(x: x, y: y)
                    let event = ContextMenuEvent(
                        timestamp: .zero,
                        binding: nil,
                        location: .zero,
                        globalLocation: point
                    )
                    if rootResponder.bindEvent(event)?.firstAncestor(
                        ofType: ContextMenuResponder.self
                    ) === longPressResponder {
                        sampledLongPressPoint = point
                        return
                    }
                }
            }
        }
        let longPressPoint = try XCTUnwrap(sampledLongPressPoint)

        XCTAssertTrue(controller.handleMouseEvent(event: MouseEvent(
            type: .buttonDown,
            device: .genericMouse,
            deviceID: 3,
            buttonID: 0,
            location: longPressPoint,
            timestamp: 1
        )))

        try await Task.sleep(nanoseconds: 250_000_000)
        controller.updateView(
            tick: 1,
            delta: 0.25,
            date: controller.date.addingTimeInterval(0.25),
            contentSize: CGSize(width: 420, height: 240),
            redraw: &redraw
        ) { _, _ in }

        var presentationChildCount = 0
        controller.forEachPresentationChild { _ in
            presentationChildCount += 1
        }
        XCTAssertEqual(presentationChildCount, 1)

        XCTAssertTrue(controller.handleMouseEvent(event: MouseEvent(
            type: .buttonUp,
            device: .genericMouse,
            deviceID: 3,
            buttonID: 0,
            location: longPressPoint,
            timestamp: 1.25
        )))
        controller.dismissAllPresentationChildren()
    }

    private func responderTree(_ responder: ViewResponder) -> [ViewResponder] {
        [responder] + responder.children.flatMap(responderTree)
    }

}

private struct ConditionalContinuousHoverRoot: View {
    var body: some View {
        HStack {
            hoverRegion(isVisible: true)
            Text("Sibling")
        }
        .padding(20)
    }

    @ViewBuilder
    private func hoverRegion(isVisible: Bool) -> some View {
        if isVisible {
            Text("Hover")
                .padding(8)
                .onContinuousHover { _ in }
        } else {
            EmptyView()
        }
    }
}

private struct ConditionalPrimaryActionMenuRoot: View {
    var body: some View {
        HStack {
            menu("Menu Action") {}
            menu("Open Menu")
        }
        .padding(20)
    }

    @ViewBuilder
    private func menu(
        _ title: String,
        primaryAction: (() -> Void)? = nil
    ) -> some View {
        if let primaryAction {
            Menu(title) {
                Button("Menu Item") {}
            } primaryAction: {
                primaryAction()
            }
        } else {
            Menu(title) {
                Button("Menu Item") {}
            }
        }
    }
}

private struct NestedMenuItemCollectionRoot: View {
    var body: some View {
        Menu("Open Menu") {
            Button("First") {}
            Menu("Submenu") {
                Button("Submenu Child 1") {}
                Button("Submenu Child 2") {}
            } primaryAction: {}
            Menu("Submenu2") {
                Button("Submenu2 Child 1") {}
                Button("Submenu2 Child 2") {}
            } primaryAction: {}
        }
    }
}

private struct NestedContextMenuItemCollectionRoot: View {
    var body: some View {
        Text("Target")
            .contextMenu {
                VStack {
                    Button("First") {}
                    Menu("Submenu") {
                        Button("Submenu Child 1") {}
                        Button("Submenu Child 2") {}
                    } primaryAction: {}
                    Menu("Plain Submenu") {
                        Button("Plain Child 1") {}
                        Button("Plain Child 2") {}
                    }
                }
            }
    }
}

private struct CompositeContextMenuItemCollectionRoot: View {
    @State private var toggle = true
    @State private var liveCount = 0

    var body: some View {
        Text("Target")
            .contextMenu {
                CompositeContextMenuItems(
                    toggle: $toggle,
                    liveCount: liveCount
                )
            }
            .styleContext(.sheet)
    }
}

private struct CompositeContextMenuItems: View {
    @Binding var toggle: Bool
    let liveCount: Int

    var body: some View {
        VStack {
            Text("Live Count \(liveCount)")
            Button("Live Enabled \(liveCount)") {}
                .environment(\.isEnabled, liveCount.isMultiple(of: 2))
            Toggle("Live Toggle \(liveCount)", isOn: $toggle)
            if liveCount > 0 {
                Button("Inserted Live \(liveCount)") {}
            }
            if liveCount < 6 {
                Button("Removed Live \(liveCount)") {}
            }
            Divider()
            Text("1234")
            Label("Static Label", systemImage: "star.fill")
            Button {} label: {
                Label("Disabled Image", systemImage: "star.fill")
            }
            .environment(\.isEnabled, false)
            Button("Disabled Shortcut") {}
                .keyboardShortcut("d", modifiers: [.command, .option])
                .environment(\.isEnabled, false)
            Toggle("Disabled Toggle", isOn: .constant(true))
                .environment(\.isEnabled, false)
            Menu("Disabled More") {
                Button("Disabled Nested") {}
            }
            .environment(\.isEnabled, false)
            Button("Menu1") {}
            Button("Shortcut Menu") {}
                .keyboardShortcut("k", modifiers: [.command, .shift])
            Toggle("Toggle Menu", isOn: $toggle)
            Divider()
            Section("Section Header") {
                Button("Section Action") {}
            }
            Button("Menu2") {}
            Menu("More") {
                Button("Nested Live \(liveCount)") {}
                Button("Rename") {}
                Button("Developer Mode") {}
            }
        }
    }
}

private struct PositionedContextMenuRoot: View {
    var body: some View {
        HStack(spacing: 80) {
            Color.blue.opacity(0.2)
                .frame(width: 100, height: 40)
                .contextMenu {
                    Button("First") {}
                }
            Color.green.opacity(0.2)
                .frame(width: 100, height: 40)
                .contextMenu {
                    Button("Second") {}
                }
                .environment(\.contextMenuTriggerPolicy, .longPress)
        }
    }
}
