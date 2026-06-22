//
//  File: CollisionAlgorithm.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

fileprivate enum CollisionPrimitiveDispatch: Hashable {
    case box(Box)
    case sphere(Sphere)
    case capsule(Capsule)
    case cylinder(Cylinder)
    case cone(Cone)
    case convexHull(ConvexHull)
    case staticPlane(StaticPlane)
    case triangleMesh(TriangleMesh)
    case compound(CompoundPrimitive)
}

fileprivate protocol _CollisionDispatchablePrimitive: CollisionPrimitive {
    var dispatchValue: CollisionPrimitiveDispatch { get }
}

extension Box: _CollisionDispatchablePrimitive {
    fileprivate var dispatchValue: CollisionPrimitiveDispatch { .box(self) }
}

extension Sphere: _CollisionDispatchablePrimitive {
    fileprivate var dispatchValue: CollisionPrimitiveDispatch { .sphere(self) }
}

extension Capsule: _CollisionDispatchablePrimitive {
    fileprivate var dispatchValue: CollisionPrimitiveDispatch { .capsule(self) }
}

extension Cylinder: _CollisionDispatchablePrimitive {
    fileprivate var dispatchValue: CollisionPrimitiveDispatch { .cylinder(self) }
}

extension Cone: _CollisionDispatchablePrimitive {
    fileprivate var dispatchValue: CollisionPrimitiveDispatch { .cone(self) }
}

extension ConvexHull: _CollisionDispatchablePrimitive {
    fileprivate var dispatchValue: CollisionPrimitiveDispatch { .convexHull(self) }
}

extension StaticPlane: _CollisionDispatchablePrimitive {
    fileprivate var dispatchValue: CollisionPrimitiveDispatch { .staticPlane(self) }
}

extension TriangleMesh: _CollisionDispatchablePrimitive {
    fileprivate var dispatchValue: CollisionPrimitiveDispatch { .triangleMesh(self) }
}

extension CompoundPrimitive: _CollisionDispatchablePrimitive {
    fileprivate var dispatchValue: CollisionPrimitiveDispatch { .compound(self) }
}

public protocol CollisionAlgorithm {
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
        if let a = a as? any _CollisionDispatchablePrimitive,
           let b = b as? any _CollisionDispatchablePrimitive {
            return _intersects(a.dispatchValue, b.dispatchValue, frame: frame)
        }
        fatalError("CollisionPrimitive is not registered for collision dispatch.")
    }

    public static func contactManifold(_ a: any CollisionShape,
                                       _ b: any CollisionShape,
                                       frame: Transform = .identity) -> ContactManifold? {
        contactManifold(a.primitive, b.primitive, frame: frame)
    }

    public static func contactManifold(_ a: any CollisionPrimitive,
                                       _ b: any CollisionPrimitive,
                                       frame: Transform = .identity) -> ContactManifold? {
        if let a = a as? any _CollisionDispatchablePrimitive,
           let b = b as? any _CollisionDispatchablePrimitive {
            return contactManifold(a.dispatchValue, b.dispatchValue, frame: frame)
        }
        fatalError("CollisionPrimitive is not registered for collision dispatch.")
    }

    fileprivate static func _intersects(_ a: CollisionPrimitiveDispatch,
                                        _ b: CollisionPrimitiveDispatch,
                                        frame: Transform = .identity) -> Bool {
        switch (a, b) {
        case (.box(let a), .box(let b)):
            return intersects(a, b, frame: frame)
        case (.box(let a), .sphere(let b)):
            return intersects(a, b, frame: frame)
        case (.box(let a), .capsule(let b)):
            return intersects(a, b, frame: frame)
        case (.box(let a), .cylinder(let b)):
            return intersects(a, b, frame: frame)
        case (.box(let a), .cone(let b)):
            return intersects(a, b, frame: frame)
        case (.box(let a), .convexHull(let b)):
            return intersects(a, b, frame: frame)
        case (.box(let a), .staticPlane(let b)):
            return intersects(a, b, frame: frame)
        case (.box(let a), .triangleMesh(let b)):
            return intersects(a, b, frame: frame)
        case (.box(let a), .compound(let b)):
            return intersects(a, b, frame: frame)
        case (.sphere(let a), .box(let b)):
            return intersects(a, b, frame: frame)
        case (.sphere(let a), .sphere(let b)):
            return intersects(a, b, frame: frame)
        case (.sphere(let a), .capsule(let b)):
            return intersects(a, b, frame: frame)
        case (.sphere(let a), .cylinder(let b)):
            return intersects(a, b, frame: frame)
        case (.sphere(let a), .cone(let b)):
            return intersects(a, b, frame: frame)
        case (.sphere(let a), .convexHull(let b)):
            return intersects(a, b, frame: frame)
        case (.sphere(let a), .staticPlane(let b)):
            return intersects(a, b, frame: frame)
        case (.sphere(let a), .triangleMesh(let b)):
            return intersects(a, b, frame: frame)
        case (.sphere(let a), .compound(let b)):
            return intersects(a, b, frame: frame)
        case (.capsule(let a), .box(let b)):
            return intersects(a, b, frame: frame)
        case (.capsule(let a), .sphere(let b)):
            return intersects(a, b, frame: frame)
        case (.capsule(let a), .capsule(let b)):
            return intersects(a, b, frame: frame)
        case (.capsule(let a), .cylinder(let b)):
            return intersects(a, b, frame: frame)
        case (.capsule(let a), .cone(let b)):
            return intersects(a, b, frame: frame)
        case (.capsule(let a), .convexHull(let b)):
            return intersects(a, b, frame: frame)
        case (.capsule(let a), .staticPlane(let b)):
            return intersects(a, b, frame: frame)
        case (.capsule(let a), .triangleMesh(let b)):
            return intersects(a, b, frame: frame)
        case (.capsule(let a), .compound(let b)):
            return intersects(a, b, frame: frame)
        case (.cylinder(let a), .box(let b)):
            return intersects(a, b, frame: frame)
        case (.cylinder(let a), .sphere(let b)):
            return intersects(a, b, frame: frame)
        case (.cylinder(let a), .capsule(let b)):
            return intersects(a, b, frame: frame)
        case (.cylinder(let a), .cylinder(let b)):
            return intersects(a, b, frame: frame)
        case (.cylinder(let a), .cone(let b)):
            return intersects(a, b, frame: frame)
        case (.cylinder(let a), .convexHull(let b)):
            return intersects(a, b, frame: frame)
        case (.cylinder(let a), .staticPlane(let b)):
            return intersects(a, b, frame: frame)
        case (.cylinder(let a), .triangleMesh(let b)):
            return intersects(a, b, frame: frame)
        case (.cylinder(let a), .compound(let b)):
            return intersects(a, b, frame: frame)
        case (.cone(let a), .box(let b)):
            return intersects(a, b, frame: frame)
        case (.cone(let a), .sphere(let b)):
            return intersects(a, b, frame: frame)
        case (.cone(let a), .capsule(let b)):
            return intersects(a, b, frame: frame)
        case (.cone(let a), .cylinder(let b)):
            return intersects(a, b, frame: frame)
        case (.cone(let a), .cone(let b)):
            return intersects(a, b, frame: frame)
        case (.cone(let a), .convexHull(let b)):
            return intersects(a, b, frame: frame)
        case (.cone(let a), .staticPlane(let b)):
            return intersects(a, b, frame: frame)
        case (.cone(let a), .triangleMesh(let b)):
            return intersects(a, b, frame: frame)
        case (.cone(let a), .compound(let b)):
            return intersects(a, b, frame: frame)
        case (.convexHull(let a), .box(let b)):
            return intersects(a, b, frame: frame)
        case (.convexHull(let a), .sphere(let b)):
            return intersects(a, b, frame: frame)
        case (.convexHull(let a), .capsule(let b)):
            return intersects(a, b, frame: frame)
        case (.convexHull(let a), .cylinder(let b)):
            return intersects(a, b, frame: frame)
        case (.convexHull(let a), .cone(let b)):
            return intersects(a, b, frame: frame)
        case (.convexHull(let a), .convexHull(let b)):
            return intersects(a, b, frame: frame)
        case (.convexHull(let a), .staticPlane(let b)):
            return intersects(a, b, frame: frame)
        case (.convexHull(let a), .triangleMesh(let b)):
            return intersects(a, b, frame: frame)
        case (.convexHull(let a), .compound(let b)):
            return intersects(a, b, frame: frame)
        case (.staticPlane(let a), .box(let b)):
            return intersects(a, b, frame: frame)
        case (.staticPlane(let a), .sphere(let b)):
            return intersects(a, b, frame: frame)
        case (.staticPlane(let a), .capsule(let b)):
            return intersects(a, b, frame: frame)
        case (.staticPlane(let a), .cylinder(let b)):
            return intersects(a, b, frame: frame)
        case (.staticPlane(let a), .cone(let b)):
            return intersects(a, b, frame: frame)
        case (.staticPlane(let a), .convexHull(let b)):
            return intersects(a, b, frame: frame)
        case (.staticPlane(let a), .staticPlane(let b)):
            return intersects(a, b, frame: frame)
        case (.staticPlane(let a), .triangleMesh(let b)):
            return intersects(a, b, frame: frame)
        case (.staticPlane(let a), .compound(let b)):
            return intersects(a, b, frame: frame)
        case (.triangleMesh(let a), .box(let b)):
            return intersects(a, b, frame: frame)
        case (.triangleMesh(let a), .sphere(let b)):
            return intersects(a, b, frame: frame)
        case (.triangleMesh(let a), .capsule(let b)):
            return intersects(a, b, frame: frame)
        case (.triangleMesh(let a), .cylinder(let b)):
            return intersects(a, b, frame: frame)
        case (.triangleMesh(let a), .cone(let b)):
            return intersects(a, b, frame: frame)
        case (.triangleMesh(let a), .convexHull(let b)):
            return intersects(a, b, frame: frame)
        case (.triangleMesh(let a), .staticPlane(let b)):
            return intersects(a, b, frame: frame)
        case (.triangleMesh(let a), .triangleMesh(let b)):
            return intersects(a, b, frame: frame)
        case (.triangleMesh(let a), .compound(let b)):
            return intersects(a, b, frame: frame)
        case (.compound(let a), .box(let b)):
            return intersects(a, b, frame: frame)
        case (.compound(let a), .sphere(let b)):
            return intersects(a, b, frame: frame)
        case (.compound(let a), .capsule(let b)):
            return intersects(a, b, frame: frame)
        case (.compound(let a), .cylinder(let b)):
            return intersects(a, b, frame: frame)
        case (.compound(let a), .cone(let b)):
            return intersects(a, b, frame: frame)
        case (.compound(let a), .convexHull(let b)):
            return intersects(a, b, frame: frame)
        case (.compound(let a), .staticPlane(let b)):
            return intersects(a, b, frame: frame)
        case (.compound(let a), .triangleMesh(let b)):
            return intersects(a, b, frame: frame)
        case (.compound(let a), .compound(let b)):
            return intersects(a, b, frame: frame)
        }
    }

    fileprivate static func contactManifold(_ a: CollisionPrimitiveDispatch,
                                            _ b: CollisionPrimitiveDispatch,
                                            frame: Transform = .identity) -> ContactManifold? {
        switch (a, b) {
        case (.box(let a), .box(let b)):
            return contactManifold(a, b, frame: frame)
        case (.box(let a), .sphere(let b)):
            return contactManifold(a, b, frame: frame)
        case (.sphere(let a), .box(let b)):
            return contactManifold(a, b, frame: frame)
        case (.sphere(let a), .sphere(let b)):
            return contactManifold(a, b, frame: frame)
        case (.sphere(let a), .capsule(let b)):
            return contactManifold(a, b, frame: frame)
        case (.capsule(let a), .sphere(let b)):
            return contactManifold(a, b, frame: frame)
        case (.capsule(let a), .capsule(let b)):
            return contactManifold(a, b, frame: frame)
        case (.box(let a), .staticPlane(let b)):
            return contactManifold(a, b, frame: frame)
        case (.staticPlane(let a), .box(let b)):
            return contactManifold(a, b, frame: frame)
        case (.sphere(let a), .staticPlane(let b)):
            return contactManifold(a, b, frame: frame)
        case (.staticPlane(let a), .sphere(let b)):
            return contactManifold(a, b, frame: frame)
        default:
            return nil
        }
    }
}

public struct CollisionAlgorithmRegistry {
    public init() {
    }

    public func intersects(_ a: any CollisionShape,
                           _ b: any CollisionShape,
                           frame: Transform = .identity) -> Bool {
        CollisionAlgorithms.intersects(a, b, frame: frame)
    }

    public func contactManifold(_ a: any CollisionShape,
                                _ b: any CollisionShape,
                                frame: Transform = .identity) -> ContactManifold? {
        CollisionAlgorithms.contactManifold(a, b, frame: frame)
    }

}
