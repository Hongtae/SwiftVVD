import Foundation
import XCTest
@testable import VVD
@testable import VUI

final class TextEditingCommandsTests: XCTestCase {
    func testDefaultPasteboardCommandsExistWithoutApplicationCommands()
        throws {
        // ASSERTIONS commandsDefaultEditMenuRuntimeObserved
        let appGraph = AppGraph(app: DefaultPasteboardCommandsTestApp())
        setVectorFontRendering(in: appGraph)
        XCTAssertNil(appGraph.commandsListAttr)

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

        XCTAssertEqual(
            try textEditingItems(in: root).items.compactMap(itemTitle),
            ["Cut", "Copy", "Paste", "Delete", "Select All"]
        )
    }

    func testTextEditingCommandsBuildObservedMenuInventoryWithoutResponder()
        throws {
        // ASSERTIONS commandsDefaultEditMenuRuntimeObserved
        // ASSERTIONS commandsDefaultPasteboardValidationRuntimeObserved
        // ASSERTIONS commandsTextEditingBodyDisassemblyObserved
        // ASSERTIONS commandsTextEditingMenuRuntimeObserved
        // ASSERTIONS commandsTextEditingResponderRuntimeObserved
        let appGraph = AppGraph(app: TextEditingCommandsTestApp())
        setVectorFontRendering(in: appGraph)
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

        let allItems = flattened(list.items)
        let pasteboardItems = allItems.filter {
            guard let command = $0.textEditingCommand else { return false }
            return TextEditingCommand.defaultPasteboardCommands.contains(
                command
            )
        }
        XCTAssertEqual(pasteboardItems.count, expectedPasteboardCommands.count)
        for expected in expectedPasteboardCommands {
            let item = try XCTUnwrap(pasteboardItems.first {
                $0.textEditingCommand == expected.command
            })
            XCTAssertEqual(itemTitle(item), expected.title)
            XCTAssertEqual(
                item.keyboardShortcut,
                expected.keyBinding.map(builtInKeyboardShortcut)
            )
            XCTAssertFalse(item.isEnabled)
            XCTAssertNotNil(item.selectionBehavior?.onSelect)
            if case .initialize? = item.commandOperation?.mutation {
                // Framework defaults initialize before app operations.
            } else {
                XCTFail("expected initialize operation for \(expected.title)")
            }
        }

        let commandItems = allItems.filter {
            guard let command = $0.textEditingCommand else { return false }
            return TextEditingCommand.allTextEditingBodyCommands.contains(
                command
            )
        }
        XCTAssertEqual(commandItems.count, expectedCommands.count)

        for expected in expectedCommands {
            let item = try XCTUnwrap(commandItems.first {
                $0.textEditingCommand == expected.command
            })
            XCTAssertEqual(itemTitle(item), expected.title)
            XCTAssertEqual(item.platformTag, expected.tag)
            XCTAssertEqual(
                item.keyboardShortcut,
                expected.keyBinding.map(builtInKeyboardShortcut)
            )
            XCTAssertEqual(
                item.isEnabled,
                expected.command.isFindCommand ? false : true
            )
            XCTAssertNotNil(item.selectionBehavior?.onSelect)
            XCTAssertNil(item.toggleState)
        }
    }

    func testDefaultPasteboardCommandsSupportAugmentationAndReplacement()
        throws {
        // ASSERTIONS commandsDefaultPasteboardAugmentationRuntimeObserved
        // ASSERTIONS commandsDefaultPasteboardReplacementRuntimeObserved
        let previousAppContext = appContext
        appContext = nil
        defer { appContext = previousAppContext }

        var augmented = _ResolvedCommands()
        augmented.initializeDefaultPasteboardCommands()
        CommandGroup(before: .pasteboard) {
            Button("Before Pasteboard") {}
        }._resolve(into: &augmented)
        CommandGroup(after: .pasteboard) {
            Button("After Pasteboard") {}
        }._resolve(into: &augmented)

        XCTAssertEqual(
            try editItems(in: augmented).items.compactMap(itemTitle),
            [
                "Before Pasteboard",
                "Cut",
                "Copy",
                "Paste",
                "Delete",
                "Select All",
                "After Pasteboard",
            ]
        )

        var replaced = _ResolvedCommands()
        replaced.initializeDefaultPasteboardCommands()
        CommandGroup(replacing: .pasteboard) {
            Button("Replacement Pasteboard") {}
        }._resolve(into: &replaced)

        XCTAssertEqual(
            try editItems(in: replaced).items.compactMap(itemTitle),
            ["Replacement Pasteboard"]
        )
    }

    func testDefaultPasteboardShortcutTargetsActiveModalResponder() throws {
        // ASSERTIONS commandsPresentationChildShortcutRuntimeObserved
        // ASSERTIONS commandsDefaultPasteboardValidationRuntimeObserved
        let appGraph = AppGraph(app: DefaultPasteboardCommandsTestApp())
        setVectorFontRendering(in: appGraph)
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

        let responder = RecordingTextEditingResponder(
            enabledCommands: [.copy]
        )
        let modal: ModalWindowController = root.viewGraph.data.withCurrent {
            let graph = root.viewGraph.data.graph
            let content = AnyView(EmptyView())
            let contentAttribute: Attribute<AnyView> = graph.makeInput(
                value: content
            )
            let modal = ModalWindowController(
                crossGraphContent: contentAttribute,
                sourceGraph: graph,
                scene: WindowKey(
                    namespace: .app,
                    sceneID: SceneID(
                        RecordingTextEditingResponder.self,
                        index: 9
                    )
                ),
                parentController: root,
                usesPlatformWindow: false
            )
            root.addModal(
                child: modal,
                session: .sheet(SheetPreference(
                    content: content,
                    onDismiss: nil,
                    namespaceID: Namespace.ID(id: 90_001),
                    itemID: nil,
                    drawsBackground: true,
                    placement: .automatic,
                    activeInspector: nil,
                    usesPlatformWindow: false
                ))
            )
            return modal
        }
        modal.focusTextInputResponder(responder)

        XCTAssertTrue(windowsController.canPerformRootTextEditingCommand(.copy))
        let shortcut = builtInKeyboardShortcut(.pasteboardCopy)
        XCTAssertEqual(shortcut.key.character, "c")
        let modifiers = platformModifiers(shortcut.modifiers)
        XCTAssertTrue(modal.handleKeyboardEvent(event: KeyboardEvent(
            type: .keyDown,
            window: nil,
            deviceID: 7,
            key: .c,
            text: "c",
            modifiers: modifiers
        )))
        XCTAssertTrue(modal.handleKeyboardEvent(event: KeyboardEvent(
            type: .keyUp,
            window: nil,
            deviceID: 7,
            key: .c,
            text: "c",
            modifiers: modifiers
        )))
        update(root, ticks: 12..<24)
        XCTAssertEqual(responder.performedCommands, [.copy])
    }

    func testTextEditingCommandsResolveActiveFocusedResponderOnSelection()
        throws {
        // ASSERTIONS commandsTextEditingResponderActionObserved
        // ASSERTIONS commandsTextEditingRuntimeTransitionsObserved
        // ASSERTIONS textFieldClipboardEditingRuntimeObserved
        let appGraph = AppGraph(app: TextEditingCommandsTestApp())
        setVectorFontRendering(in: appGraph)
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
            enabledCommands: [.copy, .findNext]
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
        let staleCopySelection = try XCTUnwrap(
            try item(for: .copy, in: items).selectionBehavior?.onSelect
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
        XCTAssertTrue(
            windowsController.canPerformRootTextEditingCommand(.copy)
        )

        // This selection closure was retained while the first root was active.
        // The command must still resolve the second root at invocation time.
        staleCopySelection()
        updateAll(roots, startingAt: 120)
        XCTAssertEqual(firstResponder.performedCommands, [])
        XCTAssertEqual(secondResponder.performedCommands, [.copy])

        // The action came from the first root's old menu snapshot, but selection
        // must resolve the second root and its focused responder again.
        staleUpperCaseAction()
        updateAll(roots, startingAt: 160)
        XCTAssertEqual(firstResponder.performedCommands, [])
        XCTAssertEqual(
            secondResponder.performedCommands,
            [.copy, .makeUpperCase]
        )

        windowsController.rootWindowDidActivate(plainRoot)
        updateAll(roots, startingAt: 200)
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

    private func editItems(
        in resolved: _ResolvedCommands
    ) throws -> PlatformItemList {
        let editMenu = try XCTUnwrap(
            resolved.mainMenuItems(env: EnvironmentValues()).first {
                $0.id == .edit
            }
        )
        return MainMenuItemHost(
            item: editMenu,
            environment: EnvironmentValues(),
            focusedValues: FocusedValues()
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

    private func platformModifiers(
        _ modifiers: EventModifiers
    ) -> KeyboardModifierFlags {
        var result: KeyboardModifierFlags = []
        if modifiers.contains(.capsLock) { result.insert(.capsLock) }
        if modifiers.contains(.shift) { result.insert(.shift) }
        if modifiers.contains(.control) { result.insert(.control) }
        if modifiers.contains(.option) { result.insert(.option) }
        if modifiers.contains(.command) { result.insert(.command) }
        if modifiers.contains(.numericPad) { result.insert(.numericPad) }
        if modifiers.contains(.function) { result.insert(.function) }
        return result
    }
}

private func setVectorFontRendering<A: App>(in appGraph: AppGraph<A>) {
    var rootEnvironment = EnvironmentValues.tracking()
    rootEnvironment.defaultFontRenderingMode = .vector()
    _ = _AGGraph.withCurrent(appGraph.graph) {
        appGraph.rootEnvironmentAttr.setValue(rootEnvironment)
    }
}

private struct ExpectedTextEditingCommand {
    var command: TextEditingCommand
    var title: String
    var tag: Int?
    var keyBinding: KeyBindingID?
}

private let expectedPasteboardCommands = [
    ExpectedTextEditingCommand(
        command: .cut,
        title: "Cut",
        tag: nil,
        keyBinding: .pasteboardCut
    ),
    ExpectedTextEditingCommand(
        command: .copy,
        title: "Copy",
        tag: nil,
        keyBinding: .pasteboardCopy
    ),
    ExpectedTextEditingCommand(
        command: .paste,
        title: "Paste",
        tag: nil,
        keyBinding: .pasteboardPaste
    ),
    ExpectedTextEditingCommand(
        command: .delete,
        title: "Delete",
        tag: nil,
        keyBinding: nil
    ),
    ExpectedTextEditingCommand(
        command: .selectAll,
        title: "Select All",
        tag: nil,
        keyBinding: .pasteboardSelectAll
    ),
]

private let expectedCommands = [
    ExpectedTextEditingCommand(
        command: .find,
        title: "Find…",
        tag: 1,
        keyBinding: .textEditingFind
    ),
    ExpectedTextEditingCommand(
        command: .findAndReplace,
        title: "Find and Replace…",
        tag: 12,
        keyBinding: .textEditingFindAndReplace
    ),
    ExpectedTextEditingCommand(
        command: .findNext,
        title: "Find Next",
        tag: 2,
        keyBinding: .textEditingFindNext
    ),
    ExpectedTextEditingCommand(
        command: .findPrevious,
        title: "Find Previous",
        tag: 3,
        keyBinding: .textEditingFindPrevious
    ),
    ExpectedTextEditingCommand(
        command: .useSelectionForFind,
        title: "Use Selection for Find",
        tag: 7,
        keyBinding: .textEditingUseSelectionForFind
    ),
    ExpectedTextEditingCommand(
        command: .jumpToSelection,
        title: "Jump to Selection",
        tag: nil,
        keyBinding: .textEditingJumpToSelection
    ),
    ExpectedTextEditingCommand(
        command: .showSpellingAndGrammar,
        title: "Show Spelling and Grammar",
        tag: nil,
        keyBinding: .textEditingShowSpellingAndGrammar
    ),
    ExpectedTextEditingCommand(
        command: .checkDocumentNow,
        title: "Check Document Now",
        tag: nil,
        keyBinding: .textEditingCheckDocumentNow
    ),
    ExpectedTextEditingCommand(
        command: .toggleCheckSpellingWhileTyping,
        title: "Check Spelling While Typing",
        tag: nil,
        keyBinding: nil
    ),
    ExpectedTextEditingCommand(
        command: .toggleCheckGrammarWithSpelling,
        title: "Check Grammar With Spelling",
        tag: nil,
        keyBinding: nil
    ),
    ExpectedTextEditingCommand(
        command: .toggleAutomaticSpellingCorrection,
        title: "Correct Spelling Automatically",
        tag: nil,
        keyBinding: nil
    ),
    ExpectedTextEditingCommand(
        command: .showSubstitutions,
        title: "Show Substitutions",
        tag: nil,
        keyBinding: nil
    ),
    ExpectedTextEditingCommand(
        command: .toggleSmartCopyPaste,
        title: "Smart Copy/Paste",
        tag: nil,
        keyBinding: nil
    ),
    ExpectedTextEditingCommand(
        command: .toggleSmartQuotes,
        title: "Smart Quotes",
        tag: nil,
        keyBinding: nil
    ),
    ExpectedTextEditingCommand(
        command: .toggleSmartDashes,
        title: "Smart Dashes",
        tag: nil,
        keyBinding: nil
    ),
    ExpectedTextEditingCommand(
        command: .toggleSmartLinks,
        title: "Smart Links",
        tag: nil,
        keyBinding: nil
    ),
    ExpectedTextEditingCommand(
        command: .toggleDataDetectors,
        title: "Data Detectors",
        tag: nil,
        keyBinding: nil
    ),
    ExpectedTextEditingCommand(
        command: .toggleTextReplacement,
        title: "Text Replacement",
        tag: nil,
        keyBinding: nil
    ),
    ExpectedTextEditingCommand(
        command: .makeUpperCase,
        title: "Make Upper Case",
        tag: nil,
        keyBinding: nil
    ),
    ExpectedTextEditingCommand(
        command: .makeLowerCase,
        title: "Make Lower Case",
        tag: nil,
        keyBinding: nil
    ),
    ExpectedTextEditingCommand(
        command: .capitalize,
        title: "Capitalize",
        tag: nil,
        keyBinding: nil
    ),
    ExpectedTextEditingCommand(
        command: .startSpeaking,
        title: "Start Speaking",
        tag: nil,
        keyBinding: nil
    ),
    ExpectedTextEditingCommand(
        command: .stopSpeaking,
        title: "Stop Speaking",
        tag: nil,
        keyBinding: nil
    ),
]

private extension TextEditingCommand {
    static let defaultPasteboardCommands = expectedPasteboardCommands.map(
        \.command
    )

    static let allTextEditingBodyCommands = expectedCommands.map(\.command)

    static let allFindCommands: [TextEditingCommand] = [
        .find,
        .findAndReplace,
        .findNext,
        .findPrevious,
        .useSelectionForFind,
        .jumpToSelection,
    ]

    static let allTestCommands = defaultPasteboardCommands
        + allTextEditingBodyCommands

    var isFindCommand: Bool {
        Self.allFindCommands.contains(self)
    }
}

private final class RecordingTextEditingResponder:
    ResponderNode,
    TextEditingCommandResponder,
    TextInputResponder {
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

    func handleTextInputEvent(_ event: KeyboardEvent) -> Bool { false }

    func textInputFocusDidChange(_ focused: Bool) {}

    func containsTextInputPoint(_ point: CGPoint) -> Bool { false }
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

    var body: some VUI.Scene {
        Window("Text editing commands", id: "text-editing-commands") {
            EmptyView()
        }
        .commandMenuPresentationStyle(.window)
        .commands { TextEditingCommands() }
    }
}

private struct DefaultPasteboardCommandsTestApp: App {
    init() {}

    var body: some VUI.Scene {
        Window("Default pasteboard commands", id: "default-pasteboard") {
            EmptyView()
        }
        .commandMenuPresentationStyle(.window)
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
}
