//
//  File: IndirectOptional.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

@propertyWrapper
enum IndirectOptional<Value>: ExpressibleByNilLiteral {
    indirect case some(Value)
    case none

    init(nilLiteral: ()) { self = .none }
    init(_ value: Value) { self = .some(value) }

    init(wrappedValue: Value?) {
        if let wrappedValue {
            self = .some(wrappedValue)
        } else {
            self = .none
        }
    }

    var wrappedValue: Value? {
        get {
            switch self {
            case let .some(value): value
            case .none: nil
            }
        }
        set {
            // Writes replace the box, including writeback from optional chaining.
            self = .none
            if let newValue {
                self = .some(newValue)
            }
        }
    }
}

extension IndirectOptional: Equatable where Value: Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.wrappedValue == rhs.wrappedValue
    }
}

extension IndirectOptional: Hashable where Value: Hashable {
    func hash(into hasher: inout Hasher) {
        switch self {
        case let .some(value):
            hasher.combine(UInt(1))
            value.hash(into: &hasher)
        case .none:
            hasher.combine(UInt(0))
        }
    }
}
