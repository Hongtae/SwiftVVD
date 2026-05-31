//
//  File: DynamicPropertyCache.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

// Caches DynamicProperty field offsets per type so _makeView/_makeViewList
// avoids repeated _forEachField scans for the same modifier type.
// The current cache is single-threaded.

struct DynamicPropertyCache {
    struct Fields {
        struct Entry {
            let offset: Int
            let type: any DynamicProperty.Type
        }
        let entries: [Entry]
        var isEmpty: Bool { entries.isEmpty }
    }

    nonisolated(unsafe) private static var cache: [ObjectIdentifier: Fields] = [:]

    static func fields(of type: Any.Type) -> Fields {
        let key = ObjectIdentifier(type)
        if let cached = cache[key] { return cached }
        var entries: [Fields.Entry] = []
        _forEachField(of: type) { _, offset, fieldType in
            if let dpType = fieldType as? any DynamicProperty.Type {
                entries.append(Fields.Entry(offset: offset, type: dpType))
            }
            return true
        }
        let result = Fields(entries: entries)
        cache[key] = result
        return result
    }
}
