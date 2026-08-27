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

    func testAccessKeysPreferTheFirstUnusedTitleCharacter() {
        let presenter = WindowCommandMenuPresenter()
        presenter.update(
            items: [
                MainMenuItem(name: "File", id: .file, groups: []),
                MainMenuItem(name: "Format", id: .format, groups: []),
                MainMenuItem(name: "Edit", id: .edit, groups: []),
            ],
            environment: EnvironmentValues(),
            hostEnvironment: EnvironmentValues(),
            sceneResources: SceneResources()
        )

        XCTAssertEqual(presenter.accessKey(for: .file), "F")
        XCTAssertEqual(presenter.accessKey(for: .format), "o")
        XCTAssertEqual(presenter.accessKey(for: .edit), "E")
    }

    func testRendererShortcutUsesPortableModifierSymbols() {
        let shortcut = KeyboardShortcut(
            "R",
            modifiers: [.control, .option, .shift, .command]
        )
        let names = menuKeyboardShortcutSymbolNames(
            for: shortcut.modifiers
        )

        XCTAssertEqual(names, [
            "keyboard.control",
            "keyboard.option",
            "keyboard.shift",
            "keyboard.command",
        ])
        for name in names {
            XCTAssertNotNil(SymbolAssetCatalog.resolve(
                name: name,
                variableValue: nil,
                bundle: nil
            ))
        }
        XCTAssertEqual(shortcut.displayLabel, "Ctrl+Alt+Shift+Cmd+R")
    }

    @MainActor
    func testKeyboardRoutesNestedShortcutsAndTraversesTheMenuBar() throws {
        let previousAppContext = appContext
        appContext = WindowCommandMenuTestAppContext()
        defer { appContext = previousAppContext }

        var disabledInvocations = 0
        var nestedInvocations = 0
        let fileID = MainMenuItem.Identifier.file
        let editID = MainMenuItem.Identifier.edit
        let shortcut = KeyboardShortcut(
            "R",
            modifiers: [.command, .shift]
        )
        let presenter = WindowCommandMenuPresenter()
        let environment = EnvironmentValues()
        presenter.update(
            items: [
                MainMenuItem(
                    name: "File",
                    id: fileID,
                    groups: [
                        CommandAccumulator.Result(
                            viewContent: AnyView(TupleView((
                                Button("Disabled") {
                                    disabledInvocations += 1
                                }
                                .keyboardShortcut(shortcut)
                                .disabled(true),
                                Button("File Action") {},
                                Menu("Nested") {
                                    Button("Run") {
                                        nestedInvocations += 1
                                    }
                                    .keyboardShortcut(shortcut)
                                }
                            )))
                        ),
                    ]
                ),
                MainMenuItem(
                    name: "Edit",
                    id: editID,
                    groups: [
                        CommandAccumulator.Result(
                            viewContent: AnyView(TupleView((
                                Button("Edit Action") {},
                                Button("Second Edit Action") {}
                            )))
                        ),
                    ]
                ),
            ],
            environment: environment,
            hostEnvironment: environment,
            sceneResources: SceneResources()
        )

        let controller = WindowController(
            content: presenter.rootView(sceneContent: AnyView(EmptyView())),
            environment: environment,
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(Self.self)
            )
        )
        controller.setWindowCommandMenuPresenter(presenter)
        var redraw = false
        controller.updateView(
            tick: 0,
            delta: 0,
            date: controller.date,
            contentSize: CGSize(width: 320, height: 208),
            redraw: &redraw
        ) { _, _ in }

        let shortcutDown = keyboardEvent(
            .keyDown,
            key: .r,
            text: "R",
            modifiers: [.command, .shift]
        )
        XCTAssertTrue(
            presenter.handleKeyboardEvent(shortcutDown, in: controller)
        )
        XCTAssertEqual(disabledInvocations, 0)
        XCTAssertEqual(nestedInvocations, 1)
        XCTAssertTrue(presenter.handleKeyboardEvent(
            keyboardEvent(
                .keyUp,
                key: .r,
                text: "R",
                modifiers: [.command, .shift]
            ),
            in: controller
        ))

        XCTAssertTrue(presenter.handleKeyboardEvent(
            keyboardEvent(.keyDown, key: .f10, modifiers: [.function]),
            in: controller
        ))
        XCTAssertTrue(presenter.keyboardMenuIsActive)
        XCTAssertEqual(presenter.keyboardSelectedItemID, fileID)

        let responders = try menuResponders(in: controller)
        let fileResponder = try XCTUnwrap(responders[fileID])
        let editResponder = try XCTUnwrap(responders[editID])
        XCTAssertFalse(fileResponder.menuIsOpen)

        XCTAssertTrue(presenter.handleKeyboardEvent(
            keyboardEvent(.keyDown, key: .down),
            in: controller
        ))
        XCTAssertTrue(fileResponder.menuIsOpen)

        let filePopup = try XCTUnwrap(
            firstMenuPopup(in: controller)
        )
        let firstFileSelection = try XCTUnwrap(
            filePopup.keyboardSelectionID
        )
        XCTAssertTrue(filePopup.handleKeyboardEvent(
            event: keyboardEvent(.keyDown, key: .down),
            at: filePopup.currentTimestamp
        ))
        XCTAssertNotEqual(filePopup.keyboardSelectionID, firstFileSelection)
        XCTAssertTrue(filePopup.handleKeyboardEvent(
            event: keyboardEvent(.keyDown, key: .right),
            at: filePopup.currentTimestamp
        ))
        let nestedPopup = try XCTUnwrap(firstMenuPopup(in: filePopup))
        XCTAssertNotNil(nestedPopup.keyboardSelectionID)
        XCTAssertTrue(nestedPopup.handleKeyboardEvent(
            event: keyboardEvent(.keyDown, key: .r),
            at: nestedPopup.currentTimestamp
        ))
        XCTAssertEqual(nestedInvocations, 2)
        XCTAssertFalse(fileResponder.menuIsOpen)
        XCTAssertFalse(presenter.keyboardMenuIsActive)

        XCTAssertTrue(presenter.handleKeyboardEvent(
            keyboardEvent(.keyDown, key: .f10, modifiers: [.function]),
            in: controller
        ))
        XCTAssertTrue(presenter.handleKeyboardEvent(
            keyboardEvent(.keyDown, key: .down),
            in: controller
        ))
        XCTAssertTrue(fileResponder.menuIsOpen)

        XCTAssertTrue(controller.handleKeyboardEvent(event: keyboardEvent(
            .keyDown,
            key: .right
        )))
        XCTAssertFalse(fileResponder.menuIsOpen)
        XCTAssertTrue(editResponder.menuIsOpen)
        XCTAssertEqual(presenter.keyboardSelectedItemID, editID)

        XCTAssertTrue(controller.handleKeyboardEvent(event: keyboardEvent(
            .keyDown,
            key: .escape
        )))
        XCTAssertFalse(editResponder.menuIsOpen)
        XCTAssertTrue(presenter.keyboardMenuIsActive)
        XCTAssertEqual(presenter.keyboardSelectedItemID, editID)

        XCTAssertTrue(controller.handleKeyboardEvent(event: keyboardEvent(
            .keyDown,
            key: .escape
        )))
        XCTAssertFalse(presenter.keyboardMenuIsActive)
        XCTAssertNil(presenter.keyboardSelectedItemID)

        XCTAssertTrue(controller.handleKeyboardEvent(event: keyboardEvent(
            .keyDown,
            key: .f,
            modifiers: [.option]
        )))
        XCTAssertTrue(controller.handleKeyboardEvent(event: keyboardEvent(
            .keyUp,
            key: .f,
            modifiers: [.option]
        )))
        XCTAssertTrue(fileResponder.menuIsOpen)
        XCTAssertEqual(presenter.keyboardSelectedItemID, fileID)
        let accessKeyPopup = try XCTUnwrap(firstMenuPopup(in: controller))
        let firstAccessKeySelection = try XCTUnwrap(
            accessKeyPopup.keyboardSelectionID
        )
        XCTAssertTrue(controller.handleKeyboardEvent(event: keyboardEvent(
            .keyDown,
            key: .down
        )))
        XCTAssertNotEqual(
            accessKeyPopup.keyboardSelectionID,
            firstAccessKeySelection
        )
        controller.dismissAllPresentationChildren()
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

    private func menuResponders(
        in controller: WindowController
    ) throws -> [MainMenuItem.Identifier: MenuControlResponder] {
        let root = try XCTUnwrap(
            controller.viewGraph.responderNode as? MultiViewResponder
        )
        return Dictionary(uniqueKeysWithValues: responderTree(root).compactMap {
            responder -> (MainMenuItem.Identifier, MenuControlResponder)? in
            guard let menu = responder as? MenuControlResponder,
                  let id = menu.menuBarItemIdentifier?.base
                    as? MainMenuItem.Identifier else {
                return nil
            }
            return (id, menu)
        })
    }

    private func keyboardEvent(
        _ type: KeyboardEventType,
        key: VirtualKey,
        text: String = "",
        modifiers: KeyboardModifierFlags = []
    ) -> KeyboardEvent {
        KeyboardEvent(
            type: type,
            window: nil,
            deviceID: 7,
            key: key,
            text: text,
            isRepeat: false,
            modifiers: modifiers
        )
    }

    private func firstMenuPopup(
        in controller: WindowController
    ) -> ContextMenuWindowController? {
        var result: ContextMenuWindowController?
        controller.forEachPresentationChild { child in
            if result == nil {
                result = child as? ContextMenuWindowController
            }
        }
        return result
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
