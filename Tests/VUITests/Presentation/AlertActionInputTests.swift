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

        for tick in 1...12 {
            parent.updateView(
                tick: UInt64(tick),
                delta: 0.05,
                date: parent.date,
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
                    .eventBinding(at: point, accepting: MouseEvent.self)?
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
