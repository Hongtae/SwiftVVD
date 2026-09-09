//
//  File: EquatableOptionalObject.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

@propertyWrapper
struct EquatableOptionalObject<Value: AnyObject>: Equatable {
    var wrappedValue: Value?

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.wrappedValue === rhs.wrappedValue
    }
}
