import Foundation
import XCTest
@testable import VVD
@testable import VUI

final class PlatformCommandMenuPresenterTests: XCTestCase {
    func testAutomaticPresentationStyleResolvesAtTheRootPresenter() {
#if os(macOS)
        XCTAssertEqual(
            CommandMenuPresentationStyle.automatic.resolvedForRootPresenter,
            .platform
        )
#else
        XCTAssertEqual(
            CommandMenuPresentationStyle.automatic.resolvedForRootPresenter,
            .window
        )
#endif
        XCTAssertEqual(
            CommandMenuPresentationStyle.window.resolvedForRootPresenter,
            .window
        )
        XCTAssertEqual(
            CommandMenuPresentationStyle.platform.resolvedForRootPresenter,
            .platform
        )

        XCTAssertEqual(
            CommandMenuPresentationStyle.window.rootPresenterSelection(
                platformControllerAvailable: nil
            ),
            .window
        )
        XCTAssertEqual(
            CommandMenuPresentationStyle.platform.rootPresenterSelection(
                platformControllerAvailable: nil
            ),
            .pendingPlatformCapability
        )
        XCTAssertEqual(
            CommandMenuPresentationStyle.platform.rootPresenterSelection(
                platformControllerAvailable: true
            ),
            .platform
        )
        XCTAssertEqual(
            CommandMenuPresentationStyle.platform.rootPresenterSelection(
                platformControllerAvailable: false
            ),
            .window
        )
    }

    @MainActor
    func testSnapshotBuilderConvertsItemsAndQueuesActionsOnTheRootHost() throws {
        // ASSERTIONS commandsMainMenuHostValidationActionShortcutObserved commandsMainMenuHostNestedMaterializationObserved
        let counter = PlatformMenuActionCounter()
        let controller = WindowController(
            content: EmptyView(),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(Self.self)
            )
        )
        let withGC: WindowContext.WithGraphicsContext = { _, _ in }
        controller.updateFrame(
            tick: 0,
            delta: 0,
            date: controller.date,
            contentSize: CGSize(width: 200, height: 120),
            shouldDrawFrame: false,
            withGC
        )

        var actionItem = PlatformItemList.Item()
        actionItem.label = NSAttributedString(string: "Run")
        actionItem.platformIdentifier = "run"
        actionItem.toggleState = .mixed
        actionItem.keyboardShortcut = KeyboardShortcut(
            KeyEquivalent("\u{F70B}"),
            modifiers: [.command, .shift]
        )
        actionItem.tooltip = "Run the command"
        actionItem.selectionBehavior = selectionBehavior {
            counter.value += 1
        }

        var submenuChild = PlatformItemList.Item()
        submenuChild.text = NSAttributedString(string: "Unavailable")

        var submenu = PlatformItemList.Item(systemItem: .menu)
        submenu.label = NSAttributedString(string: "More")
        submenu.isEnabled = false
        submenu.wantsPlatformInterfaceValidation = true
        submenu.children = PlatformItemList(items: [submenuChild])

        var sectionChild = PlatformItemList.Item()
        sectionChild.label = NSAttributedString(string: "Section Action")
        sectionChild.selectionBehavior = selectionBehavior {}

        var section = PlatformItemList.Item(systemItem: .section)
        section.label = NSAttributedString(string: "Section")
        section.children = PlatformItemList(items: [sectionChild])

        let input = PendingWindowMenuSnapshot(
            menus: [
                PendingWindowMenu(
                    id: "commands.fixture",
                    title: "Fixture",
                    role: .file,
                    items: PlatformItemList(items: [
                        actionItem,
                        PlatformItemList.Item(systemItem: .divider),
                        submenu,
                        section,
                    ])
                ),
            ],
            environment: EnvironmentValues(),
            actionDispatcher: PlatformCommandMenuActionDispatcher(
                owner: controller
            )
        )
        let snapshot = try XCTUnwrap(WindowMenuSnapshotBuilder.build(
            input,
            graphicsDevice: nil
        ))

        let menu = try XCTUnwrap(snapshot.menus.first)
        XCTAssertEqual(menu.id, "commands.fixture")
        XCTAssertEqual(menu.title, "Fixture")
        XCTAssertEqual(menu.role, .file)
        XCTAssertEqual(menu.elements.count, 7)

        guard case let .item(run) = menu.elements[0],
              case .separator = menu.elements[1],
              case let .submenu(more) = menu.elements[2],
              case .separator = menu.elements[3],
              case let .item(header) = menu.elements[4],
              case let .item(sectionAction) = menu.elements[5],
              case .separator = menu.elements[6] else {
            return XCTFail("Unexpected platform menu structure")
        }

        XCTAssertEqual(run.id, "commands.fixture/run")
        XCTAssertEqual(run.title, "Run")
        XCTAssertEqual(run.state, .mixed)
        XCTAssertTrue(run.isEnabled)
        XCTAssertEqual(
            run.shortcut,
            WindowMenu.Shortcut(.f8, modifiers: [.command, .shift])
        )
        XCTAssertEqual(run.toolTip, "Run the command")

        XCTAssertEqual(more.title, "More")
        XCTAssertTrue(more.isEnabled)
        XCTAssertTrue(more.usesPlatformItemValidation)
        guard case let .item(unavailable) = more.elements.first else {
            return XCTFail("Expected nested menu item")
        }
        XCTAssertFalse(unavailable.isEnabled)

        XCTAssertEqual(header.title, "Section")
        XCTAssertFalse(header.isEnabled)
        XCTAssertEqual(sectionAction.title, "Section Action")
        XCTAssertTrue(sectionAction.isEnabled)

        run.action?()
        XCTAssertEqual(counter.value, 0)
        controller.updateFrame(
            tick: 1,
            delta: 1.0 / 60.0,
            date: controller.date.addingTimeInterval(1.0 / 60.0),
            contentSize: CGSize(width: 200, height: 120),
            shouldDrawFrame: false,
            withGC
        )
        XCTAssertEqual(counter.value, 1)
    }

    func testSnapshotBuilderRendersNamedImagesOffscreen() throws {
        guard let deviceContext = makeGraphicsDeviceContext(api: .metal) else {
            throw XCTSkip("Metal graphics device is unavailable")
        }

        var item = PlatformItemList.Item()
        item.label = NSAttributedString(string: "Play")
        item.namedResolvedImage = VUI.Image(systemName: "play")
        item.selectionBehavior = selectionBehavior {}

        let input = PendingWindowMenuSnapshot(
            menus: [
                PendingWindowMenu(
                    id: "commands.image",
                    title: "Image",
                    role: .custom,
                    items: PlatformItemList(items: [item])
                ),
            ],
            environment: EnvironmentValues(),
            actionDispatcher: PlatformCommandMenuActionDispatcher(
                owner: WindowController(
                    content: EmptyView(),
                    scene: WindowKey(
                        namespace: .app,
                        sceneID: SceneID(Self.self)
                    )
                )
            )
        )
        let snapshot = try XCTUnwrap(WindowMenuSnapshotBuilder.build(
            input,
            graphicsDevice: deviceContext.device
        ))
        guard case let .item(renderedItem) = try XCTUnwrap(
            snapshot.menus.first?.elements.first
        ) else {
            return XCTFail("Expected a rendered menu item")
        }
        let image = try XCTUnwrap(renderedItem.image)

        XCTAssertEqual(image.width, 32)
        XCTAssertEqual(image.height, 32)
        XCTAssertEqual(image.pixelFormat, .rgba8)
        XCTAssertTrue(
            stride(from: 3, to: image.data.count, by: 4).contains {
                image.data[$0] > 0
            }
        )
    }

    @MainActor
    func testControllerRefreshReturnsThroughTheRootUpdateLane() async throws {
        // ASSERTIONS commandsMainMenuHostRefreshObserved commandsMainMenuHostDeferredRefreshRuntimeObserved
        let controller = WindowController(
            content: EmptyView(),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(Self.self)
            )
        )
        let withGC: WindowContext.WithGraphicsContext = { _, _ in }
        controller.updateFrame(
            tick: 0,
            delta: 0,
            date: controller.date,
            contentSize: CGSize(width: 200, height: 120),
            shouldDrawFrame: false,
            withGC
        )

        let identifier = MainMenuItem.Identifier.custom(UUID())
        let presenter = PlatformCommandMenuPresenter(owner: controller)
        controller.platformCommandMenuPresenter = presenter
        presenter.update(
            items: [
                MainMenuItem(
                    name: "Refresh",
                    id: identifier,
                    groups: [
                        CommandAccumulator.Result(
                            viewContent: AnyView(Button("Action") {})
                        ),
                    ]
                ),
            ],
            environment: EnvironmentValues()
        )

        let menuController = PlatformMenuControllerRecorder()
        presenter.attach(to: menuController)
        presenter.update(at: Time(seconds: 0))
        try await waitUntil { menuController.menu != nil }
        XCTAssertEqual(menuController.menu?.menus.first?.title, "Refresh")
        let initialSetMenuCount = menuController.setMenuCount

        menuController.requestRefresh(
            menuID: "commands.custom." + identifier.customID.uuidString
        )
        presenter.update(at: Time(seconds: 1))
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(menuController.setMenuCount, initialSetMenuCount)

        controller.updateFrame(
            tick: 1,
            delta: 1.0 / 60.0,
            date: controller.date.addingTimeInterval(1.0 / 60.0),
            contentSize: CGSize(width: 200, height: 120),
            shouldDrawFrame: false,
            withGC
        )
        presenter.update(at: Time(seconds: 1))
        try await waitUntil {
            menuController.setMenuCount == initialSetMenuCount + 1
        }

        presenter.invalidate()
        await Task.yield()
        XCTAssertNil(menuController.menu)
        XCTAssertNil(menuController.delegate)
    }

    private func selectionBehavior(
        action: @escaping () -> Void
    ) -> PlatformItemList.Item.SelectionBehavior {
        PlatformItemList.Item.SelectionBehavior(
            isMomentary: true,
            isContainerSelection: true,
            yieldsToContainerSelection: false,
            isPickerOption: false,
            visualStyle: .plain,
            onSelect: action,
            onDeselect: nil,
            springLoadingBehavior: .automatic
        )
    }

    @MainActor
    private func waitUntil(
        _ condition: () -> Bool,
        timeout: Duration = .seconds(2)
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition() {
            guard clock.now < deadline else {
                return XCTFail("Timed out waiting for a platform menu update")
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

private final class PlatformMenuActionCounter: @unchecked Sendable {
    var value = 0
}

@MainActor
private final class PlatformMenuControllerRecorder: WindowMenuController {
    weak var delegate: (any WindowMenuControllerDelegate)?
    private(set) var menu: WindowMenu?
    private(set) var setMenuCount = 0

    func setMenu(_ menu: WindowMenu?) {
        self.menu = menu
        setMenuCount += 1
    }

    func requestRefresh(menuID: WindowMenu.ID?) {
        delegate?.windowMenuController(self, needsUpdateMenu: menuID)
    }
}

private extension MainMenuItem.Identifier {
    var customID: UUID {
        guard case let .custom(id) = self else {
            fatalError("Expected a custom menu identifier")
        }
        return id
    }
}
