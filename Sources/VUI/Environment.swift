//
//  File: Environment.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import Observation

@attached(accessor)
@attached(peer, names: prefixed(__Key_))
public macro Entry() = #externalMacro(
    module: "VUIMacros",
    type: "EntryMacro"
)

@attached(accessor)
public macro __EntryDefaultValue() = #externalMacro(
    module: "VUIMacros",
    type: "EntryDefaultValueMacro"
)

public protocol EnvironmentKey {
    associatedtype Value
    static var defaultValue: Self.Value { get }
    static func _valuesEqual(_ lhs: Self.Value, _ rhs: Self.Value) -> Bool
}

extension EnvironmentKey {
    public static func _valuesEqual(_ lhs: Self.Value, _ rhs: Self.Value) -> Bool {
        false
    }
}

extension EnvironmentKey where Self.Value: Equatable {
    public static func _valuesEqual(_ lhs: Self.Value, _ rhs: Self.Value) -> Bool {
        lhs == rhs
    }
}

// Adapter that stores EnvironmentKey values in the PropertyList backing store.
struct EnvironmentPropertyKey<K: EnvironmentKey>: PropertyKey {
    typealias Value = K.Value
    static var defaultValue: K.Value { K.defaultValue }
    static func valuesEqual(_ a: K.Value, _ b: K.Value) -> Bool { K._valuesEqual(a, b) }
}

protocol DerivedEnvironmentKey {
    associatedtype Value: Equatable
    static func value(in environment: EnvironmentValues) -> Value
}

struct DerivedEnvironmentPropertyKey<K: DerivedEnvironmentKey>: DerivedPropertyKey {
    static func value(in plist: PropertyList) -> K.Value {
        // The outer tracker observes the aggregate value, not each input read
        // performed while computing it.
        K.value(in: EnvironmentValues(plist))
    }
}

// Stores Observable objects in the environment property list via a per-type key.
// ObservableObjectKey<T> is the PropertyList carrier for object storage.
struct ObservableObjectKey<T: AnyObject & Observable>: PropertyKey {
    typealias Value = T?
    static var defaultValue: T? { nil }
    static func valuesEqual(_ a: T?, _ b: T?) -> Bool { a === b }
}

// PropertyList-backed environment values plus optional per-key read tracking.
public struct EnvironmentValues: CustomStringConvertible {
    var _plist: PropertyList
    var tracker: _PropertyListTracker?

    public init() {
        self._plist = PropertyList()
        self.tracker = nil
    }

    public subscript<K>(key: K.Type) -> K.Value where K: EnvironmentKey {
        get {
            if let tracker {
                return tracker.value(_plist, for: EnvironmentPropertyKey<K>.self)
            }
            return _plist[EnvironmentPropertyKey<K>.self]
        }
        set { setTrackedValue(newValue, for: EnvironmentPropertyKey<K>.self) }
    }

    public var description: String { _plist.description }
}

extension EnvironmentValues {
    static func tracking(_ plist: PropertyList = PropertyList()) -> EnvironmentValues {
        EnvironmentValues(plist, tracker: _PropertyListTracker())
    }

    init(_ plist: PropertyList, tracker: _PropertyListTracker? = nil) {
        self._plist = plist
        self.tracker = tracker
        tracker?.initializeValues(from: plist)
    }

    func trackingCopy() -> EnvironmentValues {
        EnvironmentValues.tracking(_plist)
    }

    // Render callbacks run outside AG evaluation. Keep the property-list snapshot
    // while detaching the dependency tracker owned by the graph-side environment.
    func untrackedCopy() -> EnvironmentValues {
        var copy = self
        copy.tracker = nil
        return copy
    }

    subscript<K: DerivedPropertyKey>(_ key: K.Type) -> K.Value {
        if let tracker {
            return tracker.derivedValue(_plist, for: key)
        }
        return _plist[key]
    }

    subscript<K: DerivedEnvironmentKey>(_ key: K.Type) -> K.Value {
        if let tracker {
            return tracker.derivedValue(_plist, for: DerivedEnvironmentPropertyKey<K>.self)
        }
        return K.value(in: self)
    }

    func valueWithSecondaryLookup<K: PropertyKeyLookup>(_ lookup: K.Type) -> K.Primary.Value {
        if let tracker {
            return tracker.valueWithSecondaryLookup(_plist, secondaryLookupHandler: lookup)
        }
        return _plist.valueWithSecondaryLookup(lookup)
    }

    func addDependencies(from tracker: _PropertyListTracker) {
        self.tracker?.formUnion(tracker)
    }

    func addDependencies(from values: EnvironmentValues) {
        guard let tracker = values.tracker else { return }
        addDependencies(from: tracker)
    }

    mutating func setTrackedValue<K: PropertyKey>(_ value: K.Value, for key: K.Type) {
        let oldList = _plist
        _plist[key] = value
        tracker?.invalidateValue(for: key, from: oldList, to: _plist)
    }

    public subscript<T: AnyObject & Observable>(objectType type: T.Type) -> T? {
        get { _plist[ObservableObjectKey<T>.self] }
        set { setTrackedValue(newValue, for: ObservableObjectKey<T>.self) }
    }

    // Internal subscripts for keypath literal use.

    subscript<T: AnyObject & Observable>(_obs id: ObjectIdentifier) -> T? {
        get { _plist[ObservableObjectKey<T>.self] }
        set { setTrackedValue(newValue, for: ObservableObjectKey<T>.self) }
    }

    subscript<T: AnyObject & Observable>(_crashingObs id: ObjectIdentifier) -> T {
        get {
            guard let obj = _plist[ObservableObjectKey<T>.self] else {
                fatalError("No observable object of type \(T.self) found in the environment. Inject it with .environment(_ object:).")
            }
            return obj
        }
    }
}

public struct IsEnabledKey: EnvironmentKey {
    public static let defaultValue: Bool = true
}

public struct IsFocusedKey: EnvironmentKey {
    public static let defaultValue: Bool = false
}

struct AccessibilityEnabledKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

private struct LocaleKey: EnvironmentKey {
    static let defaultValue: Locale = .current
}

private struct CalendarKey: EnvironmentKey {
    static let defaultValue: Calendar = .autoupdatingCurrent
}

private struct TimeZoneKey: EnvironmentKey {
    static let defaultValue: TimeZone = .autoupdatingCurrent
}

extension EnvironmentValues {
    public var locale: Locale {
        get { self[LocaleKey.self] }
        set { self[LocaleKey.self] = newValue }
    }

    public var calendar: Calendar {
        get { self[CalendarKey.self] }
        set { self[CalendarKey.self] = newValue }
    }

    public var timeZone: TimeZone {
        get { self[TimeZoneKey.self] }
        set { self[TimeZoneKey.self] = newValue }
    }

    public var isEnabled: Bool {
        get { self[IsEnabledKey.self] }
        set { self[IsEnabledKey.self] = newValue }
    }
    public var isFocused: Bool {
        get { self[IsFocusedKey.self] }
        set { self[IsFocusedKey.self] = newValue }
    }
    var accessibilityEnabled: Bool {
        get { self[AccessibilityEnabledKey.self] }
        set { self[AccessibilityEnabledKey.self] = newValue }
    }
}

@propertyWrapper public struct Environment<Value> {
    @usableFromInline
    enum Content: @unchecked Sendable {
        case keyPath(KeyPath<EnvironmentValues, Value>)
        case value(Value)
    }
    @usableFromInline
    var content: Content

    /// Returns the resolved value.
    ///
    /// During body evaluation, `_makeProperty` + the body rule in `View._makeView`
    /// will have already resolved this field from `.keyPath` to `.value` via `_write`.
    /// Outside that context (e.g. before the view is mounted), `.keyPath` returns
    /// the default value from an empty `EnvironmentValues`.
    @inlinable public var wrappedValue: Value {
        switch content {
        case .value(let value):
            return value
        case .keyPath(let keyPath):
            return EnvironmentValues()[keyPath: keyPath]
        }
    }

    @inlinable public init(_ keyPath: KeyPath<EnvironmentValues, Value>) {
        content = .keyPath(keyPath)
    }

    @usableFromInline
    internal init(_ value: Value) {
        content = .value(value)
    }

    /// Returns a copy of self with `.keyPath` resolved to `.value` using `values`.
    func _resolve(_ values: EnvironmentValues) -> Self {
        if case .keyPath(let keyPath) = content {
            return Self(values[keyPath: keyPath])
        }
        return self
    }

    /// Writes `self` into the raw memory at `ptr` (must point to an `Environment<Value>` field).
    func _write(_ ptr: UnsafeMutableRawPointer) {
        ptr.assumingMemoryBound(to: Environment<Value>.self).pointee = self
    }
}

extension Environment {
    /// Reads an `Observable` object of type `Value` injected via `.environment(_ object:)`.
    /// Crashes at runtime if no object of that type is present.
    public init(_ objectType: Value.Type) where Value: AnyObject, Value: Observable {
        content = .keyPath(\EnvironmentValues[_crashingObs: ObjectIdentifier(objectType)])
    }

    /// Reads an `Observable` object of type `T` as `T?`.
    /// Returns `nil` if the object was not injected into the environment.
    public init<T: AnyObject & Observable>(_ objectType: T.Type) where Value == T? {
        content = .keyPath(\EnvironmentValues[_obs: ObjectIdentifier(objectType)])
    }
}

extension Environment: DynamicProperty {
    /// Registers a write closure in `buffer.contexts[fieldOffset]`.
    ///
    /// The closure is called inside the body rule (see `View._makeView`) with a pointer
    /// to the corresponding field in a mutable copy of the view struct. It reads the
    /// current `.keyPath` value from the copy, resolves it against the live
    /// `EnvironmentValues` AG node, and writes the resulting `.value` back.
    public static func _makeProperty<V>(in buffer: inout _DynamicPropertyBuffer,
                                        container: _GraphValue<V>,
                                        fieldOffset: Int,
                                        inputs: inout _GraphInputs) {
        assert(buffer.properties.contains { $0.offset == fieldOffset } == false)
        let envAttr = inputs.cachedEnvironment.value.environment
        buffer.properties.append(.init(type: Self.self, offset: fieldOffset))
        buffer.contexts[fieldOffset] = { (ptr: UnsafeMutableRawPointer) in
            // Read the .keyPath instance from the view copy, resolve, write back.
            let current = ptr.assumingMemoryBound(to: Self.self).pointee
            current._resolve(envAttr.value)._write(ptr)
        }
    }
}

extension Environment: Sendable where Value: Sendable {
}
