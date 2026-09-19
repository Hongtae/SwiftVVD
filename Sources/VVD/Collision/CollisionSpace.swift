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

private struct BroadPhaseSnapshot {
    let bounds: [AABB]
    let activeIndices: [Int]
    let hierarchy: BVH
    let unboundedIndices: [Int]

    init(_ colliders: [Collider]) {
        var bounds = Array(repeating: AABB.null, count: colliders.count)
        var activeIndices: [Int] = []
        var elements: [BVH.Element] = []
        var unboundedIndices: [Int] = []

        activeIndices.reserveCapacity(colliders.count)
        elements.reserveCapacity(colliders.count)
        unboundedIndices.reserveCapacity(colliders.count)

        for (index, collider) in colliders.enumerated()
        where collider.isEnabled && collider.isValid {
            let colliderBounds = collider.bounds
            bounds[index] = colliderBounds
            activeIndices.append(index)
            if colliderBounds.isNull {
                unboundedIndices.append(index)
            } else {
                elements.append(BVH.Element(bounds: colliderBounds,
                                            primitiveIndex: index))
            }
        }

        self.bounds = bounds
        self.activeIndices = activeIndices
        self.hierarchy = BVH(elements)
        self.unboundedIndices = unboundedIndices
    }

    func candidateIndices(overlapping queryBounds: AABB) -> [Int] {
        if queryBounds.isNull {
            return activeIndices
        }

        var candidates = hierarchy.primitiveIndices(overlapping: queryBounds)
        candidates.append(contentsOf: unboundedIndices)
        candidates.sort()
        return candidates
    }

    func candidateIndices(intersecting ray: Ray) -> [Int] {
        guard ray.isValid else { return [] }

        var candidates = hierarchy.primitiveIndices(intersecting: ray)
        candidates.append(contentsOf: unboundedIndices)
        candidates.sort()
        return candidates
    }
}

/// Stores colliders and performs broad-phase candidate queries.
///
/// Each query builds an immutable BVH snapshot from current finite collider
/// bounds. Colliders with null bounds remain unconditional candidates. This
/// keeps mutable collider state synchronized without a separate dirty-tracking
/// contract.
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

    /// Returns the closest enabled, valid, and filter-compatible ray hit.
    public func raycast(_ ray: Ray,
                        maximumDistance: Scalar = .infinity,
                        filter: CollisionFilter = CollisionFilter()) -> RayHit? {
        guard ray.isValid && maximumDistance >= .zero else { return nil }

        let snapshot = BroadPhaseSnapshot(storage)
        var closest: (storageIndex: Int, hit: RayHit)?
        for index in snapshot.candidateIndices(intersecting: ray) {
            let collider = storage[index]
            guard filter.allowsCollision(with: collider.filter),
                  let hit = collider.raycast(ray),
                  hit.distance <= maximumDistance
            else { continue }

            if let current = closest,
               current.hit.distance < hit.distance ||
                (current.hit.distance == hit.distance &&
                 current.storageIndex < index) {
                continue
            }
            closest = (index, hit)
        }
        return closest?.hit
    }

    /// Returns enabled, valid, and filter-compatible ray hits ordered by
    /// distance. Hits at the same distance preserve collider storage order.
    public func raycastAll(_ ray: Ray,
                           maximumDistance: Scalar = .infinity,
                           filter: CollisionFilter = CollisionFilter()) -> [RayHit] {
        guard ray.isValid && maximumDistance >= .zero else { return [] }

        let snapshot = BroadPhaseSnapshot(storage)
        var indexedHits: [(storageIndex: Int, hit: RayHit)] = []
        for index in snapshot.candidateIndices(intersecting: ray) {
            let collider = storage[index]
            guard filter.allowsCollision(with: collider.filter),
                  let hit = collider.raycast(ray),
                  hit.distance <= maximumDistance
            else { continue }
            indexedHits.append((index, hit))
        }
        indexedHits.sort { lhs, rhs in
            if lhs.hit.distance == rhs.hit.distance {
                return lhs.storageIndex < rhs.storageIndex
            }
            return lhs.hit.distance < rhs.hit.distance
        }
        return indexedHits.map(\.hit)
    }

    /// Returns the first collider reached while translating `primitive` from
    /// `transform`. Rotation remains fixed throughout the query.
    public func sweep(_ primitive: any CollisionPrimitive,
                      from transform: Transform = .identity,
                      translation: Vector3,
                      filter: CollisionFilter = CollisionFilter()) -> SweepHit? {
        sweepAll(primitive,
                 from: transform,
                 translation: translation,
                 filter: filter).first
    }

    /// Returns all supported translational impacts ordered by time-of-impact
    /// fraction. Equal fractions preserve collider storage order.
    public func sweepAll(_ primitive: any CollisionPrimitive,
                         from transform: Transform = .identity,
                         translation: Vector3,
                         filter: CollisionFilter = CollisionFilter()) -> [SweepHit] {
        sweepAll(primitive,
                 from: transform,
                 translation: translation,
                 filter: filter,
                 excluding: nil)
    }

    public func sweep(_ shape: any CollisionShape,
                      from transform: Transform = .identity,
                      translation: Vector3,
                      filter: CollisionFilter = CollisionFilter()) -> SweepHit? {
        sweep(shape.primitive,
              from: transform,
              translation: translation,
              filter: filter)
    }

    public func sweepAll(_ shape: any CollisionShape,
                         from transform: Transform = .identity,
                         translation: Vector3,
                         filter: CollisionFilter = CollisionFilter()) -> [SweepHit] {
        sweepAll(shape.primitive,
                 from: transform,
                 translation: translation,
                 filter: filter)
    }

    /// Sweeps a registered or external collider without mutating its transform.
    /// The collider's own filter is used, and the collider is excluded from the
    /// target set when it is registered in this space.
    public func sweep(_ collider: Collider,
                      translation: Vector3) -> SweepHit? {
        sweepAll(collider, translation: translation).first
    }

    public func sweepAll(_ collider: Collider,
                         translation: Vector3) -> [SweepHit] {
        guard collider.isEnabled && collider.isValid else { return [] }
        return sweepAll(collider.primitive,
                        from: collider.transform,
                        translation: translation,
                        filter: collider.filter,
                        excluding: collider)
    }

    /// Returns colliders intersecting `collider`, excluding the collider itself.
    public func overlaps(with collider: Collider) -> [Collider] {
        guard collider.isEnabled && collider.isValid else { return [] }

        let snapshot = BroadPhaseSnapshot(storage)
        return snapshot.candidateIndices(overlapping: collider.bounds).compactMap {
            let candidate = storage[$0]
            return collider.intersects(candidate, using: algorithms)
                ? candidate
                : nil
        }
    }

    /// Evaluates every unique enabled and filter-compatible collider pair.
    public func collisionPairs() -> [CollisionPair] {
        guard storage.count > 1 else { return [] }

        let snapshot = BroadPhaseSnapshot(storage)
        var pairs: [CollisionPair] = []
        for indexA in 0..<(storage.count - 1) {
            guard storage[indexA].isEnabled && storage[indexA].isValid else {
                continue
            }

            let colliderA = storage[indexA]
            let candidateIndices = snapshot.candidateIndices(
                overlapping: snapshot.bounds[indexA])
            for indexB in candidateIndices where indexB > indexA {
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

    private func sweepAll(_ primitive: any CollisionPrimitive,
                          from transform: Transform,
                          translation: Vector3,
                          filter: CollisionFilter,
                          excluding excludedCollider: Collider?) -> [SweepHit] {
        let translationLength = translation.length
        guard primitive.isValid,
              translation.x.isFinite,
              translation.y.isFinite,
              translation.z.isFinite,
              translationLength.isFinite
        else { return [] }

        let primitiveBounds = primitive.bounds
        let queryBounds: AABB
        if primitiveBounds.isNull {
            queryBounds = .null
        } else {
            let startBounds = primitiveBounds.applying(transform)
            var endTransform = transform
            endTransform.position += translation
            let endBounds = primitiveBounds.applying(endTransform)
            queryBounds = startBounds.combining(endBounds)
        }

        let snapshot = BroadPhaseSnapshot(storage)
        let inverseTransform = transform.inverted()
        let localTranslation = translation
            .applying(inverseTransform.orientation)
        var indexedHits: [(storageIndex: Int, hit: SweepHit)] = []

        for index in snapshot.candidateIndices(overlapping: queryBounds) {
            let collider = storage[index]
            guard collider !== excludedCollider,
                  filter.allowsCollision(with: collider.filter),
                  let impact = algorithms.timeOfImpact(
                    primitive,
                    collider.primitive,
                    frame: collider.transform * inverseTransform,
                    translation: localTranslation),
                  impact.isValid
            else { continue }

            let hit = SweepHit(
                collider: collider,
                fraction: impact.fraction,
                pointOnMoving: impact.pointOnA.applying(transform),
                pointOnCollider: impact.pointOnB.applying(transform),
                normal: impact.normal
                    .applying(transform.orientation)
                    .normalized(),
                distance: translationLength * impact.fraction)
            indexedHits.append((index, hit))
        }

        indexedHits.sort { lhs, rhs in
            if lhs.hit.fraction == rhs.hit.fraction {
                return lhs.storageIndex < rhs.storageIndex
            }
            return lhs.hit.fraction < rhs.hit.fraction
        }
        return indexedHits.map(\.hit)
    }
}
