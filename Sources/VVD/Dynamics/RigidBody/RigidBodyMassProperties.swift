//
//  File: RigidBodyMassProperties.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

/// Optional finite-volume mass-property support for collision primitives.
public protocol RigidBodyMassPropertiesProvider: CollisionPrimitive {
    func rigidBodyMassProperties(density: Scalar) -> RigidBodyMassProperties?
}

public extension RigidBodyMassProperties {
    /// Derives mass, center of mass, and the full local inertia tensor from a
    /// primitive that provides finite-volume mass properties.
    init?(primitive: any CollisionPrimitive, density: Scalar) {
        guard density.isFinite,
              density > .zero,
              let provider = primitive as? any RigidBodyMassPropertiesProvider,
              let properties = provider.rigidBodyMassProperties(density: density)
        else { return nil }
        self = properties
    }
}

extension Box: RigidBodyMassPropertiesProvider {
    public func rigidBodyMassProperties(
        density: Scalar
    ) -> RigidBodyMassProperties? {
        guard _isValidDensity(density),
              isValid,
              halfExtents.x > .zero,
              halfExtents.y > .zero,
              halfExtents.z > .zero
        else { return nil }

        let mass = density * Scalar(8) *
            halfExtents.x * halfExtents.y * halfExtents.z
        let factor = mass / Scalar(3)
        let inertia = Vector3(
            factor * (halfExtents.y * halfExtents.y +
                      halfExtents.z * halfExtents.z),
            factor * (halfExtents.x * halfExtents.x +
                      halfExtents.z * halfExtents.z),
            factor * (halfExtents.x * halfExtents.x +
                      halfExtents.y * halfExtents.y))
        return RigidBodyMassProperties(mass: mass,
                                       centerOfMass: .zero,
                                       inertia: inertia)
    }
}

extension Sphere: RigidBodyMassPropertiesProvider {
    public func rigidBodyMassProperties(
        density: Scalar
    ) -> RigidBodyMassProperties? {
        guard _isValidDensity(density), isValid, radius > .zero else {
            return nil
        }

        let mass = density * Scalar(4.0 / 3.0) * Scalar.pi *
            radius * radius * radius
        let moment = Scalar(2.0 / 5.0) * mass * radius * radius
        return RigidBodyMassProperties(mass: mass,
                                       centerOfMass: center,
                                       inertia: Vector3(moment,
                                                        moment,
                                                        moment))
    }
}

extension Capsule: RigidBodyMassPropertiesProvider {
    public func rigidBodyMassProperties(
        density: Scalar
    ) -> RigidBodyMassProperties? {
        guard _isValidDensity(density), isValid, radius > .zero else {
            return nil
        }

        let radiusSquared = radius * radius
        let cylinderMass = density * Scalar.pi * radiusSquared * height
        let capMass = density * Scalar(4.0 / 3.0) * Scalar.pi *
            radiusSquared * radius
        let mass = cylinderMass + capMass
        let axial = Scalar(0.5) * cylinderMass * radiusSquared +
            Scalar(2.0 / 5.0) * capMass * radiusSquared
        let transverse = cylinderMass *
            (Scalar(3) * radiusSquared + height * height) / Scalar(12) +
            capMass * (Scalar(2.0 / 5.0) * radiusSquared +
                       height * height / Scalar(4) +
                       Scalar(3.0 / 8.0) * height * radius)
        return RigidBodyMassProperties(
            mass: mass,
            centerOfMass: .zero,
            inertia: Vector3(transverse, axial, transverse))
    }
}

extension Cylinder: RigidBodyMassPropertiesProvider {
    public func rigidBodyMassProperties(
        density: Scalar
    ) -> RigidBodyMassProperties? {
        guard _isValidDensity(density),
              isValid,
              radius > .zero,
              height > .zero
        else { return nil }

        let radiusSquared = radius * radius
        let mass = density * Scalar.pi * radiusSquared * height
        let transverse = mass *
            (Scalar(3) * radiusSquared + height * height) / Scalar(12)
        let axial = Scalar(0.5) * mass * radiusSquared
        return RigidBodyMassProperties(
            mass: mass,
            centerOfMass: .zero,
            inertia: Vector3(transverse, axial, transverse))
    }
}

extension Cone: RigidBodyMassPropertiesProvider {
    public func rigidBodyMassProperties(
        density: Scalar
    ) -> RigidBodyMassProperties? {
        guard _isValidDensity(density), isValid, radius > .zero else {
            return nil
        }

        let radiusSquared = radius * radius
        let mass = density * Scalar(1.0 / 3.0) * Scalar.pi *
            radiusSquared * height
        let transverse = mass *
            (Scalar(3.0 / 20.0) * radiusSquared +
             Scalar(3.0 / 80.0) * height * height)
        let axial = Scalar(3.0 / 10.0) * mass * radiusSquared
        return RigidBodyMassProperties(
            mass: mass,
            centerOfMass: Vector3(0, -height * Scalar(0.25), 0),
            inertia: Vector3(transverse, axial, transverse))
    }
}

extension ConvexHull: RigidBodyMassPropertiesProvider {
    public func rigidBodyMassProperties(
        density: Scalar
    ) -> RigidBodyMassProperties? {
        guard _isValidDensity(density), isValid, hasSurfaceTopology else {
            return nil
        }

        var triangles: [Triangle] = []
        for face in faces {
            let first = vertices[face[0]]
            for index in 1..<(face.count - 1) {
                triangles.append(Triangle(first,
                                          vertices[face[index]],
                                          vertices[face[index + 1]]))
            }
        }
        return _polyhedronMassProperties(triangles: triangles,
                                         density: density,
                                         validateClosedSurface: false)
    }
}

extension TriangleMesh: RigidBodyMassPropertiesProvider {
    public func rigidBodyMassProperties(
        density: Scalar
    ) -> RigidBodyMassProperties? {
        guard _isValidDensity(density), isValid else { return nil }
        let triangles = (0..<triangleCount).map { triangle(at: $0) }
        return _polyhedronMassProperties(triangles: triangles,
                                         density: density,
                                         validateClosedSurface: true)
    }
}

extension CompoundPrimitive: RigidBodyMassPropertiesProvider {
    public func rigidBodyMassProperties(
        density: Scalar
    ) -> RigidBodyMassProperties? {
        guard _isValidDensity(density), isValid else { return nil }

        struct Component {
            let mass: Scalar
            let center: Vector3
            let inertia: Matrix3
        }

        var components: [Component] = []
        var totalMass: Scalar = .zero
        var weightedCenter = Vector3.zero
        for child in flattenedChildren() where child.primitive.isValid {
            guard let properties = RigidBodyMassProperties(
                primitive: child.primitive,
                density: density) else { return nil }

            let center = properties.centerOfMass.applying(child.transform)
            let rotation = child.transform.orientation.matrix3
            let inertia = rotation.transposed() *
                properties.inertiaTensor * rotation
            components.append(Component(mass: properties.mass,
                                        center: center,
                                        inertia: inertia))
            totalMass += properties.mass
            weightedCenter += center * properties.mass
        }
        guard totalMass.isFinite, totalMass > .zero else { return nil }

        let centerOfMass = weightedCenter / totalMass
        var inertiaTensor = _zeroMatrix3
        for component in components {
            inertiaTensor += component.inertia + _parallelAxisTensor(
                mass: component.mass,
                offset: component.center - centerOfMass)
        }
        return RigidBodyMassProperties(mass: totalMass,
                                       centerOfMass: centerOfMass,
                                       inertiaTensor: inertiaTensor)
    }
}

private let _zeroMatrix3 = Matrix3(0, 0, 0,
                                   0, 0, 0,
                                   0, 0, 0)

private func _isValidDensity(_ density: Scalar) -> Bool {
    density.isFinite && density > .zero
}

private func _parallelAxisTensor(mass: Scalar,
                                 offset: Vector3) -> Matrix3 {
    let xx = offset.x * offset.x
    let yy = offset.y * offset.y
    let zz = offset.z * offset.z
    let xy = offset.x * offset.y
    let xz = offset.x * offset.z
    let yz = offset.y * offset.z
    return Matrix3(
        mass * (yy + zz), -mass * xy, -mass * xz,
        -mass * xy, mass * (xx + zz), -mass * yz,
        -mass * xz, -mass * yz, mass * (xx + yy))
}

private struct _MassDirectedEdge: Hashable {
    let a: Vector3
    let b: Vector3
}

private func _hasClosedConsistentSurface(_ triangles: [Triangle]) -> Bool {
    var edgeUses: [_MassDirectedEdge: Int] = [:]
    for triangle in triangles {
        guard triangle.area > .ulpOfOne else { return false }
        for edge in [(triangle.p0, triangle.p1),
                     (triangle.p1, triangle.p2),
                     (triangle.p2, triangle.p0)] {
            edgeUses[_MassDirectedEdge(a: edge.0, b: edge.1), default: 0] += 1
        }
    }
    return edgeUses.isEmpty == false && edgeUses.allSatisfy { edge, count in
        count == 1 && edgeUses[_MassDirectedEdge(a: edge.b, b: edge.a)] == 1
    }
}

private func _polyhedronMassProperties(
    triangles: [Triangle],
    density: Scalar,
    validateClosedSurface: Bool
) -> RigidBodyMassProperties? {
    guard triangles.isEmpty == false,
          validateClosedSurface == false ||
            _hasClosedConsistentSurface(triangles)
    else { return nil }

    var signedVolume: Scalar = .zero
    var firstMoment = Vector3.zero
    var integralX2: Scalar = .zero
    var integralY2: Scalar = .zero
    var integralZ2: Scalar = .zero
    var integralXY: Scalar = .zero
    var integralXZ: Scalar = .zero
    var integralYZ: Scalar = .zero

    for triangle in triangles {
        let a = triangle.p0
        let b = triangle.p1
        let c = triangle.p2
        let volume = Vector3.dot(a, Vector3.cross(b, c)) / Scalar(6)
        signedVolume += volume
        firstMoment += (a + b + c) * (volume / Scalar(4))

        func squareIntegral(_ x0: Scalar,
                            _ x1: Scalar,
                            _ x2: Scalar) -> Scalar {
            volume / Scalar(10) *
                (x0 * x0 + x1 * x1 + x2 * x2 +
                 x0 * x1 + x0 * x2 + x1 * x2)
        }
        func productIntegral(_ x0: Scalar,
                             _ y0: Scalar,
                             _ x1: Scalar,
                             _ y1: Scalar,
                             _ x2: Scalar,
                             _ y2: Scalar) -> Scalar {
            volume / Scalar(20) *
                (Scalar(2) * (x0 * y0 + x1 * y1 + x2 * y2) +
                 x0 * y1 + x1 * y0 +
                 x0 * y2 + x2 * y0 +
                 x1 * y2 + x2 * y1)
        }

        integralX2 += squareIntegral(a.x, b.x, c.x)
        integralY2 += squareIntegral(a.y, b.y, c.y)
        integralZ2 += squareIntegral(a.z, b.z, c.z)
        integralXY += productIntegral(a.x, a.y,
                                      b.x, b.y,
                                      c.x, c.y)
        integralXZ += productIntegral(a.x, a.z,
                                      b.x, b.z,
                                      c.x, c.z)
        integralYZ += productIntegral(a.y, a.z,
                                      b.y, b.z,
                                      c.y, c.z)
    }

    let bounds = AABB(triangles.flatMap { [$0.p0, $0.p1, $0.p2] })
    let scale = Swift.max(bounds.extents.length, Scalar(1))
    let epsilon = MemoryLayout<Scalar>.size > MemoryLayout<Float32>.size
        ? Scalar(1.0e-12)
        : Scalar(1.0e-6)
    guard abs(signedVolume) > scale * scale * scale * epsilon else {
        return nil
    }

    if signedVolume < .zero {
        signedVolume = -signedVolume
        firstMoment = -firstMoment
        integralX2 = -integralX2
        integralY2 = -integralY2
        integralZ2 = -integralZ2
        integralXY = -integralXY
        integralXZ = -integralXZ
        integralYZ = -integralYZ
    }

    let mass = density * signedVolume
    let centerOfMass = firstMoment / signedVolume
    let inertiaAtOrigin = Matrix3(
        density * (integralY2 + integralZ2), -density * integralXY,
        -density * integralXZ,
        -density * integralXY, density * (integralX2 + integralZ2),
        -density * integralYZ,
        -density * integralXZ, -density * integralYZ,
        density * (integralX2 + integralY2))
    let inertiaAtCenter = inertiaAtOrigin - _parallelAxisTensor(
        mass: mass,
        offset: centerOfMass)
    return RigidBodyMassProperties(mass: mass,
                                   centerOfMass: centerOfMass,
                                   inertiaTensor: inertiaAtCenter)
}
