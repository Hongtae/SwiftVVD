import XCTest
@testable import VVD
@testable import VUI

final class WindowCommandMenuPresenterTests: XCTestCase {
    func testMenuBarClientAllocationPreservesSceneContentSize() {
        let sceneSize = CGSize(width: 900, height: 620)
        let platformSize = WindowCommandMenuPresenter.platformContentSize(
            preserving: sceneSize
        )

        XCTAssertEqual(
            platformSize,
            CGSize(
                width: 900,
                height: 620 + WindowCommandMenuPresenter.menuBarHeight
            )
        )
        XCTAssertEqual(
            WindowCommandMenuPresenter.sceneContentSize(
                from: platformSize
            ),
            sceneSize
        )
    }

    @MainActor
    func testRendererMenuUsesRootResponderPopupAndMaterializationEnvironment()
        throws
    {
        let previousAppContext = appContext
        appContext = WindowCommandMenuTestAppContext()
        defer { appContext = previousAppContext }

        var menuEnvironment = EnvironmentValues()
        menuEnvironment.commandMenuEnvironmentProbeValue = "app"
        menuEnvironment.defaultPresentationHostMode = .overlay
        menuEnvironment.defaultFontRenderingMode = .vector()

        var sceneEnvironment = EnvironmentValues()
        sceneEnvironment.commandMenuEnvironmentProbeValue = "scene"
        sceneEnvironment.defaultPresentationHostMode = .platformWindow

        let presenter = WindowCommandMenuPresenter()
        presenter.update(
            items: [
                MainMenuItem(
                    name: "Fixture",
                    id: .custom(UUID()),
                    groups: [
                        CommandAccumulator.Result(
                            viewContent: AnyView(
                                CommandMenuEnvironmentProbeButton()
                            )
                        ),
                    ]
                ),
                MainMenuItem(
                    name: "Second Fixture",
                    id: .custom(UUID()),
                    groups: []
                ),
            ],
            environment: menuEnvironment,
            hostEnvironment: sceneEnvironment,
            sceneResources: SceneResources()
        )

        let controller = WindowController(
            content: presenter.rootView(sceneContent: AnyView(EmptyView())),
            environment: sceneEnvironment,
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(Self.self)
            )
        )
        let sceneSize = CGSize(width: 320, height: 180)
        let platformSize = WindowCommandMenuPresenter.platformContentSize(
            preserving: sceneSize
        )
        var redraw = false
        controller.updateView(
            tick: 0,
            delta: 0,
            date: controller.date,
            contentSize: platformSize,
            redraw: &redraw
        ) { _, _ in }

        let rootResponder = try XCTUnwrap(
            controller.viewGraph.responderNode as? MultiViewResponder
        )
        let menuResponders = responderTree(rootResponder).compactMap {
            $0 as? MenuControlResponder
        }
        XCTAssertEqual(menuResponders.count, 2)
        let menuFrames = menuResponders.map(globalFrame).sorted {
            $0.minX < $1.minX
        }
        XCTAssertLessThanOrEqual(menuFrames[0].maxX, menuFrames[1].minX)
        XCTAssertLessThan(menuFrames[1].maxX, platformSize.width)
        XCTAssertGreaterThan(menuFrames[0].width, 16)
        XCTAssertGreaterThan(menuFrames[1].width, 16)
        XCTAssertGreaterThan(menuFrames[1].width, menuFrames[0].width)

        let menuResponder = try XCTUnwrap(menuResponders.first)
        XCTAssertEqual(
            menuResponder.helper.size.height,
            WindowCommandMenuPresenter.menuBarHeight,
            accuracy: 0.001
        )

        let items = controller.viewGraph.data.withCurrent {
            menuResponder.itemList.value.menuItems
        }
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(
            (items[0].label ?? items[0].text)?.string,
            "app-platformWindow"
        )

        var points = [CGPoint(
            x: menuResponder.helper.size.width / 2,
            y: menuResponder.helper.size.height / 2
        )]
        menuResponder.helper.transform.convertGlobal(
            from: .local,
            points: &points
        )
        let center = try XCTUnwrap(points.first)
        XCTAssertLessThanOrEqual(
            center.y,
            WindowCommandMenuPresenter.menuBarHeight
        )

        XCTAssertTrue(controller.handleMouseEvent(event: MouseEvent(
            type: .buttonDown,
            device: .genericMouse,
            deviceID: 0,
            buttonID: 0,
            location: center,
            timestamp: 0
        )))
        XCTAssertTrue(menuResponder.menuIsOpen)

        var discoveredPopup: ContextMenuWindowController?
        controller.forEachPresentationChild { child in
            if discoveredPopup == nil {
                discoveredPopup = child as? ContextMenuWindowController
            }
        }
        let popup = try XCTUnwrap(discoveredPopup)
        XCTAssertEqual(
            popup.presentationPointInParent(forLocalPoint: CGPoint.zero).y,
            WindowCommandMenuPresenter.menuBarHeight,
            accuracy: 0.001
        )
        controller.dismissAllPresentationChildren()
    }

    private func responderTree(_ responder: ViewResponder) -> [ViewResponder] {
        [responder] + responder.children.flatMap(responderTree)
    }

    private func globalFrame(_ responder: MenuControlResponder) -> CGRect {
        var points = [
            CGPoint.zero,
            CGPoint(
                x: responder.helper.size.width,
                y: responder.helper.size.height
            ),
        ]
        responder.helper.transform.convertGlobal(
            from: .local,
            points: &points
        )
        return CGRect(
            x: min(points[0].x, points[1].x),
            y: min(points[0].y, points[1].y),
            width: abs(points[1].x - points[0].x),
            height: abs(points[1].y - points[0].y)
        )
    }
}

private final class WindowCommandMenuTestAppContext: AppContext {
    let graphicsDeviceContext: GraphicsDeviceContext? = nil
    let audioDeviceContext: AudioDeviceContext? = nil
    var appWindowsController: AppWindowsController? { nil }
    private var resources: [URL: any DataProtocol] = [:]

    func resourceData(forURL url: URL) -> (any DataProtocol)? {
        resources[url]
    }

    func setResource(data: (any DataProtocol)?, forURL url: URL) {
        resources[url] = data
    }

    func checkWindowActivities() {
    }
}

private struct CommandMenuEnvironmentProbeValueKey: EnvironmentKey {
    static let defaultValue = "default"
}

private extension EnvironmentValues {
    var commandMenuEnvironmentProbeValue: String {
        get { self[CommandMenuEnvironmentProbeValueKey.self] }
        set { self[CommandMenuEnvironmentProbeValueKey.self] = newValue }
    }
}

private struct CommandMenuEnvironmentProbeButton: View {
    @Environment(\.commandMenuEnvironmentProbeValue)
    private var value

    @Environment(\.defaultPresentationHostMode)
    private var presentationHostMode

    var body: some View {
        Button("\(value)-\(hostModeName)") {}
    }

    private var hostModeName: String {
        switch presentationHostMode {
        case .overlay:
            return "overlay"
        case .platformWindow:
            return "platformWindow"
        }
    }
}
