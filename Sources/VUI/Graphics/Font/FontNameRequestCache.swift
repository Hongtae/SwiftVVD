//
//  File: FontNameRequestCache.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

/// Thread-owned name requests for immutable catalog snapshots.
final class FontNameRequestCache {
    final class Scope: Sendable {}

    private struct Entry {
        let name: String
        let candidate: FontResourceResolver.Candidate
        let coordinates: [String]
    }

    private final class Storage {
        var caches: [ObjectIdentifier: FontNameRequestCache] = [:]
    }

    private static let storageKey = "FontNameRequestCache." + UUID().uuidString
    private weak var scope: Scope?
    private var entries: [Entry] = []

    private init(scope: Scope) { self.scope = scope }

    static func current(in scope: Scope) -> FontNameRequestCache {
        let dictionary = Thread.current.threadDictionary
        let storage: Storage
        if let retained = dictionary[storageKey] as? Storage {
            storage = retained
        } else {
            storage = Storage()
            dictionary[storageKey] = storage
        }
        // Drop expired catalogs' resource snapshots on the next request.
        storage.caches = storage.caches.filter { $0.value.scope != nil }
        let key = ObjectIdentifier(scope)
        if let cache = storage.caches[key] { return cache }
        let cache = FontNameRequestCache(scope: scope)
        storage.caches[key] = cache
        return cache
    }

    func candidate(for name: String) -> FontResourceResolver.Candidate? {
        guard let index = entries.firstIndex(where: { $0.name == name }) else { return nil }
        let entry = entries.remove(at: index)
        entries.insert(entry, at: 0)
        let selection = entry.candidate.variationSelection
        let coordinates = entry.coordinates.map { CGFloat(Double($0)!) }
        let reconstructed = FontVariationSelection(metadata: selection.metadata, coordinates: coordinates)
        return entry.candidate.selecting(reconstructed, comparison: reconstructed.comparisonCoordinates(requested: [:]))
    }

    func insert(_ candidate: FontResourceResolver.Candidate, for name: String) {
        // Cached file references encode each axis as a float formatted with six
        // significant digits. Reopening that reference constructs Double axes.
        let coordinates = candidate.coordinates.map {
            String(format: "%g", locale: Locale(identifier: "en_US_POSIX"), Double(Float($0)))
        }
        if entries.count == 16 { entries.removeLast() }
        entries.insert(Entry(name: name, candidate: candidate, coordinates: coordinates), at: 0)
    }
}
