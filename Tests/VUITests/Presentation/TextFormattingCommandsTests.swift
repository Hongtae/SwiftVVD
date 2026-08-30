import XCTest
@testable import VUI
import class VVD.AudioDeviceContext
import class VVD.GraphicsDeviceContext

final class TextFormattingCommandsTests: XCTestCase {
    func testTextFormattingCommandsBuildObservedMenuInventory() throws {
        // ASSERTIONS commandsTextFormattingBodyDisassemblyObserved
        // ASSERTIONS commandsTextFormattingExternalMenuOwnerObserved
        // ASSERTIONS commandsTextFormattingExternalMenuRuntimeObserved
        // ASSERTIONS commandsTextFormattingMenuRuntimeObserved
        let appGraph = AppGraph(app: TextFormattingCommandsTestApp())
        setVectorFontRendering(in: appGraph)
        let windowsController = AppWindowsController()
        let previousAppContext = appContext
        appContext = TextFormattingCommandsTestAppContext(
            windowsController: windowsController
        )
        defer { appContext = previousAppContext }

        windowsController.syncWindowControllers(
            sceneListAttr: appGraph.sceneListAttr,
            commandsListAttr: appGraph.commandsListAttr,
            rootEnvironmentAttr: appGraph.rootEnvironmentAttr,
            focusedValuesAttr: appGraph.focusedValuesAttr,
            in: appGraph.graph
        )

        let root = try XCTUnwrap(windowsController.allWindowControllers.first)
        windowsController.rootWindowDidActivate(root)
        update(root, ticks: 0..<12)

        let list = try textFormattingItems(in: root)
        let outerSection = try XCTUnwrap(list.items.first(where: {
            if case .section? = $0.systemItem { return true }
            return false
        }))
        let outerItems = try XCTUnwrap(outerSection.children).items
        XCTAssertEqual(outerItems.compactMap(itemTitle), ["Font", "Text"])

        let font = try XCTUnwrap(outerItems.first(where: {
            itemTitle($0) == "Font"
        }))
        XCTAssertTrue(font.isExternal)
        XCTAssertEqual(font.platformIdentifier, "NSFontMenu")
        if case .menu? = font.systemItem {
        } else {
            XCTFail("Font must remain an external menu item")
        }
        XCTAssertTrue(font.wantsPlatformInterfaceValidation)
        XCTAssertNil(font.children)
        XCTAssertNil(font.selectionBehavior)

        let text = try XCTUnwrap(outerItems.first(where: {
            itemTitle($0) == "Text"
        }))
        let textItems = try XCTUnwrap(text.children).items
        XCTAssertEqual(
            sectionSignatures(textItems),
            [
                "section[Align Left,Center,Justify,Align Right]",
                "section[Writing Direction]",
                "section[Show Ruler,Copy Ruler,Paste Ruler]",
            ]
        )

        let writingDirection = try XCTUnwrap(flattened(textItems).first(where: {
            itemTitle($0) == "Writing Direction" && $0.children != nil
        }))
        XCTAssertEqual(
            sectionSignatures(try XCTUnwrap(writingDirection.children).items),
            [
                "section:Paragraph[Default,Left to Right,Right to Left]",
                "section:Selection[Default,Left to Right,Right to Left]",
            ]
        )

        let commandItems = flattened(textItems).filter {
            $0.textFormattingCommand != nil
        }
        XCTAssertEqual(commandItems.count, expectedTextFormattingCommands.count)
        for expected in expectedTextFormattingCommands {
            let item = try XCTUnwrap(commandItems.first {
                $0.textFormattingCommand == expected.command
            })
            XCTAssertEqual(itemTitle(item), expected.title)
            XCTAssertEqual(item.keyboardShortcut?.key, expected.key)
            XCTAssertEqual(
                item.keyboardShortcut?.modifiers,
                expected.modifiers
            )
            XCTAssertTrue(item.isEnabled)
            XCTAssertNotNil(item.selectionBehavior?.onSelect)
        }
    }

    func testTextFormattingCommandsResolveActiveFocusedResponderOnSelection()
        throws {
        // ASSERTIONS commandsTextFormattingResponderActionObserved
        // ASSERTIONS commandsTextFormattingResponderRuntimeObserved
        // ASSERTIONS commandsTextFormattingRuntimeTransitionsObserved
        let appGraph = AppGraph(app: TextFormattingCommandsTestApp())
        setVectorFontRendering(in: appGraph)
        let windowsController = AppWindowsController()
        let previousAppContext = appContext
        appContext = TextFormattingCommandsTestAppContext(
            windowsController: windowsController
        )
        defer { appContext = previousAppContext }

        let firstResponder = RecordingTextFormattingResponder()
        let secondResponder = RecordingTextFormattingResponder()
        let firstKey = textFormattingWindowKey(index: 0)
        let secondKey = textFormattingWindowKey(index: 1)
        let plainKey = textFormattingWindowKey(index: 2)
        var sceneItems = [
            SceneList.Item(windowKey: firstKey, kind: .single) { _ in
                TextFormattingCommandWindowController(
                    scene: firstKey,
                    focusedResponder: firstResponder
                )
            },
            SceneList.Item(windowKey: secondKey, kind: .single) { _ in
                TextFormattingCommandWindowController(
                    scene: secondKey,
                    focusedResponder: secondResponder
                )
            },
            SceneList.Item(windowKey: plainKey, kind: .single) { _ in
                TextFormattingCommandWindowController(
                    scene: plainKey,
                    focusedResponder: nil
                )
            },
        ]
        for index in sceneItems.indices {
            sceneItems[index].sceneConfiguration.commandMenuPresentationStyle =
                .window
        }
        let sceneListAttr: Attribute<[SceneList.Item]> =
            _AGGraph.withCurrent(appGraph.graph) {
                appGraph.graph.makeInput(value: sceneItems)
            }

        windowsController.syncWindowControllers(
            sceneListAttr: sceneListAttr,
            commandsListAttr: appGraph.commandsListAttr,
            rootEnvironmentAttr: appGraph.rootEnvironmentAttr,
            focusedValuesAttr: appGraph.focusedValuesAttr,
            in: appGraph.graph
        )

        let roots = windowsController.allWindowControllers
        let firstRoot = try root(for: firstKey, in: roots)
        let secondRoot = try root(for: secondKey, in: roots)
        let plainRoot = try root(for: plainKey, in: roots)
        updateAll(roots, startingAt: 0)

        windowsController.rootWindowDidActivate(firstRoot)
        updateAll(roots, startingAt: 40)
        var items = flattened(try textFormattingItems(in: firstRoot).items)
        let staleAction = try XCTUnwrap(items.first {
            $0.textFormattingCommand == .alignCenter
        }?.selectionBehavior?.onSelect)

        windowsController.rootWindowDidActivate(secondRoot)
        updateAll(roots, startingAt: 80)
        staleAction()
        updateAll(roots, startingAt: 120)
        XCTAssertEqual(firstResponder.performedCommands, [])
        XCTAssertEqual(secondResponder.performedCommands, [.alignCenter])

        windowsController.rootWindowDidActivate(plainRoot)
        updateAll(roots, startingAt: 160)
        items = flattened(try textFormattingItems(in: secondRoot).items)
        let plainAction = try XCTUnwrap(items.first {
            $0.textFormattingCommand == .alignRight
        }?.selectionBehavior?.onSelect)
        XCTAssertTrue(items.filter {
            $0.textFormattingCommand != nil
        }.allSatisfy(\.isEnabled))
        plainAction()
        updateAll(roots, startingAt: 200)
        XCTAssertEqual(secondResponder.performedCommands, [.alignCenter])
    }

    private func textFormattingItems(
        in root: WindowController
    ) throws -> PlatformItemList {
        let presenter = try XCTUnwrap(root.windowCommandMenuPresenter)
        let formatMenu = try XCTUnwrap(
            presenter.items.first(where: { $0.id == .format })
        )
        return MainMenuItemHost(
            item: formatMenu,
            environment: presenter.environment,
            focusedValues: root.resolvedFocusedValues
        ).menuItems()
    }

    private func root(
        for key: WindowKey,
        in roots: [WindowController]
    ) throws -> WindowController {
        try XCTUnwrap(roots.first { $0.scene == key })
    }

    private func flattened(
        _ items: [PlatformItemList.Item]
    ) -> [PlatformItemList.Item] {
        items.flatMap { item in
            [item]
                + flattened(item.children?.items ?? [])
                + flattened(item.labelGroupChildren?.items ?? [])
        }
    }

    private func itemTitle(_ item: PlatformItemList.Item) -> String? {
        (item.label ?? item.text)?.string
    }

    private func sectionSignatures(
        _ items: [PlatformItemList.Item]
    ) -> [String] {
        items.map { item in
            guard case .section? = item.systemItem else {
                return itemTitle(item) ?? ""
            }
            let title = itemTitle(item).map { ":\($0)" } ?? ""
            let children = item.children?.items.compactMap(itemTitle) ?? []
            return "section\(title)[\(children.joined(separator: ","))]"
        }
    }

    private func updateAll(
        _ roots: [WindowController],
        startingAt tick: Int
    ) {
        for (offset, root) in roots.enumerated() {
            let firstTick = tick + offset * 12
            update(root, ticks: firstTick..<(firstTick + 12))
        }
    }

    private func update(
        _ root: WindowController,
        ticks: Range<Int>
    ) {
        for tick in ticks {
            var redraw = false
            root.updateView(
                tick: UInt64(tick),
                delta: 1.0 / 60.0,
                date: root.date.addingTimeInterval(1.0 / 60.0),
                contentSize: CGSize(width: 720, height: 360),
                redraw: &redraw
            ) { _, _ in }
        }
    }
}

private struct ExpectedTextFormattingCommand {
    var command: TextFormattingCommand
    var title: String
    var key: KeyEquivalent?
    var modifiers: EventModifiers?
}

private let expectedTextFormattingCommands = [
    ExpectedTextFormattingCommand(
        command: .alignLeft,
        title: "Align Left",
        key: "{",
        modifiers: .command
    ),
    ExpectedTextFormattingCommand(
        command: .alignCenter,
        title: "Center",
        key: "|",
        modifiers: .command
    ),
    ExpectedTextFormattingCommand(
        command: .alignJustify,
        title: "Justify",
        key: nil,
        modifiers: nil
    ),
    ExpectedTextFormattingCommand(
        command: .alignRight,
        title: "Align Right",
        key: "}",
        modifiers: .command
    ),
    ExpectedTextFormattingCommand(
        command: .defaultParagraphWritingDirection,
        title: "Default",
        key: nil,
        modifiers: nil
    ),
    ExpectedTextFormattingCommand(
        command: .leftToRightParagraphWritingDirection,
        title: "Left to Right",
        key: nil,
        modifiers: nil
    ),
    ExpectedTextFormattingCommand(
        command: .rightToLeftParagraphWritingDirection,
        title: "Right to Left",
        key: nil,
        modifiers: nil
    ),
    ExpectedTextFormattingCommand(
        command: .defaultSelectionWritingDirection,
        title: "Default",
        key: nil,
        modifiers: nil
    ),
    ExpectedTextFormattingCommand(
        command: .leftToRightSelectionWritingDirection,
        title: "Left to Right",
        key: nil,
        modifiers: nil
    ),
    ExpectedTextFormattingCommand(
        command: .rightToLeftSelectionWritingDirection,
        title: "Right to Left",
        key: nil,
        modifiers: nil
    ),
    ExpectedTextFormattingCommand(
        command: .toggleRuler,
        title: "Show Ruler",
        key: nil,
        modifiers: nil
    ),
    ExpectedTextFormattingCommand(
        command: .copyRuler,
        title: "Copy Ruler",
        key: "c",
        modifiers: [.command, .control]
    ),
    ExpectedTextFormattingCommand(
        command: .pasteRuler,
        title: "Paste Ruler",
        key: "v",
        modifiers: [.command, .control]
    ),
]

private final class RecordingTextFormattingResponder:
    ResponderNode,
    TextFormattingCommandResponder {
    var performedCommands: [TextFormattingCommand] = []

    override var nextResponder: ResponderNode? { nil }

    func performTextFormattingCommand(_ command: TextFormattingCommand) {
        performedCommands.append(command)
    }
}

private final class TextFormattingCommandWindowController:
    WindowController,
    @unchecked Sendable {
    private let commandResponder: ResponderNode?

    override var focusedResponder: ResponderNode? { commandResponder }

    init(scene: WindowKey, focusedResponder: ResponderNode?) {
        commandResponder = focusedResponder
        super.init(content: EmptyView(), scene: scene)
    }
}

private func textFormattingWindowKey(index: UInt8) -> WindowKey {
    WindowKey(
        namespace: .app,
        sceneID: SceneID(
            TextFormattingCommandWindowController.self,
            index: index
        )
    )
}

private func setVectorFontRendering<A: App>(in appGraph: AppGraph<A>) {
    var rootEnvironment = EnvironmentValues.tracking()
    rootEnvironment.defaultFontRenderingMode = .vector()
    _ = _AGGraph.withCurrent(appGraph.graph) {
        appGraph.rootEnvironmentAttr.setValue(rootEnvironment)
    }
}

private struct TextFormattingCommandsTestApp: App {
    init() {}

    var body: some Scene {
        Window("Text formatting commands", id: "text-formatting-commands") {
            EmptyView()
        }
        .commandMenuPresentationStyle(.window)
        .commands { TextFormattingCommands() }
    }
}

private final class TextFormattingCommandsTestAppContext: AppContext {
    let graphicsDeviceContext: GraphicsDeviceContext? = nil
    let audioDeviceContext: AudioDeviceContext? = nil
    let appWindowsController: AppWindowsController?
    private var resources: [URL: any DataProtocol] = [:]

    init(windowsController: AppWindowsController) {
        appWindowsController = windowsController
    }

    func resourceData(forURL url: URL) -> (any DataProtocol)? {
        resources[url]
    }

    func setResource(data: (any DataProtocol)?, forURL url: URL) {
        resources[url] = data
    }

    func checkWindowActivities() {}
}
