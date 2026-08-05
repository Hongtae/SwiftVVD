//
//  File: GraphInputReuse.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

// PropertyKey hierarchy for graph inputs.
//
// PropertyKey  (PropertyList.swift) - base: defaultValue, valuesEqual
//   -> GraphInput - adds AG reuse support (makeReusable, tryToReuse, isTriviallyReusable)
//      -> ViewInput - marker: keys stored in _ViewInputs.customInputs channel

/// Opaque map passed to GraphReusable methods.
/// Reserved for AG reuse bookkeeping.
struct IndirectAttributeMap {}

/// Protocol for values that support AG node reuse.
protocol GraphReusable {
    mutating func makeReusable(indirectMap: IndirectAttributeMap)
    mutating func tryToReuse(by other: Self, indirectMap: IndirectAttributeMap, testOnly: Bool) -> Bool
    static var isTriviallyReusable: Bool { get }
}

extension GraphReusable {
    mutating func makeReusable(indirectMap: IndirectAttributeMap) {}
    mutating func tryToReuse(by other: Self, indirectMap: IndirectAttributeMap, testOnly: Bool) -> Bool { false }
    static var isTriviallyReusable: Bool { false }
}

/// Refinement of PropertyKey that participates in AG node reuse.
/// Keys conforming to GraphInput can be stored in _GraphInputs.customInputs (base channel).
protocol GraphInput: PropertyKey {
    static func makeReusable(indirectMap: IndirectAttributeMap, value: inout Value)
    static func tryToReuse(_ a: Value, by b: Value, indirectMap: IndirectAttributeMap, testOnly: Bool) -> Bool
    static var isTriviallyReusable: Bool { get }
}

extension GraphInput {
    static func makeReusable(indirectMap: IndirectAttributeMap, value: inout Value) {}
    static func tryToReuse(_ a: Value, by b: Value, indirectMap: IndirectAttributeMap, testOnly: Bool) -> Bool { false }
    static var isTriviallyReusable: Bool { false }
}

extension GraphInput where Value: GraphReusable {
    static func makeReusable(indirectMap: IndirectAttributeMap, value: inout Value) {
        value.makeReusable(indirectMap: indirectMap)
    }
    static func tryToReuse(_ a: Value, by b: Value, indirectMap: IndirectAttributeMap, testOnly: Bool) -> Bool {
        var copy = a
        return copy.tryToReuse(by: b, indirectMap: indirectMap, testOnly: testOnly)
    }
    static var isTriviallyReusable: Bool { Value.isTriviallyReusable }
}

/// Marker refinement of GraphInput for view-level channel.
/// Keys conforming to ViewInput are stored in _ViewInputs.customInputs (view channel).
/// No additional requirements.
protocol ViewInput: GraphInput {}
