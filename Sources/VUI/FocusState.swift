//
//  File: FocusState.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

@preconcurrency import Foundation

@propertyWrapper
public struct FocusState<Value>: DynamicProperty where Value: Hashable {
    @propertyWrapper
    public struct Binding {
        var _binding: VUI.Binding<Value>

        public var wrappedValue: Value {
            get { _binding.wrappedValue }
            nonmutating set { _binding.wrappedValue = newValue }
        }

        public var projectedValue: FocusState<Value>.Binding {
            self
        }

        var propertyID: ObjectIdentifier {
            if let location = _binding.location as? FocusStoreLocation<Value> {
                return location.id
            }
            return ObjectIdentifier(_binding.location)
        }
    }

    var value: Value
    var location: AnyLocation<Value>?
    var resetValue: Value

    public var wrappedValue: Value {
        get { getValue(forReading: true) }
        nonmutating set {
            location?.setValue(newValue, transaction: Transaction())
        }
    }

    public var projectedValue: FocusState<Value>.Binding {
        let value = getValue(forReading: false)
        let binding: VUI.Binding<Value>
        if let location {
            binding = VUI.Binding(location: location)
        } else {
            binding = VUI.Binding.constant(value)
        }
        return Binding(_binding: binding)
    }

    public static func _makeProperty<V>(
        in buffer: inout _DynamicPropertyBuffer,
        container: _GraphValue<V>,
        fieldOffset: Int,
        inputs: inout _GraphInputs
    ) {
        buffer.append(
            Box(
                _store: inputs[FocusStoreInputKey.self],
                _focusedItem: inputs[FocusedItemInputKey.self]
            ),
            fieldOffset: fieldOffset
        )
    }

    public init() where Value == Bool {
        value = false
        location = nil
        resetValue = false
    }

    public init<T>() where Value == T?, T: Hashable {
        value = nil
        location = nil
        resetValue = nil
    }

    private func getValue(forReading: Bool) -> Value {
        guard let location else { return value }
        if forReading, GraphHost.isUpdating {
            return location.getValue()
        }
        if let location = location as? FocusStoreLocation<Value> {
            return location.getValue(forReading: forReading)
        }
        return location.getValue()
    }
}

extension FocusState {
    struct Box: DynamicPropertyBox {
        var _store: OptionalAttribute<FocusStore>
        var _focusedItem: OptionalAttribute<FocusItem?>
        var location: FocusStoreLocation<Value>?

        mutating func reset() {
            location = nil
        }

        mutating func update(
            property: inout FocusState<Value>,
            phase: _GraphInputs.Phase
        ) -> Bool {
            let isInitial = location == nil
            if location == nil {
                location = property.location as? FocusStoreLocation<Value>
                    ?? FocusStoreLocation(
                        host: GraphHost.currentHost,
                        resetValue: property.resetValue
                    )
            }
            guard let location else { return false }

            location.store = _store.attribute?.value ?? FocusStore()
            var version = location.store.version
            if let item = _focusedItem.attribute?.value {
                version.combine(with: item.version)
            }
            location.focusVersion = version

            let result = location.update()
            property.value = result.0
            property.location = location

            if isInitial || location.deferredUpdate != nil {
                scheduleDeferredUpdate(for: location)
            }
            return result.1 && location.wasReadValue()
        }

        func getState<T>(type: T.Type) -> VUI.Binding<T>? {
            nil
        }

        private func scheduleDeferredUpdate(
            for location: FocusStoreLocation<Value>
        ) {
            let action = UnsafeBox { [weak location] in
                location?.performDeferredUpdate()
            }
            RunLoop.main.perform {
                action.value()
            }
        }
    }
}

@available(*, unavailable)
extension FocusState: Sendable {}

@available(*, unavailable)
extension FocusState.Binding: Sendable {}
