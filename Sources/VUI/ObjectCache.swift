//
//  File: ObjectCache.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Synchronization

private final class AtomicBuffer<Value: Sendable>: Sendable {
    let storage: Mutex<Value>

    init(_ value: Value) {
        self.storage = Mutex(value)
    }
}

struct AtomicBox<Value: Sendable>: Sendable {
    private let buffer: AtomicBuffer<Value>

    init(wrappedValue value: Value) {
        self.buffer = AtomicBuffer(value)
    }

    func access<Result>(_ body: (inout Value) throws -> Result) rethrows -> Result {
        try buffer.storage.withLock { value in
            UnsafeSendableBox(try body(&value))
        }.value
    }
}

/// A bounded cache with four candidates per hash bucket.
final class ObjectCache<Key: Hashable, Value> {
    struct Item {
        var data: (key: Key, hash: Int, value: Value)?
        var used: UInt32 = 0
    }

    // This mutable state is accessed only while the cache mutex is held.
    struct Data: @unchecked Sendable {
        var table = Array(repeating: Item(), count: 32)
        var clock: UInt32 = 0
    }

    let constructor: @Sendable (Key) -> Value
    var _data: AtomicBox<Data>

    init(constructor: @escaping @Sendable (Key) -> Value) {
        self.constructor = constructor
        self._data = AtomicBox(wrappedValue: Data())
    }

    subscript(key: Key) -> Value {
        let hash = key.hashValue
        let start = (hash & 7) * 4
        var replacement = start
        let cached: Value? = _data.access { data in
            var greatestAge = Int32.min
            for index in start..<(start + 4) {
                if let entry = data.table[index].data {
                    if entry.hash == hash && entry.key == key {
                        data.clock &+= 1
                        data.table[index].used = data.clock
                        return entry.value
                    }
                    let age = Int32(bitPattern: data.clock &- data.table[index].used)
                    if age > greatestAge {
                        greatestAge = age
                        replacement = index
                    }
                } else if greatestAge != Int32.max {
                    greatestAge = Int32.max
                    replacement = index
                }
            }
            return nil
        }
        if let cached { return cached }

        // Construction can re-enter the cache. The selected slot belongs to this
        // lookup; concurrent misses may construct independently and replace it.
        let value = constructor(key)
        _data.access { data in
            data.clock &+= 1
            data.table[replacement] = Item(
                data: (key, hash, value),
                used: data.clock
            )
        }
        return value
    }
}

extension ObjectCache: @unchecked Sendable where Key: Sendable, Value: Sendable {}
