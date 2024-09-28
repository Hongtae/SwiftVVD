//
//  File: WeakObject.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2024 Hongtae Kim. All rights reserved.
//

import Foundation

public struct WeakObject<T: AnyObject>: Equatable {
    public weak var value: T?
    static public func == (a: Self, b: Self) -> Bool { a.value === b.value }

    public init(_ value: T? = nil) {
        self.value = value
    }
}

extension WeakObject: ExpressibleByNilLiteral {
    @inlinable public init(nilLiteral: ()) {
        self.init(nil)
    }
}

extension WeakObject: Sendable where T: Sendable {}
