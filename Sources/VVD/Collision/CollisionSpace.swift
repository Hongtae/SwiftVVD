//
//  File: CollisionSpace.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

/// A broad-phase collision candidate that has passed an exact intersection
/// test. Contact data remains optional because not every primitive pair has a
/// contact generator yet.
public struct CollisionPair {
    public let colliderA: Collider
    public let colliderB: Collider
    public let contactManifold: ContactManifold?

    public init(colliderA: Collider,
                colliderB: Collider,
                contactManifold: ContactManifold?) {
        self.colliderA = colliderA
        self.colliderB = colliderB
        self.contactManifold = contactManifold
    }

    /// Converts contact geometry from collider A's local space to the space's
    /// coordinate system.
    public var worldContactManifold: ContactManifold? {
        contactManifold.map { manifold in
            ContactManifold(contacts: manifold.contacts.map { contact in
                Contact(pointOnA: contact.pointOnA.applying(colliderA.transform),
                        pointOnB: contact.pointOnB.applying(colliderA.transform),
                        normal: contact.normal.applying(colliderA.transform.orientation).normalized(),
                        penetrationDepth: contact.penetrationDepth,
                        featureID: contact.featureID)
            })
        }
    }
}

/// Stores colliders and performs a simple pairwise broad phase.
///
/// The array-backed implementation establishes the public ownership and query
/// behavior. A BVH can replace candidate generation later without changing
/// collider or dynamics APIs.
public final class CollisionSpace {
    private var storage: [Collider]
    public var algorithms: CollisionAlgorithmRegistry

    public var colliders: [Collider] {
        storage
    }

    public init(colliders: [Collider] = [],
                algorithms: CollisionAlgorithmRegistry =
                    CollisionAlgorithmRegistry()) {
        self.storage = []
        self.algorithms = algorithms
        for collider in colliders where !storage.contains(collider) {
            storage.append(collider)
        }
    }

    @discardableResult
    public func add(_ collider: Collider) -> Bool {
        guard !storage.contains(collider) else { return false }
        storage.append(collider)
        return true
    }

    @discardableResult
    public func remove(_ collider: Collider) -> Bool {
        guard let index = storage.firstIndex(of: collider) else { return false }
        storage.remove(at: index)
        return true
    }

    public func removeAll(keepingCapacity: Bool = false) {
        storage.removeAll(keepingCapacity: keepingCapacity)
    }

    public func contains(_ collider: Collider) -> Bool {
        storage.contains(collider)
    }

    /// Returns colliders intersecting `collider`, excluding the collider itself.
    public func overlaps(with collider: Collider) -> [Collider] {
        storage.filter { collider.intersects($0, using: algorithms) }
    }

    /// Evaluates every unique enabled and filter-compatible collider pair.
    public func collisionPairs() -> [CollisionPair] {
        guard storage.count > 1 else { return [] }

        var pairs: [CollisionPair] = []
        for indexA in 0..<(storage.count - 1) {
            let colliderA = storage[indexA]
            for indexB in (indexA + 1)..<storage.count {
                let colliderB = storage[indexB]
                if colliderA.intersects(colliderB, using: algorithms) {
                    pairs.append(CollisionPair(colliderA: colliderA,
                                               colliderB: colliderB,
                                               contactManifold: colliderA.contactManifold(
                                                with: colliderB,
                                                using: algorithms)))
                }
            }
        }
        return pairs
    }
}
