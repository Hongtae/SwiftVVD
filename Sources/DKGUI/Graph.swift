//
//  File: Graph.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

struct Graph {
}

struct GraphInputs {
}

struct GraphValue<Value> {
    var value: Value

    init(value: Value) {
        self.value = value
    }

    subscript<U>(keyPath: KeyPath<Value, U>) -> GraphValue<U> {
        GraphValue<U>(value: value[keyPath: keyPath])
    }
}

extension GraphValue: Equatable where Value: Equatable {
    static func == (a: GraphValue<Value>, b: GraphValue<Value>) -> Bool where Value: Equatable {
        return a.value == b.value
    }
}
