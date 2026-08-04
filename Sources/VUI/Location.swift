//
//  File: Location.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Observation

protocol TransactionHostProvider {
    var mutationHost: GraphHost? { get }
}

protocol _Location {
    associatedtype Value
    func getValue() -> Value
    mutating func setValue(_: Value, transaction: Transaction)
}

/// Describes a stable lens from a stored location value into a projected value.
protocol Projection: Hashable {
    associatedtype Base
    associatedtype Projected

    func get(base: Base) -> Projected
    func set(base: inout Base, newValue: Projected)
}

extension WritableKeyPath: Projection {
    func get(base: Root) -> Value {
        base[keyPath: self]
    }

    func set(base: inout Root, newValue: Value) {
        base[keyPath: self] = newValue
    }
}

enum BindingOperations {
    struct ToOptional<Value>: Projection {
        func get(base: Value) -> Value? {
            base
        }

        func set(base: inout Value, newValue: Value?) {
            if let newValue {
                base = newValue
            }
        }
    }

    struct ForceUnwrapping<Value>: Projection {
        func get(base: Value?) -> Value {
            base!
        }

        func set(base: inout Value?, newValue: Value) {
            base = newValue
        }
    }

    struct ToAnyHashable<Value: Hashable>: Projection {
        func get(base: Value) -> AnyHashable {
            AnyHashable(base)
        }

        func set(base: inout Value, newValue: AnyHashable) {
            base = newValue.base as! Value
        }
    }
}

/// Cache key that keeps repeated binding projections sharing the same location box.
private struct ProjectionCacheKey: Hashable {
    var type: ObjectIdentifier
    var projection: AnyHashable

    init<P: Projection>(_ projection: P) {
        self.type = ObjectIdentifier(P.self)
        self.projection = AnyHashable(projection)
    }
}

@usableFromInline
class AnyLocationBase {
    init() {}

    struct TrackerKey: Hashable {
        let id: ObjectIdentifier
        let offset: Int
    }
    private var notificationTargets: [TrackerKey: () -> Void] = [:]
    private var projectedLocations: [ProjectionCacheKey: AnyLocationBase] = [:]

    func addTracker(key: TrackerKey, tracker: @escaping ()->Void) {
        notificationTargets[key] = tracker
    }
    func removeTracker(key: TrackerKey) {
        notificationTargets.removeValue(forKey: key)
    }
    func notifyChange() {
        notificationTargets.values.map { $0 }
            .forEach { $0() }
    }

    func cachedProjectedLocation<P: Projection>(
        for projection: P,
        make: () -> AnyLocation<P.Projected>
    ) -> AnyLocation<P.Projected> {
        let key = ProjectionCacheKey(projection)
        if let location = projectedLocations[key] as? AnyLocation<P.Projected> {
            return location
        }

        let location = make()
        projectedLocations[key] = location
        return location
    }
}

@usableFromInline
class AnyLocation<Value>: AnyLocationBase, @unchecked Sendable {
    override init() {}

    func getValue() -> Value {
        fatalError()
    }

    func setValue(_: Value, transaction: Transaction) {
        notifyChange()
    }

    func update() -> (Value, Bool) {
        (getValue(), false)
    }

    func wasReadValue() -> Bool {
        false
    }

    func projecting<P>(_ projection: P) -> AnyLocation<P.Projected>
        where P: Projection, P.Base == Value
    {
        cachedProjectedLocation(for: projection) {
            LocationBox(location: ProjectedLocation(base: self, projection: projection))
        }
    }
}

extension AnyLocation: Equatable {
    @usableFromInline
    static func == (lhs: AnyLocation<Value>, rhs: AnyLocation<Value>) -> Bool {
        lhs === rhs
    }
}

struct FunctionalLocation<Value>: _Location {
    struct Functions {
        var getValue: ()->Value
        var setValue: (Value, Transaction)->Void
    }
    let functions: Functions

    init(
        get: @escaping ()->Value,
        set: @escaping (Value, Transaction)->Void
    ) {
        self.functions = Functions(getValue: get, setValue: set)
    }

    func getValue() -> Value {
        functions.getValue()
    }

    func setValue(_ value: Value, transaction: Transaction) {
        functions.setValue(value, transaction)
    }
}

struct ConstantLocation<Value>: _Location {
    let value: Value
    func getValue() -> Value { value }
    func setValue(_: Value, transaction: Transaction) {}
}

/// Location wrapper that writes a projected value back through its base location.
private struct ProjectedLocation<P: Projection>: _Location {
    var base: AnyLocation<P.Base>
    var projection: P

    func getValue() -> P.Projected {
        projection.get(base: base.getValue())
    }

    mutating func setValue(_ value: P.Projected, transaction: Transaction) {
        Transaction.withScopedThreadTransaction(transaction.current) {
            var baseValue = base.getValue()
            projection.set(base: &baseValue, newValue: value)
            base.setValue(baseValue, transaction: Transaction.current)
        }
    }
}

class StoredLocationBase<Value>: AnyLocation<Value>, @unchecked Sendable {
    struct BeginUpdate: GraphMutation {
        weak var location: StoredLocationBase<Value>?
        var transaction: Transaction

        func apply() {
            location?.beginUpdate(transaction: transaction)
        }

        mutating func combine<M>(with mutation: M) -> Bool where M: GraphMutation {
            guard let mutation = mutation as? BeginUpdate,
                  let location,
                  let nextLocation = mutation.location,
                  location === nextLocation else {
                return false
            }
            location.removeCombinedSavedValue()
            transaction = mutation.transaction
            return true
        }
    }

    private struct Data {
        var currentValue: Value
        var savedValue: [Value] = []
    }

    private var data: Data
    private var readValueHandler: (() -> Value)?
    private var commitValueHandler: ((Value, Transaction) -> Void)?

    private(set) var wasRead: Bool = false

    var isValid: Bool {
        true
    }

    var isUpdating: Bool {
        fatalError("StoredLocationBase.isUpdating must be implemented by a concrete location.")
    }

    var updateValue: Value {
        data.savedValue.first ?? data.currentValue
    }

    init(
        initialValue value: Value,
        readValue: (() -> Value)? = nil,
        onCommit: ((Value, Transaction) -> Void)? = nil
    ) {
        self.data = Data(currentValue: value)
        self.readValueHandler = readValue
        self.commitValueHandler = onCommit
        super.init()
    }

    override func getValue() -> Value {
        wasRead = true
        if let readValueHandler {
            let value = readValueHandler()
            data.currentValue = value
            return value
        }
        return data.currentValue
    }

    override func setValue(_ value: Value, transaction: Transaction) {
        guard !isUpdating else {
            print("Modifying state during view update, this will cause undefined behavior.")
            return
        }
        guard isValid else {
            data.currentValue = value
            return
        }
        guard !_stateValuesAreKnownEqual(data.currentValue, value) else { return }
        let current = transaction.current
        data.savedValue.append(data.currentValue)
        data.currentValue = value
        commit(
            transaction: current,
            id: Transaction.id,
            mutation: BeginUpdate(location: self, transaction: current)
        )
        notifyChange()
    }

    override func update() -> (Value, Bool) {
        wasRead = true
        return (updateValue, true)
    }

    override func wasReadValue() -> Bool {
        wasRead
    }

    func setCommitValueHandler(_ handler: ((Value, Transaction) -> Void)?) {
        commitValueHandler = handler
    }

    func setReadValueHandler(_ handler: (() -> Value)?) {
        readValueHandler = handler
    }

    func commit(
        transaction: Transaction,
        id: Transaction.ID,
        mutation: BeginUpdate
    ) {
        fatalError("StoredLocationBase.commit must be implemented by a concrete location.")
    }

    func notifyObservers() {
        fatalError("StoredLocationBase.notifyObservers must be implemented by a concrete location.")
    }

    private func beginUpdate(transaction: Transaction) {
        if !data.savedValue.isEmpty {
            data.savedValue.removeFirst()
        }
        commitValue(updateValue, transaction: transaction)
        notifyObservers()
    }

    private func removeCombinedSavedValue() {
        if !data.savedValue.isEmpty {
            data.savedValue.removeLast()
        }
    }

    fileprivate func commitValue(_ value: Value, transaction: Transaction) {
        commitValueHandler?(value, transaction)
    }

    fileprivate func setWasRead(_ value: Bool) {
        wasRead = value
    }
}

final class StoredLocation<Value>: StoredLocationBase<Value>, @unchecked Sendable {
    private weak var host: GraphHost?
    private var signal: AGWeakAttribute?

    convenience init(_ value: Value, onValueUpdated: @escaping (Value) -> Void) {
        self.init(initialValue: value)
        setCommitValueHandler { value, _ in
            onValueUpdated(value)
        }
    }

    init(
        initialValue value: Value,
        host: GraphHost? = nil,
        signal: AGWeakAttribute? = nil,
        readValue: (() -> Value)? = nil,
        onCommit: ((Value, Transaction) -> Void)? = nil
    ) {
        self.host = host
        self.signal = signal
        super.init(initialValue: value, readValue: readValue, onCommit: onCommit)
    }

    override var isValid: Bool {
        host?.data.isValid == true
    }

    override var isUpdating: Bool {
        host?.isUpdatingGraph == true
    }

    override func commit(
        transaction: Transaction,
        id: Transaction.ID,
        mutation: BeginUpdate
    ) {
        guard let host else {
            mutation.apply()
            return
        }
        host.asyncTransaction(
            transaction,
            id: id,
            mutation: mutation,
            style: .deferred,
            mayDeferUpdate: true
        )
    }

    override func update() -> (Value, Bool) {
        let isValid: Bool
        if let signal {
            if let host {
                isValid = signal.isValid(in: host.data.graph)
            } else if let graph = _AGGraph.current {
                isValid = signal.isValid(in: graph)
            } else {
                isValid = false
            }
        } else {
            isValid = true
        }

        if isValid {
            setWasRead(true)
        }
        return (updateValue, isValid)
    }

    override func notifyObservers() {
        guard let signal else { return }

        if let host {
            guard signal.isValid(in: host.data.graph) else { return }
            host.continueTransaction(invalidating: signal)
        } else if let graph = _AGGraph.current, signal.isValid(in: graph) {
            graph.invalidateAttribute(signal.toStrong())
        }
    }
}

final class ObservableLocation<Value>: StoredLocationBase<Value>, TransactionHostProvider, @unchecked Sendable {
    private struct Observer {
        weak var host: GraphHost?
        var signal: AGWeakAttribute
    }

    private var valueUpdated: (Value) -> Void
    private var observers: [Observer] = []

    var mutationHost: GraphHost? {
        for observer in observers {
            if let host = observer.host {
                return host
            }
        }
        return nil
    }

    init(_ value: Value, onValueUpdated: @escaping (Value)->Void) {
        self.valueUpdated = onValueUpdated
        super.init(initialValue: value)
        setCommitValueHandler { [weak self] value, _ in
            self?.valueUpdated(value)
        }
    }

    convenience init(initialValue value: Value) {
        self.init(value, onValueUpdated: { _ in })
    }

    override var isUpdating: Bool {
        GraphHost.isUpdating
    }

    override func commit(
        transaction: Transaction,
        id: Transaction.ID,
        mutation: BeginUpdate
    ) {
        GraphHost.globalTransaction(
            transaction,
            id: id,
            mutation: mutation,
            hostProvider: self
        )
    }

    func addObserver(host: GraphHost, signal: AGWeakAttribute) {
        observers.append(Observer(host: host, signal: signal))
    }

    func removeObserver(signal: AGWeakAttribute) {
        observers.removeAll { $0.signal == signal }
    }

    override func notifyObservers() {
        var liveObservers: [Observer] = []
        liveObservers.reserveCapacity(observers.count)

        for observer in observers {
            guard let host = observer.host else { continue }
            guard observer.signal.isValid(in: host.data.graph) else { continue }

            liveObservers.append(observer)
            host.continueTransaction(invalidating: observer.signal)
        }

        observers = liveObservers
    }
}

class LocationBox<Location: _Location>: AnyLocation<Location.Value>, @unchecked Sendable {
    var location: Location
    var _value: Location.Value
    init(location: Location) {
        self.location = location
        self._value = location.getValue()
    }
    override func getValue() -> Location.Value {
        location.getValue()
    }
    override func update() -> (Location.Value, Bool) {
        let value = location.getValue()
        let changed = !_stateValuesAreKnownEqual(_value, value)
        _value = value
        return (value, changed)
    }
    override func setValue(_ value: Location.Value, transaction: Transaction) {
        location.setValue(value, transaction: transaction)
        _value = value
        super.setValue(value, transaction: transaction)
    }
}

protocol AnyLocationBox {
    associatedtype Location: _Location
    var location: Location { get }
}

extension LocationBox: AnyLocationBox {
}
