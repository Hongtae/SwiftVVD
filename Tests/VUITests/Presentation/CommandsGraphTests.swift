import XCTest
@testable import VUI

final class CommandsGraphTests: XCTestCase {
    func testCommandsModifiersAppendItemsInApplicationOrder() throws {
        // ASSERTIONS commandsGraphCollectionRuntimeObserved
        let appGraph = AppGraph(app: OrderedCommandsTestApp())
        let (commands, scenes) = try graphOutputs(from: appGraph)

        XCTAssertEqual(commandFlagIDs(commands), [1, 2])
        XCTAssertEqual(commands.items.map(\.version.value), [1, 2])
        XCTAssertFalse(try XCTUnwrap(scenes.first).options.contains(.commandsRemoved))
    }

    func testDefaultCommandsBodyInstallsDynamicPropertiesBeforeDelegating() throws {
        // ASSERTIONS commandsDefaultBodyRuntimeObserved
        let appGraph = AppGraph(app: DynamicCommandsTestApp())
        let (commands, _) = try graphOutputs(from: appGraph)

        XCTAssertEqual(commandFlagIDs(commands), [41])
    }

    func testCommandsRemovedSuppressesCollectionAndMarksSceneItem() throws {
        // ASSERTIONS commandsRemovedSceneListRuntimeObserved
        let appGraph = AppGraph(app: RemovedCommandsTestApp())
        let scenes = try _AGGraph.withCurrent(appGraph.graph) {
            try XCTUnwrap(appGraph.sceneListAttr).value
        }

        XCTAssertNil(appGraph.commandsListAttr)
        XCTAssertTrue(try XCTUnwrap(scenes.first).options.contains(.commandsRemoved))
    }

    func testCommandsReplacedSuppressesWrappedCommandsAndCollectsReplacement() throws {
        // ASSERTIONS commandsReplacedSceneRuntimeObserved
        let appGraph = AppGraph(app: ReplacedCommandsTestApp())
        let (commands, scenes) = try graphOutputs(from: appGraph)

        XCTAssertEqual(commandFlagIDs(commands), [2])
        XCTAssertTrue(try XCTUnwrap(scenes.first).options.contains(.commandsRemoved))
    }

    func testCommandGroupPlacementsHaveStableProcessLocalIdentities() {
        // ASSERTIONS commandGroupPlacementIdentityRuntimeObserved
        let placements: [(CommandGroupPlacement, String)] = [
            (.appInfo, "App Info"),
            (.appSettings, "App Settings"),
            (.systemServices, "System Services"),
            (.appVisibility, "App Visibility"),
            (.appTermination, "App Termination"),
            (.newItem, "New Item"),
            (.saveItem, "Save Item"),
            (.importExport, "Import/Export Item"),
            (.printItem, "Print Item"),
            (.undoRedo, "Undo/Redo"),
            (.pasteboard, "Pasteboard"),
            (.textEditing, "Text Editing"),
            (.textFormatting, "Text Formatting"),
            (.toolbar, "Toolbar"),
            (.sidebar, "Sidebar"),
            (.windowSize, "Window Size"),
            (.windowList, "Window List"),
            (.singleWindowList, "Singleton Window List"),
            (.windowArrangement, "Window Arrangement"),
            (.help, "Help"),
        ]

        XCTAssertEqual(Set(placements.map { $0.0.id }).count, placements.count)
        for (placement, name) in placements {
            XCTAssertEqual(placement.name, Text(verbatim: name))
        }
        XCTAssertEqual(CommandGroupPlacement.newItem.id, CommandGroupPlacement.newItem.id)
    }

    func testCommandMenuPresentationStyleIsStoredOnSceneRootItems() throws {
        let defaultGraph = AppGraph(app: DefaultCommandMenuStyleTestApp())
        let defaultScenes = try _AGGraph.withCurrent(defaultGraph.graph) {
            try XCTUnwrap(defaultGraph.sceneListAttr).value
        }
        XCTAssertEqual(
            try XCTUnwrap(defaultScenes.first).sceneConfiguration.commandMenuPresentationStyle,
            .window
        )
        XCTAssertEqual(
            try XCTUnwrap(defaultScenes.first).sceneConfiguration.defaultPresentationHostMode,
            .overlay
        )

        let platformGraph = AppGraph(app: PlatformCommandMenuStyleTestApp())
        let platformScenes = try _AGGraph.withCurrent(platformGraph.graph) {
            try XCTUnwrap(platformGraph.sceneListAttr).value
        }
        XCTAssertEqual(
            try XCTUnwrap(platformScenes.first).sceneConfiguration.commandMenuPresentationStyle,
            .platform
        )

        let popupGraph = AppGraph(app: PlatformWindowPresentationHostTestApp())
        let popupScenes = try _AGGraph.withCurrent(popupGraph.graph) {
            try XCTUnwrap(popupGraph.sceneListAttr).value
        }
        let popupConfiguration = try XCTUnwrap(popupScenes.first).sceneConfiguration
        XCTAssertEqual(popupConfiguration.commandMenuPresentationStyle, .window)
        XCTAssertEqual(popupConfiguration.defaultPresentationHostMode, .platformWindow)
    }

    private func graphOutputs<A: App>(
        from appGraph: AppGraph<A>
    ) throws -> (CommandsList, [SceneList.Item]) {
        try _AGGraph.withCurrent(appGraph.graph) {
            (
                try XCTUnwrap(appGraph.commandsListAttr).value,
                try XCTUnwrap(appGraph.sceneListAttr).value
            )
        }
    }

    private func commandFlagIDs(_ commands: CommandsList) -> [Int] {
        commands.items.compactMap { item in
            guard case let .flag(flag) = item.value else { return nil }
            return flag.id
        }
    }
}

private struct FlagCommands: Commands {
    var id: Int

    typealias Body = Never

    static func _makeCommands(
        content: _GraphValue<Self>,
        inputs: _CommandsInputs
    ) -> _CommandsOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("FlagCommands._makeCommands called outside _AGGraph context")
        }
        let list: Attribute<CommandsList> = graph.makeRule {
            let command = content._attribute.value
            return CommandsList(items: [
                CommandsList.Item(
                    value: .flag(CommandFlag(id: command.id)),
                    version: DisplayList.Version(value: command.id)
                )
            ])
        }
        var preferences = PreferencesOutputs()
        preferences.makePreferenceWriter(
            inputs: inputs.preferences,
            key: CommandsList.Key.self,
            value: list
        )
        return _CommandsOutputs(preferences: preferences)
    }

    func _resolve(into resolved: inout _ResolvedCommands) {}
}

@propertyWrapper
private struct IncrementingCommandProperty: DynamicProperty {
    var wrappedValue: Int

    static func _makeProperty<Container>(
        in buffer: inout _DynamicPropertyBuffer,
        container: _GraphValue<Container>,
        fieldOffset: Int,
        inputs: inout _GraphInputs
    ) {
        buffer.properties.append(.init(type: Self.self, offset: fieldOffset))
        buffer.contexts[fieldOffset] = { (pointer: UnsafeMutableRawPointer) in
            var property = pointer
                .assumingMemoryBound(to: IncrementingCommandProperty.self)
                .pointee
            property.wrappedValue += 1
            pointer.assumingMemoryBound(to: IncrementingCommandProperty.self)
                .pointee = property
        }
    }
}

private struct DynamicProbeCommands: Commands {
    @IncrementingCommandProperty var identifier = 40

    var body: some Commands {
        FlagCommands(id: identifier)
    }
}

private struct OrderedCommandsTestApp: App {
    init() {}

    var body: some Scene {
        WindowGroup("Ordered commands test") { EmptyView() }
            .commands { FlagCommands(id: 1) }
            .commands { FlagCommands(id: 2) }
    }
}

private struct DynamicCommandsTestApp: App {
    init() {}

    var body: some Scene {
        WindowGroup("Dynamic commands test") { EmptyView() }
            .commands { DynamicProbeCommands() }
    }
}

private struct RemovedCommandsTestApp: App {
    init() {}

    var body: some Scene {
        WindowGroup("Removed commands test") { EmptyView() }
            .commands { FlagCommands(id: 1) }
            .commandsRemoved()
    }
}

private struct ReplacedCommandsTestApp: App {
    init() {}

    var body: some Scene {
        WindowGroup("Replaced commands test") { EmptyView() }
            .commands { FlagCommands(id: 1) }
            .commandsReplaced { FlagCommands(id: 2) }
    }
}

private struct DefaultCommandMenuStyleTestApp: App {
    init() {}

    var body: some Scene {
        WindowGroup("Default command-menu style test") { EmptyView() }
    }
}

private struct PlatformCommandMenuStyleTestApp: App {
    init() {}

    var body: some Scene {
        WindowGroup("Platform command-menu style test") { EmptyView() }
            .commandMenuPresentationStyle(.platform)
    }
}

private struct PlatformWindowPresentationHostTestApp: App {
    init() {}

    var body: some Scene {
        WindowGroup("Platform-window presentation host test") { EmptyView() }
            .defaultPresentationHostMode(.platformWindow)
    }
}
