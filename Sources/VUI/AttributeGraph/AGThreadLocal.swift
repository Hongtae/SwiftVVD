//
//  File: AGThreadLocal.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import VVD

final class _AGThreadLocal<Value>: @unchecked Sendable {
    private final class Storage {
        let value: Value

        init(_ value: Value) {
            self.value = value
        }
    }

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
        return Unmanaged<Storage>.fromOpaque(pointer).takeUnretainedValue().value
    }

    @discardableResult
    func withValue<R>(_ valueDuringOperation: Value, operation: () throws -> R) rethrows -> R {
        let previous = ThreadLocalStorage.get(key)
        let storage = Storage(valueDuringOperation)
        ThreadLocalStorage.set(key, Unmanaged.passUnretained(storage).toOpaque())

        return try withExtendedLifetime(storage) {
            defer { ThreadLocalStorage.set(key, previous) }
            return try operation()
        }
    }
}
