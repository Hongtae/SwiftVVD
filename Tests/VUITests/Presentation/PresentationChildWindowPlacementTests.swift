import XCTest
@testable import VVD
@testable import VUI

final class PresentationChildWindowPlacementTests: XCTestCase {
    // ASSERTIONS contextMenuPointerPopupAnchorObserved
    @MainActor
    func testInitialPlatformPopupFitsVisibleScreenBeforeWindowAttachment() async throws {
        let host = PresentationPlacementHostController(
            contentSize: CGSize(width: 688, height: 368)
        )
        let platformWindow = DeferredPresentationWindow()
        let popup = UnattachedPlatformPopupController(
            platformWindow: platformWindow,
            content: Color.clear.frame(width: 251, height: 451),
            scene: host.scene,
            anchor: CGPoint(x: 300, y: 228)
        )

        host.addPresentationChild(child: popup) { [weak popup] attach in
            popup?.resolvePresentationWindowAttachment(attach)
        }
        for _ in 0..<4 {
            await Task.yield()
        }

        XCTAssertEqual(platformWindow.contentSize, CGSize(width: 251, height: 451))
        XCTAssertEqual(platformWindow.origin, CGPoint(x: 300, y: 228))
    }

    @MainActor
    func testPlatformChildActivatesAfterApplyingItsFirstFittedFrame() async throws {
        let host = PresentationPlacementHostController(
            contentSize: CGSize(width: 640, height: 420)
        )
        let platformWindow = DeferredPresentationWindow()
        let child = DeferredActivationPresentationController(
            platformWindow: platformWindow,
            content: Color.clear.frame(width: 200, height: 100),
            scene: host.scene
        )

        host.addPresentationChild(child: child) { [weak child] attach in
            child?.resolvePresentationWindowAttachment(attach)
        }
        for _ in 0..<4 {
            await Task.yield()
        }

        XCTAssertFalse(
            platformWindow.events.contains(.contentSize(CGSize(width: 10, height: 10)))
        )
        XCTAssertTrue(platformWindow.events.contains { event in
            guard case .contentSize(let size) = event else { return false }
            return size.width > 10 && size.height > 10
        })
        XCTAssertFalse(platformWindow.events.contains(.activate))

        let withGC: WindowContext.WithGraphicsContext = { _, _ in
            XCTFail("Fixed presentation content should not request graphics resources.")
        }
        var redraw = false
        child.updateView(
            tick: 0,
            delta: 0,
            date: child.date,
            contentSize: CGSize(width: 10, height: 10),
            redraw: &redraw,
            withGC
        )
        for _ in 0..<4 {
            await Task.yield()
        }

        let activationIndex = platformWindow.events.firstIndex(of: .activate)
        let fittedSizeIndex = platformWindow.events.firstIndex {
            if case .contentSize(let size) = $0 {
                return size.width > 10 && size.height > 10
            }
            return false
        }
        XCTAssertNotNil(fittedSizeIndex)
        XCTAssertNotNil(activationIndex)
        if let fittedSizeIndex, let activationIndex {
            XCTAssertLessThan(fittedSizeIndex, activationIndex)
        }
        XCTAssertEqual(
            platformWindow.events.filter { $0 == .activate }.count,
            1
        )
    }

    @MainActor
    func testEndedPlatformChildDoesNotActivateFromLateInitialLayout() async throws {
        let host = PresentationPlacementHostController(
            contentSize: CGSize(width: 640, height: 420)
        )
        let platformWindow = DeferredPresentationWindow()
        let child = DeferredActivationPresentationController(
            platformWindow: platformWindow,
            content: Color.clear.frame(width: 200, height: 100),
            scene: host.scene
        )

        host.addPresentationChild(child: child) { [weak child] attach in
            child?.resolvePresentationWindowAttachment(attach)
        }
        for _ in 0..<4 {
            await Task.yield()
        }
        host.removePresentationChild(child: child)

        let withGC: WindowContext.WithGraphicsContext = { _, _ in
            XCTFail("Fixed presentation content should not request graphics resources.")
        }
        var redraw = false
        child.updateView(
            tick: 0,
            delta: 0,
            date: child.date,
            contentSize: CGSize(width: 10, height: 10),
            redraw: &redraw,
            withGC
        )
        for _ in 0..<4 {
            await Task.yield()
        }

        XCTAssertFalse(platformWindow.events.contains(.activate))
    }

    @MainActor
    func testPlatformModalPresentsAfterApplyingItsFirstFittedSize() async throws {
        let host = PresentationPlacementHostController(
            contentSize: CGSize(width: 640, height: 420)
        )
        let content = AnyView(Color.clear.frame(width: 200, height: 100))
        let modal = makePlatformModal(
            parent: host,
            content: content,
            sceneIndex: 3
        )
        let platformWindow = DeferredPresentationWindow()
        let firstFittedSize = CGSize(width: 208, height: 108)

        host.addModal(
            child: modal,
            session: sheetSession(
                content: content,
                namespaceID: 91_003,
                usesPlatformWindow: true
            ),
            attachWindow: { attach in
                platformWindow.contentSize = firstFittedSize
                attach?(platformWindow)
            }
        )

        XCTAssertEqual(host.presentedModalSizes, [firstFittedSize])
        XCTAssertEqual(platformWindow.contentSize, firstFittedSize)

        let updatedSize = CGSize(width: 240, height: 140)
        platformWindow.contentSize = updatedSize

        XCTAssertEqual(host.presentedModalSizes, [firstFittedSize])
        XCTAssertEqual(platformWindow.contentSize, updatedSize)
    }

    @MainActor
    func testLatePlatformModalAttachmentIsRejectedAfterOverlayFallback() async throws {
        let host = PresentationPlacementHostController(
            contentSize: CGSize(width: 640, height: 420)
        )
        let content = AnyView(Color.clear.frame(width: 200, height: 100))
        let modal = makePlatformModal(
            parent: host,
            content: content,
            sceneIndex: 4
        )
        let platformWindow = DeferredPresentationWindow()
        var deferredAttach: WindowController.AttachWindow?

        host.addModal(
            child: modal,
            session: sheetSession(
                content: content,
                namespaceID: 91_004,
                usesPlatformWindow: true
            ),
            attachWindow: { attach in
                deferredAttach = attach
                platformWindow.contentSize = CGSize(width: 10, height: 10)
            }
        )

        for _ in 0..<4 {
            await Task.yield()
        }
        platformWindow.contentSize = CGSize(width: 208, height: 108)
        deferredAttach?(platformWindow)

        XCTAssertTrue(host.presentedModalSizes.isEmpty)
        XCTAssertEqual(platformWindow.closeCount, 1)
    }

    @MainActor
    func testOverlayModalRecentersAfterParentResizeAndTopAlignsWhenTooTall() async throws {
        let initialHostSize = CGSize(width: 640, height: 420)
        let host = PresentationPlacementHostController(contentSize: initialHostSize)
        let withGC: WindowContext.WithGraphicsContext = { _, _ in
            XCTFail("Overlay modal placement should not request graphics resources.")
        }

        var redraw = false
        host.updateView(
            tick: 0,
            delta: 0,
            date: host.date,
            contentSize: initialHostSize,
            redraw: &redraw,
            withGC
        )

        let content = AnyView(Color.clear.frame(width: 300, height: 200))
        let modal = makeOverlayModal(
            parent: host,
            content: content,
            sceneIndex: 0
        )
        host.addModal(
            child: modal,
            session: sheetSession(content: content, namespaceID: 91_000)
        )

        redraw = false
        host.updateView(
            tick: 1,
            delta: 1,
            date: host.date.addingTimeInterval(1),
            contentSize: initialHostSize,
            redraw: &redraw,
            withGC
        )
        redraw = false
        host.updateView(
            tick: 2,
            delta: 1.0 / 60.0,
            date: host.date.addingTimeInterval(1.0 + 1.0 / 60.0),
            contentSize: initialHostSize,
            redraw: &redraw,
            withGC
        )

        let modalSize = modal.cachedContentSize
        XCTAssertGreaterThan(modalSize.width, 0)
        XCTAssertGreaterThan(modalSize.height, 0)
        assertOverlayOrigin(
            modal.presentationPointInParent(forLocalPoint: .zero),
            equals: CGPoint(
                x: (initialHostSize.width - modalSize.width) * 0.5,
                y: (initialHostSize.height - modalSize.height) * 0.5
            )
        )

        let expandedHostSize = CGSize(width: 900, height: 700)
        redraw = false
        host.updateView(
            tick: 3,
            delta: 1.0 / 60.0,
            date: host.date.addingTimeInterval(1.0 + 2.0 / 60.0),
            contentSize: expandedHostSize,
            redraw: &redraw,
            withGC
        )
        assertOverlayOrigin(
            modal.presentationPointInParent(forLocalPoint: .zero),
            equals: CGPoint(
                x: (expandedHostSize.width - modalSize.width) * 0.5,
                y: (expandedHostSize.height - modalSize.height) * 0.5
            )
        )

        let shortHostSize = CGSize(
            width: modalSize.width + 80,
            height: max(modalSize.height - 40, 1)
        )
        redraw = false
        host.updateView(
            tick: 4,
            delta: 1.0 / 60.0,
            date: host.date.addingTimeInterval(1.0 + 3.0 / 60.0),
            contentSize: shortHostSize,
            redraw: &redraw,
            withGC
        )
        assertOverlayOrigin(
            modal.presentationPointInParent(forLocalPoint: .zero),
            equals: CGPoint(x: 40, y: 0)
        )
    }

    @MainActor
    func testOverlayPopupInsideOverlayModalFitsNearestPlatformHostSurface() async throws {
        let hostSize = CGSize(width: 640, height: 420)
        let host = PresentationPlacementHostController(contentSize: hostSize)
        let withGC: WindowContext.WithGraphicsContext = { _, _ in
            XCTFail("Presentation placement should not request graphics resources.")
        }

        var redraw = false
        host.updateView(
            tick: 0,
            delta: 0,
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
    func testNestedOverlayModalReceivesMouseEventInItsLocalCoordinates() async throws {
        let hostSize = CGSize(width: 640, height: 420)
        let host = PresentationPlacementHostController(contentSize: hostSize)
        let withGC: WindowContext.WithGraphicsContext = { _, _ in
            XCTFail("Nested overlay input should not request graphics resources.")
        }

        var redraw = false
        host.updateView(
            tick: 0,
            delta: 0,
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
            delta: 1.0 - host.animationTimestamp.seconds,
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
            delta: 2.0 - host.animationTimestamp.seconds,
            date: host.date.addingTimeInterval(2.0),
            contentSize: hostSize,
            redraw: &redraw,
            withGC
        )
        redraw = false
        host.updateView(
            tick: 3,
            delta: (2.0 + 1.0 / 60.0) - host.animationTimestamp.seconds,
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
            location: pointInHost,
            timestamp: 0
        ))
        host.onMouseEvent(event: MouseEvent(
            type: .buttonUp,
            window: host.window,
            device: .genericMouse,
            deviceID: 0,
            buttonID: 0,
            location: pointInHost,
            timestamp: 0
        ))

        redraw = false
        host.updateView(
            tick: 4,
            delta: (2.0 + 2.0 / 60.0) - host.animationTimestamp.seconds,
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

    @MainActor
    private func makePlatformModal(parent: WindowController,
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
                usesPlatformWindow: true
            )
        }
    }

    private func sheetSession(content: AnyView,
                              namespaceID: Int,
                              usesPlatformWindow: Bool = false) -> PresentationSession {
        .sheet(SheetPreference(
            content: content,
            onDismiss: nil,
            namespaceID: Namespace.ID(id: namespaceID),
            itemID: nil,
            drawsBackground: true,
            placement: .automatic,
            activeInspector: nil,
            usesPlatformWindow: usesPlatformWindow
        ))
    }

    private func assertOverlayOrigin(_ actual: CGPoint,
                                     equals expected: CGPoint,
                                     file: StaticString = #filePath,
                                     line: UInt = #line) {
        XCTAssertEqual(actual.x, expected.x, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actual.y, expected.y, accuracy: 0.001, file: file, line: line)
    }
}

private final class NestedOverlayInputProbe {
    var actionCount = 0
}

@MainActor
private final class UnattachedPlatformPopupController:
    PopupWindowController, @unchecked Sendable {
    private let platformWindow: DeferredPresentationWindow

    init<Content: View>(
        platformWindow: DeferredPresentationWindow,
        content: Content,
        scene: WindowKey,
        anchor: CGPoint
    ) {
        self.platformWindow = platformWindow
        super.init(
            content: content,
            scene: scene,
            usesPlatformWindow: true,
            frameInParent: CGRect(origin: anchor, size: .zero)
        )
    }

    override func makeWindow() -> (any VVD.Window)? {
        platformWindow
    }
}

@MainActor
private final class DeferredActivationPresentationController:
    PresentationChildWindowController, @unchecked Sendable {
    private let platformWindow: DeferredPresentationWindow

    override var window: (any VVD.Window)? { platformWindow }

    init<Content: View>(
        platformWindow: DeferredPresentationWindow,
        content: Content,
        scene: WindowKey
    ) {
        self.platformWindow = platformWindow
        super.init(
            content: content,
            scene: scene,
            usesPlatformWindow: true
        )
    }

    override func makeWindow() -> (any VVD.Window)? {
        platformWindow
    }
}

@MainActor
private final class DeferredPresentationWindow: VVD.Window {
    enum Event: Equatable {
        case contentSize(CGSize)
        case origin(CGPoint)
        case activate
    }

    var activated = false
    var visible = false
    var contentBounds = CGRect(origin: .zero, size: CGSize(width: 10, height: 10))
    var windowFrame = CGRect(origin: .zero, size: CGSize(width: 10, height: 10))
    var contentScaleFactor: CGFloat = 1
    var resolution = CGSize(width: 10, height: 10)
    var origin: CGPoint = .zero {
        didSet { events.append(.origin(origin)) }
    }
    var contentSize = CGSize.zero {
        didSet {
            contentBounds.size = contentSize
            windowFrame.size = contentSize
            resolution = contentSize
            events.append(.contentSize(contentSize))
        }
    }
    var title = "Deferred Presentation Test"
    weak var delegate: WindowDelegate?
    var screen: (any VVD.Screen)? { nil }
    var isValid: Bool { true }
    var platformHandle: OpaquePointer? { nil }
    var eventObservers = WindowEventObserverContainer()
    var events: [Event] = []
    var closeCount = 0

    required init?(
        name: String,
        style: WindowStyle,
        delegate: WindowDelegate?,
        data: [String: Any]
    ) {
        title = name
        self.delegate = delegate
    }

    init() {}

    func show() { visible = true }
    func hide() { visible = false }
    func activate() {
        activated = true
        visible = true
        events.append(.activate)
    }
    func minimize() {}
    func requestToClose() -> Bool { true }
    func close() {
        closeCount += 1
        activated = false
        visible = false
    }
    func convertPointToScreen(_ point: CGPoint) -> CGPoint { point }
    func convertPointFromScreen(_ point: CGPoint) -> CGPoint { point }
}

@MainActor
private final class PresentationPlacementHostController: WindowController, @unchecked Sendable {
    private let platformWindow: PresentationPlacementWindow

    override var window: (any VVD.Window)? { platformWindow }
    var presentedModalSizes: [CGSize] { platformWindow.presentedModalSizes }

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
    let screen: (any VVD.Screen)? = PresentationPlacementScreen()
    var isValid: Bool { true }
    var platformHandle: OpaquePointer? { nil }
    var eventObservers = WindowEventObserverContainer()
    var presentedModalSizes: [CGSize] = []
    var canPresentModalWindow: Bool { true }
    var modalWindows: [any VVD.Window] { [] }

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
    func presentModalWindow(
        _ window: any VVD.Window,
        completionHandler: (() -> Void)?
    ) -> Bool {
        presentedModalSizes.append(window.contentSize)
        return true
    }
    func dismissModalWindow(_ window: any VVD.Window) -> Bool { true }
    func convertPointToScreen(_ point: CGPoint) -> CGPoint { point }
    func convertPointFromScreen(_ point: CGPoint) -> CGPoint { point }
}

private struct PresentationPlacementScreen: VVD.Screen {
    let id = ScreenID(rawValue: 91_000)
    let frame = CGRect(x: 0, y: 0, width: 1710, height: 1107)
    let visibleFrame = CGRect(x: 0, y: 50, width: 1710, height: 1023)
    let safeAreaInsets = ScreenInsets.zero
    let scaleFactor: CGFloat = 1
    let displayModeResolution = CGSize(width: 1710, height: 1107)
}
