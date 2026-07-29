//
//  File: Animatable.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

public struct AnimatableValues<each Value>: VectorArithmetic where repeat each Value: VectorArithmetic {
    public var value: (repeat each Value)

    @inlinable public init(_ value: repeat each Value) {
        self.value = (repeat each value)
    }

    public init(_ _valueType: repeat (each Value).Type) {
        self.value = (repeat (each _valueType).zero)
    }

    public static var zero: AnimatableValues<repeat each Value> {
        AnimatableValues(repeat (each Value).zero)
    }

    public static func += (
        lhs: inout AnimatableValues<repeat each Value>,
        rhs: AnimatableValues<repeat each Value>
    ) {
        lhs = AnimatableValues(repeat each lhs.value + each rhs.value)
    }

    public static func -= (
        lhs: inout AnimatableValues<repeat each Value>,
        rhs: AnimatableValues<repeat each Value>
    ) {
        lhs = AnimatableValues(repeat each lhs.value - each rhs.value)
    }

    public static func + (
        lhs: AnimatableValues<repeat each Value>,
        rhs: AnimatableValues<repeat each Value>
    ) -> AnimatableValues<repeat each Value> {
        AnimatableValues(repeat each lhs.value + each rhs.value)
    }

    public static func - (
        lhs: AnimatableValues<repeat each Value>,
        rhs: AnimatableValues<repeat each Value>
    ) -> AnimatableValues<repeat each Value> {
        AnimatableValues(repeat each lhs.value - each rhs.value)
    }

    public mutating func scale(by rhs: Double) {
        value = (repeat (each value).scaled(by: rhs))
    }

    public var magnitudeSquared: Double {
        var result = 0.0
        for value in repeat each value {
            result += value.magnitudeSquared
        }
        return result
    }

    public static func == (
        lhs: AnimatableValues<repeat each Value>,
        rhs: AnimatableValues<repeat each Value>
    ) -> Bool {
        for (lhsValue, rhsValue) in repeat (each lhs.value, each rhs.value) {
            if lhsValue != rhsValue {
                return false
            }
        }
        return true
    }
}

public protocol Animatable {
    associatedtype AnimatableData: VectorArithmetic
    var animatableData: Self.AnimatableData { get set }

    static func _makeAnimatable(value: inout _GraphValue<Self>, inputs: _GraphInputs)
}

extension Animatable where Self: VectorArithmetic {
    public var animatableData: Self {
        get { self }
        set { self = newValue }
    }
}

extension Animatable where Self.AnimatableData == EmptyAnimatableData {
    public var animatableData: EmptyAnimatableData {
        @inlinable get { return EmptyAnimatableData() }
        @inlinable set {}
    }
    public static func _makeAnimatable(value: inout _GraphValue<Self>, inputs: _GraphInputs) {
    }
}

extension Animatable {
    @inline(__always)
    public static subscript<T>(_animatableType _: KeyPath<Self, T>) -> T.Type where T: VectorArithmetic {
        T.self
    }

    @_disfavoredOverload
    @inline(__always)
    public static subscript<T>(_animatableType _: KeyPath<Self, T>) -> T.AnimatableData.Type where T: Animatable {
        T.AnimatableData.self
    }

    @_disfavoredOverload
    @inline(__always)
    public static subscript<T>(_animatableType _: KeyPath<Self, T>) -> T.Type {
        T.self
    }

    @inline(__always)
    public subscript<T>(_animatableValue keyPath: WritableKeyPath<Self, T>) -> T where T: VectorArithmetic {
        get { self[keyPath: keyPath] }
        set { self[keyPath: keyPath] = newValue }
    }

    @_disfavoredOverload
    @inline(__always)
    public subscript<T>(_animatableValue keyPath: WritableKeyPath<Self, T>) -> T.AnimatableData where T: Animatable {
        get { self[keyPath: keyPath].animatableData }
        set { self[keyPath: keyPath].animatableData = newValue }
    }

    @_disfavoredOverload
    @inline(__always)
    public subscript<T>(_animatableValue _: WritableKeyPath<Self, T>) -> EmptyAnimatableData {
        get { .zero }
        nonmutating set {}
    }

    @inline(__always)
    public subscript<T>(_animatableValue keyPath: ReferenceWritableKeyPath<Self, T>) -> T where T: VectorArithmetic {
        get { self[keyPath: keyPath] }
        nonmutating set { self[keyPath: keyPath] = newValue }
    }

    @_disfavoredOverload
    @inline(__always)
    public subscript<T>(_animatableValue keyPath: ReferenceWritableKeyPath<Self, T>) -> T.AnimatableData where T: Animatable {
        get { self[keyPath: keyPath].animatableData }
        nonmutating set { self[keyPath: keyPath].animatableData = newValue }
    }
}

public func _animatableMacroKind() -> AnimatableValues<> {
    let result: AnimatableValues<> = .zero
    return result
}

@attached(extension, conformances: Animatable)
@attached(member, names: named(animatableData))
public macro Animatable() = #externalMacro(
    module: "VUIMacros",
    type: "AnimatableValuesMacro"
)

@attached(accessor, names: named(willSet))
public macro AnimatableIgnored() = #externalMacro(
    module: "VUIMacros",
    type: "AnimatableIgnoredMacro"
)

@freestanding(declaration)
public macro _UIAnimatableDataProperty(
    animatableMacroContext: String,
    kind: AnimatableValues<>
) = #externalMacro(
    module: "VUIMacros",
    type: "AnimatableValuesDataPropertyMacro"
)

@attached(accessor)
public macro _AnimatableData() = #externalMacro(
    module: "VUIMacros",
    type: "AnimatableValuesDataMacro"
)

@attached(accessor)
public macro _AnimatablePairData() = #externalMacro(
    module: "VUIMacros",
    type: "AnimatablePairDataMacro"
)

@freestanding(expression)
public macro _UIAnimatableProperty<T>(_ t: T.Type) -> T.Type = #externalMacro(
    module: "VUIMacros",
    type: "AnimatablePropertyMacro"
) where T: VectorArithmetic

@freestanding(expression)
public macro _UIAnimatableProperty<T>(_ t: T.Type) -> EmptyAnimatableData.Type = #externalMacro(
    module: "VUIMacros",
    type: "InvalidAnimatablePropertyMacro"
)

extension View where Self: Animatable {
    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        var view = view
        Self._makeAnimatable(value: &view, inputs: inputs.base)
        return _makeDefaultView(view: view, inputs: inputs)
    }

    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        var view = view
        Self._makeAnimatable(value: &view, inputs: inputs.base)
        return _makeDefaultViewList(view: view, inputs: inputs)
    }
}

public struct AnimatablePair<First, Second>: VectorArithmetic where First: VectorArithmetic, Second: VectorArithmetic {
    public var first: First
    public var second: Second

    public init(_ first: First, _ second: Second) {
        self.first = first
        self.second = second
    }

    public init(_ _firstType: First.Type, _ _secondType: Second.Type) {
        self.first = _firstType.zero
        self.second = _secondType.zero
    }

    @inlinable subscript() -> (First, Second) {
      get { return (first, second) }
      set { (first, second) = newValue }
    }

    public static var zero: AnimatablePair<First, Second> {
        return .init(First.zero, Second.zero)
    }

    public static func += (lhs: inout AnimatablePair<First, Second>, rhs: AnimatablePair<First, Second>) {
        lhs.first += rhs.first
        lhs.second += rhs.second
    }

    public static func -= (lhs: inout AnimatablePair<First, Second>, rhs: AnimatablePair<First, Second>) {
        lhs.first -= rhs.first
        lhs.second -= rhs.second
    }

    public static func + (lhs: AnimatablePair<First, Second>, rhs: AnimatablePair<First, Second>) -> AnimatablePair<First, Second> {
        return .init(lhs.first + rhs.first, lhs.second + rhs.second)
    }

    public static func - (lhs: AnimatablePair<First, Second>, rhs: AnimatablePair<First, Second>) -> AnimatablePair<First, Second> {
        return .init(lhs.first - rhs.first, lhs.second - rhs.second)
    }

    public mutating func scale(by rhs: Double) {
        first.scale(by: rhs)
        second.scale(by: rhs)
    }

    public var magnitudeSquared: Double {
        return first.magnitudeSquared + second.magnitudeSquared
    }
}

extension AnimatablePair: Equatable {
    public static func == (a: AnimatablePair<First, Second>, b: AnimatablePair<First, Second>) -> Bool {
        return a.first == b.first && a.second == b.second
    }
}

extension AnimatablePair: Sendable where First: Sendable, Second: Sendable {
}

struct AnimatableArray<Element: VectorArithmetic>: VectorArithmetic {
    var elements: [Element]

    init(_ elements: [Element]) {
        self.elements = elements
    }

    static var zero: Self {
        Self([])
    }

    static func += (lhs: inout Self, rhs: Self) {
        let sharedCount = min(lhs.elements.count, rhs.elements.count)
        for index in 0..<sharedCount {
            lhs.elements[index] += rhs.elements[index]
        }
    }

    static func -= (lhs: inout Self, rhs: Self) {
        let sharedCount = min(lhs.elements.count, rhs.elements.count)
        for index in 0..<sharedCount {
            lhs.elements[index] -= rhs.elements[index]
        }
    }

    static func + (lhs: Self, rhs: Self) -> Self {
        var result = lhs
        result += rhs
        return result
    }

    static func - (lhs: Self, rhs: Self) -> Self {
        var result = lhs
        result -= rhs
        return result
    }

    mutating func scale(by rhs: Double) {
        for index in elements.indices {
            elements[index].scale(by: rhs)
        }
    }

    var magnitudeSquared: Double {
        elements.reduce(0) { $0 + $1.magnitudeSquared }
    }
}

extension AnimatableArray: Sendable where Element: Sendable {
}

struct KeyedAnimatableArray<Key: Comparable, Data: VectorArithmetic>: VectorArithmetic {
    struct Element: Equatable {
        var key: Key
        var data: Data
    }

    var elements: [Element]
    var isZero: Bool

    init(_ elements: [Element]) {
        self.elements = elements
        self.isZero = false
    }

    private init(elements: [Element], isZero: Bool) {
        self.elements = elements
        self.isZero = isZero
    }

    static var zero: Self {
        Self(elements: [], isZero: true)
    }

    static func += (lhs: inout Self, rhs: Self) {
        if lhs.isZero {
            lhs = rhs
            return
        }
        guard !rhs.isZero else { return }
        lhs.combine(rhs, subtracting: false)
    }

    static func -= (lhs: inout Self, rhs: Self) {
        guard !rhs.isZero else { return }
        if lhs.isZero {
            lhs = rhs
            lhs.scale(by: -1)
            return
        }
        lhs.combine(rhs, subtracting: true)
    }

    static func + (lhs: Self, rhs: Self) -> Self {
        var result = lhs
        result += rhs
        return result
    }

    static func - (lhs: Self, rhs: Self) -> Self {
        var result = lhs
        result -= rhs
        return result
    }

    mutating func scale(by rhs: Double) {
        guard !isZero else { return }
        for index in elements.indices {
            elements[index].data.scale(by: rhs)
        }
    }

    var magnitudeSquared: Double {
        guard !isZero else { return 0 }
        return elements.reduce(0) { $0 + $1.data.magnitudeSquared }
    }

    func extract<Value>(
        into values: inout [Value],
        key: (Value) -> Key,
        set: (inout Value, Data) -> Void
    ) {
        guard !isZero else { return }
        var valueIndex = values.startIndex
        var elementIndex = elements.startIndex
        while valueIndex < values.endIndex && elementIndex < elements.endIndex {
            let element = elements[elementIndex]
            let valueKey = key(values[valueIndex])
            if valueKey == element.key {
                set(&values[valueIndex], element.data)
                values.formIndex(after: &valueIndex)
                elements.formIndex(after: &elementIndex)
            } else if valueKey < element.key {
                values.formIndex(after: &valueIndex)
            } else {
                elements.formIndex(after: &elementIndex)
            }
        }
    }

    private mutating func combine(_ rhs: Self, subtracting: Bool) {
        var lhsIndex = 0
        var rhsIndex = 0
        while lhsIndex < elements.count && rhsIndex < rhs.elements.count {
            if elements[lhsIndex].key == rhs.elements[rhsIndex].key {
                if subtracting {
                    elements[lhsIndex].data -= rhs.elements[rhsIndex].data
                } else {
                    elements[lhsIndex].data += rhs.elements[rhsIndex].data
                }
                lhsIndex += 1
                rhsIndex += 1
            } else if elements[lhsIndex].key < rhs.elements[rhsIndex].key {
                elements.remove(at: lhsIndex)
            } else {
                rhsIndex += 1
            }
        }
        if lhsIndex < elements.count {
            elements.removeSubrange(lhsIndex...)
        }
    }
}

extension KeyedAnimatableArray.Element: Sendable where Key: Sendable, Data: Sendable {
}

extension KeyedAnimatableArray: Sendable where Key: Sendable, Data: Sendable {
}
