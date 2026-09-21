//
//  File: CollisionContact.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

private let _contactTolerance: Scalar = {
    MemoryLayout<Scalar>.size > MemoryLayout<Float32>.size
        ? Scalar(1.0e-8)
        : Scalar(1.0e-4)
}()

private let _contactIterationLimit = 64

extension CollisionAlgorithms {
    /// Generates one penetration contact for two intersecting convex support
    /// maps. GJK supplies an origin-containing simplex and EPA resolves the
    /// closest Minkowski boundary with barycentric surface witnesses.
    static func supportMapContactManifold<
        A: CollisionPrimitive & _SupportMap,
        B: CollisionPrimitive & _SupportMap
    >(
        _ a: A,
        _ b: B,
        frame: Transform
    ) -> ContactManifold? {
        guard a.isSupportMappingValid && b.isSupportMappingValid else {
            return nil
        }

        let transformedB = _SweepTransformedSupport(base: b,
                                                     transform: frame)
        return _supportMapContact(a, transformedB)
    }

    /// Projects a convex support map onto a two-sided plane and returns the
    /// shallowest support point needed to place the primitive on the plane.
    static func supportMapPlaneContactManifold<
        A: CollisionPrimitive & _SupportMap
    >(
        _ primitive: A,
        _ staticPlane: StaticPlane,
        frame: Transform
    ) -> ContactManifold? {
        guard primitive.isSupportMappingValid && staticPlane.isValid else {
            return nil
        }

        let transformedNormal = staticPlane.plane.normal
            .applying(frame.orientation)
        let normalLength = transformedNormal.length
        guard normalLength > _contactTolerance else { return nil }

        let planeNormal = transformedNormal / normalLength
        let planeDistance = (staticPlane.plane.d -
            Vector3.dot(transformedNormal, frame.position)) / normalLength
        let minimumPoint = primitive.support(-planeNormal)
        let maximumPoint = primitive.support(planeNormal)
        let minimumDistance = Vector3.dot(planeNormal, minimumPoint) +
            planeDistance
        let maximumDistance = Vector3.dot(planeNormal, maximumPoint) +
            planeDistance
        guard minimumDistance <= _contactTolerance,
              maximumDistance >= -_contactTolerance
        else { return nil }

        let centerDistance = Vector3.dot(planeNormal, primitive.center) +
            planeDistance
        let normal: Vector3
        let pointOnA: Vector3
        let signedDistance: Scalar
        if centerDistance >= .zero {
            normal = -planeNormal
            pointOnA = minimumPoint
            signedDistance = minimumDistance
        } else {
            normal = planeNormal
            pointOnA = maximumPoint
            signedDistance = maximumDistance
        }

        let depth = Swift.max(Vector3.dot(normal, planeNormal) *
                              signedDistance, .zero)
        let pointOnB = pointOnA - planeNormal * signedDistance
        return ContactManifold(Contact(pointOnA: pointOnA,
                                       pointOnB: pointOnB,
                                       normal: normal,
                                       penetrationDepth: depth))
    }

    /// Queries mesh-local triangle candidates and keeps the deepest convex
    /// triangle penetration contact in the convex primitive's local space.
    static func supportMapMeshContactManifold<
        A: CollisionPrimitive & _SupportMap
    >(
        _ primitive: A,
        _ mesh: TriangleMesh,
        frame: Transform
    ) -> ContactManifold? {
        guard primitive.isSupportMappingValid && mesh.isValid else {
            return nil
        }

        let queryBounds = primitive.bounds.applying(frame.inverted())
        var deepest: Contact?
        mesh.queryTriangles(overlapping: queryBounds) { index in
            let triangle = mesh.triangle(at: index)
            let transformedTriangle = _SweepTransformedSupport(
                base: triangle,
                transform: frame)
            guard let contact = _supportMapContact(
                primitive,
                transformedTriangle)?.contacts.first
            else { return true }

            let candidate = Contact(
                pointOnA: contact.pointOnA,
                pointOnB: contact.pointOnB,
                normal: contact.normal,
                penetrationDepth: contact.penetrationDepth,
                featureID: ContactFeatureID(UInt64(index)))
            if deepest == nil ||
                candidate.penetrationDepth > deepest!.penetrationDepth {
                deepest = candidate
            }
            return true
        }
        return deepest.map(ContactManifold.init)
    }

    /// Produces zero-depth surface contacts for exact triangle-pair overlaps.
    /// Candidate traversal remains delegated to both mesh storage layers.
    static func meshContactManifold(
        _ a: TriangleMesh,
        _ b: TriangleMesh,
        frame: Transform
    ) -> ContactManifold? {
        guard a.isValid && b.isValid else { return nil }

        let inverseFrame = frame.inverted()
        let boundsBInA = b.bounds.applying(frame)
        var contacts: [Contact] = []
        a.queryTriangles(overlapping: boundsBInA) { indexA in
            let triangleA = a.triangle(at: indexA)
            let boundsAInB = triangleA.aabb.applying(inverseFrame)
            b.queryTriangles(overlapping: boundsAInB) { indexB in
                let triangleB = _contactTransformedTriangle(
                    b.triangle(at: indexB),
                    by: frame)
                guard let overlap = triangleA.overlapTest(triangleB) else {
                    return true
                }

                let point: Vector3
                switch overlap {
                case .segment(let p0, let p1):
                    point = (p0 + p1) * Scalar(0.5)
                case .coplanar:
                    guard let overlapPoint = _coplanarTriangleContactPoint(
                        triangleA,
                        triangleB) else { return true }
                    point = overlapPoint
                }

                var normal = triangleA.normal
                let centerDelta = triangleB.center - triangleA.center
                if Vector3.dot(normal, centerDelta) < .zero {
                    normal = -normal
                }
                if normal.lengthSquared <= _contactTolerance *
                    _contactTolerance {
                    normal = triangleB.normal
                }
                if normal.lengthSquared <= _contactTolerance *
                    _contactTolerance {
                    normal = Vector3(1, 0, 0)
                }

                contacts.append(Contact(
                    pointOnA: point,
                    pointOnB: point,
                    normal: normal.normalized(),
                    penetrationDepth: .zero,
                    featureID: _meshContactFeature(indexA, indexB)))
                return contacts.count < 4
            }
            return contacts.count < 4
        }
        return contacts.isEmpty ? nil : ContactManifold(contacts: contacts)
    }

    /// Produces zero-depth contacts where transformed mesh triangles cross or
    /// touch the static plane.
    static func planeMeshContactManifold(
        _ staticPlane: StaticPlane,
        _ mesh: TriangleMesh,
        frame: Transform
    ) -> ContactManifold? {
        guard staticPlane.isValid && mesh.isValid else { return nil }

        let normalLength = staticPlane.plane.normal.length
        guard normalLength > _contactTolerance else { return nil }
        let planeNormal = staticPlane.plane.normal / normalLength
        let planeDistance = staticPlane.plane.d / normalLength
        var contacts: [Contact] = []

        for index in 0..<mesh.triangleCount {
            let triangle = _contactTransformedTriangle(mesh.triangle(at: index),
                                                       by: frame)
            let distances = [triangle.p0, triangle.p1, triangle.p2].map {
                Vector3.dot(planeNormal, $0) + planeDistance
            }
            guard distances.min()! <= _contactTolerance,
                  distances.max()! >= -_contactTolerance,
                  let point = _trianglePlaneContactPoint(
                    triangle,
                    distances: distances,
                    tolerance: _contactTolerance)
            else { continue }

            let centerDistance = distances.reduce(.zero, +) / Scalar(3)
            let normal = centerDistance >= .zero ? planeNormal : -planeNormal
            contacts.append(Contact(
                pointOnA: point,
                pointOnB: point,
                normal: normal,
                penetrationDepth: .zero,
                featureID: ContactFeatureID(UInt64(index))))
            if contacts.count == 4 { break }
        }
        return contacts.isEmpty ? nil : ContactManifold(contacts: contacts)
    }
}

private struct _ContactSupportVertex {
    let point: Vector3
    let pointOnA: Vector3
    let pointOnB: Vector3
}

private struct _ContactFace {
    let a: Int
    let b: Int
    let c: Int
    let normal: Vector3
    let distance: Scalar
}

private struct _ContactEdge: Equatable {
    let a: Int
    let b: Int
}

private func _supportMapContact(
    _ a: any _SupportMap,
    _ b: _SweepTransformedSupport
) -> ContactManifold? {
    let scale = Swift.max(a.bounds.extents.length,
                          b.bounds.extents.length,
                          Scalar(1))
    let tolerance = scale * _contactTolerance
    let closest = _gjkClosestPoints(a,
                                    b,
                                    offset: .zero,
                                    tolerance: tolerance)
    guard closest.distance <= tolerance else { return nil }

    switch _contactSimplex(a, b, tolerance: tolerance) {
    case .none:
        return nil
    case .fallback(let direction):
        return _fallbackContact(a, b, direction: direction,
                                tolerance: tolerance)
    case .tetrahedron(let simplex):
        return _epaContact(a, b, simplex: simplex,
                           tolerance: tolerance) ??
            _fallbackContact(a, b,
                             direction: b.center - a.center,
                             tolerance: tolerance)
    }
}

private enum _ContactSimplexResult {
    case none
    case fallback(Vector3)
    case tetrahedron([_ContactSupportVertex])
}

private func _contactSimplex(
    _ a: any _SupportMap,
    _ b: _SweepTransformedSupport,
    tolerance: Scalar
) -> _ContactSimplexResult {
    var direction = b.center - a.center
    if direction.lengthSquared <= tolerance * tolerance {
        direction = Vector3(1, 0, 0)
    }

    var simplex = [_contactSupport(a, b, direction: direction)]
    direction = -simplex[0].point
    if direction.lengthSquared <= tolerance * tolerance {
        return .fallback(b.center - a.center)
    }

    for _ in 0..<_contactIterationLimit {
        let vertex = _contactSupport(a, b, direction: direction)
        if Vector3.dot(vertex.point, direction) < -tolerance {
            return .none
        }
        if simplex.contains(where: {
            ($0.point - vertex.point).lengthSquared <= tolerance * tolerance
        }) {
            return .fallback(direction)
        }

        simplex.append(vertex)
        if _handleContactSimplex(&simplex, direction: &direction,
                                 tolerance: tolerance) {
            return simplex.count == 4
                ? .tetrahedron(simplex)
                : .fallback(direction)
        }
        if direction.lengthSquared <= tolerance * tolerance {
            return .fallback(b.center - a.center)
        }
    }
    return .fallback(direction)
}

private func _contactSupport(
    _ a: any _SupportMap,
    _ b: _SweepTransformedSupport,
    direction: Vector3
) -> _ContactSupportVertex {
    let pointOnA = a.support(direction)
    let pointOnB = b.support(-direction)
    return _ContactSupportVertex(point: pointOnA - pointOnB,
                                 pointOnA: pointOnA,
                                 pointOnB: pointOnB)
}

private func _handleContactSimplex(
    _ simplex: inout [_ContactSupportVertex],
    direction: inout Vector3,
    tolerance: Scalar
) -> Bool {
    switch simplex.count {
    case 2:
        return _handleContactLine(&simplex, direction: &direction,
                                  tolerance: tolerance)
    case 3:
        return _handleContactTriangle(&simplex, direction: &direction,
                                      tolerance: tolerance)
    case 4:
        return _handleContactTetrahedron(&simplex, direction: &direction,
                                         tolerance: tolerance)
    default:
        direction = -simplex[0].point
        return false
    }
}

private func _handleContactLine(
    _ simplex: inout [_ContactSupportVertex],
    direction: inout Vector3,
    tolerance: Scalar
) -> Bool {
    let a = simplex[1]
    let b = simplex[0]
    let ab = b.point - a.point
    let ao = -a.point

    if Vector3.dot(ab, ao) > .zero {
        direction = Vector3.cross(Vector3.cross(ab, ao), ab)
        if direction.lengthSquared <= tolerance * tolerance {
            direction = _contactPerpendicular(to: ab)
            return true
        }
    } else {
        simplex = [a]
        direction = ao
    }
    return false
}

private func _handleContactTriangle(
    _ simplex: inout [_ContactSupportVertex],
    direction: inout Vector3,
    tolerance: Scalar
) -> Bool {
    let a = simplex[2]
    let b = simplex[1]
    let c = simplex[0]
    let ab = b.point - a.point
    let ac = c.point - a.point
    let ao = -a.point
    let abc = Vector3.cross(ab, ac)

    let acPerpendicular = Vector3.cross(abc, ac)
    if Vector3.dot(acPerpendicular, ao) > .zero {
        if Vector3.dot(ac, ao) > .zero {
            simplex = [c, a]
            direction = Vector3.cross(Vector3.cross(ac, ao), ac)
            if direction.lengthSquared <= tolerance * tolerance {
                direction = _contactPerpendicular(to: ac)
                return true
            }
            return false
        }
        simplex = [b, a]
        return _handleContactLine(&simplex,
                                  direction: &direction,
                                  tolerance: tolerance)
    }

    let abPerpendicular = Vector3.cross(ab, abc)
    if Vector3.dot(abPerpendicular, ao) > .zero {
        simplex = [b, a]
        return _handleContactLine(&simplex,
                                  direction: &direction,
                                  tolerance: tolerance)
    }

    if Vector3.dot(abc, ao) > .zero {
        direction = abc
    } else {
        simplex = [b, c, a]
        direction = -abc
    }
    return direction.lengthSquared <= tolerance * tolerance
}

private func _handleContactTetrahedron(
    _ simplex: inout [_ContactSupportVertex],
    direction: inout Vector3,
    tolerance: Scalar
) -> Bool {
    let a = simplex[3]
    let b = simplex[2]
    let c = simplex[1]
    let d = simplex[0]

    if _outsideContactFace(a, b, c, opposite: d,
                           simplex: &simplex,
                           direction: &direction,
                           tolerance: tolerance) {
        return false
    }
    if _outsideContactFace(a, c, d, opposite: b,
                           simplex: &simplex,
                           direction: &direction,
                           tolerance: tolerance) {
        return false
    }
    if _outsideContactFace(a, d, b, opposite: c,
                           simplex: &simplex,
                           direction: &direction,
                           tolerance: tolerance) {
        return false
    }
    return true
}

private func _outsideContactFace(
    _ a: _ContactSupportVertex,
    _ b: _ContactSupportVertex,
    _ c: _ContactSupportVertex,
    opposite d: _ContactSupportVertex,
    simplex: inout [_ContactSupportVertex],
    direction: inout Vector3,
    tolerance: Scalar
) -> Bool {
    var normal = Vector3.cross(b.point - a.point, c.point - a.point)
    var face = [c, b, a]
    if Vector3.dot(normal, d.point - a.point) > .zero {
        normal = -normal
        face = [b, c, a]
    }

    if Vector3.dot(normal, -a.point) > tolerance {
        simplex = face
        direction = normal
        return true
    }
    return false
}

private func _epaContact(
    _ a: any _SupportMap,
    _ b: _SweepTransformedSupport,
    simplex: [_ContactSupportVertex],
    tolerance: Scalar
) -> ContactManifold? {
    guard simplex.count == 4 else { return nil }

    var vertices = simplex
    var faces = [
        _makeContactFace(0, 1, 2, vertices: vertices, tolerance: tolerance),
        _makeContactFace(0, 3, 1, vertices: vertices, tolerance: tolerance),
        _makeContactFace(0, 2, 3, vertices: vertices, tolerance: tolerance),
        _makeContactFace(1, 3, 2, vertices: vertices, tolerance: tolerance),
    ].compactMap { $0 }
    guard faces.count == 4 else { return nil }

    for _ in 0..<_contactIterationLimit {
        guard let closestIndex = faces.indices.min(by: {
            faces[$0].distance < faces[$1].distance
        }) else { return nil }
        let closestFace = faces[closestIndex]
        let support = _contactSupport(a, b,
                                      direction: closestFace.normal)
        let supportDistance = Vector3.dot(support.point,
                                          closestFace.normal)
        let duplicate = vertices.contains {
            ($0.point - support.point).lengthSquared <= tolerance * tolerance
        }
        if duplicate || supportDistance - closestFace.distance <= tolerance {
            return _contactFromFace(closestFace, vertices: vertices,
                                    tolerance: tolerance)
        }

        let newIndex = vertices.count
        vertices.append(support)
        var boundary: [_ContactEdge] = []
        var retained: [_ContactFace] = []
        retained.reserveCapacity(faces.count)

        for face in faces {
            let visible = Vector3.dot(
                face.normal,
                support.point - vertices[face.a].point) > tolerance
            if visible {
                _addContactBoundaryEdge(.init(a: face.a, b: face.b),
                                        to: &boundary)
                _addContactBoundaryEdge(.init(a: face.b, b: face.c),
                                        to: &boundary)
                _addContactBoundaryEdge(.init(a: face.c, b: face.a),
                                        to: &boundary)
            } else {
                retained.append(face)
            }
        }

        for edge in boundary {
            if let face = _makeContactFace(edge.a, edge.b, newIndex,
                                           vertices: vertices,
                                           tolerance: tolerance) {
                retained.append(face)
            }
        }
        faces = retained
        if faces.isEmpty { return nil }
    }

    guard let closest = faces.min(by: { $0.distance < $1.distance }) else {
        return nil
    }
    return _contactFromFace(closest, vertices: vertices,
                            tolerance: tolerance)
}

private func _makeContactFace(
    _ a: Int,
    _ b: Int,
    _ c: Int,
    vertices: [_ContactSupportVertex],
    tolerance: Scalar
) -> _ContactFace? {
    var b = b
    var c = c
    var normal = Vector3.cross(vertices[b].point - vertices[a].point,
                               vertices[c].point - vertices[a].point)
    let length = normal.length
    guard length > tolerance else { return nil }
    normal /= length

    var distance = Vector3.dot(normal, vertices[a].point)
    if distance < .zero {
        swap(&b, &c)
        normal = -normal
        distance = -distance
    }
    return _ContactFace(a: a, b: b, c: c,
                        normal: normal, distance: distance)
}

private func _addContactBoundaryEdge(
    _ edge: _ContactEdge,
    to boundary: inout [_ContactEdge]
) {
    if let reverseIndex = boundary.firstIndex(of: .init(a: edge.b,
                                                        b: edge.a)) {
        boundary.remove(at: reverseIndex)
    } else {
        boundary.append(edge)
    }
}

private func _contactFromFace(
    _ face: _ContactFace,
    vertices: [_ContactSupportVertex],
    tolerance: Scalar
) -> ContactManifold? {
    let a = vertices[face.a]
    let b = vertices[face.b]
    let c = vertices[face.c]
    let closestPoint = face.normal * face.distance
    guard let weights = _contactBarycentric(closestPoint,
                                            a.point,
                                            b.point,
                                            c.point,
                                            tolerance: tolerance) else {
        return nil
    }

    let pointOnA = a.pointOnA * weights.x +
        b.pointOnA * weights.y + c.pointOnA * weights.z
    let pointOnB = a.pointOnB * weights.x +
        b.pointOnB * weights.y + c.pointOnB * weights.z
    return ContactManifold(Contact(pointOnA: pointOnA,
                                   pointOnB: pointOnB,
                                   normal: face.normal,
                                   penetrationDepth: Swift.max(face.distance,
                                                               .zero)))
}

private func _contactBarycentric(
    _ point: Vector3,
    _ a: Vector3,
    _ b: Vector3,
    _ c: Vector3,
    tolerance: Scalar
) -> Vector3? {
    let v0 = b - a
    let v1 = c - a
    let v2 = point - a
    let d00 = Vector3.dot(v0, v0)
    let d01 = Vector3.dot(v0, v1)
    let d11 = Vector3.dot(v1, v1)
    let d20 = Vector3.dot(v2, v0)
    let d21 = Vector3.dot(v2, v1)
    let denominator = d00 * d11 - d01 * d01
    guard abs(denominator) > tolerance * tolerance else { return nil }

    let v = (d11 * d20 - d01 * d21) / denominator
    let w = (d00 * d21 - d01 * d20) / denominator
    let u = Scalar(1) - v - w
    let clamped = Vector3(Swift.max(u, .zero),
                          Swift.max(v, .zero),
                          Swift.max(w, .zero))
    let total = clamped.x + clamped.y + clamped.z
    guard total > tolerance else { return nil }
    return clamped / total
}

private func _fallbackContact(
    _ a: any _SupportMap,
    _ b: _SweepTransformedSupport,
    direction: Vector3,
    tolerance: Scalar
) -> ContactManifold? {
    let centerDirection = b.center - a.center
    let normal: Vector3
    if centerDirection.lengthSquared > tolerance * tolerance {
        normal = centerDirection.normalized()
    } else if direction.lengthSquared > tolerance * tolerance {
        normal = direction.normalized()
    } else {
        normal = Vector3(1, 0, 0)
    }

    let pointOnA = a.support(normal)
    let pointOnB = b.support(-normal)
    let depth = Vector3.dot(pointOnA - pointOnB, normal)
    guard depth >= -tolerance else { return nil }
    return ContactManifold(Contact(pointOnA: pointOnA,
                                   pointOnB: pointOnB,
                                   normal: normal,
                                   penetrationDepth: Swift.max(depth, .zero)))
}

private func _contactPerpendicular(to vector: Vector3) -> Vector3 {
    let axis: Vector3
    if abs(vector.x) <= abs(vector.y) && abs(vector.x) <= abs(vector.z) {
        axis = Vector3(1, 0, 0)
    } else if abs(vector.y) <= abs(vector.z) {
        axis = Vector3(0, 1, 0)
    } else {
        axis = Vector3(0, 0, 1)
    }
    return Vector3.cross(vector, axis).normalized()
}

/// Expands compound operands and aggregates transformed leaf contacts through
/// the active registry. At least one operand must be a compound.
func _compoundLeafContactManifold(
    _ a: any CollisionPrimitive,
    _ b: any CollisionPrimitive,
    frame: Transform,
    using contactManifold: (any CollisionPrimitive,
                            any CollisionPrimitive,
                            Transform) -> ContactManifold?
) -> ContactManifold? {
    guard a.isValid && b.isValid else { return nil }

    let childrenA = _contactLeaves(of: a)
    let childrenB = _contactLeaves(of: b)
    let childrenBInA = childrenB.map { child in
        (child: child, bounds: child.bounds.applying(frame))
    }
    var contacts: [Contact] = []

    for (indexA, childA) in childrenA.enumerated() {
        let inverseChildTransform = childA.transform.inverted()
        for (indexB, childBInA) in childrenBInA.enumerated() {
            if _contactBoundsAreSeparated(childA.bounds,
                                          childBInA.bounds) {
                continue
            }

            let childB = childBInA.child
            let childFrame = childB.transform * frame * inverseChildTransform
            guard let leafManifold = contactManifold(childA.primitive,
                                                      childB.primitive,
                                                      childFrame) else {
                continue
            }

            for contact in leafManifold.contacts {
                contacts.append(Contact(
                    pointOnA: contact.pointOnA.applying(childA.transform),
                    pointOnB: contact.pointOnB.applying(childA.transform),
                    normal: contact.normal
                        .applying(childA.transform.orientation)
                        .normalized(),
                    penetrationDepth: contact.penetrationDepth,
                    featureID: _compoundContactFeature(indexA,
                                                       indexB,
                                                       contact.featureID)))
            }
        }
    }
    return contacts.isEmpty ? nil : ContactManifold(contacts: contacts)
}

private func _contactLeaves(
    of primitive: any CollisionPrimitive
) -> [CompoundPrimitive.Child] {
    let children: [CompoundPrimitive.Child]
    if let compound = primitive as? CompoundPrimitive {
        children = compound.flattenedChildren()
    } else {
        children = [CompoundPrimitive.Child(primitive)]
    }
    return children.filter { $0.primitive.isValid }
}

private func _contactBoundsAreSeparated(_ a: AABB, _ b: AABB) -> Bool {
    !a.isNull && !b.isNull && !a.intersects(b)
}

private func _compoundContactFeature(
    _ indexA: Int,
    _ indexB: Int,
    _ childFeature: ContactFeatureID
) -> ContactFeatureID {
    // Leaf features can already occupy all 64 bits (mesh/mesh triangle pairs).
    // Use fixed integer mixing, independent of Swift's randomized Hasher. For
    // a fixed leaf pair this is a permutation of the full child feature ID.
    func mix(_ value: UInt64) -> UInt64 {
        var value = value
        value = (value ^ (value >> 30)) &* 0xbf58_476d_1ce4_e5b9
        value = (value ^ (value >> 27)) &* 0x94d0_49bb_1331_11eb
        return value ^ (value >> 31)
    }
    let a = mix(UInt64(truncatingIfNeeded: indexA) &+ 0x9e37_79b9_7f4a_7c15)
    let pair = mix(a ^ UInt64(truncatingIfNeeded: indexB))
    return ContactFeatureID(mix(pair ^ childFeature.rawValue))
}

private func _meshContactFeature(_ indexA: Int,
                                 _ indexB: Int) -> ContactFeatureID {
    ContactFeatureID(
        (UInt64(truncatingIfNeeded: indexA) & 0xffff_ffff) << 32 |
        (UInt64(truncatingIfNeeded: indexB) & 0xffff_ffff))
}

private func _contactTransformedTriangle(_ triangle: Triangle,
                                         by transform: Transform) -> Triangle {
    Triangle(triangle.p0.applying(transform),
             triangle.p1.applying(transform),
             triangle.p2.applying(transform))
}

private func _coplanarTriangleContactPoint(
    _ a: Triangle,
    _ b: Triangle
) -> Vector3? {
    let verticesA = [a.p0, a.p1, a.p2]
    let verticesB = [b.p0, b.p1, b.p2]
    var candidates: [Vector3] = []

    for point in verticesA where _triangleContains(point, triangle: b) {
        _appendUniqueContactPoint(point, to: &candidates)
    }
    for point in verticesB where _triangleContains(point, triangle: a) {
        _appendUniqueContactPoint(point, to: &candidates)
    }

    let dropAxis = _dominantAxis(a.normal)
    for edgeA in _triangleEdges(a) {
        for edgeB in _triangleEdges(b) {
            if let point = _coplanarSegmentIntersection(edgeA.0,
                                                        edgeA.1,
                                                        edgeB.0,
                                                        edgeB.1,
                                                        dropAxis: dropAxis) {
                _appendUniqueContactPoint(point, to: &candidates)
            }
        }
    }

    guard candidates.isEmpty == false else { return nil }
    return candidates.reduce(Vector3.zero, +) / Scalar(candidates.count)
}

private func _triangleContains(_ point: Vector3,
                               triangle: Triangle) -> Bool {
    guard let weights = triangle.barycentric(at: point) else { return false }
    return weights.x >= -_contactTolerance &&
        weights.y >= -_contactTolerance &&
        weights.z >= -_contactTolerance
}

private func _appendUniqueContactPoint(_ point: Vector3,
                                       to points: inout [Vector3]) {
    let toleranceSquared = _contactTolerance * _contactTolerance
    if points.contains(where: { ($0 - point).lengthSquared <= toleranceSquared }) {
        return
    }
    points.append(point)
}

private func _triangleEdges(_ triangle: Triangle) -> [(Vector3, Vector3)] {
    [(triangle.p0, triangle.p1),
     (triangle.p1, triangle.p2),
     (triangle.p2, triangle.p0)]
}

private func _dominantAxis(_ vector: Vector3) -> Int {
    let absolute = Vector3(abs(vector.x), abs(vector.y), abs(vector.z))
    if absolute.x >= absolute.y && absolute.x >= absolute.z { return 0 }
    if absolute.y >= absolute.z { return 1 }
    return 2
}

private func _coplanarSegmentIntersection(
    _ p0: Vector3,
    _ p1: Vector3,
    _ q0: Vector3,
    _ q1: Vector3,
    dropAxis: Int
) -> Vector3? {
    let p = _projectContactPoint(p0, dropping: dropAxis)
    let r = _projectContactPoint(p1 - p0, dropping: dropAxis)
    let q = _projectContactPoint(q0, dropping: dropAxis)
    let s = _projectContactPoint(q1 - q0, dropping: dropAxis)
    let denominator = _cross2(r, s)
    guard abs(denominator) > _contactTolerance else { return nil }

    let qMinusP = (q.0 - p.0, q.1 - p.1)
    let t = _cross2(qMinusP, s) / denominator
    let u = _cross2(qMinusP, r) / denominator
    guard t >= -_contactTolerance,
          t <= Scalar(1) + _contactTolerance,
          u >= -_contactTolerance,
          u <= Scalar(1) + _contactTolerance
    else { return nil }
    return p0 + (p1 - p0) * t.clamp(min: .zero, max: Scalar(1))
}

private func _projectContactPoint(
    _ point: Vector3,
    dropping axis: Int
) -> (Scalar, Scalar) {
    switch axis {
    case 0: return (point.y, point.z)
    case 1: return (point.x, point.z)
    default: return (point.x, point.y)
    }
}

private func _cross2(_ a: (Scalar, Scalar),
                     _ b: (Scalar, Scalar)) -> Scalar {
    a.0 * b.1 - a.1 * b.0
}

private func _trianglePlaneContactPoint(
    _ triangle: Triangle,
    distances: [Scalar],
    tolerance: Scalar
) -> Vector3? {
    let vertices = [triangle.p0, triangle.p1, triangle.p2]
    var points: [Vector3] = []
    for index in vertices.indices where abs(distances[index]) <= tolerance {
        _appendUniqueContactPoint(vertices[index], to: &points)
    }

    for (indexA, indexB) in [(0, 1), (1, 2), (2, 0)] {
        let distanceA = distances[indexA]
        let distanceB = distances[indexB]
        if (distanceA < -tolerance && distanceB > tolerance) ||
            (distanceA > tolerance && distanceB < -tolerance) {
            let t = distanceA / (distanceA - distanceB)
            let point = vertices[indexA] +
                (vertices[indexB] - vertices[indexA]) * t
            _appendUniqueContactPoint(point, to: &points)
        }
    }

    guard points.isEmpty == false else { return nil }
    return points.reduce(Vector3.zero, +) / Scalar(points.count)
}
