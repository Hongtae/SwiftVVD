//
//  File: CollisionSweep.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

private let _sweepEpsilon: Scalar = {
    MemoryLayout<Scalar>.size > MemoryLayout<Float32>.size
        ? Scalar(1.0e-9)
        : Scalar(1.0e-5)
}()

extension CollisionAlgorithms {
    /// Analytic translational sweep for two spheres.
    static func sphereTimeOfImpact(_ a: Sphere,
                                   _ b: Sphere,
                                   frame: Transform,
                                   translation: Vector3) -> TimeOfImpact? {
        guard a.isValid && b.isValid else { return nil }

        let centerB = b.center.applying(frame)
        let initialDelta = centerB - a.center
        let radius = a.radius + b.radius
        let separationSquared = initialDelta.lengthSquared
        if separationSquared <= radius * radius + _sweepEpsilon {
            let normal = _sweepNormal(initialDelta, fallback: translation)
            return TimeOfImpact(fraction: .zero,
                                pointOnA: a.center + normal * a.radius,
                                pointOnB: centerB - normal * b.radius,
                                normal: normal)
        }

        let speedSquared = translation.lengthSquared
        guard speedSquared > _sweepEpsilon else { return nil }

        let offset = a.center - centerB
        let projectedOffset = Vector3.dot(offset, translation)
        guard projectedOffset < .zero else { return nil }

        let constant = offset.lengthSquared - radius * radius
        let discriminant = projectedOffset * projectedOffset -
            speedSquared * constant
        guard discriminant >= .zero else { return nil }

        let fraction = (-projectedOffset - discriminant.squareRoot()) /
            speedSquared
        guard fraction >= -.ulpOfOne,
              fraction <= Scalar(1) + _sweepEpsilon
        else { return nil }

        let clampedFraction = fraction.clamp(min: .zero, max: Scalar(1))
        let centerA = a.center + translation * clampedFraction
        let normal = _sweepNormal(centerB - centerA,
                                  fallback: translation)
        return TimeOfImpact(fraction: clampedFraction,
                            pointOnA: centerA + normal * a.radius,
                            pointOnB: centerB - normal * b.radius,
                            normal: normal)
    }

    /// Analytic translational sweep for a sphere against a two-sided plane.
    static func spherePlaneTimeOfImpact(
        _ sphere: Sphere,
        _ staticPlane: StaticPlane,
        frame: Transform,
        translation: Vector3
    ) -> TimeOfImpact? {
        guard sphere.isValid && staticPlane.isValid else { return nil }

        let transformedNormal = staticPlane.plane.normal
            .applying(frame.orientation)
        let normalLength = transformedNormal.length
        guard normalLength > _sweepEpsilon else { return nil }

        let planeNormal = transformedNormal / normalLength
        let planeDistance = (staticPlane.plane.d -
            Vector3.dot(transformedNormal, frame.position)) / normalLength
        let signedDistance = Vector3.dot(planeNormal, sphere.center) +
            planeDistance
        let normal = signedDistance >= .zero ? -planeNormal : planeNormal
        let separation = abs(signedDistance) - sphere.radius

        if separation <= _sweepEpsilon {
            return TimeOfImpact(
                fraction: .zero,
                pointOnA: sphere.center + normal * sphere.radius,
                pointOnB: sphere.center - planeNormal * signedDistance,
                normal: normal)
        }

        let closingSpeed = Vector3.dot(translation, normal)
        guard closingSpeed > _sweepEpsilon else { return nil }

        let fraction = separation / closingSpeed
        guard fraction <= Scalar(1) + _sweepEpsilon else { return nil }

        let clampedFraction = fraction.clamp(min: .zero, max: Scalar(1))
        let center = sphere.center + translation * clampedFraction
        let impactDistance = Vector3.dot(planeNormal, center) + planeDistance
        return TimeOfImpact(
            fraction: clampedFraction,
            pointOnA: center + normal * sphere.radius,
            pointOnB: center - planeNormal * impactDistance,
            normal: normal)
    }

    /// Conservative advancement using GJK closest-point witnesses for two
    /// convex support maps.
    static func convexTimeOfImpact<A: _SupportMap, B: _SupportMap>(
        _ a: A,
        _ b: B,
        frame: Transform,
        translation: Vector3
    ) -> TimeOfImpact? {
        guard a.isSupportMappingValid && b.isSupportMappingValid,
              CollisionMotion(start: frame, translation: translation).isValid else {
            return nil
        }

        let transformedB = _SweepTransformedSupport(base: b, transform: frame)
        let scale = Swift.max(a.bounds.extents.length,
                              transformedB.bounds.extents.length)
        let tolerance = Swift.max(scale * _sweepDistanceEpsilon, Scalar.ulpOfOne * 32)
        var fraction = Scalar.zero
        var separatingNormal: Vector3?

        for _ in 0..<_sweepIterationLimit {
            let offset = translation * fraction
            let closest = _gjkClosestPoints(a,
                                            transformedB,
                                            offset: offset,
                                            tolerance: tolerance)
            if closest.distance <= tolerance {
                let fallback = transformedB.center - (a.center + offset)
                let normal = separatingNormal ?? _sweepNormal(
                    closest.pointOnB - closest.pointOnA,
                    fallback: fallback)
                if fraction <= .ulpOfOne {
                    return TimeOfImpact(
                        fraction: .zero,
                        pointOnA: a.support(normal),
                        pointOnB: transformedB.support(-normal),
                        normal: normal)
                }
                return TimeOfImpact(fraction: fraction,
                                    pointOnA: closest.pointOnA,
                                    pointOnB: closest.pointOnB,
                                    normal: normal)
            }

            let normal = (closest.pointOnB - closest.pointOnA) /
                closest.distance
            // The GJK witness distance is an upper bound until convergence.
            // Advance only across a separating support plane, whose gap is a
            // lower bound even when witness refinement stopped early.
            let gap = Vector3.dot(transformedB.support(-normal) - a.support(normal) - offset, normal)
            guard gap.isFinite, gap > .zero else { return nil }
            separatingNormal = normal
            let closingSpeed = Vector3.dot(translation, normal)
            guard closingSpeed.isFinite, closingSpeed > .zero else { return nil }

            let advance = gap / closingSpeed
            guard advance.isFinite, fraction + advance > fraction else { return nil }

            fraction += advance
            guard fraction <= Scalar(1) + _sweepDistanceEpsilon else {
                return nil
            }
            fraction = fraction.clamp(min: .zero, max: Scalar(1))
        }
        return nil
    }

    /// Analytic projection sweep for a convex support map against a two-sided
    /// plane.
    static func convexPlaneTimeOfImpact<A: _SupportMap>(
        _ primitive: A,
        _ staticPlane: StaticPlane,
        frame: Transform,
        translation: Vector3
    ) -> TimeOfImpact? {
        guard primitive.isSupportMappingValid && staticPlane.isValid else {
            return nil
        }

        let transformedNormal = staticPlane.plane.normal
            .applying(frame.orientation)
        let normalLength = transformedNormal.length
        guard normalLength > _sweepEpsilon else { return nil }

        let planeNormal = transformedNormal / normalLength
        let planeDistance = (staticPlane.plane.d -
            Vector3.dot(transformedNormal, frame.position)) / normalLength
        let minimumPoint = primitive.support(-planeNormal)
        let maximumPoint = primitive.support(planeNormal)
        let minimumDistance = Vector3.dot(planeNormal, minimumPoint) +
            planeDistance
        let maximumDistance = Vector3.dot(planeNormal, maximumPoint) +
            planeDistance

        let normal: Vector3
        let point: Vector3
        let separation: Scalar
        if minimumDistance <= _sweepEpsilon &&
            maximumDistance >= -_sweepEpsilon {
            let centerDistance = Vector3.dot(planeNormal, primitive.center) +
                planeDistance
            normal = centerDistance >= .zero ? -planeNormal : planeNormal
            point = primitive.support(normal)
            separation = .zero
        } else if minimumDistance > .zero {
            normal = -planeNormal
            point = minimumPoint
            separation = minimumDistance
        } else {
            normal = planeNormal
            point = maximumPoint
            separation = -maximumDistance
        }

        if separation <= _sweepEpsilon {
            let signedDistance = Vector3.dot(planeNormal, point) + planeDistance
            return TimeOfImpact(
                fraction: .zero,
                pointOnA: point,
                pointOnB: point - planeNormal * signedDistance,
                normal: normal)
        }

        let closingSpeed = Vector3.dot(translation, normal)
        guard closingSpeed > _sweepEpsilon else { return nil }

        let fraction = separation / closingSpeed
        guard fraction <= Scalar(1) + _sweepDistanceEpsilon else { return nil }

        let clampedFraction = fraction.clamp(min: .zero, max: Scalar(1))
        let pointOnA = point + translation * clampedFraction
        let signedDistance = Vector3.dot(planeNormal, pointOnA) + planeDistance
        return TimeOfImpact(
            fraction: clampedFraction,
            pointOnA: pointOnA,
            pointOnB: pointOnA - planeNormal * signedDistance,
            normal: normal)
    }

    /// Sweeps a convex support map through mesh-local BVH candidates.
    static func convexMeshTimeOfImpact<
        A: CollisionPrimitive & _SupportMap
    >(
        _ primitive: A,
        _ mesh: TriangleMesh,
        frame: Transform,
        translation: Vector3
    ) -> TimeOfImpact? {
        guard primitive.isSupportMappingValid && mesh.isValid else {
            return nil
        }

        let inverseFrame = frame.inverted()
        let queryBounds = _sweptBounds(
            primitive.bounds,
            transformedBy: inverseFrame,
            translation: translation.applying(inverseFrame.orientation))
        var earliest: TimeOfImpact?

        mesh.queryTriangles(overlapping: queryBounds) { index in
            let triangle = mesh.triangle(at: index)
            guard let impact = convexTimeOfImpact(
                primitive,
                triangle,
                frame: frame,
                translation: translation)
            else { return true }

            if earliest == nil || impact.fraction < earliest!.fraction {
                earliest = impact
            }
            return earliest?.fraction != .zero
        }
        return earliest
    }

    /// Sweeps every valid mesh triangle against a two-sided plane.
    static func meshPlaneTimeOfImpact(
        _ mesh: TriangleMesh,
        _ staticPlane: StaticPlane,
        frame: Transform,
        translation: Vector3
    ) -> TimeOfImpact? {
        guard mesh.isValid && staticPlane.isValid else { return nil }

        var earliest: TimeOfImpact?
        for index in 0..<mesh.triangleCount {
            guard let impact = convexPlaneTimeOfImpact(
                mesh.triangle(at: index),
                staticPlane,
                frame: frame,
                translation: translation)
            else { continue }

            if earliest == nil || impact.fraction < earliest!.fraction {
                earliest = impact
                if impact.fraction == .zero { break }
            }
        }
        return earliest
    }

    /// Sweeps two triangle meshes after pruning both triangle sets through
    /// their storage-defined bounds queries.
    static func meshTimeOfImpact(
        _ a: TriangleMesh,
        _ b: TriangleMesh,
        frame: Transform,
        translation: Vector3
    ) -> TimeOfImpact? {
        guard a.isValid && b.isValid else { return nil }

        let inverseFrame = frame.inverted()
        var boundsBRelativeToA = b.bounds.applying(frame)
        boundsBRelativeToA.combine(b.bounds.applying(Transform(
            orientation: frame.orientation,
            position: frame.position - translation)))

        var earliest: TimeOfImpact?
        a.queryTriangles(overlapping: boundsBRelativeToA) { indexA in
            let triangleA = a.triangle(at: indexA)
            let boundsAInB = _sweptBounds(
                triangleA.bounds,
                transformedBy: inverseFrame,
                translation: translation.applying(inverseFrame.orientation))

            b.queryTriangles(overlapping: boundsAInB) { indexB in
                guard let impact = convexTimeOfImpact(
                    triangleA,
                    b.triangle(at: indexB),
                    frame: frame,
                    translation: translation)
                else { return true }

                if earliest == nil || impact.fraction < earliest!.fraction {
                    earliest = impact
                }
                return earliest?.fraction != .zero
            }
            return earliest?.fraction != .zero
        }
        return earliest
    }
}

extension CollisionAlgorithmRegistry {
    mutating func registerBuiltinSweepAlgorithms() {
        registerConvexSweep(Box.self, Box.self)
        registerConvexSweep(Box.self, Sphere.self)
        registerConvexSweep(Box.self, Capsule.self)
        registerConvexSweep(Box.self, Cylinder.self)
        registerConvexSweep(Box.self, Cone.self)
        registerConvexSweep(Box.self, ConvexHull.self)

        registerConvexSweep(Sphere.self, Capsule.self)
        registerConvexSweep(Sphere.self, Cylinder.self)
        registerConvexSweep(Sphere.self, Cone.self)
        registerConvexSweep(Sphere.self, ConvexHull.self)

        registerConvexSweep(Capsule.self, Capsule.self)
        registerConvexSweep(Capsule.self, Cylinder.self)
        registerConvexSweep(Capsule.self, Cone.self)
        registerConvexSweep(Capsule.self, ConvexHull.self)

        registerConvexSweep(Cylinder.self, Cylinder.self)
        registerConvexSweep(Cylinder.self, Cone.self)
        registerConvexSweep(Cylinder.self, ConvexHull.self)

        registerConvexSweep(Cone.self, Cone.self)
        registerConvexSweep(Cone.self, ConvexHull.self)
        registerConvexSweep(ConvexHull.self, ConvexHull.self)

        registerConvexPlaneSweep(Box.self)
        registerConvexPlaneSweep(Sphere.self)
        registerConvexPlaneSweep(Capsule.self)
        registerConvexPlaneSweep(Cylinder.self)
        registerConvexPlaneSweep(Cone.self)
        registerConvexPlaneSweep(ConvexHull.self)

        registerConvexMeshSweep(Box.self)
        registerConvexMeshSweep(Sphere.self)
        registerConvexMeshSweep(Capsule.self)
        registerConvexMeshSweep(Cylinder.self)
        registerConvexMeshSweep(Cone.self)
        registerConvexMeshSweep(ConvexHull.self)

        registerSymmetricSweep(TriangleMesh.self, StaticPlane.self) {
            mesh, plane, frame, translation in
            CollisionAlgorithms.meshPlaneTimeOfImpact(
                mesh,
                plane,
                frame: frame,
                translation: translation)
        }
        registerSymmetricSweep(TriangleMesh.self, TriangleMesh.self) {
            a, b, frame, translation in
            CollisionAlgorithms.meshTimeOfImpact(
                a,
                b,
                frame: frame,
                translation: translation)
        }

        registerSymmetricSweep(Sphere.self, Sphere.self) {
            a, b, frame, translation in
            CollisionAlgorithms.sphereTimeOfImpact(a,
                                                   b,
                                                   frame: frame,
                                                   translation: translation)
        }
        registerSymmetricSweep(Sphere.self, StaticPlane.self) {
            sphere, plane, frame, translation in
            CollisionAlgorithms.spherePlaneTimeOfImpact(
                sphere,
                plane,
                frame: frame,
                translation: translation)
        }
    }

    private mutating func registerConvexSweep<
        A: CollisionPrimitive & _SupportMap,
        B: CollisionPrimitive & _SupportMap
    >(_ a: A.Type, _ b: B.Type) {
        registerSymmetricSweep(a, b) { a, b, frame, translation in
            CollisionAlgorithms.convexTimeOfImpact(a,
                                                   b,
                                                   frame: frame,
                                                   translation: translation)
        }
    }

    private mutating func registerConvexPlaneSweep<
        A: CollisionPrimitive & _SupportMap
    >(_ primitive: A.Type) {
        registerSymmetricSweep(primitive, StaticPlane.self) {
            primitive, plane, frame, translation in
            CollisionAlgorithms.convexPlaneTimeOfImpact(
                primitive,
                plane,
                frame: frame,
                translation: translation)
        }
    }

    private mutating func registerConvexMeshSweep<
        A: CollisionPrimitive & _SupportMap
    >(_ primitive: A.Type) {
        registerSymmetricSweep(primitive, TriangleMesh.self) {
            primitive, mesh, frame, translation in
            CollisionAlgorithms.convexMeshTimeOfImpact(
                primitive,
                mesh,
                frame: frame,
                translation: translation)
        }
    }
}

/// Expands compound operands into leaf pairs while preserving ordered registry
/// dispatch. Leaf results are transformed back into compound A's start-local
/// space before the earliest impact is selected.
func _compoundLeafTimeOfImpact(
    _ a: any CollisionPrimitive,
    _ b: any CollisionPrimitive,
    frame: Transform,
    translation: Vector3,
    using timeOfImpact: (any CollisionPrimitive,
                         any CollisionPrimitive,
                         Transform,
                         Vector3) -> TimeOfImpact?
) -> TimeOfImpact? {
    guard a.isValid && b.isValid else { return nil }

    let childrenA = _sweepLeaves(of: a)
    let childrenB = _sweepLeaves(of: b)
    let childrenBInA = childrenB.map { child in
        (child: child, bounds: child.bounds.applying(frame))
    }
    var earliest: TimeOfImpact?

    for childA in childrenA {
        let sweptChildBounds = _translatedSweepBounds(childA.bounds,
                                                       by: translation)
        let inverseChildTransform = childA.transform.inverted()
        let childTranslation = translation
            .applying(inverseChildTransform.orientation)

        for childBInA in childrenBInA {
            if _finiteBoundsAreSeparated(sweptChildBounds,
                                         childBInA.bounds) {
                continue
            }

            let childB = childBInA.child
            let childFrame = childB.transform * frame * inverseChildTransform
            guard let impact = timeOfImpact(childA.primitive,
                                             childB.primitive,
                                             childFrame,
                                             childTranslation)
            else { continue }

            let transformedImpact = TimeOfImpact(
                fraction: impact.fraction,
                pointOnA: impact.pointOnA.applying(childA.transform),
                pointOnB: impact.pointOnB.applying(childA.transform),
                normal: impact.normal
                    .applying(childA.transform.orientation)
                    .normalized())
            if earliest == nil || transformedImpact.fraction < earliest!.fraction {
                earliest = transformedImpact
            }
            if earliest?.fraction == .zero { return earliest }
        }
    }
    return earliest
}

private func _sweepLeaves(
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

private func _sweptBounds(_ bounds: AABB,
                          transformedBy transform: Transform,
                          translation: Vector3) -> AABB {
    guard bounds.isNull == false else { return .null }
    let startBounds = bounds.applying(transform)
    let endTransform = Transform(
        orientation: transform.orientation,
        position: transform.position + translation)
    return startBounds.combining(bounds.applying(endTransform))
}

private func _translatedSweepBounds(_ bounds: AABB,
                                    by translation: Vector3) -> AABB {
    guard bounds.isNull == false else { return .null }
    return bounds.combining(AABB(min: bounds.min + translation,
                                 max: bounds.max + translation))
}

private func _finiteBoundsAreSeparated(_ a: AABB, _ b: AABB) -> Bool {
    !a.isNull && !b.isNull && !a.intersects(b)
}

struct _SweepTransformedSupport: _SupportMap {
    let base: any _SupportMap
    let transform: Transform

    var isSupportMappingValid: Bool { base.isSupportMappingValid }

    var center: Vector3 { base.center.applying(transform) }
    var bounds: AABB { base.bounds.applying(transform) }

    func support(_ direction: Vector3) -> Vector3 {
        let localDirection = direction
            .applying(transform.orientation.conjugated())
        return base.support(localDirection).applying(transform)
    }
}

private struct _SweepSupportVertex {
    let point: Vector3
    let pointOnA: Vector3
    let pointOnB: Vector3
}

struct _SweepClosestResult {
    let pointOnA: Vector3
    let pointOnB: Vector3
    let distance: Scalar
}

private struct _SweepSimplexSolution {
    let point: Vector3
    let weights: [Scalar]
}

private let _sweepDistanceEpsilon: Scalar = {
    MemoryLayout<Scalar>.size > MemoryLayout<Float32>.size
        ? Scalar(1.0e-8)
        : Scalar(1.0e-4)
}()

private let _sweepWeightEpsilon: Scalar = {
    MemoryLayout<Scalar>.size > MemoryLayout<Float32>.size
        ? Scalar(1.0e-12)
        : Scalar(1.0e-6)
}()

private let _sweepIterationLimit = 48

func _gjkClosestPoints(
    _ a: any _SupportMap,
    _ b: _SweepTransformedSupport,
    offset: Vector3,
    tolerance: Scalar
) -> _SweepClosestResult {
    var direction = b.center - (a.center + offset)
    if direction.lengthSquared <= tolerance * tolerance {
        direction = Vector3(1, 0, 0)
    }

    var simplex = [_sweepSupport(a, b, offset: offset, direction: direction)]
    var solution = _reduceSweepSimplex(&simplex)

    for _ in 0..<_sweepIterationLimit {
        let distanceSquared = solution.point.lengthSquared
        if distanceSquared <= tolerance * tolerance { break }

        let searchDirection = -solution.point
        let vertex = _sweepSupport(a,
                                   b,
                                   offset: offset,
                                   direction: searchDirection)
        let duplicate = simplex.contains {
            ($0.point - vertex.point).lengthSquared <= tolerance * tolerance
        }
        if duplicate { break }

        let supportGap = Vector3.dot(vertex.point, searchDirection) +
            distanceSquared
        // supportGap is a squared-distance quantity. Scaling by the actual
        // search length avoids terminating with sqrt(tolerance) position error
        // when a motion sweep approaches a small positive separation.
        if supportGap <= tolerance *
            Swift.max(searchDirection.length, tolerance) {
            break
        }

        simplex.append(vertex)
        solution = _reduceSweepSimplex(&simplex)
    }

    var pointOnA = Vector3.zero
    var pointOnB = Vector3.zero
    for (vertex, weight) in zip(simplex, solution.weights) {
        pointOnA += vertex.pointOnA * weight
        pointOnB += vertex.pointOnB * weight
    }
    return _SweepClosestResult(pointOnA: pointOnA,
                               pointOnB: pointOnB,
                               distance: (pointOnB - pointOnA).length)
}

private func _sweepSupport(_ a: any _SupportMap,
                           _ b: _SweepTransformedSupport,
                           offset: Vector3,
                           direction: Vector3) -> _SweepSupportVertex {
    let pointOnA = a.support(direction) + offset
    let pointOnB = b.support(-direction)
    return _SweepSupportVertex(point: pointOnA - pointOnB,
                               pointOnA: pointOnA,
                               pointOnB: pointOnB)
}

private func _reduceSweepSimplex(
    _ simplex: inout [_SweepSupportVertex]
) -> _SweepSimplexSolution {
    var points = simplex.map(\.point)
    // Barycentric weights are invariant under uniform scaling. Normalize the
    // simplex before comparing squared lengths, areas, and volumes with the
    // dimensionless degeneracy thresholds; retain original witness coordinates.
    let scale = points.reduce(Scalar.zero) {
        Swift.max($0, Swift.max(abs($1.x), abs($1.y), abs($1.z)))
    }
    if scale.isFinite && scale > .zero {
        points = points.map { $0 / scale }
    }
    let rawSolution: _SweepSimplexSolution
    switch points.count {
    case 1:
        rawSolution = _SweepSimplexSolution(point: points[0], weights: [1])
    case 2:
        rawSolution = _closestOnSegment(points[0], points[1])
    case 3:
        rawSolution = _closestOnTriangle(points[0], points[1], points[2])
    default:
        rawSolution = _closestOnTetrahedron(points[0],
                                            points[1],
                                            points[2],
                                            points[3])
    }

    var reduced: [_SweepSupportVertex] = []
    var weights: [Scalar] = []
    for (index, weight) in rawSolution.weights.enumerated()
    where weight > _sweepWeightEpsilon {
        reduced.append(simplex[index])
        weights.append(weight)
    }
    if reduced.isEmpty {
        let index = points.indices.min {
            points[$0].lengthSquared < points[$1].lengthSquared
        } ?? 0
        reduced = [simplex[index]]
        weights = [1]
    } else {
        let total = weights.reduce(.zero, +)
        weights = weights.map { $0 / total }
    }
    simplex = reduced

    let point = zip(simplex, weights).reduce(Vector3.zero) {
        $0 + $1.0.point * $1.1
    }
    return _SweepSimplexSolution(point: point, weights: weights)
}

private func _closestOnSegment(_ a: Vector3,
                               _ b: Vector3) -> _SweepSimplexSolution {
    let edge = b - a
    let lengthSquared = edge.lengthSquared
    guard lengthSquared > _sweepWeightEpsilon else {
        return _SweepSimplexSolution(point: a, weights: [1, 0])
    }
    let t = (-Vector3.dot(a, edge) / lengthSquared)
        .clamp(min: .zero, max: Scalar(1))
    return _SweepSimplexSolution(point: a + edge * t,
                                 weights: [1 - t, t])
}

private func _closestOnTriangle(_ a: Vector3,
                                _ b: Vector3,
                                _ c: Vector3) -> _SweepSimplexSolution {
    let ab = b - a
    let ac = c - a
    let ap = -a
    let d1 = Vector3.dot(ab, ap)
    let d2 = Vector3.dot(ac, ap)
    if d1 <= .zero && d2 <= .zero {
        return _SweepSimplexSolution(point: a, weights: [1, 0, 0])
    }

    let bp = -b
    let d3 = Vector3.dot(ab, bp)
    let d4 = Vector3.dot(ac, bp)
    if d3 >= .zero && d4 <= d3 {
        return _SweepSimplexSolution(point: b, weights: [0, 1, 0])
    }

    let vc = d1 * d4 - d3 * d2
    if vc <= .zero && d1 >= .zero && d3 <= .zero {
        let v = d1 / (d1 - d3)
        return _SweepSimplexSolution(point: a + ab * v,
                                     weights: [1 - v, v, 0])
    }

    let cp = -c
    let d5 = Vector3.dot(ab, cp)
    let d6 = Vector3.dot(ac, cp)
    if d6 >= .zero && d5 <= d6 {
        return _SweepSimplexSolution(point: c, weights: [0, 0, 1])
    }

    let vb = d5 * d2 - d1 * d6
    if vb <= .zero && d2 >= .zero && d6 <= .zero {
        let w = d2 / (d2 - d6)
        return _SweepSimplexSolution(point: a + ac * w,
                                     weights: [1 - w, 0, w])
    }

    let va = d3 * d6 - d5 * d4
    if va <= .zero && d4 - d3 >= .zero && d5 - d6 >= .zero {
        let edge = c - b
        let w = (d4 - d3) / ((d4 - d3) + (d5 - d6))
        return _SweepSimplexSolution(point: b + edge * w,
                                     weights: [0, 1 - w, w])
    }

    let denominator = va + vb + vc
    guard abs(denominator) > _sweepWeightEpsilon else {
        return _closestDegenerateTriangle(a, b, c)
    }
    let inverse = Scalar(1) / denominator
    let v = vb * inverse
    let w = vc * inverse
    let u = 1 - v - w
    return _SweepSimplexSolution(point: a * u + b * v + c * w,
                                 weights: [u, v, w])
}

private func _closestDegenerateTriangle(
    _ a: Vector3,
    _ b: Vector3,
    _ c: Vector3
) -> _SweepSimplexSolution {
    let candidates = [
        _closestOnSegment(a, b),
        _closestOnSegment(a, c),
        _closestOnSegment(b, c),
    ]
    let index = candidates.indices.min {
        candidates[$0].point.lengthSquared < candidates[$1].point.lengthSquared
    } ?? 0
    switch index {
    case 0:
        return _SweepSimplexSolution(point: candidates[0].point,
                                     weights: [candidates[0].weights[0],
                                               candidates[0].weights[1], 0])
    case 1:
        return _SweepSimplexSolution(point: candidates[1].point,
                                     weights: [candidates[1].weights[0], 0,
                                               candidates[1].weights[1]])
    default:
        return _SweepSimplexSolution(point: candidates[2].point,
                                     weights: [0, candidates[2].weights[0],
                                               candidates[2].weights[1]])
    }
}

private func _closestOnTetrahedron(
    _ a: Vector3,
    _ b: Vector3,
    _ c: Vector3,
    _ d: Vector3
) -> _SweepSimplexSolution {
    let ad = a - d
    let bd = b - d
    let cd = c - d
    let target = -d
    let determinant = Vector3.dot(ad, Vector3.cross(bd, cd))
    if abs(determinant) > _sweepWeightEpsilon {
        let w0 = Vector3.dot(target, Vector3.cross(bd, cd)) / determinant
        let w1 = Vector3.dot(ad, Vector3.cross(target, cd)) / determinant
        let w2 = Vector3.dot(ad, Vector3.cross(bd, target)) / determinant
        let w3 = 1 - w0 - w1 - w2
        let weights = [w0, w1, w2, w3]
        if weights.allSatisfy({ $0 >= -_sweepWeightEpsilon }) {
            return _SweepSimplexSolution(point: .zero, weights: weights)
        }
    }

    let faces: [(indices: [Int], solution: _SweepSimplexSolution)] = [
        ([0, 1, 2], _closestOnTriangle(a, b, c)),
        ([0, 1, 3], _closestOnTriangle(a, b, d)),
        ([0, 2, 3], _closestOnTriangle(a, c, d)),
        ([1, 2, 3], _closestOnTriangle(b, c, d)),
    ]
    let faceIndex = faces.indices.min {
        faces[$0].solution.point.lengthSquared <
            faces[$1].solution.point.lengthSquared
    } ?? 0
    let face = faces[faceIndex]
    var weights = Array(repeating: Scalar.zero, count: 4)
    for (localIndex, vertexIndex) in face.indices.enumerated() {
        weights[vertexIndex] = face.solution.weights[localIndex]
    }
    return _SweepSimplexSolution(point: face.solution.point,
                                 weights: weights)
}

private func _sweepNormal(_ vector: Vector3,
                          fallback: Vector3) -> Vector3 {
    if vector.lengthSquared > _sweepEpsilon {
        return vector.normalized()
    }
    if fallback.lengthSquared > _sweepEpsilon {
        return fallback.normalized()
    }
    return Vector3(1, 0, 0)
}
