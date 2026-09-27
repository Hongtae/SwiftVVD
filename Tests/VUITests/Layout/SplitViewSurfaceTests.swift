import Observation
import XCTest
@testable import VUI
@testable import VVD

final class SplitViewSurfaceTests: XCTestCase {
    func testPublicTypesRetainContentAndHorizontalInspectorSlot() {
        // ASSERTIONS splitViewSurfaceOwner27Observed
        // ASSERTIONS splitViewFieldMetadata27Observed
        let horizontal = HSplitView {
            Text("Leading")
            Text("Trailing")
        }
        let vertical = VSplitView {
            Text("Top")
            Text("Bottom")
        }

        XCTAssertEqual(
            Mirror(reflecting: horizontal).children.compactMap(\.label),
            ["content", "inspectorState"]
        )
        XCTAssertEqual(
            Mirror(reflecting: vertical).children.compactMap(\.label),
            ["content"]
        )
        let horizontalBodyType = String(
            reflecting: type(of: horizontal.internalBody)
        )
        let verticalBodyType = String(
            reflecting: type(of: vertical.internalBody)
        )
        XCTAssertTrue(
            horizontalBodyType.contains("_VariadicView.Tree<VUI._SplitViewContainer"),
            horizontalBodyType
        )
        XCTAssertTrue(
            verticalBodyType.contains("_VariadicView.Tree<VUI._SplitViewContainer"),
            verticalBodyType
        )
    }

    func testConstraintSizingAndDividerOffsetsMatchPublicControl() {
        // ASSERTIONS splitViewConstraintSizing27Observed
        // ASSERTIONS splitViewDividerDrag27Observed
        let horizontal = [
            SplitViewLayout.PaneMetric(
                minimum: 120,
                ideal: 180,
                maximum: 260
            ),
            SplitViewLayout.PaneMetric(
                minimum: 160,
                ideal: 320,
                maximum: .infinity
            ),
        ]
        XCTAssertEqual(
            SplitViewLayout.resolveLengths(
                available: 599,
                metrics: horizontal,
                dividerOffsets: [0]
            ),
            [260, 339]
        )
        XCTAssertEqual(
            SplitViewLayout.resolveLengths(
                available: 599,
                metrics: horizontal,
                dividerOffsets: [-64]
            ),
            [196, 403]
        )
        XCTAssertEqual(
            SplitViewLayout.resolveLengths(
                available: 599,
                metrics: horizontal,
                dividerOffsets: [-500]
            ),
            [120, 479]
        )
        XCTAssertEqual(
            SplitViewLayout.resolveLengths(
                available: 599,
                metrics: horizontal,
                dividerOffsets: [64]
            ),
            [260, 339]
        )

        let vertical = [
            SplitViewLayout.PaneMetric(
                minimum: 80,
                ideal: 120,
                maximum: 180
            ),
            SplitViewLayout.PaneMetric(
                minimum: 100,
                ideal: 220,
                maximum: .infinity
            ),
        ]
        XCTAssertEqual(
            SplitViewLayout.resolveLengths(
                available: 419,
                metrics: vertical,
                dividerOffsets: [0]
            ),
            [180, 239]
        )
    }

    @MainActor
    func testPublicSplitViewMountsOneInteractiveDivider() throws {
        // ASSERTIONS splitViewOwnerLowering27Observed
        // ASSERTIONS splitViewPublicControl27Observed
        // ASSERTIONS splitViewPlatformHost27Observed
        let root = HSplitView {
            Color.red.frame(
                minWidth: 120,
                idealWidth: 180,
                maxWidth: 260,
                maxHeight: .infinity
            )
            Color.blue.frame(
                minWidth: 160,
                idealWidth: 320,
                maxWidth: .infinity,
                maxHeight: .infinity
            )
        }
        let controller = WindowController(
            content: root,
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(SplitViewSurfaceTests.self)
            )
        )
        var redraw = false
        controller.updateView(
            tick: 0,
            delta: 0,
            date: controller.date,
            contentSize: CGSize(width: 600, height: 240),
            redraw: &redraw
        ) { _, _ in }

        var hoverCount = 0
        _ = controller.responderNode?.visit { responder in
            if responder is HoverResponder {
                hoverCount += 1
            }
            return .next
        }
        XCTAssertEqual(hoverCount, 1)
    }

    @MainActor
    func testMountedDividersPublishAxisSpecificCursors() async throws {
        // ASSERTIONS splitViewCursorTransition27Observed
        let horizontal = SplitViewHostController(
            content: HSplitView {
                Color.red
                Color.blue
            }
        )
        try mount(horizontal, size: CGSize(width: 600, height: 240))
        let horizontalHover = try XCTUnwrap(firstHover(in: horizontal))
        horizontalHover.updatePhase(.active(.zero))
        Update.dispatchActions()
        await Task.yield()
        XCTAssertEqual(horizontal.testWindow.cursorChanges, [.horizontal])
        horizontalHover.updatePhase(.ended)
        Update.dispatchActions()
        await Task.yield()
        XCTAssertEqual(
            horizontal.testWindow.cursorChanges,
            [.horizontal, .platformDefault]
        )

        let vertical = SplitViewHostController(
            content: VSplitView {
                Color.red
                Color.blue
            }
        )
        try mount(vertical, size: CGSize(width: 320, height: 420))
        let verticalHover = try XCTUnwrap(firstHover(in: vertical))
        verticalHover.updatePhase(.active(.zero))
        Update.dispatchActions()
        await Task.yield()
        XCTAssertEqual(vertical.testWindow.cursorChanges, [.vertical])
    }

    @MainActor
    func testPointerReleaseOutsideDividerRestoresPlatformCursor() async throws {
        // ASSERTIONS splitViewCursorTransition27Observed
        let size = CGSize(width: 600, height: 240)
        let controller = SplitViewHostController(
            content: HSplitView {
                Color.red
                Color.blue
            }
        )
        try mount(controller, size: size)
        let hover = try XCTUnwrap(firstHover(in: controller))
        let initial = try XCTUnwrap(horizontalHitRange(
            of: hover,
            y: size.height / 2,
            width: Int(size.width)
        ))
        let start = CGPoint(x: initial.mid, y: size.height / 2)
        let outside = CGPoint(x: size.width - 4, y: size.height / 2)

        controller.onMouseEvent(event: MouseEvent(
            type: .move,
            window: controller.testWindow,
            device: .genericMouse,
            deviceID: 0,
            buttonID: 0,
            location: start,
            timestamp: 0
        ))
        Update.dispatchActions()
        await Task.yield()
        XCTAssertEqual(controller.testWindow.cursorChanges, [.horizontal])

        controller.onMouseEvent(event: MouseEvent(
            type: .buttonDown,
            window: controller.testWindow,
            device: .genericMouse,
            deviceID: 0,
            buttonID: 0,
            location: start,
            timestamp: 0.01
        ))
        controller.onMouseEvent(event: MouseEvent(
            type: .move,
            window: controller.testWindow,
            device: .genericMouse,
            deviceID: 0,
            buttonID: 0,
            location: outside,
            timestamp: 0.02
        ))
        controller.onMouseEvent(event: MouseEvent(
            type: .buttonUp,
            window: controller.testWindow,
            device: .genericMouse,
            deviceID: 0,
            buttonID: 0,
            location: outside,
            timestamp: 0.03
        ))
        Update.dispatchActions()
        await Task.yield()

        XCTAssertEqual(
            controller.testWindow.cursorChanges,
            [.horizontal, .platformDefault]
        )
    }

    @MainActor
    func testPointerDragRetainsAxisCursorUntilTerminalRelease() async throws {
        // ASSERTIONS splitViewCursorTransition27Observed
        try await assertDragCursorLifetime(
            content: HSplitView {
                Color.red
                Color.blue
            },
            size: CGSize(width: 600, height: 240),
            axis: .horizontal,
            expected: .horizontal
        )
        try await assertDragCursorLifetime(
            content: VSplitView {
                Color.red
                Color.blue
            },
            size: CGSize(width: 320, height: 420),
            axis: .vertical,
            expected: .vertical
        )
    }

    @MainActor
    func testPointerDragMovesAndRetainsTheDivider() throws {
        // ASSERTIONS splitViewDividerDrag27Observed
        // ASSERTIONS splitViewPositionRetention27Observed
        let size = CGSize(width: 600, height: 240)
        let model = SplitViewRevisionModel()
        let controller = SplitViewHostController(
            content: SplitViewRevisionRoot(model: model)
        )
        try mount(controller, size: size)
        let hover = try XCTUnwrap(firstHover(in: controller))
        let initial = try XCTUnwrap(horizontalHitRange(
            of: hover,
            y: size.height / 2,
            width: Int(size.width)
        ))
        let root = try XCTUnwrap(
            controller.responderNode as? MultiViewResponder
        )
        let start = try XCTUnwrap(firstGesturePoint(in: root, size: size))
        XCTAssertEqual(start.x, initial.mid, accuracy: 3)
        let moved = CGPoint(x: start.x - 64, y: start.y)

        XCTAssertTrue(controller.handleMouseEvent(event: MouseEvent(
            type: .buttonDown,
            window: controller.testWindow,
            device: .genericMouse,
            deviceID: 0,
            buttonID: 0,
            location: start,
            timestamp: 0
        )))
        XCTAssertTrue(controller.handleMouseEvent(event: MouseEvent(
            type: .move,
            window: controller.testWindow,
            device: .genericMouse,
            deviceID: 0,
            buttonID: 0,
            location: moved,
            timestamp: 0.02
        )))
        XCTAssertTrue(controller.handleMouseEvent(event: MouseEvent(
            type: .buttonUp,
            window: controller.testWindow,
            device: .genericMouse,
            deviceID: 0,
            buttonID: 0,
            location: moved,
            timestamp: 0.03
        )))
        Update.dispatchActions()
        var redraw = false
        controller.updateView(
            tick: 1,
            delta: 0.03,
            date: controller.date,
            contentSize: size,
            redraw: &redraw
        ) { _, _ in }

        let retainedHover = try XCTUnwrap(firstHover(in: controller))
        let retained = try XCTUnwrap(horizontalHitRange(
            of: retainedHover,
            y: size.height / 2,
            width: Int(size.width)
        ))
        XCTAssertEqual(retained.mid, initial.mid - 64, accuracy: 1)

        model.revision += 1
        Update.dispatchActions()
        controller.updateView(
            tick: 2,
            delta: 0.03,
            date: controller.date,
            contentSize: size,
            redraw: &redraw
        ) { _, _ in }

        let reconstructedHover = try XCTUnwrap(firstHover(in: controller))
        let reconstructed = try XCTUnwrap(horizontalHitRange(
            of: reconstructedHover,
            y: size.height / 2,
            width: Int(size.width)
        ))
        XCTAssertEqual(reconstructed.mid, retained.mid, accuracy: 1)
    }

    @MainActor
    func testPointerDragTracksRepeatedLayoutUpdatesInBothAxes() throws {
        let horizontalSize = CGSize(width: 600, height: 240)
        let horizontal = SplitViewHostController(
            content: HSplitView {
                Color.red
                Color.blue
            }
        )
        try mount(horizontal, size: horizontalSize)
        let horizontalHover = try XCTUnwrap(firstHover(in: horizontal))
        let horizontalInitial = try XCTUnwrap(horizontalHitRange(
            of: horizontalHover,
            y: horizontalSize.height / 2,
            width: Int(horizontalSize.width)
        ))
        let horizontalStart = CGPoint(
            x: horizontalInitial.mid,
            y: horizontalSize.height / 2
        )
        try drag(
            horizontal,
            from: horizontalStart,
            first: CGPoint(
                x: horizontalStart.x + 24,
                y: horizontalStart.y
            ),
            final: CGPoint(
                x: horizontalStart.x + 48,
                y: horizontalStart.y
            ),
            size: horizontalSize
        )
        let horizontalFinal = try XCTUnwrap(horizontalHitRange(
            of: try XCTUnwrap(firstHover(in: horizontal)),
            y: horizontalSize.height / 2,
            width: Int(horizontalSize.width)
        ))
        XCTAssertEqual(
            horizontalFinal.mid,
            horizontalInitial.mid + 48,
            accuracy: 1
        )

        let verticalSize = CGSize(width: 320, height: 420)
        let vertical = SplitViewHostController(
            content: VSplitView {
                Color.red
                Color.blue
            }
        )
        try mount(vertical, size: verticalSize)
        let verticalHover = try XCTUnwrap(firstHover(in: vertical))
        let verticalInitial = try XCTUnwrap(verticalHitRange(
            of: verticalHover,
            x: verticalSize.width / 2,
            height: Int(verticalSize.height)
        ))
        let verticalStart = CGPoint(
            x: verticalSize.width / 2,
            y: verticalInitial.mid
        )
        try drag(
            vertical,
            from: verticalStart,
            first: CGPoint(
                x: verticalStart.x,
                y: verticalStart.y + 24
            ),
            final: CGPoint(
                x: verticalStart.x,
                y: verticalStart.y + 48
            ),
            size: verticalSize
        )
        let verticalFinal = try XCTUnwrap(verticalHitRange(
            of: try XCTUnwrap(firstHover(in: vertical)),
            x: verticalSize.width / 2,
            height: Int(verticalSize.height)
        ))
        XCTAssertEqual(
            verticalFinal.mid,
            verticalInitial.mid + 48,
            accuracy: 1
        )
    }

    @MainActor
    private func mount(
        _ controller: WindowController,
        size: CGSize
    ) throws {
        var redraw = false
        controller.updateView(
            tick: 0,
            delta: 0,
            date: controller.date,
            contentSize: size,
            redraw: &redraw
        ) { _, _ in }
        XCTAssertNotNil(controller.responderNode)
    }

    @MainActor
    private func firstHover(
        in controller: WindowController
    ) -> HoverResponder? {
        var result: HoverResponder?
        _ = controller.responderNode?.visit { responder in
            if let hover = responder as? HoverResponder {
                result = hover
                return .cancel
            }
            return .next
        }
        return result
    }

    private func horizontalHitRange(
        of responder: HoverResponder,
        y: CGFloat,
        width: Int
    ) -> (min: CGFloat, max: CGFloat, mid: CGFloat)? {
        var hits: [CGFloat] = []
        for x in 0..<width {
            let result = responder.containsGlobalPoints(
                [CGPoint(x: CGFloat(x), y: y)],
                cacheKey: nil,
                options: [.includeHoverResponders, .uncached]
            )
            if result.mask[0] {
                hits.append(CGFloat(x))
            }
        }
        guard let minimum = hits.first, let maximum = hits.last else {
            return nil
        }
        return (minimum, maximum, (minimum + maximum) / 2)
    }

    private func verticalHitRange(
        of responder: HoverResponder,
        x: CGFloat,
        height: Int
    ) -> (min: CGFloat, max: CGFloat, mid: CGFloat)? {
        var hits: [CGFloat] = []
        for y in 0..<height {
            let result = responder.containsGlobalPoints(
                [CGPoint(x: x, y: CGFloat(y))],
                cacheKey: nil,
                options: [.includeHoverResponders, .uncached]
            )
            if result.mask[0] {
                hits.append(CGFloat(y))
            }
        }
        guard let minimum = hits.first, let maximum = hits.last else {
            return nil
        }
        return (minimum, maximum, (minimum + maximum) / 2)
    }

    @MainActor
    private func drag(
        _ controller: SplitViewHostController,
        from start: CGPoint,
        first: CGPoint,
        final: CGPoint,
        size: CGSize
    ) throws {
        XCTAssertTrue(controller.handleMouseEvent(event: MouseEvent(
            type: .buttonDown,
            window: controller.testWindow,
            device: .genericMouse,
            deviceID: 0,
            buttonID: 0,
            location: start,
            timestamp: 0
        )))
        XCTAssertTrue(controller.handleMouseEvent(event: MouseEvent(
            type: .move,
            window: controller.testWindow,
            device: .genericMouse,
            deviceID: 0,
            buttonID: 0,
            location: first,
            timestamp: 0.01
        )))
        var redraw = false
        controller.updateView(
            tick: 1,
            delta: 0.01,
            date: controller.date,
            contentSize: size,
            redraw: &redraw
        ) { _, _ in }

        XCTAssertTrue(controller.handleMouseEvent(event: MouseEvent(
            type: .move,
            window: controller.testWindow,
            device: .genericMouse,
            deviceID: 0,
            buttonID: 0,
            location: final,
            timestamp: 0.02
        )))
        controller.updateView(
            tick: 2,
            delta: 0.01,
            date: controller.date,
            contentSize: size,
            redraw: &redraw
        ) { _, _ in }

        XCTAssertTrue(controller.handleMouseEvent(event: MouseEvent(
            type: .buttonUp,
            window: controller.testWindow,
            device: .genericMouse,
            deviceID: 0,
            buttonID: 0,
            location: final,
            timestamp: 0.03
        )))
        controller.updateView(
            tick: 3,
            delta: 0.01,
            date: controller.date,
            contentSize: size,
            redraw: &redraw
        ) { _, _ in }
    }

    @MainActor
    private func assertDragCursorLifetime<Content: View>(
        content: Content,
        size: CGSize,
        axis: Axis,
        expected: SplitViewCursorChange
    ) async throws {
        let controller = SplitViewHostController(content: content)
        try mount(controller, size: size)
        let hover = try XCTUnwrap(firstHover(in: controller))
        let start: CGPoint
        let first: CGPoint
        let outside: CGPoint
        switch axis {
        case .horizontal:
            let range = try XCTUnwrap(horizontalHitRange(
                of: hover,
                y: size.height / 2,
                width: Int(size.width)
            ))
            start = CGPoint(x: range.mid, y: size.height / 2)
            first = CGPoint(x: start.x + 24, y: start.y)
            outside = CGPoint(x: size.width + 80, y: start.y)
        case .vertical:
            let range = try XCTUnwrap(verticalHitRange(
                of: hover,
                x: size.width / 2,
                height: Int(size.height)
            ))
            start = CGPoint(x: size.width / 2, y: range.mid)
            first = CGPoint(x: start.x, y: start.y + 24)
            outside = CGPoint(x: start.x, y: size.height + 80)
        }

        controller.onMouseEvent(event: MouseEvent(
            type: .move,
            window: controller.testWindow,
            device: .genericMouse,
            deviceID: 0,
            buttonID: 0,
            location: start,
            timestamp: 0
        ))
        Update.dispatchActions()
        await Task.yield()
        XCTAssertEqual(controller.testWindow.cursorChanges, [expected])

        controller.onMouseEvent(event: MouseEvent(
            type: .buttonDown,
            window: controller.testWindow,
            device: .genericMouse,
            deviceID: 0,
            buttonID: 0,
            location: start,
            timestamp: 0.01
        ))
        controller.onMouseEvent(event: MouseEvent(
            type: .move,
            window: controller.testWindow,
            device: .genericMouse,
            deviceID: 0,
            buttonID: 0,
            location: first,
            timestamp: 0.02
        ))
        Update.dispatchActions()
        var redraw = false
        controller.updateView(
            tick: 1,
            delta: 0.02,
            date: controller.date,
            contentSize: size,
            redraw: &redraw
        ) { _, _ in }
        Update.dispatchActions()
        await Task.yield()
        XCTAssertEqual(controller.testWindow.cursorChanges, [expected])

        controller.onMouseEvent(event: MouseEvent(
            type: .move,
            window: controller.testWindow,
            device: .genericMouse,
            deviceID: 0,
            buttonID: 0,
            location: outside,
            timestamp: 0.03
        ))
        Update.dispatchActions()
        controller.updateView(
            tick: 2,
            delta: 0.01,
            date: controller.date,
            contentSize: size,
            redraw: &redraw
        ) { _, _ in }
        Update.dispatchActions()
        await Task.yield()
        XCTAssertEqual(controller.testWindow.cursorChanges, [expected])

        controller.onMouseEvent(event: MouseEvent(
            type: .buttonUp,
            window: controller.testWindow,
            device: .genericMouse,
            deviceID: 0,
            buttonID: 0,
            location: outside,
            timestamp: 0.04
        ))
        Update.dispatchActions()
        controller.updateView(
            tick: 3,
            delta: 0.01,
            date: controller.date,
            contentSize: size,
            redraw: &redraw
        ) { _, _ in }
        Update.dispatchActions()
        await Task.yield()
        XCTAssertEqual(
            controller.testWindow.cursorChanges,
            [expected, .platformDefault]
        )
    }

    private func firstGesturePoint(
        in root: MultiViewResponder,
        size: CGSize
    ) -> CGPoint? {
        for y in stride(from: CGFloat(2), to: size.height - 2, by: 2) {
            for x in stride(from: CGFloat(2), to: size.width - 2, by: 2) {
                let point = CGPoint(x: x, y: y)
                if root.respondersContaining(point: point).contains(where: {
                    $0 is any AnyGestureResponder
                }) {
                    return point
                }
            }
        }
        return nil
    }
}

@Observable
private final class SplitViewRevisionModel {
    var revision = 0
}

private struct SplitViewRevisionRoot: View {
    var model: SplitViewRevisionModel

    var body: some View {
        HSplitView {
            SplitViewRevisionPane(
                color: .red,
                revision: model.revision
            )
            Color.blue
        }
    }
}

private struct SplitViewRevisionPane: View {
    var color: VUI.Color
    var revision: Int

    var body: some View {
        color.overlay {
            Text("\(revision)")
        }
    }
}

@MainActor
private final class SplitViewHostController: WindowController,
    @unchecked Sendable
{
    let testWindow = SplitViewTestWindow()

    override var window: (any VVD.Window)? { testWindow }

    init<Content: View>(content: Content) {
        super.init(
            content: content,
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(SplitViewHostController.self)
            )
        )
    }
}

private enum SplitViewCursorChange: Equatable {
    case horizontal
    case vertical
    case platformDefault
    case other
}

@MainActor
private final class SplitViewTestWindow: VVD.Window {
    var activated = true
    var visible = true
    var contentBounds = CGRect(x: 0, y: 0, width: 600, height: 420)
    var windowFrame = CGRect(x: 0, y: 0, width: 600, height: 420)
    var contentScaleFactor: CGFloat = 1
    var resolution = CGSize(width: 600, height: 420)
    var origin = CGPoint.zero
    var contentSize = CGSize(width: 600, height: 420)
    var title = "Split View Test"
    weak var delegate: WindowDelegate?
    var screen: (any VVD.Screen)? { nil }
    var isValid: Bool { true }
    var platformHandle: OpaquePointer? { nil }
    var eventObservers = WindowEventObserverContainer()
    var cursorChanges: [SplitViewCursorChange] = []

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

    func show() {}
    func hide() {}
    func activate() {}
    func minimize() {}
    func requestToClose() -> Bool { true }
    func close() {}

    func setCursor(_ cursor: Cursor?, forDeviceID _: Int) {
        switch cursor {
        case .resizeLeftRight:
            cursorChanges.append(.horizontal)
        case .resizeUpDown:
            cursorChanges.append(.vertical)
        case nil:
            cursorChanges.append(.platformDefault)
        default:
            cursorChanges.append(.other)
        }
    }

    func cursor(forDeviceID _: Int) -> Cursor? { nil }
    func convertPointToScreen(_ point: CGPoint) -> CGPoint { point }
    func convertPointFromScreen(_ point: CGPoint) -> CGPoint { point }
}
