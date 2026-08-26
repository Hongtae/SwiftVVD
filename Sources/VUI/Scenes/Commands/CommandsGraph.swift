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
}
