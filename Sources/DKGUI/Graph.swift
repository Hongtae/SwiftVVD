//
//  File: Graph.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

public struct _Graph {
}

public struct _GraphInputs {
}

public struct _ViewInputs {
    var modifiers: [any ViewModifier]
}

public struct _ViewOutputs {
    var bindings: [String]
    var modifiers: [any ViewModifier]
//    var view: any ViewProxy

    init() {
        self.bindings = []
        self.modifiers = []
    }
}

public struct _ViewListInputs {
}

public struct _ViewListOutputs {
}

@dynamicMemberLookup
public struct _GraphValue<Value> {
    public var value: Value

    public init(value: Value) {
        self.value = value
    }

    public subscript<U>(dynamicMember keyPath: KeyPath<Value, U>) -> _GraphValue<U> {
        _GraphValue<U>(value: self.value[keyPath: keyPath])
    }
}

extension _GraphValue: Equatable where Value: Equatable {
    public static func == (a: _GraphValue<Value>, b: _GraphValue<Value>) -> Bool {
        return a.value == b.value
    }
}
