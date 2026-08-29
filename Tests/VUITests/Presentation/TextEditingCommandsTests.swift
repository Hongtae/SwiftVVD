import XCTest
@testable import VUI
import class VVD.AudioDeviceContext
import class VVD.GraphicsDeviceContext

final class TextEditingCommandsTests: XCTestCase {
    func testTextEditingCommandsBuildObservedMenuInventoryWithoutResponder()
        throws {
        // ASSERTIONS commandsTextEditingBodyDisassemblyObserved
        // ASSERTIONS commandsTextEditingMenuRuntimeObserved
        // ASSERTIONS commandsTextEditingResponderRuntimeObserved
        let appGraph = AppGraph(app: TextEditingCommandsTestApp())
        let windowsController = AppWindowsController()
        let previousAppContext = appContext
        appContext = TextEditingCommandsTestAppContext(
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

        let list = try textEditingItems(in: root)
        XCTAssertEqual(
            list.items.compactMap { item in
                if case .menu? = item.systemItem {
                    return itemTitle(item)
                }
                return nil
            },
            [
                "Find",
                "Spelling and Grammar",
                "Substitutions",
                "Transformations",
                "Speech",
            ]
        )
        XCTAssertEqual(
            try submenuStructure(named: "Find", in: list),
            [
                "Find…",
                "Find and Replace…",
                "Find Next",
                "Find Previous",
                "Use Selection for Find",
                "Jump to Selection",
            ]
        )
        XCTAssertEqual(
            try submenuStructure(named: "Spelling and Grammar", in: list),
            [
                "section[Show Spelling and Grammar,Check Document Now]",
                "section[Check Spelling While Typing,Check Grammar With Spelling,Correct Spelling Automatically]",
            ]
        )
        XCTAssertEqual(
            try submenuStructure(named: "Substitutions", in: list),
            [
                "Show Substitutions",
                "section[Smart Copy/Paste,Smart Quotes,Smart Dashes,Smart Links,Data Detectors,Text Replacement]",
            ]
        )
        XCTAssertEqual(
            try submenuStructure(named: "Transformations", in: list),
            ["Make Upper Case", "Make Lower Case", "Capitalize"]
        )
        XCTAssertEqual(
            try submenuStructure(named: "Speech", in: list),
            ["Start Speaking", "Stop Speaking"]
        )

        let commandItems = flattened(list.items).filter {
            $0.textEditingCommand != nil
        }
        XCTAssertEqual(commandItems.count, expectedCommands.count)

        for expected in expectedCommands {
            let item = try XCTUnwrap(commandItems.first {
                $0.textEditingCommand == expected.command
            })
            XCTAssertEqual(itemTitle(item), expected.title)
            XCTAssertEqual(item.platformTag, expected.tag)
            XCTAssertEqual(item.keyboardShortcut?.key, expected.key)
            XCTAssertEqual(
                item.keyboardShortcut?.modifiers,
                expected.modifiers
            )
            XCTAssertEqual(
                item.isEnabled,
                expected.command.isFindCommand ? false : true
            )
            XCTAssertNotNil(item.selectionBehavior?.onSelect)
            XCTAssertNil(item.toggleState)
        }
    }

    func testTextEditingCommandsResolveActiveFocusedResponderOnSelection()
        throws {
        // ASSERTIONS commandsTextEditingResponderActionObserved
        // ASSERTIONS commandsTextEditingRuntimeTransitionsObserved
        let appGraph = AppGraph(app: TextEditingCommandsTestApp())
        let windowsController = AppWindowsController()
        let previousAppContext = appContext
        appContext = TextEditingCommandsTestAppContext(
            windowsController: windowsController
        )
        defer { appContext = previousAppContext }

        let firstResponder = RecordingTextEditingResponder(
            enabledCommands: Set(TextEditingCommand.allTestCommands)
        )
        let secondResponder = RecordingTextEditingResponder(
            enabledCommands: [.findNext]
        )
        let firstKey = textEditingWindowKey(index: 0)
        let secondKey = textEditingWindowKey(index: 1)
        let plainKey = textEditingWindowKey(index: 2)
        var sceneItems = [
            SceneList.Item(windowKey: firstKey, kind: .single) { _ in
                TextEditingCommandWindowController(
                    scene: firstKey,
                    focusedResponder: firstResponder
                )
            },
            SceneList.Item(windowKey: secondKey, kind: .single) { _ in
                TextEditingCommandWindowController(
                    scene: secondKey,
                    focusedResponder: secondResponder
                )
            },
            SceneList.Item(windowKey: plainKey, kind: .single) { _ in
                TextEditingCommandWindowController(
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
        var items = flattened(try textEditingItems(in: firstRoot).items)
        XCTAssertTrue(
            try item(for: .useSelectionForFind, in: items).isEnabled
        )
        let staleUpperCaseAction = try XCTUnwrap(
            try item(for: .makeUpperCase, in: items)
                .selectionBehavior?.onSelect
        )

        windowsController.rootWindowDidActivate(secondRoot)
        updateAll(roots, startingAt: 80)
        items = flattened(try textEditingItems(in: firstRoot).items)
        for command in TextEditingCommand.allFindCommands {
            XCTAssertEqual(
                try item(for: command, in: items).isEnabled,
                command == .findNext
            )
        }

        // The action came from the first root's old menu snapshot, but selection
        // must resolve the second root and its focused responder again.
        staleUpperCaseAction()
        updateAll(roots, startingAt: 120)
        XCTAssertEqual(firstResponder.performedCommands, [])
        XCTAssertEqual(secondResponder.performedCommands, [.makeUpperCase])

        windowsController.rootWindowDidActivate(plainRoot)
        updateAll(roots, startingAt: 160)
        items = flattened(try textEditingItems(in: secondRoot).items)
        for command in TextEditingCommand.allFindCommands {
            XCTAssertFalse(try item(for: command, in: items).isEnabled)
        }
        XCTAssertTrue(try item(for: .makeUpperCase, in: items).isEnabled)
    }

    private func item(
        for command: TextEditingCommand,
        in items: [PlatformItemList.Item]
    ) throws -> PlatformItemList.Item {
        try XCTUnwrap(items.first { $0.textEditingCommand == command })
    }

    private func textEditingItems(
        in root: WindowController
    ) throws -> PlatformItemList {
        let presenter = try XCTUnwrap(root.windowCommandMenuPresenter)
        let editMenu = try XCTUnwrap(
            presenter.items.first(where: { $0.id == .edit })
        )
        return MainMenuItemHost(
            item: editMenu,
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

    private func submenuStructure(
        named title: String,
        in list: PlatformItemList
    ) throws -> [String] {
        let menu = try XCTUnwrap(list.items.first {
            itemTitle($0) == title && $0.children != nil
        })
        return try XCTUnwrap(menu.children).items.map { item in
            if case .section? = item.systemItem {
                let titles = item.children?.items.compactMap(itemTitle) ?? []
                return "section[\(titles.joined(separator: ","))]"
            }
            return itemTitle(item) ?? ""
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

private struct ExpectedTextEditingCommand {
    var command: TextEditingCommand
    var title: String
    var tag: Int?
    var key: KeyEquivalent?
    var modifiers: EventModifiers?
}

private let expectedCommands = [
    ExpectedTextEditingCommand(
        command: .find,
        title: "Find…",
        tag: 1,
        key: "f",
        modifiers: .command
    ),
    ExpectedTextEditingCommand(
        command: .findAndReplace,
        title: "Find and Replace…",
        tag: 12,
        key: "f",
        modifiers: [.command, .option]
    ),
    ExpectedTextEditingCommand(
        command: .findNext,
        title: "Find Next",
        tag: 2,
        key: "g",
        modifiers: .command
    ),
    ExpectedTextEditingCommand(
        command: .findPrevious,
        title: "Find Previous",
        tag: 3,
        key: "g",
        modifiers: [.command, .shift]
    ),
    ExpectedTextEditingCommand(
        command: .useSelectionForFind,
        title: "Use Selection for Find",
        tag: 7,
        key: "e",
        modifiers: .command
    ),
    ExpectedTextEditingCommand(
        command: .jumpToSelection,
        title: "Jump to Selection",
        tag: nil,
        key: "j",
        modifiers: .command
    ),
    ExpectedTextEditingCommand(
        command: .showSpellingAndGrammar,
        title: "Show Spelling and Grammar",
        tag: nil,
        key: ":",
        modifiers: .command
    ),
    ExpectedTextEditingCommand(
        command: .checkDocumentNow,
        title: "Check Document Now",
        tag: nil,
        key: ";",
        modifiers: .command
    ),
    ExpectedTextEditingCommand(
        command: .toggleCheckSpellingWhileTyping,
        title: "Check Spelling While Typing",
        tag: nil,
        key: nil,
        modifiers: nil
    ),
    ExpectedTextEditingCommand(
        command: .toggleCheckGrammarWithSpelling,
        title: "Check Grammar With Spelling",
        tag: nil,
        key: nil,
        modifiers: nil
    ),
    ExpectedTextEditingCommand(
        command: .toggleAutomaticSpellingCorrection,
        title: "Correct Spelling Automatically",
        tag: nil,
        key: nil,
        modifiers: nil
    ),
    ExpectedTextEditingCommand(
        command: .showSubstitutions,
        title: "Show Substitutions",
        tag: nil,
        key: nil,
        modifiers: nil
    ),
    ExpectedTextEditingCommand(
        command: .toggleSmartCopyPaste,
        title: "Smart Copy/Paste",
        tag: nil,
        key: nil,
        modifiers: nil
    ),
    ExpectedTextEditingCommand(
        command: .toggleSmartQuotes,
        title: "Smart Quotes",
        tag: nil,
        key: nil,
        modifiers: nil
    ),
    ExpectedTextEditingCommand(
        command: .toggleSmartDashes,
        title: "Smart Dashes",
        tag: nil,
        key: nil,
        modifiers: nil
    ),
    ExpectedTextEditingCommand(
        command: .toggleSmartLinks,
        title: "Smart Links",
        tag: nil,
        key: nil,
        modifiers: nil
    ),
    ExpectedTextEditingCommand(
        command: .toggleDataDetectors,
        title: "Data Detectors",
        tag: nil,
        key: nil,
        modifiers: nil
    ),
    ExpectedTextEditingCommand(
        command: .toggleTextReplacement,
        title: "Text Replacement",
        tag: nil,
        key: nil,
        modifiers: nil
    ),
    ExpectedTextEditingCommand(
        command: .makeUpperCase,
        title: "Make Upper Case",
        tag: nil,
        key: nil,
        modifiers: nil
    ),
    ExpectedTextEditingCommand(
        command: .makeLowerCase,
        title: "Make Lower Case",
        tag: nil,
        key: nil,
        modifiers: nil
    ),
    ExpectedTextEditingCommand(
        command: .capitalize,
        title: "Capitalize",
        tag: nil,
        key: nil,
        modifiers: nil
    ),
    ExpectedTextEditingCommand(
        command: .startSpeaking,
        title: "Start Speaking",
        tag: nil,
        key: nil,
        modifiers: nil
    ),
    ExpectedTextEditingCommand(
        command: .stopSpeaking,
        title: "Stop Speaking",
        tag: nil,
        key: nil,
        modifiers: nil
    ),
]

private extension TextEditingCommand {
    static let allFindCommands: [TextEditingCommand] = [
        .find,
        .findAndReplace,
        .findNext,
        .findPrevious,
        .useSelectionForFind,
        .jumpToSelection,
    ]

    static let allTestCommands = expectedCommands.map(\.command)

    var isFindCommand: Bool {
        Self.allFindCommands.contains(self)
    }
}

private final class RecordingTextEditingResponder:
    ResponderNode,
    TextEditingCommandResponder {
    var enabledCommands: Set<TextEditingCommand>
    var performedCommands: [TextEditingCommand] = []

    init(enabledCommands: Set<TextEditingCommand>) {
        self.enabledCommands = enabledCommands
        super.init()
    }

    override var nextResponder: ResponderNode? { nil }

    func canPerformTextEditingCommand(_ command: TextEditingCommand) -> Bool {
        enabledCommands.contains(command)
    }

    func performTextEditingCommand(_ command: TextEditingCommand) {
        performedCommands.append(command)
    }
}

private final class TextEditingCommandWindowController:
    WindowController,
    @unchecked Sendable {
    private let commandResponder: ResponderNode?

    override var focusedResponder: ResponderNode? { commandResponder }

    init(scene: WindowKey, focusedResponder: ResponderNode?) {
        commandResponder = focusedResponder
        super.init(content: EmptyView(), scene: scene)
    }
}

private func textEditingWindowKey(index: UInt8) -> WindowKey {
    WindowKey(
        namespace: .app,
        sceneID: SceneID(TextEditingCommandWindowController.self, index: index)
    )
}

private struct TextEditingCommandsTestApp: App {
    init() {}

    var body: some Scene {
        Window("Text editing commands", id: "text-editing-commands") {
            EmptyView()
        }
        .commandMenuPresentationStyle(.window)
        .commands { TextEditingCommands() }
    }
}

private final class TextEditingCommandsTestAppContext: AppContext {
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
