//
//  File: Commands.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

public protocol Commands {
    associatedtype Body: Commands
    @CommandsBuilder var body: Self.Body { get }
    
    nonisolated static func _makeCommands(content: _GraphValue<Self>, inputs: _CommandsInputs) -> _CommandsOutputs
    func _resolve(into resolved: inout _ResolvedCommands)
}

extension Commands {
    nonisolated public static func _makeCommands(content: _GraphValue<Self>, inputs: _CommandsInputs) -> _CommandsOutputs {
        fatalError()
    }
    
    public func _resolve(into resolved: inout _ResolvedCommands) {
        fatalError()
    }
}

public struct EmptyCommands: Commands {
    nonisolated public static func _makeCommands(content: _GraphValue<EmptyCommands>, inputs: _CommandsInputs) -> _CommandsOutputs {
        fatalError()
    }
    nonisolated public init() {}
    
    public func _resolve(into: inout _ResolvedCommands) {
        fatalError()
    }
    
    public typealias Body = Never
}

public struct _ResolvedCommands {
}

extension Scene {
    nonisolated public func commands<Content>(@CommandsBuilder content: () -> Content) -> some Scene where Content: Commands {
        fatalError()
    }
}

extension _ConditionalContent: Commands where TrueContent: Commands, FalseContent: Commands {
    nonisolated public static func _makeCommands(content: _GraphValue<Self>, inputs: _CommandsInputs) -> _CommandsOutputs {
        fatalError()
    }
    
    public typealias Body = Never
}

extension Optional: Commands where Wrapped: Commands {
    public static func _makeCommands(content: _GraphValue<Optional<Wrapped>>, inputs: _CommandsInputs) -> _CommandsOutputs {
        fatalError()
    }
    public typealias Body = Never
}

public struct _CommandsInputs {
}

public struct _CommandsOutputs {
}

extension Never: Commands {
}

extension Commands where Self.Body == Never {
    public var body: Never {
        fatalError("\(Self.self) may not have Body == Never")
    }
}
