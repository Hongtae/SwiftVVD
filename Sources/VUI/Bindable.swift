//
//  File: Bindable.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

import Foundation
import Observation

@dynamicMemberLookup @propertyWrapper public struct Bindable<Value> {
    public var wrappedValue: Value
    public var projectedValue: Bindable<Value> {
        self
    }
    
    @available(*, unavailable, message: "The wrapped value must be an object that conforms to Observable")
    public init(wrappedValue: Value) {
        fatalError() 
    }
    @available(*, unavailable, message: "The wrapped value must be an object that conforms to Observable")
    public init(projectedValue: Bindable<Value>) {
        fatalError()
    }
}

extension Bindable where Value: AnyObject {
    public subscript<Subject>(dynamicMember keyPath: ReferenceWritableKeyPath<Value, Subject>) -> Binding<Subject> {
        let value = self.wrappedValue
        let getter = { value[keyPath: keyPath] }
        let setter = { newValue in
            value[keyPath: keyPath] = newValue
        }
        return Binding<Subject>(get: getter, set: setter)
    }
}

extension Bindable where Value: AnyObject, Value: Observable {
    public init(wrappedValue: Value) {
        self.wrappedValue = wrappedValue
    }
    
    public init(_ wrappedValue: Value) {
        self.wrappedValue = wrappedValue
    }
    
    public init(projectedValue: Bindable<Value>) {
        self.wrappedValue = projectedValue.wrappedValue
    }
}

extension Bindable: Identifiable where Value: Identifiable {
    public var id: Value.ID {
        wrappedValue.id
    }
    
    public typealias ID = Value.ID
}

extension Bindable: Sendable where Value: Sendable {
}
