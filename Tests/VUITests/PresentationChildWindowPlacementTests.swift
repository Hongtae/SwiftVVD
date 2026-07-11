import XCTest
@testable import VVD
@testable import VUI

final class PresentationChildWindowPlacementTests: XCTestCase {
    @MainActor
    func testOverlayPopupInsideOverlayModalFitsNearestPlatformHostSurface() throws {
        let hostSize = CGSize(width: 640, height: 420)
        let host = PresentationPlacementHostController(contentSize: hostSize)
        let withGC: WindowContext.WithGraphicsContext = { _, _ in
            XCTFail("Presentation placement should not request graphics resources.")
        }

        var redraw = false
        host.updateView(
            tick: 0,
            delta: 1.0 / 60.0,
            date: host.date,
            contentSize: hostSize,
            redraw: &redraw,
            withGC
        )

        let modal = host.viewGraph.data.withCurrent {
            let sourceGraph = host.viewGraph.data.graph
            let contentAttr: Attribute<AnyView> = sourceGraph.makeInput(
                value: AnyView(Color.clear.frame(width: 300, height: 200))
            )
            return ModalWindowController(
                crossGraphContent: contentAttr,
                sourceGraph: sourceGraph,
                scene: WindowKey(
                    namespace: .app,
                    sceneID: SceneID(PresentationChildWindowPlacementTests.self)
                ),
                parentController: host,
                usesPlatformWindow: false
            )
        }
        modal.parentWindow = host

        redraw = false
        modal.updateView(
            tick: 0,
            delta: 1.0 / 60.0,
            date: modal.date,
            contentSize: hostSize,
            redraw: &redraw,
            withGC
        )

        let popup = PopupWindowController(
            content: Color.clear.frame(width: 200, height: 100),
            scene: host.scene,
            usesPlatformWindow: false,
            frameInParent: CGRect(x: 500, y: 150, width: 0, height: 0)
        )
        popup.parentWindow = modal

        let available = try XCTUnwrap(popup.availableFrameForPresentationPlacement())
        XCTAssertEqual(available, CGRect(origin: .zero, size: hostSize))

        let frame = popup.presentationFrame(forContentSize: CGSize(width: 200, height: 100))
        let comparison = try XCTUnwrap(
            popup.comparisonFrameForPresentationPlacement(frame)
        )
        XCTAssertLessThan(frame.minX, 500)
        XCTAssertGreaterThanOrEqual(comparison.minX, available.minX)
        XCTAssertLessThanOrEqual(comparison.maxX, available.maxX)
        XCTAssertGreaterThanOrEqual(comparison.minY, available.minY)
        XCTAssertLessThanOrEqual(comparison.maxY, available.maxY)

        let rootPopup = PopupWindowController(
            content: Color.clear.frame(width: 160, height: 120),
            scene: host.scene,
            usesPlatformWindow: false,
            frameInParent: CGRect(x: 300, y: 100, width: 160, height: 120)
        )
        rootPopup.parentWindow = modal
        let submenu = PopupWindowController(
            content: Color.clear.frame(width: 200, height: 100),
            scene: host.scene,
            usesPlatformWindow: false,
            frameInParent: CGRect(x: 150, y: 20, width: 0, height: 0)
        )
        submenu.parentWindow = rootPopup

        let submenuAvailable = try XCTUnwrap(
            submenu.availableFrameForPresentationPlacement()
        )
        XCTAssertEqual(submenuAvailable, available)
        let submenuFrame = submenu.presentationFrame(
            forContentSize: CGSize(width: 200, height: 100)
        )
        let submenuComparison = try XCTUnwrap(
            submenu.comparisonFrameForPresentationPlacement(submenuFrame)
        )
        XCTAssertLessThan(submenuFrame.minX, 150)
        XCTAssertGreaterThanOrEqual(submenuComparison.minX, submenuAvailable.minX)
        XCTAssertLessThanOrEqual(submenuComparison.maxX, submenuAvailable.maxX)
        XCTAssertGreaterThanOrEqual(submenuComparison.minY, submenuAvailable.minY)
        XCTAssertLessThanOrEqual(submenuComparison.maxY, submenuAvailable.maxY)

        let preferredPlatformPopup = PopupWindowController(
            content: Color.clear.frame(width: 200, height: 100),
            scene: host.scene,
            usesPlatformWindow: true,
            frameInParent: CGRect(x: 500, y: 150, width: 0, height: 0)
        )
        preferredPlatformPopup.parentWindow = modal

        // A platform preference falls back to overlay when its parent has no
        // platform window. Placement must follow the resolved overlay mode and
        // fit the host surface rather than the screen visible frame.
        switch preferredPlatformPopup.presentationAvailableFrameSpace {
        case .hostSurface:
            break
        case .platformVisibleScreen:
            XCTFail("A platform preference that fell back to overlay used screen placement.")
        }
        let fallbackFrame = preferredPlatformPopup.presentationFrame(
            forContentSize: CGSize(width: 200, height: 100)
        )
        let fallbackComparison = try XCTUnwrap(
            preferredPlatformPopup.comparisonFrameForPresentationPlacement(fallbackFrame)
        )
        XCTAssertLessThan(fallbackFrame.minX, 500)
        XCTAssertGreaterThanOrEqual(fallbackComparison.minX, available.minX)
        XCTAssertLessThanOrEqual(fallbackComparison.maxX, available.maxX)
        XCTAssertGreaterThanOrEqual(fallbackComparison.minY, available.minY)
        XCTAssertLessThanOrEqual(fallbackComparison.maxY, available.maxY)
    }

    @MainActor
    func testNestedOverlayModalReceivesMouseEventInItsLocalCoordinates() throws {
        let hostSize = CGSize(width: 640, height: 420)
        let host = PresentationPlacementHostController(contentSize: hostSize)
        let withGC: WindowContext.WithGraphicsContext = { _, _ in
            XCTFail("Nested overlay input should not request graphics resources.")
        }

        var redraw = false
        host.updateView(
            tick: 0,
            delta: 1.0,
            date: host.date,
            contentSize: hostSize,
            redraw: &redraw,
            withGC
        )

        let outerContent = AnyView(Color.clear.frame(width: 300, height: 200))
        let outer = makeOverlayModal(
            parent: host,
            content: outerContent,
            sceneIndex: 1
        )
        host.addModal(
            child: outer,
            session: sheetSession(content: outerContent, namespaceID: 91_001)
        )
        redraw = false
        host.updateView(
            tick: 1,
            delta: 1.0,
            date: host.date.addingTimeInterval(1.0),
            contentSize: hostSize,
            redraw: &redraw,
            withGC
        )

        let probe = NestedOverlayInputProbe()
        let innerContent = AnyView(
            Color.blue
                .frame(width: 120, height: 50)
                .onTapGesture {
                    probe.actionCount += 1
                }
        )
        let inner = makeOverlayModal(
            parent: outer,
            content: innerContent,
            sceneIndex: 2
        )
        outer.addModal(
            child: inner,
            session: sheetSession(content: innerContent, namespaceID: 91_002)
        )
        redraw = false
        host.updateView(
            tick: 2,
            delta: 1.0,
            date: host.date.addingTimeInterval(2.0),
            contentSize: hostSize,
            redraw: &redraw,
            withGC
        )
        redraw = false
        host.updateView(
            tick: 3,
            delta: 1.0 / 60.0,
            date: host.date.addingTimeInterval(2.0 + 1.0 / 60.0),
            contentSize: hostSize,
            redraw: &redraw,
            withGC
        )

        let innerSize = inner.cachedContentSize
        XCTAssertGreaterThan(innerSize.width, 0)
        XCTAssertGreaterThan(innerSize.height, 0)
        let innerCenter = CGPoint(x: innerSize.width * 0.5,
                                  y: innerSize.height * 0.5)
        let pointInOuter = inner.presentationPointInParent(
            forLocalPoint: innerCenter
        )
        let pointInHost = outer.presentationPointInParent(
            forLocalPoint: pointInOuter
        )

        host.onMouseEvent(event: MouseEvent(
            type: .buttonDown,
            window: host.window,
            device: .genericMouse,
            deviceID: 0,
            buttonID: 0,
            location: pointInHost
        ))
        host.onMouseEvent(event: MouseEvent(
            type: .buttonUp,
            window: host.window,
            device: .genericMouse,
            deviceID: 0,
            buttonID: 0,
            location: pointInHost
        ))

        redraw = false
        host.updateView(
            tick: 4,
            delta: 1.0 / 60.0,
            date: host.date.addingTimeInterval(2.0 + 2.0 / 60.0),
            contentSize: hostSize,
            redraw: &redraw,
            withGC
        )
        XCTAssertEqual(probe.actionCount, 1)
    }

    @MainActor
    private func makeOverlayModal(parent: WindowController,
                                  content: AnyView,
                                  sceneIndex: UInt8) -> ModalWindowController {
        parent.viewGraph.data.withCurrent {
            let sourceGraph = parent.viewGraph.data.graph
            let contentAttr: Attribute<AnyView> = sourceGraph.makeInput(value: content)
            return ModalWindowController(
                crossGraphContent: contentAttr,
                sourceGraph: sourceGraph,
                scene: WindowKey(
                    namespace: .app,
                    sceneID: SceneID(NestedOverlayInputProbe.self, index: sceneIndex)
                ),
                parentController: parent,
                usesPlatformWindow: false
            )
        }
    }

    private func sheetSession(content: AnyView,
                              namespaceID: Int) -> PresentationSession {
        .sheet(SheetPreference(
            content: content,
            onDismiss: nil,
            namespaceID: Namespace.ID(id: namespaceID),
            itemID: nil,
            drawsBackground: true,
            placement: .automatic,
            activeInspector: nil,
            usesPlatformWindow: false
        ))
    }
}

private final class NestedOverlayInputProbe {
    var actionCount = 0
}

@MainActor
private final class PresentationPlacementHostController: WindowController, @unchecked Sendable {
    private let platformWindow: PresentationPlacementWindow

    override var window: (any VVD.Window)? { platformWindow }

    init(contentSize: CGSize) {
        self.platformWindow = PresentationPlacementWindow(contentSize: contentSize)
        super.init(
            content: EmptyView(),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(PresentationPlacementHostController.self)
            )
        )
    }
}

@MainActor
private final class PresentationPlacementWindow: VVD.Window {
    var activated = true
    var visible = true
    var contentBounds: CGRect
    var windowFrame: CGRect
    var contentScaleFactor: CGFloat = 1
    var resolution: CGSize
    var origin: CGPoint = .zero
    var contentSize: CGSize
    var title = "Presentation Placement Test"
    weak var delegate: WindowDelegate?
    var screen: (any VVD.Screen)? { nil }
    var isValid: Bool { true }
    var platformHandle: OpaquePointer? { nil }
    var eventObservers = WindowEventObserverContainer()

    init(contentSize: CGSize) {
        self.contentSize = contentSize
        self.contentBounds = CGRect(origin: .zero, size: contentSize)
        self.windowFrame = CGRect(origin: .zero, size: contentSize)
        self.resolution = contentSize
    }

    required init?(name: String,
                   style: WindowStyle,
                   delegate: WindowDelegate?,
                   data: [String: Any]) {
        self.contentSize = .zero
        self.contentBounds = .zero
        self.windowFrame = .zero
        self.resolution = .zero
        self.title = name
        self.delegate = delegate
    }

    func show() {}
    func hide() {}
    func activate() {}
    func minimize() {}
    func requestToClose() -> Bool { true }
    func close() {}
    func convertPointToScreen(_ point: CGPoint) -> CGPoint { point }
    func convertPointFromScreen(_ point: CGPoint) -> CGPoint { point }
}
