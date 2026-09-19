//
//  File: Box.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

public struct Box: ConvexPrimitive {
    public let halfExtents: Vector3
    public var isValid: Bool {
        halfExtents.x >= .zero && halfExtents.y >= .zero && halfExtents.z >= .zero
    }
    public var bounds: AABB {
        isValid ? AABB(center: .zero, halfExtents: halfExtents) : .null
    }

    public init(halfExtents: Vector3) {
        self.halfExtents = halfExtents
    }

    public func contains(_ point: Vector3) -> Bool {
        isValid &&
        abs(point.x) <= halfExtents.x &&
        abs(point.y) <= halfExtents.y &&
        abs(point.z) <= halfExtents.z
    }

    public func rayTest(_ ray: Ray) -> PrimitiveRayHit? {
        guard isValid && ray.isValid else { return nil }

        var nearParameter = -Scalar.infinity
        var farParameter = Scalar.infinity
        var nearNormal = Vector3.zero
        var farNormal = Vector3.zero

        for axis in 0..<Vector3.components {
            let origin = ray.origin[axis]
            let direction = ray.direction[axis]
            let minimum = -halfExtents[axis]
            let maximum = halfExtents[axis]

            if abs(direction) <= .ulpOfOne {
                guard origin >= minimum && origin <= maximum else { return nil }
                continue
            }

            var minimumParameter = (minimum - origin) / direction
            var maximumParameter = (maximum - origin) / direction
            var minimumNormal = Vector3.zero
            var maximumNormal = Vector3.zero
            minimumNormal[axis] = -1
            maximumNormal[axis] = 1

            if minimumParameter > maximumParameter {
                swap(&minimumParameter, &maximumParameter)
                swap(&minimumNormal, &maximumNormal)
            }

            if minimumParameter > nearParameter {
                nearParameter = minimumParameter
                nearNormal = minimumNormal
            }
            if maximumParameter < farParameter {
                farParameter = maximumParameter
                farNormal = maximumNormal
            }
            guard nearParameter <= farParameter else { return nil }
        }

        let parameter: Scalar
        let normal: Vector3
        if nearParameter >= .zero {
            parameter = nearParameter
            normal = nearNormal
        } else if farParameter >= .zero {
            parameter = farParameter
            normal = farNormal
        } else {
            return nil
        }
        return PrimitiveRayHit(parameter: parameter,
                               position: ray.point(at: parameter),
                               normal: normal)
    }
}

public struct BoxShape: ConvexShape {
    public let primitive: Box

    public init(_ primitive: Box) {
        self.primitive = primitive
    }
}
