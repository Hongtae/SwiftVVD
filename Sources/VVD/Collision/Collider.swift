//
//  File: Collider.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

/// A collision primitive placed in a collision space.
///
/// `transform` maps the primitive's local coordinates into the collision
/// space. Collider identity is reference based so a collider can safely be
/// registered and removed even when its mutable properties change.
public final class Collider: Hashable {
    public var primitive: any CollisionPrimitive
    public var transform: Transform
    public var filter: CollisionFilter
    public var isEnabled: Bool

    public var isValid: Bool {
        primitive.isValid
    }

    public var bounds: AABB {
        primitive.bounds.applying(transform)
    }

    public init(primitive: any CollisionPrimitive,
                transform: Transform = .identity,
                filter: CollisionFilter = CollisionFilter(),
                isEnabled: Bool = true) {
        self.primitive = primitive
        self.transform = transform
        self.filter = filter
        self.isEnabled = isEnabled
    }

    /// Creates a collider from a typed shape by storing its primitive
    /// representation.
    public convenience init<S: CollisionShape>(shape: S,
                                                transform: Transform = .identity,
                                                filter: CollisionFilter = CollisionFilter(),
                                                isEnabled: Bool = true) {
        self.init(primitive: shape.primitive,
                  transform: transform,
                  filter: filter,
                  isEnabled: isEnabled)
    }

    public func canCollide(with other: Collider) -> Bool {
        self !== other &&
        isEnabled && other.isEnabled &&
        isValid && other.isValid &&
        filter.allowsCollision(with: other.filter)
    }

    /// Tests this collider against another collider.
    public func intersects(_ other: Collider,
                           using algorithms: CollisionAlgorithmRegistry =
                            CollisionAlgorithmRegistry()) -> Bool {
        guard canCollide(with: other) else { return false }

        let boundsA = bounds
        let boundsB = other.bounds
        if !boundsA.isNull && !boundsB.isNull && !boundsA.intersects(boundsB) {
            return false
        }

        return algorithms.intersects(primitive,
                                     other.primitive,
                                     frame: other.transform * transform.inverted())
    }

    /// Generates contacts in this collider's local coordinate space.
    public func contactManifold(with other: Collider,
                                using algorithms: CollisionAlgorithmRegistry =
                                    CollisionAlgorithmRegistry()) -> ContactManifold? {
        guard canCollide(with: other) else { return nil }

        let boundsA = bounds
        let boundsB = other.bounds
        if !boundsA.isNull && !boundsB.isNull && !boundsA.intersects(boundsB) {
            return nil
        }

        return algorithms.contactManifold(primitive,
                                          other.primitive,
                                          frame: other.transform * transform.inverted())
    }

    public static func == (lhs: Collider, rhs: Collider) -> Bool {
        lhs === rhs
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }
}
