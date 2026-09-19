//
//  File: CollisionAlgorithm.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

/// An intersection and optional contact generator for one ordered primitive
/// type pair.
///
/// `frame` maps points from `PrimitiveB`'s local space into `PrimitiveA`'s
/// local space. A returned manifold must also use `PrimitiveA`'s local space.
public protocol CollisionAlgorithm {
    associatedtype PrimitiveA: CollisionPrimitive
    associatedtype PrimitiveB: CollisionPrimitive

    func intersects(_ a: PrimitiveA,
                    _ b: PrimitiveB,
                    frame: Transform) -> Bool

    func contactManifold(_ a: PrimitiveA,
                         _ b: PrimitiveB,
                         frame: Transform) -> ContactManifold?
}

public extension CollisionAlgorithm {
    func contactManifold(_ a: PrimitiveA,
                         _ b: PrimitiveB,
                         frame: Transform) -> ContactManifold? {
        nil
    }
}

public enum CollisionAlgorithms {
    public static func intersects(_ a: any CollisionShape,
                                  _ b: any CollisionShape,
                                  frame: Transform = .identity) -> Bool {
        intersects(a.primitive, b.primitive, frame: frame)
    }

    public static func intersects(_ a: any CollisionPrimitive,
                                  _ b: any CollisionPrimitive,
                                  frame: Transform = .identity) -> Bool {
        CollisionAlgorithmRegistry.builtinIntersects(a, b, frame: frame)
    }

    public static func contactManifold(_ a: any CollisionShape,
                                       _ b: any CollisionShape,
                                       frame: Transform = .identity) -> ContactManifold? {
        contactManifold(a.primitive, b.primitive, frame: frame)
    }

    public static func contactManifold(_ a: any CollisionPrimitive,
                                       _ b: any CollisionPrimitive,
                                       frame: Transform = .identity) -> ContactManifold? {
        CollisionAlgorithmRegistry.builtinContactManifold(a, b, frame: frame)
    }
}

/// An ordered pair of concrete collision primitive types.
public struct CollisionPrimitiveTypePair: Hashable {
    public let a: any CollisionPrimitive.Type
    public let b: any CollisionPrimitive.Type

    public init(_ a: any CollisionPrimitive.Type,
                _ b: any CollisionPrimitive.Type) {
        self.a = a
        self.b = b
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        ObjectIdentifier(lhs.a) == ObjectIdentifier(rhs.a) &&
        ObjectIdentifier(lhs.b) == ObjectIdentifier(rhs.b)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(a))
        hasher.combine(ObjectIdentifier(b))
    }
}

/// Runtime dispatch for collision algorithms.
///
/// Registrations are ordered. Use `registerSymmetric` when an algorithm should
/// also handle the reversed primitive order. Custom entries take precedence
/// over the built-in registry when fallback is enabled.
public struct CollisionAlgorithmRegistry {
    private struct Entry {
        let intersects: (any CollisionPrimitive, any CollisionPrimitive, Transform) -> Bool
        let contactManifold: ((any CollisionPrimitive,
                              any CollisionPrimitive,
                              Transform) -> ContactManifold?)?
    }

    nonisolated(unsafe) private static let builtinAlgorithms: Self = {
        var registry = Self(usesBuiltinFallback: false)
        registry.registerBuiltinAlgorithms()
        return registry
    }()

    fileprivate static func builtinIntersects(
        _ a: any CollisionPrimitive,
        _ b: any CollisionPrimitive,
        frame: Transform
    ) -> Bool {
        builtinAlgorithms.intersects(a, b, frame: frame)
    }

    fileprivate static func builtinContactManifold(
        _ a: any CollisionPrimitive,
        _ b: any CollisionPrimitive,
        frame: Transform
    ) -> ContactManifold? {
        builtinAlgorithms.contactManifold(a, b, frame: frame)
    }

    private var entries: [CollisionPrimitiveTypePair: Entry]

    /// Whether a missing registry entry should use the built-in registry.
    public var usesBuiltinFallback: Bool

    public init(usesBuiltinFallback: Bool = true) {
        self.entries = [:]
        self.usesBuiltinFallback = usesBuiltinFallback
    }

    public func isRegistered(_ a: any CollisionPrimitive.Type,
                             _ b: any CollisionPrimitive.Type) -> Bool {
        entries[CollisionPrimitiveTypePair(a, b)] != nil
    }

    /// Registers closures for one ordered primitive pair.
    ///
    /// `frame` maps B-local points into A-local space. A returned manifold must
    /// also be expressed in A-local space. A new registration replaces the
    /// previous entry for the same ordered pair.
    public mutating func register<A: CollisionPrimitive, B: CollisionPrimitive>(
        _ a: A.Type,
        _ b: B.Type,
        intersects: @escaping (A, B, Transform) -> Bool,
        contactManifold: ((A, B, Transform) -> ContactManifold?)? = nil
    ) {
        let key = CollisionPrimitiveTypePair(a, b)
        entries[key] = Entry(
            intersects: { primitiveA, primitiveB, frame in
                guard let primitiveA = primitiveA as? A,
                      let primitiveB = primitiveB as? B else {
                    return false
                }
                return intersects(primitiveA, primitiveB, frame)
            },
            contactManifold: contactManifold.map { contactManifold in
                { primitiveA, primitiveB, frame in
                    guard let primitiveA = primitiveA as? A,
                          let primitiveB = primitiveB as? B else {
                        return nil
                    }
                    return contactManifold(primitiveA, primitiveB, frame)
                }
            })
    }

    /// Registers a typed collision algorithm for its ordered primitive pair.
    public mutating func register<Algorithm: CollisionAlgorithm>(
        _ algorithm: Algorithm
    ) {
        register(Algorithm.PrimitiveA.self,
                 Algorithm.PrimitiveB.self,
                 intersects: { a, b, frame in
                     algorithm.intersects(a, b, frame: frame)
                 },
                 contactManifold: { a, b, frame in
                     algorithm.contactManifold(a, b, frame: frame)
                 })
    }

    /// Registers closures for both primitive orders.
    ///
    /// The reversed entry adapts the relative frame and any returned manifold
    /// to preserve the first-primitive coordinate-space contract.
    public mutating func registerSymmetric<
        A: CollisionPrimitive,
        B: CollisionPrimitive
    >(
        _ a: A.Type,
        _ b: B.Type,
        intersects: @escaping (A, B, Transform) -> Bool,
        contactManifold: ((A, B, Transform) -> ContactManifold?)? = nil
    ) {
        register(a,
                 b,
                 intersects: intersects,
                 contactManifold: contactManifold)

        guard ObjectIdentifier(a) != ObjectIdentifier(b) else { return }
        register(b,
                 a,
                 intersects: { primitiveB, primitiveA, frame in
                     intersects(primitiveA, primitiveB, frame.inverted())
                 },
                 contactManifold: contactManifold.map { contactManifold in
                     { primitiveB, primitiveA, frame in
                         contactManifold(primitiveA,
                                         primitiveB,
                                         frame.inverted()).map {
                             _reversed($0, frame: frame)
                         }
                     }
                 })
    }

    /// Registers a typed collision algorithm for both primitive orders.
    public mutating func registerSymmetric<Algorithm: CollisionAlgorithm>(
        _ algorithm: Algorithm
    ) {
        registerSymmetric(Algorithm.PrimitiveA.self,
                          Algorithm.PrimitiveB.self,
                          intersects: { a, b, frame in
                              algorithm.intersects(a, b, frame: frame)
                          },
                          contactManifold: { a, b, frame in
                              algorithm.contactManifold(a, b, frame: frame)
                          })
    }

    /// Removes one ordered primitive-pair registration.
    @discardableResult
    public mutating func unregister(_ a: any CollisionPrimitive.Type,
                                    _ b: any CollisionPrimitive.Type) -> Bool {
        entries.removeValue(forKey: CollisionPrimitiveTypePair(a, b)) != nil
    }

    public func intersects(_ a: any CollisionShape,
                           _ b: any CollisionShape,
                           frame: Transform = .identity) -> Bool {
        intersects(a.primitive, b.primitive, frame: frame)
    }

    /// Queries one ordered primitive pair.
    ///
    /// An exact registration takes precedence. Without one, compound operands
    /// are expanded and each leaf pair is queried through this same registry.
    /// Non-compound pairs use the built-in registry only when fallback is
    /// enabled.
    public func intersects(_ a: any CollisionPrimitive,
                           _ b: any CollisionPrimitive,
                           frame: Transform = .identity) -> Bool {
        let key = CollisionPrimitiveTypePair(type(of: a), type(of: b))
        if let entry = entries[key] {
            return entry.intersects(a, b, frame)
        }

        if a is CompoundPrimitive || b is CompoundPrimitive {
            return _compoundLeafIntersects(a, b, frame: frame) {
                primitiveA, primitiveB, leafFrame in
                intersects(primitiveA, primitiveB, frame: leafFrame)
            }
        }

        return usesBuiltinFallback &&
            Self.builtinIntersects(a, b, frame: frame)
    }

    public func contactManifold(_ a: any CollisionShape,
                                _ b: any CollisionShape,
                                frame: Transform = .identity) -> ContactManifold? {
        contactManifold(a.primitive, b.primitive, frame: frame)
    }

    public func contactManifold(_ a: any CollisionPrimitive,
                                _ b: any CollisionPrimitive,
                                frame: Transform = .identity) -> ContactManifold? {
        let key = CollisionPrimitiveTypePair(type(of: a), type(of: b))
        if let entry = entries[key] {
            return entry.contactManifold?(a, b, frame)
        }
        guard usesBuiltinFallback else { return nil }
        return Self.builtinContactManifold(a, b, frame: frame)
    }
}

private extension CollisionAlgorithmRegistry {
    mutating func registerBuiltinAlgorithms() {
        registerSymmetric(
            Box.self,
            Box.self,
            intersects: { a, b, frame in
                CollisionAlgorithms.intersects(a, b, frame: frame)
            },
            contactManifold: { a, b, frame in
                CollisionAlgorithms.contactManifold(a, b, frame: frame)
            })
        registerSymmetric(
            Box.self,
            Sphere.self,
            intersects: { a, b, frame in
                CollisionAlgorithms.intersects(a, b, frame: frame)
            },
            contactManifold: { a, b, frame in
                CollisionAlgorithms.contactManifold(a, b, frame: frame)
            })
        registerSymmetric(
            Box.self,
            Capsule.self,
            intersects: { a, b, frame in
                CollisionAlgorithms.intersects(a, b, frame: frame)
            })
        registerSymmetric(
            Box.self,
            Cylinder.self,
            intersects: { a, b, frame in
                CollisionAlgorithms.intersects(a, b, frame: frame)
            })
        registerSymmetric(
            Box.self,
            Cone.self,
            intersects: { a, b, frame in
                CollisionAlgorithms.intersects(a, b, frame: frame)
            })
        registerSymmetric(
            Box.self,
            ConvexHull.self,
            intersects: { a, b, frame in
                CollisionAlgorithms.intersects(a, b, frame: frame)
            })
        registerSymmetric(
            Box.self,
            StaticPlane.self,
            intersects: { a, b, frame in
                CollisionAlgorithms.intersects(a, b, frame: frame)
            },
            contactManifold: { a, b, frame in
                CollisionAlgorithms.contactManifold(a, b, frame: frame)
            })
        registerSymmetric(
            Box.self,
            TriangleMesh.self,
            intersects: { a, b, frame in
                CollisionAlgorithms.intersects(a, b, frame: frame)
            })

        registerSymmetric(
            Sphere.self,
            Sphere.self,
            intersects: { a, b, frame in
                CollisionAlgorithms.intersects(a, b, frame: frame)
            },
            contactManifold: { a, b, frame in
                CollisionAlgorithms.contactManifold(a, b, frame: frame)
            })
        registerSymmetric(
            Sphere.self,
            Capsule.self,
            intersects: { a, b, frame in
                CollisionAlgorithms.intersects(a, b, frame: frame)
            },
            contactManifold: { a, b, frame in
                CollisionAlgorithms.contactManifold(a, b, frame: frame)
            })
        registerSymmetric(
            Sphere.self,
            Cylinder.self,
            intersects: { a, b, frame in
                CollisionAlgorithms.intersects(a, b, frame: frame)
            })
        registerSymmetric(
            Sphere.self,
            Cone.self,
            intersects: { a, b, frame in
                CollisionAlgorithms.intersects(a, b, frame: frame)
            })
        registerSymmetric(
            Sphere.self,
            ConvexHull.self,
            intersects: { a, b, frame in
                CollisionAlgorithms.intersects(a, b, frame: frame)
            })
        registerSymmetric(
            Sphere.self,
            StaticPlane.self,
            intersects: { a, b, frame in
                CollisionAlgorithms.intersects(a, b, frame: frame)
            },
            contactManifold: { a, b, frame in
                CollisionAlgorithms.contactManifold(a, b, frame: frame)
            })
        registerSymmetric(
            Sphere.self,
            TriangleMesh.self,
            intersects: { a, b, frame in
                CollisionAlgorithms.intersects(a, b, frame: frame)
            })

        registerSymmetric(
            Capsule.self,
            Capsule.self,
            intersects: { a, b, frame in
                CollisionAlgorithms.intersects(a, b, frame: frame)
            },
            contactManifold: { a, b, frame in
                CollisionAlgorithms.contactManifold(a, b, frame: frame)
            })
        registerSymmetric(
            Capsule.self,
            Cylinder.self,
            intersects: { a, b, frame in
                CollisionAlgorithms.intersects(a, b, frame: frame)
            })
        registerSymmetric(
            Capsule.self,
            Cone.self,
            intersects: { a, b, frame in
                CollisionAlgorithms.intersects(a, b, frame: frame)
            })
        registerSymmetric(
            Capsule.self,
            ConvexHull.self,
            intersects: { a, b, frame in
                CollisionAlgorithms.intersects(a, b, frame: frame)
            })
        registerSymmetric(
            Capsule.self,
            StaticPlane.self,
            intersects: { a, b, frame in
                CollisionAlgorithms.intersects(a, b, frame: frame)
            })
        registerSymmetric(
            Capsule.self,
            TriangleMesh.self,
            intersects: { a, b, frame in
                CollisionAlgorithms.intersects(a, b, frame: frame)
            })

        registerSymmetric(
            Cylinder.self,
            Cylinder.self,
            intersects: { a, b, frame in
                CollisionAlgorithms.intersects(a, b, frame: frame)
            })
        registerSymmetric(
            Cylinder.self,
            Cone.self,
            intersects: { a, b, frame in
                CollisionAlgorithms.intersects(a, b, frame: frame)
            })
        registerSymmetric(
            Cylinder.self,
            ConvexHull.self,
            intersects: { a, b, frame in
                CollisionAlgorithms.intersects(a, b, frame: frame)
            })
        registerSymmetric(
            Cylinder.self,
            StaticPlane.self,
            intersects: { a, b, frame in
                CollisionAlgorithms.intersects(a, b, frame: frame)
            })
        registerSymmetric(
            Cylinder.self,
            TriangleMesh.self,
            intersects: { a, b, frame in
                CollisionAlgorithms.intersects(a, b, frame: frame)
            })

        registerSymmetric(
            Cone.self,
            Cone.self,
            intersects: { a, b, frame in
                CollisionAlgorithms.intersects(a, b, frame: frame)
            })
        registerSymmetric(
            Cone.self,
            ConvexHull.self,
            intersects: { a, b, frame in
                CollisionAlgorithms.intersects(a, b, frame: frame)
            })
        registerSymmetric(
            Cone.self,
            StaticPlane.self,
            intersects: { a, b, frame in
                CollisionAlgorithms.intersects(a, b, frame: frame)
            })
        registerSymmetric(
            Cone.self,
            TriangleMesh.self,
            intersects: { a, b, frame in
                CollisionAlgorithms.intersects(a, b, frame: frame)
            })

        registerSymmetric(
            ConvexHull.self,
            ConvexHull.self,
            intersects: { a, b, frame in
                CollisionAlgorithms.intersects(a, b, frame: frame)
            })
        registerSymmetric(
            ConvexHull.self,
            StaticPlane.self,
            intersects: { a, b, frame in
                CollisionAlgorithms.intersects(a, b, frame: frame)
            })
        registerSymmetric(
            ConvexHull.self,
            TriangleMesh.self,
            intersects: { a, b, frame in
                CollisionAlgorithms.intersects(a, b, frame: frame)
            })

        registerSymmetric(
            StaticPlane.self,
            StaticPlane.self,
            intersects: { a, b, frame in
                CollisionAlgorithms.intersects(a, b, frame: frame)
            })
        registerSymmetric(
            StaticPlane.self,
            TriangleMesh.self,
            intersects: { a, b, frame in
                CollisionAlgorithms.intersects(a, b, frame: frame)
            })

        registerSymmetric(
            TriangleMesh.self,
            TriangleMesh.self,
            intersects: { a, b, frame in
                CollisionAlgorithms.intersects(a, b, frame: frame)
            })
    }
}

/// Re-expresses an A-first manifold in B's local space and reverses its normal.
private func _reversed(_ manifold: ContactManifold,
                       frame: Transform) -> ContactManifold {
    ContactManifold(contacts: manifold.contacts.map { contact in
        Contact(pointOnA: contact.pointOnB.applying(frame),
                pointOnB: contact.pointOnA.applying(frame),
                normal: -contact.normal.applying(frame.orientation),
                penetrationDepth: contact.penetrationDepth,
                featureID: contact.featureID)
    })
}
