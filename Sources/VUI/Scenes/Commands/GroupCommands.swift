//
//  File: GroupCommands.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

extension Group: Commands where Content: Commands {
    
    nonisolated public static func _makeCommands(content: _GraphValue<Group<Content>>, inputs: _CommandsInputs) -> _CommandsOutputs {
        guard _AGGraph.current != nil else {
            fatalError("Group._makeCommands called outside _AGGraph context")
        }
        return Content._makeCommands(
            content: content[\.content],
            inputs: inputs
        )
    }
    
    @inlinable public init(@CommandsBuilder content: () -> Content) {
        self.init(_content: content())
    }
    
    public func _resolve(into resolved: inout _ResolvedCommands) {
        content._resolve(into: &resolved)
    }
}
