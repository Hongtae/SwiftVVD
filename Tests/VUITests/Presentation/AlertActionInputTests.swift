import XCTest
@testable import VUI
@testable import VVD

final class AlertActionInputTests: XCTestCase {
    // ASSERTIONS alertNativeButtonHostIsolationObserved
    @MainActor
    func testAlertActionButtonWinsHitTestingOverModalScrim() throws {
        let state = AlertActionInputState()
        let preference = alertPreference(state: state)
        let controller = WindowController(
            content: AlertOverlayView(preference: preference),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(AlertActionInputTests.self)
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

        let buttonPoint = try XCTUnwrap(
            firstButtonGesturePoint(
                in: controller,
                size: CGSize(width: 420, height: 240)
            )
        )
        click(controller, at: buttonPoint)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))

        XCTAssertEqual(state.actionCount, 1)
        XCTAssertFalse(state.isPresented)
    }

    @MainActor
    func testOverlayModalRoutesParentClickToAlertActionButton() throws {
        let state = AlertActionInputState()
        let preference = alertPreference(state: state)
        let parent = WindowController(
            content: Color.clear.frame(width: 420, height: 240),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(AlertActionInputState.self)
            )
        )
        var redraw = false
        parent.updateView(
            tick: 0,
            delta: 0,
            date: parent.date,
            contentSize: CGSize(width: 420, height: 240),
            redraw: &redraw
        ) { _, _ in }

        let child: ModalWindowController = parent.viewGraph.data.withCurrent {
            let graph = parent.viewGraph.data.graph
            let content = graph.makeInput(
                value: AnyView(AlertOverlayView(preference: preference))
            )
            let child = ModalWindowController(
                crossGraphContent: content,
                sourceGraph: graph,
                scene: WindowKey(
                    namespace: .app,
                    sceneID: SceneID(AlertOverlayView.self)
                ),
                parentController: parent,
                usesPlatformWindow: false
            )
            parent.addModal(child: child, session: .alert(preference))
            return child
        }

        // This focused route installs the modal directly. Advance the child
        // without asking the parent preference owner to reconcile an alert
        // that its root content did not publish.
        for tick in 1...12 {
            child.updateView(
                tick: UInt64(tick),
                delta: 0.05,
                date: child.date,
                contentSize: CGSize(width: 420, height: 240),
                redraw: &redraw
            ) { _, _ in }
        }

        let localButtonPoint = try XCTUnwrap(
            firstButtonGesturePoint(
                in: child,
                size: child.cachedContentSize
            )
        )
        let parentButtonPoint = child.presentationPointInParent(
            forLocalPoint: localButtonPoint
        )
        clickThroughModalBoundary(parent, at: parentButtonPoint)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))

        XCTAssertEqual(state.actionCount, 1)
        XCTAssertFalse(state.isPresented)
    }

    // ASSERTIONS alertNativePanelIsolationObserved
    @MainActor
    func testSettledOverlayAlertKeepsItsChromeClearOfALocalScrim() throws {
        #if canImport(Metal)
        let state = AlertActionInputState()
        let preference = alertPreference(state: state)
        try assertSettledOverlayChromeHasNoLocalScrim(
            content: AnyView(AlertOverlayView(preference: preference)),
            session: .alert(preference),
            label: "alert"
        )
        #else
        throw XCTSkip("Metal is required for this readback fixture")
        #endif
    }

    // ASSERTIONS alertNativePanelIsolationObserved
    @MainActor
    func testSettledOverlayConfirmationDialogKeepsItsChromeClearOfALocalScrim() throws {
        #if canImport(Metal)
        let state = AlertActionInputState()
        let preference = ConfirmationDialogPreference(
            title: Text("Choose an Option"),
            titleVisibility: .visible,
            actionsItemList: nil,
            makeActions: { AnyView(Text("Continue")) },
            makeMessage: nil,
            messageItemList: nil,
            isPresented: Binding(
                get: { state.isPresented },
                set: { state.isPresented = $0 }
            ),
            onDismiss: nil,
            usesPlatformWindow: false
        )
        try assertSettledOverlayChromeHasNoLocalScrim(
            content: AnyView(
                ConfirmationDialogOverlayView(preference: preference)
            ),
            session: .confirmationDialog(preference),
            label: "confirmation dialog"
        )
        #else
        throw XCTSkip("Metal is required for this readback fixture")
        #endif
    }

    @MainActor
    private func assertSettledOverlayChromeHasNoLocalScrim(
        content: AnyView,
        session: PresentationSession,
        label: String
    ) throws {
        let parentSize = CGSize(width: 420, height: 240)
        let parent = WindowController(
            content: Color.white.frame(
                width: parentSize.width,
                height: parentSize.height
            ),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(AlertActionInputTests.self)
            )
        )
        var redraw = false
        parent.updateView(
            tick: 0,
            delta: 0,
            date: parent.date,
            contentSize: parentSize,
            redraw: &redraw
        ) { _, _ in }

        let child: ModalWindowController = parent.viewGraph.data.withCurrent {
            let graph = parent.viewGraph.data.graph
            let contentAttr = graph.makeInput(value: content)
            let child = ModalWindowController(
                crossGraphContent: contentAttr,
                sourceGraph: graph,
                scene: WindowKey(
                    namespace: .app,
                    sceneID: SceneID(AlertOverlayView.self)
                ),
                parentController: parent,
                usesPlatformWindow: false
            )
            parent.addModal(child: child, session: session)
            return child
        }

        for tick in 1...12 {
            child.updateView(
                tick: UInt64(tick),
                delta: 0.05,
                date: child.date.addingTimeInterval(Double(tick) * 0.05),
                contentSize: parentSize,
                redraw: &redraw
            ) { _, _ in }
        }

        let device = try XCTUnwrap(makeGraphicsDeviceContext(api: .metal))
        let queue = try XCTUnwrap(device.renderQueue())
        let commands = try XCTUnwrap(queue.makeCommandBuffer())
        let context = try XCTUnwrap(GraphicsContext(
            sceneResources: parent.sceneResources,
            environment: parent.environment,
            viewport: CGRect(origin: .zero, size: parentSize),
            contentOffset: .zero,
            contentScaleFactor: 1,
            resolution: parentSize,
            commandBuffer: commands
        ))
        context.clear(with: .white)
        parent.drawFrame(offset: .zero, context)

        let completed = expectation(description: "\(label) readback")
        commands.addCompletedHandler { _ in completed.fulfill() }
        XCTAssertTrue(commands.commit())
        wait(for: [completed], timeout: 10)

        let staging = try XCTUnwrap(
            device.makeCPUAccessible(texture: context.backdrop)
        )
        let bytes = UnsafeRawBufferPointer(
            start: try XCTUnwrap(staging.contents()),
            count: Int(parentSize.width * parentSize.height) * 4
        )
        let origin = child.presentationPointInParent(forLocalPoint: .zero)
        let sample = CGPoint(
            x: origin.x + child.cachedContentSize.width * 0.5,
            y: origin.y + 2
        )
        let x = Int(sample.x.rounded(.down))
        let y = Int(sample.y.rounded(.down))
        let offset = (y * Int(parentSize.width) + x) * 4
        let pixel = Array(bytes[offset..<offset + 4])

        XCTAssertGreaterThanOrEqual(
            pixel[0],
            235,
            "A content-sized scrim must not darken \(label) chrome at \(sample): \(pixel)"
        )
        XCTAssertGreaterThanOrEqual(pixel[1], 235)
        XCTAssertGreaterThanOrEqual(pixel[2], 235)
        XCTAssertEqual(pixel[3], 255)
    }

    private func alertPreference(state: AlertActionInputState) -> AlertPreference {
        var actions = PlatformItemList()
        var item = PlatformItemList.Item(systemItem: .button)
        item.text = NSAttributedString(string: "Delete")
        item.buttonRole = .destructive
        item.selectionBehavior = .init(
            isMomentary: true,
            isContainerSelection: true,
            yieldsToContainerSelection: false,
            isPickerOption: false,
            visualStyle: .plain,
            onSelect: {
                state.actionCount += 1
            },
            onDeselect: nil,
            springLoadingBehavior: .automatic
        )
        actions.append(item)
        return AlertPreference(
            identity: ViewIdentity(),
            title: Text("Delete Item?"),
            makeActions: { AnyView(EmptyView()) },
            actionsItemList: actions,
            makeMessage: { AnyView(Text("This action cannot be undone.")) },
            messageItemList: nil,
            isPresented: Binding(
                get: { state.isPresented },
                set: { state.isPresented = $0 }
            ),
            severity: .standard,
            onDismiss: nil,
            usesPlatformWindow: false
        )
    }

    @MainActor
    private func firstButtonGesturePoint(
        in controller: WindowController,
        size: CGSize
    ) -> CGPoint? {
        for y in stride(from: 0.0, through: size.height, by: 2.0) {
            for x in stride(from: 0.0, through: size.width, by: 2.0) {
                let point = CGPoint(x: x, y: y)
                guard let responder = controller.gestureEnvironment
                    .eventBinding(at: point, accepting: VUI.MouseEvent.self)?
                    .responder as? any AnyGestureResponder else {
                    continue
                }
                if String(reflecting: responder.gestureType).contains("ButtonGesture") {
                    return point
                }
            }
        }
        return nil
    }

    @MainActor
    private func click(_ controller: WindowController, at location: CGPoint) {
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
    }

    @MainActor
    private func clickThroughModalBoundary(
        _ controller: WindowController,
        at location: CGPoint
    ) {
        controller.onMouseEvent(event: MouseEvent(
            type: .buttonDown,
            device: .genericMouse,
            deviceID: 0,
            buttonID: 0,
            location: location,
            timestamp: 0
        ))
        controller.onMouseEvent(event: MouseEvent(
            type: .buttonUp,
            device: .genericMouse,
            deviceID: 0,
            buttonID: 0,
            location: location,
            timestamp: 0
        ))
    }
}

private final class AlertActionInputState {
    var actionCount = 0
    var isPresented = true
}
