import XCTest
@testable import VVD
@testable import VUI

final class WindowSceneDefaultsTests: XCTestCase {
    // ASSERTIONS sceneDefaultWindowRuntimeObserved
    func testOutermostSceneDefaultsReplaceInnerValues() throws {
        let appGraph = AppGraph(app: SceneDefaultsModifierTestApp())
        let items = try _AGGraph.withCurrent(appGraph.graph) {
            try XCTUnwrap(appGraph.sceneListAttr).value
        }
        let item = try XCTUnwrap(items.first)

        XCTAssertEqual(
            item.sceneConfiguration.defaultSize,
            CGSize(width: 900, height: 620)
        )
        XCTAssertEqual(
            item.sceneConfiguration.defaultPosition,
            .bottomTrailing
        )
    }

    @MainActor
    func testInitialDefaultsSizeContentBeforePositioningOuterWindowFrame() {
        let screen = SceneDefaultsTestScreen(
            frame: CGRect(x: 0, y: 0, width: 2560, height: 1600),
            visibleFrame: CGRect(x: 20, y: 30, width: 2520, height: 1530)
        )
        let window = SceneDefaultsTestWindow(
            screen: screen,
            contentScaleFactor: 2,
            decorationSize: CGSize(width: 16, height: 38)
        )
        var configuration = WindowSceneConfiguration()
        configuration.defaultSize = CGSize(width: 900, height: 620)
        configuration.defaultPosition = .bottomTrailing

        WindowContext.applyInitialSceneConfiguration(configuration, to: window)

        XCTAssertEqual(window.contentSize, CGSize(width: 900, height: 620))
        XCTAssertEqual(window.contentBounds.size, CGSize(width: 900, height: 620))
        XCTAssertEqual(window.windowFrame.size, CGSize(width: 1816, height: 1278))
        XCTAssertEqual(window.origin, CGPoint(x: 724, y: 282))
        XCTAssertEqual(window.operations, [.contentSize, .origin])
    }

    @MainActor
    func testInitialPositionUsesExistingOuterFrameWhenSizeIsUnspecified() {
        let screen = SceneDefaultsTestScreen(
            frame: CGRect(x: -400, y: 0, width: 1600, height: 1000),
            visibleFrame: CGRect(x: -380, y: 24, width: 1560, height: 936)
        )
        let window = SceneDefaultsTestWindow(
            screen: screen,
            contentScaleFactor: 1,
            decorationSize: CGSize(width: 20, height: 40),
            initialContentSize: CGSize(width: 600, height: 400)
        )
        var configuration = WindowSceneConfiguration()
        configuration.defaultPosition = UnitPoint(x: 0.25, y: 0.75)

        WindowContext.applyInitialSceneConfiguration(configuration, to: window)

        XCTAssertEqual(window.contentSize, CGSize(width: 600, height: 400))
        XCTAssertEqual(window.windowFrame.size, CGSize(width: 620, height: 440))
        XCTAssertEqual(window.origin, CGPoint(x: -145, y: 396))
        XCTAssertEqual(window.operations, [.origin])
    }

    @MainActor
    func testInitialWindowCentersAfterApplyingDefaultContentSize() {
        let screen = SceneDefaultsTestScreen(
            frame: CGRect(x: 0, y: 0, width: 1800, height: 1200),
            visibleFrame: CGRect(x: 0, y: 32, width: 1800, height: 1100)
        )
        let window = SceneDefaultsTestWindow(
            screen: screen,
            contentScaleFactor: 1,
            decorationSize: CGSize(width: 0, height: 32)
        )
        var configuration = WindowSceneConfiguration()
        configuration.defaultSize = CGSize(width: 900, height: 620)

        WindowContext.applyInitialSceneConfiguration(configuration, to: window)

        XCTAssertEqual(window.windowFrame.size, CGSize(width: 900, height: 652))
        XCTAssertEqual(window.origin, CGPoint(x: 450, y: 256))
        XCTAssertEqual(window.operations, [.contentSize, .origin])
    }

    @MainActor
    func testInitialPositionIsLeftToPlatformWhenScreenIsUnavailable() {
        let window = SceneDefaultsTestWindow(
            screen: nil,
            contentScaleFactor: 1,
            decorationSize: CGSize(width: 20, height: 40)
        )
        var configuration = WindowSceneConfiguration()
        configuration.defaultSize = CGSize(width: 700, height: 500)
        configuration.defaultPosition = .center

        WindowContext.applyInitialSceneConfiguration(configuration, to: window)

        XCTAssertEqual(window.contentSize, CGSize(width: 700, height: 500))
        XCTAssertEqual(window.origin, .zero)
        XCTAssertEqual(window.operations, [.contentSize])
    }
}

private struct SceneDefaultsModifierTestApp: App {
    init() {}

    var body: some VUI.Scene {
        WindowGroup("Scene defaults modifier test") {
            EmptyView()
        }
        .defaultSize(width: 700, height: 500)
        .defaultSize(width: 900, height: 620)
        .defaultPosition(.topLeading)
        .defaultPosition(.bottomTrailing)
    }
}

private struct SceneDefaultsTestScreen: VVD.Screen {
    let id = ScreenID(rawValue: 1)
    let frame: CGRect
    let visibleFrame: CGRect
    let safeAreaInsets = ScreenInsets.zero
    let scaleFactor: CGFloat = 1
    let displayModeResolution: CGSize = .zero
}

@MainActor
private final class SceneDefaultsTestWindow: VVD.Window {
    enum Operation: Equatable {
        case contentSize
        case origin
    }

    var activated = false
    var visible = false
    var contentBounds: CGRect
    var windowFrame: CGRect
    let contentScaleFactor: CGFloat
    var resolution: CGSize
    var title = "Scene defaults test"
    weak var delegate: WindowDelegate?
    let screen: (any VVD.Screen)?
    var isValid = true
    var platformHandle: OpaquePointer? { nil }
    var eventObservers = WindowEventObserverContainer()
    private let decorationSize: CGSize
    private var storedContentSize: CGSize
    var operations: [Operation] = []

    var origin: CGPoint {
        get { windowFrame.origin }
        set {
            windowFrame.origin = newValue
            operations.append(.origin)
        }
    }

    var contentSize: CGSize {
        get { storedContentSize }
        set {
            storedContentSize = newValue
            contentBounds.size = newValue
            resolution = newValue * contentScaleFactor
            windowFrame.size = CGSize(
                width: resolution.width + decorationSize.width,
                height: resolution.height + decorationSize.height
            )
            operations.append(.contentSize)
        }
    }

    init(
        screen: (any VVD.Screen)?,
        contentScaleFactor: CGFloat,
        decorationSize: CGSize,
        initialContentSize: CGSize = CGSize(width: 640, height: 480)
    ) {
        self.screen = screen
        self.contentScaleFactor = contentScaleFactor
        self.decorationSize = decorationSize
        self.storedContentSize = initialContentSize
        self.contentBounds = CGRect(origin: .zero, size: initialContentSize)
        self.resolution = initialContentSize * contentScaleFactor
        self.windowFrame = CGRect(
            origin: .zero,
            size: CGSize(
                width: self.resolution.width + decorationSize.width,
                height: self.resolution.height + decorationSize.height
            )
        )
    }

    required init?(
        name: String,
        style: WindowStyle,
        delegate: WindowDelegate?,
        data: [String: Any]
    ) {
        self.screen = nil
        self.contentScaleFactor = 1
        self.decorationSize = .zero
        self.storedContentSize = .zero
        self.contentBounds = .zero
        self.resolution = .zero
        self.windowFrame = .zero
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
