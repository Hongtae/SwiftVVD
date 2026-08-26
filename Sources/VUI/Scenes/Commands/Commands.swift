//
//  File: Commands.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

public protocol Commands {
    associatedtype Body: Commands
    @CommandsBuilder var body: Self.Body { get }
    
    nonisolated static func _makeCommands(content: _GraphValue<Self>, inputs: _CommandsInputs) -> _CommandsOutputs
    func _resolve(into resolved: inout _ResolvedCommands)
}

extension Commands {
    nonisolated public static func _makeCommands(content: _GraphValue<Self>, inputs: _CommandsInputs) -> _CommandsOutputs {
        if Body.self is Never.Type {
            fatalError("\(Self.self) may not have Body == Never")
        }
        var bodyInputs = inputs
        let fields = DynamicPropertyCache.fields(of: Self.self)
        let (body, _) = CommandsBodyAccessor<Self>.makeBody(
            container: content,
            inputs: &bodyInputs.base,
            fields: fields
        )
        return Body._makeCommands(content: body, inputs: bodyInputs)
    }
    
    public func _resolve(into resolved: inout _ResolvedCommands) {
        body._resolve(into: &resolved)
    }
}

// Produces a graph-backed Commands body and installs the container's dynamic
// properties before each body evaluation.
private struct CommandsBodyAccessor<Content: Commands>: BodyAccessor {
    typealias Container = Content
    typealias Body = Content.Body

    let containerAttr: Attribute<Content>

    mutating func updateBody(of content: Content, changed: Bool) -> Content.Body {
        content.body
    }

    static func makeBody(
        container: _GraphValue<Content>,
        inputs: inout _GraphInputs,
        fields: DynamicPropertyCache.Fields
    ) -> (_GraphValue<Content.Body>, Optional<_DynamicPropertyBuffer>) {
        guard let graph = _AGGraph.current else {
            fatalError("CommandsBodyAccessor.makeBody called outside _AGGraph context")
        }
        let buffer = _DynamicPropertyBuffer(
            fields: fields,
            container: container,
            inputs: &inputs
        )
        let accessor = CommandsBodyAccessor(containerAttr: container._attribute)
        if buffer.isEmpty {
            let attribute = graph.makeStatefulRule(
                StaticBody<CommandsBodyAccessor<Content>, MainThreadFlags>(
                    accessor: accessor
                )
            )
            return (_GraphValue(_attribute: attribute), nil)
        }
        let attribute = graph.makeStatefulRule(
            DynamicBody<CommandsBodyAccessor<Content>, MainThreadFlags>(
                accessor: accessor,
                buffer: buffer
            )
        )
        return (_GraphValue(_attribute: attribute), buffer)
    }
}

public struct EmptyCommands: Commands {
    nonisolated public static func _makeCommands(content: _GraphValue<EmptyCommands>, inputs: _CommandsInputs) -> _CommandsOutputs {
        _CommandsOutputs(preferences: PreferencesOutputs())
    }
    nonisolated public init() {}
    
    public func _resolve(into: inout _ResolvedCommands) {
    }
    
    public typealias Body = Never
}

public struct _ResolvedCommands {
    var topLevelCommands: [HashableCommandGroupPlacementWrapper]
    var storage: [HashableCommandGroupPlacementWrapper: CommandAccumulator]
    var flags: Set<CommandFlag>

    init() {
        topLevelCommands = []
        storage = [:]
        flags = []
    }

    subscript(
        placement: CommandGroupPlacement
    ) -> CommandAccumulator? {
        storage[HashableCommandGroupPlacementWrapper(placement: placement)]
    }
}

extension Scene {
    nonisolated public func commands<Content>(@CommandsBuilder content: () -> Content) -> some Scene where Content: Commands {
        modifier(CommandsModifier(content: content()))
    }
}

extension _ConditionalContent: Commands where TrueContent: Commands, FalseContent: Commands {
    nonisolated public static func _makeCommands(content: _GraphValue<Self>, inputs: _CommandsInputs) -> _CommandsOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("_ConditionalContent._makeCommands called outside _AGGraph context")
        }

        let preferences = inputs.preferences.makeIndirectOutputs()
        let outputs = _CommandsOutputs(preferences: preferences)
        let provider = CommandsProvider(inputs: inputs, outputs: outputs)
        let container: Attribute<Info> = graph.makeStatefulRule(
            Container(
                content: content._attribute,
                provider: provider
            )
        )
        outputs.preferences.setIndirectDependency(container.identifier)
        return outputs
    }

    private struct CommandsProvider: ConditionalContentProvider {
        var inputs: _CommandsInputs
        var outputs: _CommandsOutputs

        func detachOutputs() {
            outputs.preferences.detachIndirectOutputs()
        }

        func attachOutputs(to childOutputs: _CommandsOutputs) {
            childOutputs.preferences.attachIndirectOutputs(
                to: outputs.preferences
            )
        }

        func makeChildInputs() -> _CommandsInputs {
            var childInputs = inputs
            childInputs.base.copyCaches()
            return childInputs
        }

        func makeTrueOutputs(
            child: Attribute<TrueContent>,
            inputs: _CommandsInputs
        ) -> _CommandsOutputs {
            TrueContent._makeCommands(
                content: _GraphValue(_attribute: child),
                inputs: inputs
            )
        }

        func makeFalseOutputs(
            child: Attribute<FalseContent>,
            inputs: _CommandsInputs
        ) -> _CommandsOutputs {
            FalseContent._makeCommands(
                content: _GraphValue(_attribute: child),
                inputs: inputs
            )
        }
    }
    
    public typealias Body = Never
}

extension Optional: Commands where Wrapped: Commands {
    nonisolated public static func _makeCommands(content: _GraphValue<Self>, inputs: _CommandsInputs) -> _CommandsOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("Optional._makeCommands called outside _AGGraph context")
        }
        let child: Attribute<_ConditionalContent<Wrapped, EmptyCommands>> =
            graph.makeRule(Child(_content: content._attribute))
        return _ConditionalContent<Wrapped, EmptyCommands>._makeCommands(
            content: _GraphValue(_attribute: child),
            inputs: inputs
        )
    }

    private struct Child: Rule, AsyncAttribute {
        var _content: Attribute<Wrapped?>

        var value: _ConditionalContent<Wrapped, EmptyCommands> {
            if let wrapped = _content.value {
                return _ConditionalContent(
                    storage: .trueContent(wrapped)
                )
            }
            return _ConditionalContent(
                storage: .falseContent(EmptyCommands())
            )
        }
    }

    public typealias Body = Never
}

public struct _CommandsInputs {
    var base: _GraphInputs
    var preferences: PreferencesInputs
}

public struct _CommandsOutputs {
    var preferences: PreferencesOutputs
}

extension Never: Commands {
}

extension Commands where Self.Body == Never {
    public var body: Never {
        fatalError("\(Self.self) may not have Body == Never")
    }
}
