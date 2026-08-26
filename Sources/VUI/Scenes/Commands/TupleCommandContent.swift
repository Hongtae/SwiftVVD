//
//  File: TupleCommandContent.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

protocol CommandsTypeVisitor {
    mutating func visit<Content: Commands>(type: Content.Type)
}

struct CommandsDescriptor: TupleDescriptor {
    nonisolated(unsafe) static var typeCache: [
        ObjectIdentifier: TupleTypeDescription<CommandsDescriptor>
    ] = [:]

    static var descriptor: UnsafeRawPointer {
        _protocolDescriptor(of: (any Commands).self)
    }
}

extension TypeConformance where Descriptor == CommandsDescriptor {
    func visitType<Visitor: CommandsTypeVisitor>(
        visitor: UnsafeMutablePointer<Visitor>
    ) {
        let commandType = unsafeExistentialMetatype((any Commands.Type).self)
        func visit<Content: Commands>(_ type: Content.Type) {
            visitor.pointee.visit(type: type)
        }
        _openExistential(commandType, do: visit)
    }
}

@usableFromInline
struct TupleCommandContent<T>: Commands {
    @usableFromInline
    var body: Never {
        fatalError()
    }
    
    @usableFromInline
    static func _makeCommands(content: _GraphValue<Self>, inputs: _CommandsInputs) -> _CommandsOutputs {
        guard _AGGraph.current != nil else {
            fatalError("TupleCommandContent._makeCommands called outside _AGGraph context")
        }

        let description = CommandsDescriptor.tupleDescription(T.self)
        var visitor = MakeList(
            content: content,
            inputs: inputs,
            offset: 0,
            outputs: []
        )
        for (index, conformance) in description.contentTypes {
            visitor.offset = tupleElementOffset(of: T.self, at: index)
            withUnsafeMutablePointer(to: &visitor) {
                conformance.visitType(visitor: $0)
            }
        }

        // Child-only outputs must not escape this tuple. Fold exactly the keys
        // requested by the parent command graph.
        var combiner = MultiPreferenceCombinerVisitor(
            outputs: visitor.outputs.map(\.preferences),
            result: PreferencesOutputs()
        )
        for key in inputs.preferences.keys {
            func visit<Key: PreferenceKey>(_ key: Key.Type) {
                Key.visitKey(&combiner)
            }
            _openExistential(key, do: visit)
        }
        return _CommandsOutputs(
            preferences: combiner.result
        )
    }
    
    @usableFromInline
    init(_ value: T) {
        self.value = value
    }
    
    @usableFromInline
    func _resolve(into resolved: inout _ResolvedCommands) {
        let description = CommandsDescriptor.tupleDescription(T.self)
        var visitor = Visitor(content: value, resolved: resolved, offset: 0)
        for (index, conformance) in description.contentTypes {
            visitor.offset = tupleElementOffset(of: T.self, at: index)
            withUnsafeMutablePointer(to: &visitor) {
                conformance.visitType(visitor: $0)
            }
        }
        resolved = visitor.resolved
    }
    
    @usableFromInline
    typealias Body = Never
    
    var value: T
}

private extension TupleCommandContent {
    struct MakeList: CommandsTypeVisitor {
        var content: _GraphValue<TupleCommandContent<T>>
        var inputs: _CommandsInputs
        var offset: Int
        var outputs: [_CommandsOutputs]

        mutating func visit<Content: Commands>(type: Content.Type) {
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

    struct Visitor: CommandsTypeVisitor {
        var content: T
        var resolved: _ResolvedCommands
        var offset: Int

        mutating func visit<Content: Commands>(type: Content.Type) {
            withUnsafeBytes(of: content) { bytes in
                let child = bytes.baseAddress!
                    .advanced(by: offset)
                    .assumingMemoryBound(to: type)
                    .pointee
                child._resolve(into: &resolved)
            }
        }
    }
}
