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
        children.contains { child in
            guard child.primitive.isValid else { return false }
            return child.primitive.contains(point.applying(child.transform.inverted()))
        }
    }

    public func closestPoint(to point: Vector3) -> PrimitiveClosestPoint? {
        guard isValid else { return nil }

        var closest: PrimitiveClosestPoint?
        for child in flattenedChildren() where child.primitive.isValid {
            let inverseTransform = child.transform.inverted()
            let childPoint = point.applying(inverseTransform)
            guard let childClosest = child.primitive.closestPoint(to: childPoint)
            else { continue }

            let candidate = PrimitiveClosestPoint(
                position: childClosest.position.applying(child.transform),
                normal: childClosest.normal
                    .applying(child.transform.orientation)
                    .normalized(),
                distance: childClosest.distance)
            if closest == nil || candidate.distance < closest!.distance {
                closest = candidate
            }
        }
        return closest
    }

    public func rayTest(_ ray: Ray) -> PrimitiveRayHit? {
        guard isValid && ray.isValid else { return nil }

        var closest: PrimitiveRayHit?
        for child in flattenedChildren() where child.primitive.isValid {
            if child.bounds.isNull == false && child.bounds.intersects(ray) == false {
                continue
            }

            let inverseTransform = child.transform.inverted()
            let childRay = Ray(
                origin: ray.origin.applying(inverseTransform),
                direction: ray.direction.applying(inverseTransform.orientation))
            guard let childHit = child.primitive.rayTest(childRay) else { continue }
            if let closest, closest.parameter <= childHit.parameter { continue }

            closest = PrimitiveRayHit(
                parameter: childHit.parameter,
                position: childHit.position.applying(child.transform),
                normal: childHit.normal.applying(child.transform.orientation).normalized())
        }
        return closest
    }
}

public struct CompoundShape: CollisionShape {
    public let primitive: CompoundPrimitive

    public init(_ primitive: CompoundPrimitive) {
        self.primitive = primitive
    }
}
