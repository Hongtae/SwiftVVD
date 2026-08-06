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
//      -> ViewInput - marker for view-facing graph input access

final class IndirectAttributeMap {
    // Keys are original attributes. Values are stable indirect attributes
    // owned by `subgraph` and retargeted when an element is reused.
    let subgraph: AGSubgraphRef
    var map: [AGAttribute: AGAttribute]

    init(subgraph: AGSubgraphRef) {
        self.subgraph = subgraph
        self.map = [:]
    }
}

struct GraphReuseOptions: OptionSet {
    var rawValue: Int

    static let lazyLayouts = GraphReuseOptions(rawValue: 0x2)
    static let viewListContent = GraphReuseOptions(rawValue: 0x4)
    static let expandedReuse = GraphReuseOptions(rawValue: 0x8)
    static let `default`: GraphReuseOptions = []

    nonisolated(unsafe) static var overrideValue: GraphReuseOptions?

    static var current: GraphReuseOptions {
        overrideValue ?? .default
    }
}

struct ReusableInputStorage {
    var filter: BloomFilter
    // Reusable keys are recorded newest-first so comparison and witness
    // dispatch can replay the same key sequence without type erasure.
    var stack: Stack<any GraphInput.Type>
}

struct ReusableInputs: PropertyKey {
    static var defaultValue: ReusableInputStorage {
        ReusableInputStorage(filter: BloomFilter(), stack: .empty)
    }

    static func valuesEqual(
        _ lhs: ReusableInputStorage,
        _ rhs: ReusableInputStorage
    ) -> Bool {
        _AGCompareValues(
            lhs,
            rhs,
            options: AGComparisonOptions(rawValue: 0x103)
        )
    }
}

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

/// Marker refinement used by view-facing graph input subscripts.
protocol ViewInput: GraphInput {}

extension Attribute {
    mutating func makeReusable(
        indirectMap: IndirectAttributeMap,
        withoutInvalidation: Bool
    ) {
        // Multiple materializations of the same source must share one
        // indirect node; otherwise a retarget would update only one consumer.
        let source = identifier
        if let indirect = indirectMap.map[source] {
            identifier = indirect
            return
        }

        guard let graph = indirectMap.subgraph.graph else {
            fatalError(
                "Attribute.makeReusable requires a live indirect-map subgraph."
            )
        }
        guard _AGGraph.current === graph, self.graph === graph else {
            fatalError(
                "Attribute.makeReusable requires the source, map, and active graph to match."
            )
        }

        let indirect = AGSubgraphRef.withCurrent(indirectMap.subgraph) {
            graph.makeIndirectAttribute(
                source: self,
                withoutInvalidation: withoutInvalidation
            )
        }
        indirectMap.map[source] = indirect.identifier
        identifier = indirect.identifier
    }

    mutating func tryToReuse(
        by other: Attribute<Value>,
        indirectMap: IndirectAttributeMap,
        withoutInvalidation: Bool,
        testOnly: Bool
    ) -> Bool {
        // Lookup uses the original source identifier. The caller keeps its
        // unmodified source value and materializes a reusable copy separately.
        guard let indirect = indirectMap.map[identifier] else {
            return false
        }
        // Validation probes reuse compatibility without changing the live
        // forwarding target.
        if !testOnly {
            guard let graph = indirectMap.subgraph.graph else {
                fatalError(
                    "Attribute.tryToReuse requires a live indirect-map subgraph."
                )
            }
            guard _AGGraph.current === graph,
                  self.graph === graph,
                  other.graph === graph else {
                fatalError(
                    "Attribute.tryToReuse requires the attributes, map, and active graph to match."
                )
            }
            graph.setIndirectTarget(
                indirect,
                to: other.identifier,
                withoutInvalidation: withoutInvalidation
            )
        }
        return true
    }
}

extension Attribute {
    mutating func makeReusable(indirectMap: IndirectAttributeMap) {
        makeReusable(
            indirectMap: indirectMap,
            withoutInvalidation: false
        )
    }

    mutating func tryToReuse(
        by other: Attribute<Value>,
        indirectMap: IndirectAttributeMap,
        testOnly: Bool
    ) -> Bool {
        tryToReuse(
            by: other,
            indirectMap: indirectMap,
            withoutInvalidation: false,
            testOnly: testOnly
        )
    }
}

extension _GraphValue: GraphReusable where Value: GraphReusable {
    mutating func makeReusable(indirectMap: IndirectAttributeMap) {
        _attribute.makeReusable(indirectMap: indirectMap)
    }

    mutating func tryToReuse(
        by other: _GraphValue<Value>,
        indirectMap: IndirectAttributeMap,
        testOnly: Bool
    ) -> Bool {
        _attribute.tryToReuse(
            by: other._attribute,
            indirectMap: indirectMap,
            testOnly: testOnly
        )
    }

    static var isTriviallyReusable: Bool {
        Value.isTriviallyReusable
    }
}

extension Stack: GraphReusable where Element: GraphReusable {
    static var isTriviallyReusable: Bool {
        Element.isTriviallyReusable
    }

    mutating func makeReusable(indirectMap: IndirectAttributeMap) {
        self = map { element in
            var element = element
            element.makeReusable(indirectMap: indirectMap)
            return element
        }
    }

    mutating func tryToReuse(
        by other: Stack<Element>,
        indirectMap: IndirectAttributeMap,
        testOnly: Bool
    ) -> Bool {
        // Stack order and length are part of the reusable-input contract.
        var lhs = self
        var rhs = other
        while true {
            switch (lhs.pop(), rhs.pop()) {
            case (nil, nil):
                return true
            case (.some(var lhsElement), .some(let rhsElement)):
                if !Element.isTriviallyReusable,
                   !lhsElement.tryToReuse(
                        by: rhsElement,
                        indirectMap: indirectMap,
                        testOnly: testOnly
                   ) {
                    return false
                }
            default:
                return false
            }
        }
    }
}
