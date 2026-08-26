//
//  File: TupleCommandContent.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

@usableFromInline
struct TupleCommandContent<T>: Commands {
    @usableFromInline
    var body: Never {
        fatalError()
    }
    
    @usableFromInline
    static func _makeCommands(content: _GraphValue<Self>, inputs: _CommandsInputs) -> _CommandsOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("TupleCommandContent._makeCommands called outside _AGGraph context")
        }

        var visitor = MakeList(
            content: content,
            inputs: inputs,
            offset: 0,
            outputs: []
        )
        for field in commandFields {
            visitor.offset = field.offset
            visitor.visit(field.type)
        }
        return _CommandsOutputs(
            preferences: PreferencesOutputs.merge(
                visitor.outputs.map(\.preferences),
                in: graph
            )
        )
    }
    
    @usableFromInline
    init(_ value: T) {
        self.value = value
    }
    
    @usableFromInline
    func _resolve(into resolved: inout _ResolvedCommands) {
        var visitor = Visitor(content: value, resolved: resolved, offset: 0)
        for field in Self.commandFields {
            visitor.offset = field.offset
            visitor.visit(field.type)
        }
        resolved = visitor.resolved
    }
    
    @usableFromInline
    typealias Body = Never
    
    var value: T
}

private extension TupleCommandContent {
    struct MakeList {
        var content: _GraphValue<TupleCommandContent<T>>
        var inputs: _CommandsInputs
        var offset: Int
        var outputs: [_CommandsOutputs]

        mutating func visit<Content: Commands>(_ type: Content.Type) {
            let child = _GraphValue<Content>(
                _attribute: content._attribute.unsafeOffset(
                    at: offset,
                    as: type
                )
            )
            outputs.append(
                Content._makeCommands(content: child, inputs: inputs)
            )
        }
    }

    struct Visitor {
        var content: T
        var resolved: _ResolvedCommands
        var offset: Int

        mutating func visit<Content: Commands>(_ type: Content.Type) {
            withUnsafeBytes(of: content) { bytes in
                let child = bytes.baseAddress!
                    .advanced(by: offset)
                    .assumingMemoryBound(to: type)
                    .pointee
                child._resolve(into: &resolved)
            }
        }
    }

    /// Concrete command fields and their byte offsets in the stored tuple.
    static var commandFields: [
        (offset: Int, type: any Commands.Type)
    ] {
        if let commandType = T.self as? any Commands.Type {
            return [(offset: 0, type: commandType)]
        }

        var fields: [(offset: Int, type: any Commands.Type)] = []
        _forEachField(of: T.self) { _, offset, fieldType in
            if let commandType = fieldType as? any Commands.Type {
                fields.append((offset: offset, type: commandType))
            }
            return true
        }
        return fields
    }
}
