//
//  File: CompoundPrimitive.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

public struct CompoundPrimitive: CollisionPrimitive {
    public struct Child: Hashable {
        public let primitive: any CollisionPrimitive
        public let transform: Transform
        public let bounds: AABB

        public init(_ primitive: any CollisionPrimitive, transform: Transform = .identity) {
            self.primitive = primitive
            self.transform = transform
            self.bounds = primitive.bounds.applying(transform)
        }

        public static func == (lhs: Self, rhs: Self) -> Bool {
            AnyHashable(lhs.primitive) == AnyHashable(rhs.primitive) &&
            lhs.transform == rhs.transform
        }

        public func hash(into hasher: inout Hasher) {
            primitive.hash(into: &hasher)
            hasher.combine(transform)
        }
    }

    public let children: [Child]
    public let bounds: AABB

    public var isValid: Bool {
        children.contains { $0.primitive.isValid }
    }

    public init(children: [Child] = []) {
        self.children = children
        self.bounds = children.reduce(into: AABB()) { bounds, child in
            bounds.combine(child.bounds)
        }
    }

    public func flattenedChildren() -> [Child] {
        children.flatMap { child -> [Child] in
            guard let compound = child.primitive as? CompoundPrimitive else {
                return [child]
            }

            return compound.flattenedChildren().map {
                Child($0.primitive, transform: $0.transform * child.transform)
            }
        }
    }

    public func flattened() -> CompoundPrimitive {
        CompoundPrimitive(children: flattenedChildren())
    }

    public func contains(_ point: Vector3) -> Bool {
        false
    }

    public func rayTest(rayOrigin origin: Vector3, direction: Vector3) -> Scalar {
        -1.0
    }
}

public struct CompoundShape: CollisionShape {
    public let primitive: CompoundPrimitive

    public init(_ primitive: CompoundPrimitive) {
        self.primitive = primitive
    }
}
