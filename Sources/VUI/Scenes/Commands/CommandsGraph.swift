//
//  File: CommandsGraph.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

// Ordered command operations are collected through a scene preference before
// a platform host resolves them into its menu representation.
struct CommandsList {
    struct Key: PreferenceKey {
        static var defaultValue: CommandsList { CommandsList() }

        static func reduce(
            value: inout CommandsList,
            nextValue: () -> CommandsList
        ) {
            value.items.append(contentsOf: nextValue().items)
        }
    }

    struct Item {
        enum Value {
            case operation(CommandOperation)
            case flag(CommandFlag)
        }

        var value: Value
        var version: DisplayList.Version
    }

    var items: [Item] = []

    func resolveOperations(into resolved: inout _ResolvedCommands) {
        // Resolution preserves preference order. Item versions invalidate the
        // graph value but do not reorder operations during consumption.
        for item in items {
            switch item.value {
            case let .operation(operation):
                operation.resolver?(operation, &resolved)
            case let .flag(flag):
                resolved.flags.insert(flag)
            }
        }
    }
}

// Flags share the ordered CommandsList channel with mutation operations. The
// resolver interprets the identifier when it consumes the list.
struct CommandFlag: Hashable {
    var id: Int
}

// A command operation keeps its placement mutation and deferred resolver
// together until the host performs the resolution pass.
struct CommandOperation {
    enum Mutation {
        case append
        case prepend
        case replace
        case topLevel
        case initialize
    }

    var mutation: Mutation
    var placement: CommandGroupPlacement
    var resolver: ((CommandOperation, inout _ResolvedCommands) -> Void)?

    init<Content: View>(
        mutation: Mutation,
        placement: CommandGroupPlacement,
        content: Content
    ) {
        self.mutation = mutation
        self.placement = placement
        self.resolver = { operation, resolved in
            let key = HashableCommandGroupPlacementWrapper(
                placement: placement
            )
            if mutation == .topLevel {
                resolved.topLevelCommands.append(key)
            }

            var accumulator = resolved[placement] ?? CommandAccumulator()
            accumulator.visit(content, operation: operation)
            resolved.storage[key] = accumulator
        }
    }
}

// CommandGroupPlacement intentionally does not expose Hashable conformance.
// Resolution keys compare only the placement's process-local identity.
struct HashableCommandGroupPlacementWrapper: Hashable {
    var placement: CommandGroupPlacement

    static func == (
        lhs: HashableCommandGroupPlacementWrapper,
        rhs: HashableCommandGroupPlacementWrapper
    ) -> Bool {
        lhs.placement.id == rhs.placement.id
    }

    func hash(into hasher: inout Hasher) {
        placement.id.hash(into: &hasher)
    }
}

struct CommandAccumulator {
    struct Result {
        var viewContent: AnyView
    }

    var result: Result
    var updatedPlacements: Set<HashableCommandGroupPlacementWrapper>

    init() {
        result = Result(viewContent: AnyView(EmptyView()))
        updatedPlacements = []
    }

    mutating func visit<Content: View>(
        _ content: Content,
        operation: CommandOperation
    ) {
        // Each materialized platform item retains the operation that placed
        // it, allowing the later menu-item pass to preserve group ownership.
        let annotatedContent = content.transformPlatformItemList(
            AllPlatformItemListFlags.self
        ) { list in
            for index in list.items.indices {
                list.items[index].commandOperation = operation
            }
        }
        let placement = HashableCommandGroupPlacementWrapper(
            placement: operation.placement
        )

        switch operation.mutation {
        case .append:
            result.viewContent = AnyView(
                TupleView((result.viewContent, annotatedContent))
            )
        case .prepend:
            result.viewContent = AnyView(
                TupleView((annotatedContent, result.viewContent))
            )
        case .replace, .topLevel:
            result.viewContent = AnyView(annotatedContent)
        case .initialize:
            if !updatedPlacements.contains(placement) {
                result.viewContent = AnyView(annotatedContent)
            }
        }

        updatedPlacements.insert(placement)
    }
}
