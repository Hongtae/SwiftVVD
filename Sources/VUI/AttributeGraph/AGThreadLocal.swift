//
//  File: AGThreadLocal.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import VVD

final class _AGThreadLocal<Value>: @unchecked Sendable {
    private let defaultValue: Value

    private var key: UnsafeRawPointer {
        UnsafeRawPointer(Unmanaged.passUnretained(self).toOpaque())
    }

    init(_ defaultValue: Value) {
        self.defaultValue = defaultValue
    }

    var value: Value {
        guard let pointer = ThreadLocalStorage.get(key) else {
            return defaultValue
        }
        return pointer.assumingMemoryBound(to: Value.self).pointee
    }

    @discardableResult
    func withValue<R>(_ valueDuringOperation: Value, operation: () throws -> R) rethrows -> R {
        let previous = ThreadLocalStorage.get(key)
        return try withUnsafePointer(to: valueDuringOperation) { pointer in
            ThreadLocalStorage.set(
                key,
                UnsafeMutableRawPointer(mutating: pointer)
            )
            defer { ThreadLocalStorage.set(key, previous) }
            return try operation()
        }
    }
}
