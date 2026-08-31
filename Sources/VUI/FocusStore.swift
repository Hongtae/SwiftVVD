//
//  File: FocusStore.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

struct FocusItem {
    enum Base {
        case view(ViewFocusItem)
        case platformItem
        case platformResponder
    }

    struct ViewFocusItem {
        var id: ViewIdentity
        var isFocusable: Bool
        var options: FocusableOptions
        var onFocusChange: (Bool) -> Void
        var delegatesFocusEffect: Bool
    }

    var base: Base
    var prefersFocusSystem: Bool
    weak var responder: ResponderNode?
    var version: DisplayList.Version
    var wantsRestoration: Bool

    init(responder: ResponderNode) {
        base = .view(ViewFocusItem(
            id: ViewIdentity(),
            isFocusable: true,
            options: [],
            onFocusChange: { _ in },
            delegatesFocusEffect: false
        ))
        prefersFocusSystem = false
        self.responder = responder
        version = DisplayList.Version(forUpdate: ())
        wantsRestoration = false
    }
}

struct FocusableOptions: OptionSet {
    var rawValue: UInt8

    init(rawValue: UInt8) {
        self.rawValue = rawValue
    }
}

struct FocusStateBindingUpdateAction {
    var update: () -> Void
}

struct FocusStoreUpdateAction {
    var update: ((inout PropertyList) -> Void)?
}

struct FocusStore {
    struct Entry<Value: Hashable> {
        enum Target {
            case focusResponder(
                WeakBox<FocusStateBindingResponder>,
                WeakBox<FocusBridge>
            )
        }

        var value: Value
        var focusScopes: [Namespace.ID]
        var target: Target

        var responder: FocusStateBindingResponder? {
            switch target {
            case .focusResponder(let responder, _):
                responder.base
            }
        }

        var isValid: Bool {
            switch target {
            case .focusResponder(let responder, let bridge):
                responder.base != nil && bridge.base != nil
            }
        }

        func updateFocus(_ focused: Bool) {
            switch target {
            case .focusResponder(let responder, let bridge):
                guard let responder = responder.base else { return }
                bridge.base?.updateFocus(focused, responder: responder)
            }
        }
    }

    struct Key<Value: Hashable>: PropertyKey {
        static var defaultValue: Entry<Value>? { nil }

        static func valuesEqual(
            _ lhs: Entry<Value>?,
            _ rhs: Entry<Value>?
        ) -> Bool {
            false
        }
    }

    var version = DisplayList.Version()
    var focusedResponders: [WeakBox<ViewResponder>] = []
    var plists: [ObjectIdentifier: PropertyList] = [:]

    init() {}

    init(resolving list: FocusStoreList) {
        makeStoreContent(list)
    }

    mutating func makeStoreContent(_ list: FocusStoreList) {
        version = DisplayList.Version()
        focusedResponders.removeAll(keepingCapacity: true)
        plists.removeAll(keepingCapacity: true)

        for item in list.items {
            version.combine(with: item.version)
            var plist = plists[item.propertyID] ?? PropertyList()
            item.storeUpdateAction.update?(&plist)
            plists[item.propertyID] = plist

            if item.isFocused,
               let responder = item.responder as? ViewResponder {
                focusedResponders.append(WeakBox(responder))
            }
        }
    }
}

extension FocusStore: Equatable {
    static func == (lhs: FocusStore, rhs: FocusStore) -> Bool {
        lhs.version == rhs.version
    }
}

struct FocusStoreInputKey: ViewInput {
    static var defaultValue: OptionalAttribute<FocusStore> {
        OptionalAttribute()
    }

    static func valuesEqual(
        _ lhs: OptionalAttribute<FocusStore>,
        _ rhs: OptionalAttribute<FocusStore>
    ) -> Bool {
        lhs == rhs
    }
}

struct FocusedItemInputKey: ViewInput {
    static var defaultValue: OptionalAttribute<FocusItem?> {
        OptionalAttribute()
    }

    static func valuesEqual(
        _ lhs: OptionalAttribute<FocusItem?>,
        _ rhs: OptionalAttribute<FocusItem?>
    ) -> Bool {
        lhs == rhs
    }
}

struct FocusBridgeInputKey: ViewInput {
    static var defaultValue: OptionalAttribute<FocusBridge?> {
        OptionalAttribute()
    }

    static func valuesEqual(
        _ lhs: OptionalAttribute<FocusBridge?>,
        _ rhs: OptionalAttribute<FocusBridge?>
    ) -> Bool {
        lhs == rhs
    }
}

protocol FocusStoreHost: AnyObject {
    func focusStoreDidChange(_ store: FocusStore)
    func updateFocus(
        _ focused: Bool,
        within responder: FocusStateBindingResponder
    )
}

final class FocusBridge {
    weak var host: (any FocusStoreHost)?
    private(set) var focusStore = FocusStore()

    init(host: (any FocusStoreHost)?) {
        self.host = host
    }

    func preferencesDidChange(_ list: FocusStoreList) {
        guard focusStore.version != list.version else { return }
        let next = FocusStore(resolving: list)
        focusStore = next
        host?.focusStoreDidChange(next)
    }

    func updateFocus(
        _ focused: Bool,
        responder: FocusStateBindingResponder
    ) {
        host?.updateFocus(focused, within: responder)
    }
}

final class FocusStoreLocation<Value: Hashable>: AnyLocation<Value>,
    @unchecked Sendable {
    var store = FocusStore()
    weak var host: GraphHost?
    let resetValue: Value
    var focusVersion = DisplayList.Version()
    var deferredUpdate: (Value, DisplayList.Version)?
    var resolvedEntry: FocusStore.Entry<Value>?
    var resolvedVersion = DisplayList.Version()
    private var _wasRead = false

    var id: ObjectIdentifier {
        ObjectIdentifier(self)
    }

    init(host: GraphHost, resetValue: Value) {
        self.host = host
        self.resetValue = resetValue
        super.init()
    }

    override func getValue() -> Value {
        getValue(forReading: true)
    }

    func getValue(forReading: Bool) -> Value {
        if getValueForGraphUpdate(forReading: forReading) {
            _wasRead = true
        }
        if resolvedVersion != focusVersion {
            resolvedEntry = findFocusedEntry()
            resolvedVersion = focusVersion
        }
        return resolvedEntry?.value ?? resetValue
    }

    override func setValue(_ value: Value, transaction: Transaction) {
        guard let host else { return }
        host.asyncTransaction(transaction, id: Transaction.id) { [weak self] in
            self?.apply(value)
        }
        (host as? ViewGraph)?.requestImmediateUpdate()
    }

    override func update() -> (Value, Bool) {
        let previous = resolvedEntry?.value ?? resetValue
        let value = getValue(forReading: true)
        return (value, previous != value)
    }

    override func wasReadValue() -> Bool {
        _wasRead
    }

    func performDeferredUpdate() {
        guard let deferredUpdate,
              deferredUpdate.1 != store.version else {
            return
        }
        self.deferredUpdate = nil
        setValue(deferredUpdate.0, transaction: Transaction.current)
    }

    private func getValueForGraphUpdate(forReading: Bool) -> Bool {
        GraphHost.isUpdating && forReading
    }

    private func apply(_ value: Value) {
        let current = getValue(forReading: false)
        guard current != value else {
            deferredUpdate = nil
            return
        }

        let oldEntry = findFocusedEntry()
        let newEntry = findEntry(with: value)
        if value != resetValue && newEntry == nil {
            deferUpdate(value)
            return
        }
        deferredUpdate = nil

        if let oldEntry {
            Update.enqueueAction {
                oldEntry.updateFocus(false)
            }
        }
        if let newEntry {
            Update.enqueueAction {
                newEntry.updateFocus(true)
            }
        }
    }

    private func findFocusedEntry() -> FocusStore.Entry<Value>? {
        guard let plist = store.plists[id] else { return nil }
        var result: FocusStore.Entry<Value>?
        plist.forEachValue(forKey: FocusStore.Key<Value>.self) { entry, stop in
            guard let entry, entry.isValid,
                  let responder = entry.responder,
                  store.focusedResponders.contains(where: {
                      $0.base === responder
                  }) else {
                return
            }
            result = entry
            stop = true
        }
        return result
    }

    private func findEntry(with value: Value) -> FocusStore.Entry<Value>? {
        guard let plist = store.plists[id] else { return nil }
        var result: FocusStore.Entry<Value>?
        plist.forEachValue(forKey: FocusStore.Key<Value>.self) { entry, stop in
            guard let entry, entry.isValid, entry.value == value else {
                return
            }
            result = entry
            stop = true
        }
        return result
    }

    private func deferUpdate(_ value: Value) {
        deferredUpdate = (value, store.version)
    }
}
