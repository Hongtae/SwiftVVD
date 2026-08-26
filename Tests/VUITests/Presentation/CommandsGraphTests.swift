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

    func testCommandPlacementWrapperUsesOnlyProcessLocalIdentity() {
        let sharedID = UUID()
        let original = HashableCommandGroupPlacementWrapper(
            placement: CommandGroupPlacement(
                name: Text("Original Name"),
                id: sharedID
            )
        )
        let renamed = HashableCommandGroupPlacementWrapper(
            placement: CommandGroupPlacement(
                name: Text("Renamed"),
                id: sharedID
            )
        )
        let independent = HashableCommandGroupPlacementWrapper(
            placement: CommandGroupPlacement(
                name: Text("Original Name"),
                id: UUID()
            )
        )

        XCTAssertEqual(original, renamed)
        XCTAssertNotEqual(original, independent)
        XCTAssertEqual(Set([original, renamed, independent]).count, 2)
    }

    func testCommandMenuAndGroupsProduceDeferredOperations() throws {
        // ASSERTIONS commandProducerGraphRuntimeObserved
        let appGraph = AppGraph(app: CommandProducerTestApp())
        let (commands, _) = try graphOutputs(from: appGraph)
        let operations = commandOperations(commands)

        XCTAssertEqual(operations.count, 4)
        XCTAssertEqual(operations.map(mutationName), [
            "topLevel", "append", "prepend", "replace",
        ])
        XCTAssertEqual(operations.map { $0.placement.name }, [
            Text("Fixture Menu"),
            CommandGroupPlacement.newItem.name,
            CommandGroupPlacement.saveItem.name,
            CommandGroupPlacement.help.name,
        ])
        XCTAssertTrue(operations.allSatisfy { $0.resolver != nil })
        XCTAssertTrue(commands.items.allSatisfy { $0.version.value > 0 })

        let repeated = try _AGGraph.withCurrent(appGraph.graph) {
            try XCTUnwrap(appGraph.commandsListAttr).value
        }
        XCTAssertEqual(
            commandOperations(repeated).first?.placement.id,
            operations.first?.placement.id
        )
    }

    func testCommandsCompositionGraphPreservesBranchesAndSourceOrder() throws {
        // ASSERTIONS commandsCompositionGraphRuntimeObserved
        let initial = AppGraph(app: InitialCommandsCompositionTestApp())
        let (initialCommands, _) = try graphOutputs(from: initial)
        XCTAssertEqual(commandFlagIDs(initialCommands), [1, 2, 5, 6, 7, 8])

        let alternate = AppGraph(app: AlternateCommandsCompositionTestApp())
        let (alternateCommands, _) = try graphOutputs(from: alternate)
        XCTAssertEqual(commandFlagIDs(alternateCommands), [1, 3, 4, 5, 6, 7, 8])
    }

    func testConditionalCommandsRewireIndirectOutputWhenBranchChanges() throws {
        // ASSERTIONS commandsConditionalOptionalGraphDisassemblyObserved
        let graph = _AGGraph()
        try _AGGraph.withCurrent(graph) {
            let root = AGSubgraphRef()
            try AGSubgraphRef.withCurrent(root) {
                typealias Conditional = _ConditionalContent<
                    FlagCommands,
                    FlagCommands
                >
                let source = graph.makeInput(
                    value: Conditional(
                        storage: .trueContent(FlagCommands(id: 11))
                    )
                )
                let outputs = Conditional._makeCommands(
                    content: _GraphValue(_attribute: source),
                    inputs: makeCommandsInputs(graph: graph)
                )
                let listID = try XCTUnwrap(
                    outputs.preferences.value(for: CommandsList.Key.self)
                )
                let list = Attribute<CommandsList>(listID)

                XCTAssertEqual(commandFlagIDs(list.value), [11])

                source.setValue(
                    Conditional(
                        storage: .trueContent(FlagCommands(id: 13))
                    )
                )
                XCTAssertEqual(commandFlagIDs(list.value), [13])

                source.setValue(
                    Conditional(
                        storage: .falseContent(FlagCommands(id: 12))
                    )
                )
                XCTAssertEqual(commandFlagIDs(list.value), [12])
            }
        }
    }

    func testOptionalCommandsRewireIndirectOutputWhenPresenceChanges() throws {
        // ASSERTIONS commandsConditionalOptionalGraphDisassemblyObserved
        let graph = _AGGraph()
        try _AGGraph.withCurrent(graph) {
            let root = AGSubgraphRef()
            try AGSubgraphRef.withCurrent(root) {
                let source = graph.makeInput(
                    value: Optional<FlagCommands>.none
                )
                let outputs = Optional<FlagCommands>._makeCommands(
                    content: _GraphValue(_attribute: source),
                    inputs: makeCommandsInputs(graph: graph)
                )
                let listID = try XCTUnwrap(
                    outputs.preferences.value(for: CommandsList.Key.self)
                )
                let list = Attribute<CommandsList>(listID)

                XCTAssertEqual(commandFlagIDs(list.value), [])

                source.setValue(FlagCommands(id: 21))
                XCTAssertEqual(commandFlagIDs(list.value), [21])

                source.setValue(nil)
                XCTAssertEqual(commandFlagIDs(list.value), [])
            }
        }
    }

    func testCommandsBuilderSupportsObservedAritiesAndValueResolutionOrder() {
        // ASSERTIONS commandsBuilderFixedArityRuntimeObserved
        // ASSERTIONS commandsCompositionValueResolutionObserved
        let trace = CommandResolutionTrace()
        func command(_ id: Int) -> ResolvingCommands {
            ResolvingCommands(id: id, trace: trace)
        }

        let arity2 = CommandsBuilder.buildBlock(command(1), command(2))
        let arity3 = CommandsBuilder.buildBlock(
            command(1), command(2), command(3)
        )
        let arity4 = CommandsBuilder.buildBlock(
            command(1), command(2), command(3), command(4)
        )
        let arity5 = CommandsBuilder.buildBlock(
            command(1), command(2), command(3), command(4), command(5)
        )
        let arity6 = CommandsBuilder.buildBlock(
            command(1), command(2), command(3), command(4), command(5),
            command(6)
        )
        let arity7 = CommandsBuilder.buildBlock(
            command(1), command(2), command(3), command(4), command(5),
            command(6), command(7)
        )
        let arity8 = CommandsBuilder.buildBlock(
            command(1), command(2), command(3), command(4), command(5),
            command(6), command(7), command(8)
        )
        let arity9 = CommandsBuilder.buildBlock(
            command(1), command(2), command(3), command(4), command(5),
            command(6), command(7), command(8), command(9)
        )
        let arity10 = CommandsBuilder.buildBlock(
            command(1), command(2), command(3), command(4), command(5),
            command(6), command(7), command(8), command(9), command(10)
        )

        XCTAssertEqual([
            tupleCommandArity(arity2),
            tupleCommandArity(arity3),
            tupleCommandArity(arity4),
            tupleCommandArity(arity5),
            tupleCommandArity(arity6),
            tupleCommandArity(arity7),
            tupleCommandArity(arity8),
            tupleCommandArity(arity9),
            tupleCommandArity(arity10),
        ], Array(2...10))

        var resolved = _ResolvedCommands()
        arity10._resolve(into: &resolved)
        XCTAssertEqual(trace.ids, Array(1...10))

        trace.ids.removeAll()
        Group {
            command(21)
            command(22)
        }
        ._resolve(into: &resolved)
        XCTAssertEqual(trace.ids, [21, 22])
    }

    func testCommandsBuilderParameterPackExtendsPastObservedArityRange() {
        let trace = CommandResolutionTrace()
        func command(_ id: Int) -> ResolvingCommands {
            ResolvingCommands(id: id, trace: trace)
        }

        let arity11 = CommandsBuilder.buildBlock(
            command(1), command(2), command(3), command(4), command(5),
            command(6), command(7), command(8), command(9), command(10),
            command(11)
        )

        XCTAssertEqual(tupleCommandArity(arity11), 11)
    }

    func testCommandsTupleDescriptionCachesConformancesInSourceOrder() {
        // ASSERTIONS commandsTupleHelperRuntimeObserved
        typealias Content = (
            FlagCommands,
            ResolvingCommands,
            EmptyCommands
        )

        let description = CommandsDescriptor.tupleDescription(Content.self)
        XCTAssertEqual(description.contentTypes.map(\.0), [0, 1, 2])
        XCTAssertEqual(
            description.contentTypes.map { ObjectIdentifier($0.1.type) },
            [
                ObjectIdentifier(FlagCommands.self),
                ObjectIdentifier(ResolvingCommands.self),
                ObjectIdentifier(EmptyCommands.self),
            ]
        )
        XCTAssertTrue(description.contentTypes.allSatisfy {
            UInt(bitPattern: $0.1.conformance) != 1
        })
        XCTAssertTrue(description.contentTypes.allSatisfy {
            $0.1.metadata == unsafeBitCast(
                $0.1.type,
                to: UnsafeRawPointer.self
            )
        })
        XCTAssertEqual(
            CommandsDescriptor.typeCache[ObjectIdentifier(Content.self)]?
                .contentTypes.count,
            3
        )
        XCTAssertNil(CommandsDescriptor.conformance(of: Int.self))

        var visitor = RecordingCommandsTypeVisitor()
        for (_, conformance) in description.contentTypes {
            withUnsafeMutablePointer(to: &visitor) {
                conformance.visitType(visitor: $0)
            }
        }
        XCTAssertEqual(visitor.types.map(ObjectIdentifier.init), [
            ObjectIdentifier(FlagCommands.self),
            ObjectIdentifier(ResolvingCommands.self),
            ObjectIdentifier(EmptyCommands.self),
        ])
    }

    func testMultiPreferenceCombinerPreservesSingleIdentityAndPairOrder() throws {
        // ASSERTIONS commandsTupleHelperRuntimeObserved
        let graph = _AGGraph()
        try _AGGraph.withCurrent(graph) {
            let first = graph.makeInput(value: [1])
            let second = graph.makeInput(value: [2])
            var firstOutput = PreferencesOutputs()
            firstOutput.append(
                CommandTuplePreferenceKey.self,
                node: first.identifier
            )
            var secondOutput = PreferencesOutputs()
            secondOutput.append(
                CommandTuplePreferenceKey.self,
                node: second.identifier
            )

            func combine(_ outputs: [PreferencesOutputs]) -> PreferencesOutputs {
                var visitor = MultiPreferenceCombinerVisitor(
                    outputs: outputs,
                    result: PreferencesOutputs()
                )
                CommandTuplePreferenceKey.visitKey(&visitor)
                return visitor.result
            }

            XCTAssertNil(
                combine([]).value(for: CommandTuplePreferenceKey.self)
            )

            let single = try XCTUnwrap(
                combine([firstOutput]).value(
                    for: CommandTuplePreferenceKey.self
                )
            )
            XCTAssertEqual(single, first.identifier)

            let pair = try XCTUnwrap(
                combine([firstOutput, secondOutput]).value(
                    for: CommandTuplePreferenceKey.self
                )
            )
            XCTAssertNotEqual(pair, first.identifier)
            XCTAssertNotEqual(pair, second.identifier)
            XCTAssertEqual(Attribute<[Int]>(pair).value, [1, 2])
        }
    }

    func testTupleCommandsFoldOnlyRequestedPreferencesInSourceOrder() throws {
        // ASSERTIONS commandsTupleHelperRuntimeObserved
        let graph = _AGGraph()
        try _AGGraph.withCurrent(graph) {
            let tuple = TupleCommandContent((
                RawPreferenceCommands(value: 1),
                RawPreferenceCommands(value: 2),
                RawPreferenceCommands(value: 3)
            ))
            let source = graph.makeInput(value: tuple)

            let unrequested = TupleCommandContent._makeCommands(
                content: _GraphValue(_attribute: source),
                inputs: makeCommandsInputs(graph: graph)
            )
            XCTAssertNil(
                unrequested.preferences.value(
                    for: CommandTuplePreferenceKey.self
                )
            )

            var requestedKeys = PreferenceKeys()
            requestedKeys.add(CommandTuplePreferenceKey.self)
            let requested = TupleCommandContent._makeCommands(
                content: _GraphValue(_attribute: source),
                inputs: makeCommandsInputs(
                    graph: graph,
                    keys: requestedKeys
                )
            )
            let value = try XCTUnwrap(
                requested.preferences.value(
                    for: CommandTuplePreferenceKey.self
                )
            )
            XCTAssertEqual(Attribute<[Int]>(value).value, [1, 2, 3])
        }
    }

    func testCommandsListResolutionPreservesItemOrderAndCollectsFlags() throws {
        // ASSERTIONS commandsListResolutionRuntimeObserved
        let first = CommandGroup(after: .newItem) { Text("first") }.change
        let before = CommandGroup(before: .newItem) { Text("before") }.change
        let last = CommandGroup(after: .newItem) { Text("last") }.change
        let commands = CommandsList(items: [
            .init(value: .operation(first), version: .init(value: 30)),
            .init(value: .flag(CommandFlag(id: 7)), version: .init(value: 40)),
            .init(value: .operation(before), version: .init(value: 10)),
            .init(value: .flag(CommandFlag(id: 8)), version: .init(value: 50)),
            .init(value: .operation(last), version: .init(value: 20)),
            .init(value: .flag(CommandFlag(id: 7)), version: .init(value: 60)),
        ])

        var resolved = _ResolvedCommands()
        commands.resolveOperations(into: &resolved)

        XCTAssertEqual(
            textValues(in: try XCTUnwrap(resolved[.newItem]).result.viewContent),
            [Text("before"), Text("first"), Text("last")]
        )
        XCTAssertEqual(resolved.flags, [CommandFlag(id: 7), CommandFlag(id: 8)])
    }

    func testCommandAccumulatorAppliesMutationAndInitializeRules() throws {
        // ASSERTIONS commandAccumulatorMutationRuntimeGuardObserved
        var resolved = _ResolvedCommands()
        CommandGroup(after: .newItem) { Text("after-1") }
            ._resolve(into: &resolved)
        CommandGroup(before: .newItem) { Text("before-1") }
            ._resolve(into: &resolved)
        CommandGroup(after: .newItem) { Text("after-2") }
            ._resolve(into: &resolved)

        CommandGroup(after: .saveItem) { Text("discarded") }
            ._resolve(into: &resolved)
        CommandGroup(replacing: .saveItem) { Text("replacement") }
            ._resolve(into: &resolved)
        CommandGroup(before: .saveItem) { Text("before-replacement") }
            ._resolve(into: &resolved)
        CommandGroup(after: .saveItem) { Text("after-replacement") }
            ._resolve(into: &resolved)

        let initial = CommandOperation(
            mutation: .initialize,
            placement: .help,
            content: Text("initial")
        )
        initial.resolver?(initial, &resolved)
        CommandGroup(after: .help) { Text("after-initial") }
            ._resolve(into: &resolved)
        let ignored = CommandOperation(
            mutation: .initialize,
            placement: .help,
            content: Text("ignored")
        )
        ignored.resolver?(ignored, &resolved)

        let newItem = try XCTUnwrap(resolved[.newItem])
        XCTAssertEqual(textValues(in: newItem.result.viewContent), [
            Text("before-1"), Text("after-1"), Text("after-2"),
        ])
        XCTAssertEqual(newItem.updatedPlacements.count, 1)

        let saveItem = try XCTUnwrap(resolved[.saveItem])
        XCTAssertEqual(textValues(in: saveItem.result.viewContent), [
            Text("before-replacement"),
            Text("replacement"),
            Text("after-replacement"),
        ])
        XCTAssertEqual(saveItem.updatedPlacements.count, 1)

        let help = try XCTUnwrap(resolved[.help])
        XCTAssertEqual(textValues(in: help.result.viewContent), [
            Text("initial"), Text("after-initial"),
        ])
        XCTAssertEqual(help.updatedPlacements.count, 1)
    }

    func testCommandMenuResolutionAppendsTopLevelPlacementsInOrder() throws {
        var resolved = _ResolvedCommands()
        CommandMenu("First Menu") { Text("first-item") }
            ._resolve(into: &resolved)
        CommandMenu("Second Menu") { Text("second-item") }
            ._resolve(into: &resolved)

        XCTAssertEqual(
            resolved.topLevelCommands.map(\.placement.name),
            [Text("First Menu"), Text("Second Menu")]
        )
        XCTAssertEqual(
            Set(resolved.topLevelCommands.map(\.placement.id)).count,
            2
        )
        XCTAssertEqual(
            textValues(
                in: try XCTUnwrap(
                    resolved.storage[resolved.topLevelCommands[0]]
                ).result.viewContent
            ),
            [Text("first-item")]
        )
        XCTAssertEqual(
            textValues(
                in: try XCTUnwrap(
                    resolved.storage[resolved.topLevelCommands[1]]
                ).result.viewContent
            ),
            [Text("second-item")]
        )
    }

    func testCommandContentAnnotatesEveryPlatformItemWithItsOperation() throws {
        // ASSERTIONS commandPlatformItemOperationRuntimeObserved
        let operation = CommandGroup(after: .newItem) {
            Text("annotated")
        }.change
        var accumulator = CommandAccumulator()
        accumulator.visit(Text("annotated"), operation: operation)
        let transform = try XCTUnwrap(
            platformItemTransform(in: accumulator.result.viewContent)
        )
        var list = PlatformItemList(items: [
            PlatformItemList.Item(systemItem: .button),
            PlatformItemList.Item(systemItem: .button),
        ])
        transform(&list)

        XCTAssertEqual(list.items.count, 2)
        for item in list.items {
            let stored = try XCTUnwrap(item.commandOperation)
            XCTAssertEqual(stored.placement.id, CommandGroupPlacement.newItem.id)
            XCTAssertEqual(mutationName(stored), "append")
        }
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

    private func tupleCommandArity(_ value: Any) -> Int {
        guard let tuple = Mirror(reflecting: value).children.first(where: {
            $0.label == "value"
        })?.value else {
            return 0
        }
        return Mirror(reflecting: tuple).children.count
    }

    private func makeCommandsInputs(
        graph: _AGGraph,
        keys: PreferenceKeys? = nil
    ) -> _CommandsInputs {
        var requestedKeys = keys ?? PreferenceKeys()
        if keys == nil {
            requestedKeys.add(CommandsList.Key.self)
        }
        return _CommandsInputs(
            base: _GraphInputs(
                time: graph.makeInput(value: Time(seconds: 0)),
                phase: graph.makeInput(value: _GraphInputs.Phase()),
                environment: graph.makeInput(value: EnvironmentValues.tracking()),
                transaction: graph.makeInput(value: Transaction())
            ),
            preferences: PreferencesInputs(
                keys: requestedKeys,
                hostKeys: graph.makeInput(value: requestedKeys)
            )
        )
    }

    private func commandOperations(_ commands: CommandsList) -> [CommandOperation] {
        commands.items.compactMap { item in
            guard case let .operation(operation) = item.value else {
                return nil
            }
            return operation
        }
    }

    private func mutationName(_ operation: CommandOperation) -> String {
        switch operation.mutation {
        case .append: "append"
        case .prepend: "prepend"
        case .replace: "replace"
        case .topLevel: "topLevel"
        case .initialize: "initialize"
        }
    }

    private func textValues(in value: Any) -> [Text] {
        if let text = value as? Text {
            return [text]
        }
        return Mirror(reflecting: value).children.flatMap {
            textValues(in: $0.value)
        }
    }

    private func platformItemTransform(
        in value: Any
    ) -> ((inout PlatformItemList) -> Void)? {
        if let modifier = value as? PlatformItemListTransformModifier<
            AllPlatformItemListFlags
        > {
            return modifier.transform
        }
        for child in Mirror(reflecting: value).children {
            if let transform = platformItemTransform(in: child.value) {
                return transform
            }
        }
        return nil
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

private final class CommandResolutionTrace {
    var ids: [Int] = []
}

private struct ResolvingCommands: Commands {
    var id: Int
    var trace: CommandResolutionTrace

    typealias Body = Never

    func _resolve(into resolved: inout _ResolvedCommands) {
        trace.ids.append(id)
    }
}

private struct RecordingCommandsTypeVisitor: CommandsTypeVisitor {
    var types: [Any.Type] = []

    mutating func visit<Content: Commands>(type: Content.Type) {
        types.append(type)
    }
}

private enum CommandTuplePreferenceKey: PreferenceKey {
    static let defaultValue: [Int] = []

    static func reduce(value: inout [Int], nextValue: () -> [Int]) {
        value.append(contentsOf: nextValue())
    }
}

private struct RawPreferenceCommands: Commands {
    var value: Int

    typealias Body = Never

    static func _makeCommands(
        content: _GraphValue<Self>,
        inputs: _CommandsInputs
    ) -> _CommandsOutputs {
        guard let graph = _AGGraph.current else {
            fatalError(
                "RawPreferenceCommands._makeCommands called outside AG context."
            )
        }
        let value: Attribute<[Int]> = graph.makeRule {
            [content._attribute.value.value]
        }
        var preferences = PreferencesOutputs()
        preferences.append(
            CommandTuplePreferenceKey.self,
            node: value.identifier
        )
        return _CommandsOutputs(preferences: preferences)
    }

    func _resolve(into resolved: inout _ResolvedCommands) {}
}

private struct ComposedFlagCommands: Commands {
    var selectsTrueBranch: Bool
    var includesOptional: Bool

    var body: some Commands {
        FlagCommands(id: 1)

        if selectsTrueBranch {
            FlagCommands(id: 2)
        } else {
            FlagCommands(id: 3)
        }

        if includesOptional {
            FlagCommands(id: 4)
        }

        Group {
            FlagCommands(id: 5)
            FlagCommands(id: 6)
        }

        ErasedFlagCommands()
        FlagCommands(id: 8)
    }
}

private struct ErasedFlagCommands: Commands {
    var body: some Commands {
        let erased: any Commands = FlagCommands(id: 7)
        CommandsBuilder.buildLimitedAvailability(erased)
    }
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

private struct CommandProducerTestApp: App {
    init() {}

    var body: some Scene {
        WindowGroup("Command producer test") { EmptyView() }
            .commands {
                CommandMenu("Fixture Menu") { Text("menu-item") }
            }
            .commands {
                CommandGroup(after: .newItem) { Text("after-item") }
            }
            .commands {
                CommandGroup(before: .saveItem) { Text("before-item") }
            }
            .commands {
                CommandGroup(replacing: .help) { Text("replacement-item") }
            }
    }
}

private struct InitialCommandsCompositionTestApp: App {
    init() {}

    var body: some Scene {
        WindowGroup("Commands composition test") { EmptyView() }
            .commands {
                ComposedFlagCommands(
                    selectsTrueBranch: true,
                    includesOptional: false
                )
            }
    }
}

private struct AlternateCommandsCompositionTestApp: App {
    init() {}

    var body: some Scene {
        WindowGroup("Alternate commands composition test") { EmptyView() }
            .commands {
                ComposedFlagCommands(
                    selectsTrueBranch: false,
                    includesOptional: true
                )
            }
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
