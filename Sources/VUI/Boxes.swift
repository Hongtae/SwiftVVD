//
//  File: Boxes.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import VVD

/// A reference box for sharing mutable storage across value-semantic owners.
final class MutableBox<Value>: @unchecked Sendable {
    var value: Value

    init(_ value: Value) {
        self.value = value
    }
}

/// A non-owning reference that does not extend an object's lifetime.
struct WeakBox<Base: AnyObject> {
    weak var base: Base?

    init(_ base: Base?) {
        self.base = base
    }
}

typealias UnsafeSendableBox<T> = VVD.UnsafeSendableBox<T>
typealias WeakObject<T: AnyObject> = VVD.WeakObject<T>
typealias AnyWeakObject = VVD.AnyWeakObject
