//
//  File: TupleCommandContent.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

@usableFromInline
struct TupleCommandContent<T>: Commands {
    @usableFromInline
    var body: Never {
        fatalError()
    }
    
    @usableFromInline
    static func _makeCommands(content: _GraphValue<Self>, inputs: _CommandsInputs) -> _CommandsOutputs {
        fatalError()
    }
    
    @usableFromInline
    init(_ value: T) {
        self.value = value
    }
    
    @usableFromInline
    func _resolve(into resolved: inout _ResolvedCommands) {
    }
    
    @usableFromInline
    typealias Body = Never
    
    var value: T
}
