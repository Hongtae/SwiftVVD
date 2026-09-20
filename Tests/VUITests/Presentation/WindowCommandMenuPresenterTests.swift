import XCTest
@testable import VVD
@testable import VUI

final class WindowCommandMenuPresenterTests: XCTestCase {
    // ASSERTIONS textPlatformRepresentation27Observed
    @MainActor
    func testMenuTextRepresentationOmitsDefaultsAndPreservesExplicitRuns() throws {
        let previousAppContext = appContext
        appContext = WindowCommandMenuTestAppContext()
        defer { appContext = previousAppContext }

        var environment = EnvironmentValues()
        environment.defaultFontRenderingMode = .vector()
        let presenter = WindowCommandMenuPresenter()
        presenter.update(
            items: [MainMenuItem(name: "Edit", id: .edit, groups: [
                CommandAccumulator.Result(viewContent: AnyView(VStack {
                    Button("Plain") {}
                    Button("Disabled") {}.disabled(true)
                    Button {} label: { Text("Explicit Red").foregroundStyle(.red) }
                    Button {} label: { Text("Bold").bold() }
                    Button {} label: { Text("Underline").underline() }
                    Button {} label: { Text("Inherited").background(Color.clear) }
                        .foregroundStyle(.green)
                    Button {} label: { Text("Explicit Font").font(.system(size: 23)) }
                    Button {} label: { Text("Color Reset").foregroundColor(nil) }
                    Button {} label: { Text("Font Reset").font(nil) }
                    Button {} label: {
                        Text("Mixed Plain ") + Text("Red").foregroundStyle(.red)
                    }
                    Button {} label: { Text("Styled Request").background(Color.clear) }
                        .foregroundStyle(.green)
                        .modifier(ViewInputFlagModifier(flag: IncludesStyledText()))
                }))
            ])],
            environment: environment,
            hostEnvironment: environment,
            sceneResources: SceneResources()
        )
        let controller = WindowController(
            content: presenter.rootView(sceneContent: AnyView(EmptyView())),
            environment: environment,
            scene: WindowKey(namespace: .app, sceneID: SceneID(Self.self))
        )
        var tick: UInt64 = 0
        updateController(controller, tick: &tick)
        let responder = try XCTUnwrap(menuResponders(in: controller)[.edit])
        let items = controller.viewGraph.data.withCurrent { responder.itemList.value.items }
        let labels = Dictionary(uniqueKeysWithValues: items.compactMap { item in
            (item.label ?? item.text).map { ($0.string, $0) }
        })
        XCTAssertEqual(labels.count, 11)
        let fontKey = NSAttributedString.Key("VUI.Font")
        let colorKey = NSAttributedString.Key("VUI.ForegroundColor")
        for title in ["Plain", "Disabled", "Bold", "Underline", "Inherited",
                      "Color Reset", "Font Reset", "Mixed Plain Red"] {
            let attributes = try XCTUnwrap(labels[title]).attributes(at: 0, effectiveRange: nil)
            XCTAssertNil(attributes[fontKey], title)
            XCTAssertNil(attributes[colorKey], title)
        }
        XCTAssertFalse(try XCTUnwrap(items.first { ($0.label ?? $0.text)?.string == "Disabled" }).isEnabled)
        let red = try XCTUnwrap(labels["Explicit Red"]?.attribute(colorKey, at: 0, effectiveRange: nil) as? VUI.Color)
        XCTAssertEqual(red.resolveHDR(in: environment), VUI.Color.red.resolveHDR(in: environment))
        XCTAssertNotNil(labels["Explicit Font"]?.attribute(fontKey, at: 0, effectiveRange: nil))
        XCTAssertNotNil(labels["Underline"]?.attribute(NSAttributedString.Key("VUI.UnderlineStyle"), at: 0, effectiveRange: nil))
        let mixed = try XCTUnwrap(labels["Mixed Plain Red"])
        let mixedRed = try XCTUnwrap(mixed.attribute(colorKey, at: mixed.length - 1, effectiveRange: nil) as? VUI.Color)
        XCTAssertEqual(mixedRed.resolveHDR(in: environment), VUI.Color.red.resolveHDR(in: environment))
        let styled = try XCTUnwrap(labels["Styled Request"])
        XCTAssertNotNil(styled.attribute(fontKey, at: 0, effectiveRange: nil))
        let inherited = try XCTUnwrap(styled.attribute(colorKey, at: 0, effectiveRange: nil) as? VUI.Color)
        XCTAssertEqual(inherited.resolveHDR(in: environment), VUI.Color.green.resolveHDR(in: environment))
    }

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
        var environment = EnvironmentValues()
        environment.defaultFontRenderingMode = .vector()
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
            presenter.handleShortcutKeyboardEvent(
                shortcutDown,
                in: controller
            )
        )
        XCTAssertEqual(disabledInvocations, 0)
        XCTAssertEqual(nestedInvocations, 1)
        XCTAssertTrue(presenter.handleShortcutKeyboardEvent(
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
        sceneEnvironment.defaultFontRenderingMode = .vector()

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

        var toolbarStorage = ToolbarStorage()
        toolbarStorage.configuration = ToolbarStorage.Configuration(
            customizationID: nil
        )
        toolbarStorage.items = [
            ToolbarStorage.Item(
                id: ToolbarStorage.ID("fixture-toolbar-item"),
                placement: .automatic,
                view: AnyView(Text("Toolbar"))
            ),
        ]
        let toolbarBridge = RootToolbarBridge()
        XCTAssertTrue(toolbarBridge.update(storage: toolbarStorage))

        // The renderer menu remains the outer chrome branch so its popup
        // anchor stays above the controller-owned root toolbar.
        let controller = WindowController(
            content: presenter.rootView(
                sceneContent: RootToolbarHost.hostRootView(
                    sceneContent: AnyView(EmptyView()),
                    bridge: toolbarBridge
                )
            ),
            environment: sceneEnvironment,
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(Self.self)
            )
        )
        let platformSize = CGSize(
            width: 320,
            height: 180
                + WindowCommandMenuPresenter.menuBarHeight
                + RootToolbarHost.toolbarHeight
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

    @MainActor
    func testPointerHoverSwitchesTheOpenTopLevelMenu() throws {
        let previousAppContext = appContext
        appContext = WindowCommandMenuTestAppContext()
        defer { appContext = previousAppContext }

        var environment = EnvironmentValues()
        environment.defaultPresentationHostMode = .overlay
        environment.defaultFontRenderingMode = .vector()
        let fileID = MainMenuItem.Identifier.file
        let editID = MainMenuItem.Identifier.edit
        let presenter = WindowCommandMenuPresenter()
        presenter.update(
            items: [
                MainMenuItem(
                    name: "File",
                    id: fileID,
                    groups: [CommandAccumulator.Result(
                        viewContent: AnyView(Button("File Action") {})
                    )]
                ),
                MainMenuItem(
                    name: "Edit",
                    id: editID,
                    groups: [CommandAccumulator.Result(
                        viewContent: AnyView(Button("Edit Action") {})
                    )]
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
        var tick: UInt64 = 0
        updateController(controller, tick: &tick)

        let responders = try menuResponders(in: controller)
        let fileResponder = try XCTUnwrap(responders[fileID])
        let editResponder = try XCTUnwrap(responders[editID])
        controller.viewGraph.data.withCurrent {
            fileResponder.present(from: controller)
        }
        updateController(controller, tick: &tick)

        let filePopup = try XCTUnwrap(firstMenuPopup(in: controller))
        XCTAssertTrue(fileResponder.menuIsOpen)
        XCTAssertFalse(editResponder.menuIsOpen)

        let editFrame = globalFrame(editResponder)
        XCTAssertTrue(controller.handleMouseHover(
            at: CGPoint(x: editFrame.midX, y: editFrame.midY),
            deviceID: 23,
            isTopMost: true,
            at: Time(seconds: 1)
        ))
        updateController(controller, tick: &tick, turns: 3)

        let editPopup = try XCTUnwrap(firstMenuPopup(in: controller))
        XCTAssertFalse(fileResponder.menuIsOpen)
        XCTAssertTrue(editResponder.menuIsOpen)
        XCTAssertFalse(filePopup === editPopup)
        XCTAssertFalse(presenter.keyboardMenuIsActive)
        XCTAssertNil(presenter.keyboardSelectedItemID)

        let fileFrame = globalFrame(fileResponder)
        XCTAssertTrue(controller.handleMouseHover(
            at: CGPoint(x: fileFrame.midX, y: fileFrame.midY),
            deviceID: 23,
            isTopMost: true,
            at: Time(seconds: 2)
        ))
        updateController(controller, tick: &tick, turns: 3)

        let reopenedFilePopup = try XCTUnwrap(firstMenuPopup(in: controller))
        XCTAssertTrue(fileResponder.menuIsOpen)
        XCTAssertFalse(editResponder.menuIsOpen)
        XCTAssertFalse(reopenedFilePopup === filePopup)
        XCTAssertFalse(reopenedFilePopup === editPopup)
        controller.dismissAllPresentationChildren()
    }

    // ASSERTIONS menuSubmenuActivationTransferObserved
    @MainActor
    func testRendererSubmenuReturnKeepsPopupContentAndChildIdentity() throws {
        let previousAppContext = appContext
        appContext = WindowCommandMenuTestAppContext()
        defer { appContext = previousAppContext }

        var environment = EnvironmentValues()
        environment.defaultPresentationHostMode = .overlay
        environment.defaultFontRenderingMode = .vector()
        let presenter = WindowCommandMenuPresenter()
        presenter.update(
            items: [
                MainMenuItem(
                    name: "Command Lab",
                    id: .custom(UUID()),
                    groups: [
                        CommandAccumulator.Result(
                            viewContent: AnyView(
                                Menu("Nested Commands") {
                                    Button("Nested Action") {}
                                }
                            )
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
        var tick: UInt64 = 0
        updateController(controller, tick: &tick)

        let menuResponder = try XCTUnwrap(
            menuResponders(in: controller).values.first
        )
        controller.viewGraph.data.withCurrent {
            menuResponder.present(from: controller)
        }
        updateController(controller, tick: &tick)

        let popup = try XCTUnwrap(firstMenuPopup(in: controller))
        _ = controller.handleMouseHover(
            at: popup.presentationPointInParent(
                forLocalPoint: try popupRowHoverPoint(in: popup)
            ),
            deviceID: 19,
            isTopMost: true,
            at: Time(seconds: 1)
        )
        updateController(controller, tick: &tick)

        let submenu = try XCTUnwrap(firstMenuPopup(in: popup))
        let submenuPointInPopup = submenu.presentationPointInParent(
            forLocalPoint: try popupRowHoverPoint(in: submenu)
        )
        _ = controller.handleMouseHover(
            at: popup.presentationPointInParent(
                forLocalPoint: submenuPointInPopup
            ),
            deviceID: 19,
            isTopMost: true,
            at: Time(seconds: 2)
        )
        updateController(controller, tick: &tick)
        XCTAssertFalse(popup.isActivated)
        XCTAssertTrue(submenu.isActivated)
        XCTAssertFalse(try popupHasAccentFill(popup))

        let popupContent = try XCTUnwrap(popup.viewGraph.data.withCurrent {
            popup.viewGraph.rootAnyViewContentInput?.value.storage
        })
        let submenuContent = try XCTUnwrap(submenu.viewGraph.data.withCurrent {
            submenu.viewGraph.rootAnyViewContentInput?.value.storage
        })
        let submenuSize = submenu.cachedContentSize
        let submenuOrigin = submenu.presentationPointInParent(
            forLocalPoint: .zero
        )

        _ = controller.handleMouseHover(
            at: popup.presentationPointInParent(
                forLocalPoint: try popupRowHoverPoint(in: popup)
            ),
            deviceID: 19,
            isTopMost: true,
            at: Time(seconds: 3)
        )
        updateController(controller, tick: &tick, turns: 1)

        XCTAssertTrue(popup.isActivated)
        XCTAssertFalse(submenu.isActivated)
        XCTAssertTrue(try popupHasAccentFill(popup))
        XCTAssertTrue(try popupHasDrawContent(submenu))
        XCTAssertEqual(submenu.cachedContentSize, submenuSize)
        XCTAssertEqual(
            submenu.presentationPointInParent(forLocalPoint: .zero),
            submenuOrigin
        )
        XCTAssertTrue(firstMenuPopup(in: popup) === submenu)
        XCTAssertTrue(popup.viewGraph.data.withCurrent {
            guard let current = popup.viewGraph.rootAnyViewContentInput?
                .value.storage else {
                return false
            }
            return current === popupContent
        })
        XCTAssertTrue(submenu.viewGraph.data.withCurrent {
            guard let current = submenu.viewGraph.rootAnyViewContentInput?
                .value.storage else {
                return false
            }
            return current === submenuContent
        })

        // The overlay renderer draws this first post-transfer output directly;
        // a platform child could otherwise hide a one-turn gap behind its last
        // presented surface. Keep the following steady-state turn guarded too.
        updateController(controller, tick: &tick, turns: 1)
        XCTAssertTrue(try popupHasDrawContent(submenu))
        XCTAssertTrue(firstMenuPopup(in: popup) === submenu)

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

    @MainActor
    private func updateController(
        _ controller: WindowController,
        tick: inout UInt64,
        turns: Int = 2
    ) {
        var redraw = false
        for _ in 0..<turns {
            controller.updateView(
                tick: tick,
                delta: 0,
                date: controller.date,
                contentSize: CGSize(width: 320, height: 208),
                redraw: &redraw
            ) { _, _ in }
            tick &+= 1
        }
    }

    private func popupRowHoverPoint(
        in popup: ContextMenuWindowController
    ) throws -> CGPoint {
        let root = try XCTUnwrap(
            popup.viewGraph.responderNode as? MultiViewResponder
        )
        let hover = try XCTUnwrap(
            responderTree(root)
                .compactMap { $0 as? HoverResponder }
                .min { lhs, rhs in
                    lhs.size.width * lhs.size.height <
                        rhs.size.width * rhs.size.height
                }
        )
        var points = [CGPoint(
            x: hover.size.width / 2,
            y: hover.size.height / 2
        )]
        hover.transform.convertGlobal(from: .local, points: &points)
        return try XCTUnwrap(points.first)
    }

    private func popupHasAccentFill(
        _ popup: ContextMenuWindowController
    ) throws -> Bool {
        let list = try popup.viewGraph.data.withCurrent {
            try XCTUnwrap(popup.viewGraph.displayList())
        }

        func containsAccent(_ list: DisplayList) -> Bool {
            for record in list.itemRecords {
                guard record.kind == .shapeFill,
                      case let .color(color)? = record.shapeStyle else {
                    continue
                }
                let components = color.renderingComponents()
                if components.blue - components.red > 0.5,
                   components.green - components.red > 0.2 {
                    return true
                }
            }
            return list.effects.contains {
                containsAccent($0.contents)
            }
        }

        return containsAccent(list)
    }

    private func popupHasDrawContent(
        _ popup: ContextMenuWindowController
    ) throws -> Bool {
        let list = try popup.viewGraph.data.withCurrent {
            try XCTUnwrap(popup.viewGraph.displayList())
        }

        func containsContent(_ list: DisplayList) -> Bool {
            !list.itemRecords.isEmpty || list.effects.contains {
                containsContent($0.contents)
            }
        }

        return containsContent(list)
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
