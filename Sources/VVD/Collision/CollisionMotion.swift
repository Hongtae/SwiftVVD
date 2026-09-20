//
//  CollisionMotion.swift
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

/// Constant translation and rotation over a normalized time interval [0, 1].
/// Translation moves the pivot; angular displacement is a world-space axis
/// multiplied by an angle in radians, and can describe more than one turn.
public struct CollisionMotion: Hashable, Sendable {
    public var start: Transform
    public var translation: Vector3
    public var angularDisplacement: Vector3
    public var localPivot: Vector3

    public init(start: Transform = .identity,
                translation: Vector3 = .zero,
                angularDisplacement: Vector3 = .zero,
                localPivot: Vector3 = .zero) {
        self.start = start
        self.translation = translation
        self.angularDisplacement = angularDisplacement
        self.localPivot = localPivot
    }

    public func transform(at fraction: Scalar) -> Transform {
        let angle = angularDisplacement.length * fraction
        var orientation = start.orientation
        if angle > .ulpOfOne {
            orientation = orientation.concatenating(
                Quaternion(angle: angle, axis: angularDisplacement)).normalized()
        }
        let pivot = localPivot.applying(start) + translation * fraction
        return Transform(orientation: orientation,
                         position: pivot - localPivot.applying(orientation))
    }

    /// Motion queries require finite values and a rigid, unit-quaternion frame.
    public var isValid: Bool {
        translation.length.isFinite && angularDisplacement.length.isFinite &&
            localPivot.length.isFinite && start.position.length.isFinite &&
            abs(start.orientation.lengthSquared - 1) <= Scalar.ulpOfOne.squareRoot() * 16
    }

    /// A conservative envelope of every intermediate orientation, not merely
    /// the union of endpoint bounds. Null bounds remain unconditional candidates.
    public func sweptBounds(of primitive: any CollisionPrimitive) -> AABB {
        guard isValid else { return .null }
        if let compound = primitive as? CompoundPrimitive,
           compound.flattenedChildren().contains(where: { $0.primitive.isValid && $0.primitive.bounds.isNull }) {
            return .null
        }
        let bounds = primitive.bounds
        guard !bounds.isNull else { return .null }
        if angularDisplacement == .zero {
            return bounds.applying(start).combining(bounds.applying(transform(at: 1)))
        }
        let radius = angularRadius(of: primitive)
        let extent = Vector3(radius, radius, radius)
        let pivot = localPivot.applying(start)
        return AABB(min: Vector3.minimum(pivot, pivot + translation) - extent,
                    max: Vector3.maximum(pivot, pivot + translation) + extent)
    }

    fileprivate func angularRadius(of primitive: any CollisionPrimitive) -> Scalar {
        let bounds = primitive.bounds
        guard !bounds.isNull else { return .infinity }
        let lower = bounds.min - localPivot
        let upper = bounds.max - localPivot
        let extent = Vector3(Swift.max(abs(lower.x), abs(upper.x)),
                             Swift.max(abs(lower.y), abs(upper.y)),
                             Swift.max(abs(lower.z), abs(upper.z)))
        return extent.length
    }

    fileprivate func child(_ transform: Transform) -> Self {
        Self(start: transform * start,
             translation: translation,
             angularDisplacement: angularDisplacement,
             localPivot: localPivot.applying(transform.inverted()))
    }
}

/// A motion sweep witness in world space. The normal points from A toward B.
public struct MotionSweepHit: Hashable, Sendable {
    public let fraction: Scalar
    public let pointOnA: Vector3
    public let pointOnB: Vector3
    public let normal: Vector3

    public init(fraction: Scalar, pointOnA: Vector3, pointOnB: Vector3,
                normal: Vector3) {
        self.fraction = fraction
        self.pointOnA = pointOnA
        self.pointOnB = pointOnB
        self.normal = normal
    }
}

/// Failure to establish separation is explicit; callers must not interpret it
/// as permission to integrate the untested remainder.
public enum MotionSweepResult: Hashable, Sendable {
    case miss
    case hit(MotionSweepHit)
    case inconclusive(safeFraction: Scalar)
    case unsupported

    var safeFraction: Scalar {
        switch self {
        case .miss: return 1
        case .hit(let hit): return hit.fraction
        case .inconclusive(let fraction): return fraction
        case .unsupported: return 0
        }
    }
}

extension CollisionAlgorithmRegistry {
    /// Sweeps the actual shapes with relative translation and optional rotation.
    /// Built-in convex, plane, compound, and triangle-mesh pairs are supported.
    /// An infinite plane may translate but may not rotate. Custom translational
    /// registrations retain precedence; other custom motion is unsupported.
    public func sweepMotion(_ a: any CollisionPrimitive,
                            motionA: CollisionMotion,
                            _ b: any CollisionPrimitive,
                            motionB: CollisionMotion,
                            distanceTolerance: Scalar = 1.0e-6,
                            maximumIterations: Int = 64) -> MotionSweepResult {
        _sweepMotion(a, motionA: motionA, b, motionB: motionB,
            distanceTolerance: distanceTolerance, maximumIterations: maximumIterations,
            filteringInitialContacts: false)
    }

    // CCD filters leaf hits before choosing the earliest result. Public queries
    // retain fraction-zero overlap reporting, including for separating motion.
    func _sweepMotion(_ a: any CollisionPrimitive,
                      motionA: CollisionMotion,
                      _ b: any CollisionPrimitive,
                      motionB: CollisionMotion,
                      distanceTolerance: Scalar,
                      maximumIterations: Int,
                      filteringInitialContacts: Bool) -> MotionSweepResult {
        guard a.isValid && b.isValid else { return .unsupported }
        guard motionA.isValid && motionB.isValid else { return .inconclusive(safeFraction: 0) }
        let tolerance = distanceTolerance.isFinite && distanceTolerance > 0
            ? Swift.max(distanceTolerance, Scalar.ulpOfOne * 32) : Scalar(1.0e-6)
        let boundsA = motionA.sweptBounds(of: a)
        let boundsB = motionB.sweptBounds(of: b)
        if !boundsA.isNull && !boundsB.isNull && !boundsA.intersects(boundsB) {
            return .miss
        }
        let translates = motionA.angularDisplacement == .zero &&
            motionB.angularDisplacement == .zero
        func accepted(_ result: MotionSweepResult) -> MotionSweepResult {
            guard filteringInitialContacts, case .hit(let hit) = result,
                  hit.fraction == 0 else { return result }
            let centerA = motionA.localPivot.applying(motionA.start)
            let centerB = motionB.localPivot.applying(motionB.start)
            let travelA = motionA.translation + Vector3.cross(
                motionA.angularDisplacement, hit.pointOnA - centerA)
            let travelB = motionB.translation + Vector3.cross(
                motionB.angularDisplacement, hit.pointOnB - centerB)
            guard Vector3.dot(travelA - travelB, hit.normal) <= Swift.max(tolerance, Scalar.ulpOfOne * 64)
            else { return result }
            let convexA = a is any _SupportMap, convexB = b is any _SupportMap
            if translates && ((convexA && convexB) ||
                (convexA && b is StaticPlane) || (a is StaticPlane && convexB)) {
                return .miss
            }
            // Rotation or an opaque custom compound cast can meet again later.
            // Without leaf separation evidence, stop instead of dropping it.
            return .inconclusive(safeFraction: 0)
        }
        let registered = isSweepRegistered(type(of: a), type(of: b))
        // Keep exact analytic sphere casts, and honor explicitly supplied casts.
        if translates && (registered || (usesBuiltinFallback && a is Sphere && b is Sphere)) {
            let inverse = motionA.start.inverted()
            guard let hit = timeOfImpact(a, b,
                frame: motionB.start * inverse,
                translation: (motionA.translation - motionB.translation)
                    .applying(inverse.orientation)) else { return .miss }
            guard hit.isValid else { return .inconclusive(safeFraction: 0) }
            let common = motionB.translation * hit.fraction
            return accepted(.hit(MotionSweepHit(fraction: hit.fraction,
                pointOnA: hit.pointOnA.applying(motionA.start) + common,
                pointOnB: hit.pointOnB.applying(motionA.start) + common,
                normal: hit.normal.applying(motionA.start.orientation).normalized())))
        }
        func recurse(_ childA: any CollisionPrimitive, _ moveA: CollisionMotion,
                     _ childB: any CollisionPrimitive, _ moveB: CollisionMotion) -> MotionSweepResult {
            _sweepMotion(childA, motionA: moveA, childB, motionB: moveB,
                distanceTolerance: tolerance, maximumIterations: maximumIterations,
                filteringInitialContacts: filteringInitialContacts)
        }
        func earliest(_ results: some Sequence<MotionSweepResult>) -> MotionSweepResult {
            var result: MotionSweepResult = .miss
            for candidate in results where candidate != .miss {
                if result == .miss || candidate.safeFraction < result.safeFraction {
                    result = candidate
                } else if candidate.safeFraction == result.safeFraction,
                          case .hit = result {
                    switch candidate {
                    case .inconclusive, .unsupported: result = candidate
                    case .hit, .miss: break
                    }
                }
            }
            return result
        }
        if let compound = a as? CompoundPrimitive {
            return earliest(compound.flattenedChildren().lazy.filter { $0.primitive.isValid }.map {
                recurse($0.primitive, motionA.child($0.transform), b, motionB)
            })
        }
        if let compound = b as? CompoundPrimitive {
            return earliest(compound.flattenedChildren().lazy.filter { $0.primitive.isValid }.map {
                recurse(a, motionA, $0.primitive, motionB.child($0.transform))
            })
        }
        guard usesBuiltinFallback else { return .unsupported }
        if let mesh = a as? TriangleMesh {
            return earliest(_motionTriangles(mesh, motion: motionA, query: boundsB).lazy.map {
                recurse(_MotionTriangle(triangle: mesh.triangle(at: $0)), motionA, b, motionB)
            })
        }
        if let mesh = b as? TriangleMesh {
            return earliest(_motionTriangles(mesh, motion: motionB, query: boundsA).lazy.map {
                recurse(a, motionA, _MotionTriangle(triangle: mesh.triangle(at: $0)), motionB)
            })
        }
        if let plane = a as? StaticPlane, let convex = b as? any _SupportMap {
            let result = _convexPlaneMotion(convex, primitive: b, motion: motionB,
                plane: plane, planeMotion: motionA, tolerance: tolerance,
                maximumIterations: maximumIterations)
            if case .hit(let hit) = result {
                return accepted(.hit(MotionSweepHit(fraction: hit.fraction,
                    pointOnA: hit.pointOnB, pointOnB: hit.pointOnA, normal: -hit.normal)))
            }
            return result
        }
        if let convex = a as? any _SupportMap, let plane = b as? StaticPlane {
            return accepted(_convexPlaneMotion(convex, primitive: a, motion: motionA,
                plane: plane, planeMotion: motionB, tolerance: tolerance,
                maximumIterations: maximumIterations))
        }
        guard let supportA = a as? any _SupportMap,
              let supportB = b as? any _SupportMap,
              supportA.isSupportMappingValid && supportB.isSupportMappingValid
        else { return .unsupported }
        let angularBound = motionA.angularRadius(of: a) * motionA.angularDisplacement.length +
            motionB.angularRadius(of: b) * motionB.angularDisplacement.length
        let relativeTranslation = motionA.translation - motionB.translation
        var fraction: Scalar = 0
        var separatingNormal: Vector3?
        for _ in 0..<Swift.max(maximumIterations, 0) {
            let transformedA = _SweepTransformedSupport(base: supportA, transform: motionA.transform(at: fraction))
            let transformedB = _SweepTransformedSupport(base: supportB, transform: motionB.transform(at: fraction))
            let closest = _gjkClosestPoints(transformedA, transformedB, offset: .zero,
                                           tolerance: tolerance * 0.1)
            var delta = closest.pointOnB - closest.pointOnA
            if delta.length <= Scalar.ulpOfOne {
                delta = transformedB.center - transformedA.center
            }
            let normal: Vector3
            if closest.distance <= tolerance, let separatingNormal {
                normal = separatingNormal
            } else {
                normal = delta.length > Scalar.ulpOfOne ? delta.normalized() : Vector3(1, 0, 0)
            }
            if closest.distance <= tolerance {
                return accepted(.hit(MotionSweepHit(fraction: fraction,
                    pointOnA: closest.pointOnA, pointOnB: closest.pointOnB, normal: normal)))
            }
            // Support planes give a lower bound on separation, even if GJK's
            // witness iteration has not converged to the exact closest points.
            let gap = Vector3.dot(transformedB.support(-normal) - transformedA.support(normal), normal)
            guard gap > 0 && gap.isFinite else { return .inconclusive(safeFraction: fraction) }
            separatingNormal = normal
            let closingBound = Vector3.dot(relativeTranslation, normal) + angularBound
            if closingBound <= 0 { return .miss }
            let advance = gap / closingBound
            if fraction + advance > 1 { return .miss }
            guard advance.isFinite && fraction + advance > fraction else {
                return .inconclusive(safeFraction: fraction)
            }
            fraction += advance
        }
        return .inconclusive(safeFraction: fraction)
    }
}

private struct _MotionTriangle: CollisionPrimitive, _SupportMap {
    let triangle: Triangle
    var bounds: AABB { triangle.aabb }
    var center: Vector3 { triangle.center }
    var isValid: Bool { triangle.isSupportMappingValid }
    func support(_ direction: Vector3) -> Vector3 { triangle.support(direction) }
    func contains(_ point: Vector3) -> Bool {
        (triangle.closestPoint(to: point) - point).lengthSquared <= .ulpOfOne
    }
    func closestPoint(to point: Vector3) -> PrimitiveClosestPoint? {
        let closest = triangle.closestPoint(to: point)
        return PrimitiveClosestPoint(position: closest, normal: triangle.normal,
                                     distance: (closest - point).length)
    }
    func rayTest(_ ray: Ray) -> PrimitiveRayHit? {
        guard let hit = triangle.rayTest(rayOrigin: ray.origin, direction: ray.direction)
        else { return nil }
        return PrimitiveRayHit(parameter: hit.t, position: ray.point(at: hit.t),
                               normal: triangle.normal)
    }
}

private func _motionTriangles(_ mesh: TriangleMesh, motion: CollisionMotion,
                              query: AABB) -> [Int] {
    if query.isNull || motion.angularDisplacement != .zero {
        return (0..<mesh.triangleCount).filter { mesh.triangle(at: $0).isSupportMappingValid }
    }
    // Express the entire relative translational envelope in the mesh's start frame.
    let relative = query.combining(AABB(min: query.min - motion.translation,
                                        max: query.max - motion.translation))
    var indices: [Int] = []
    mesh.queryTriangles(overlapping: relative.applying(motion.start.inverted())) {
        if mesh.triangle(at: $0).isSupportMappingValid { indices.append($0) }
        return true
    }
    return indices.sorted()
}

private func _convexPlaneMotion(_ support: any _SupportMap,
                                primitive: any CollisionPrimitive,
                                motion: CollisionMotion,
                                plane: StaticPlane,
                                planeMotion: CollisionMotion,
                                tolerance: Scalar,
                                maximumIterations: Int) -> MotionSweepResult {
    guard planeMotion.angularDisplacement == .zero else { return .unsupported }
    let rawNormal = plane.plane.normal.applying(planeMotion.start.orientation)
    let normal = rawNormal.normalized()
    let distance = (plane.plane.d - Vector3.dot(rawNormal, planeMotion.start.position)) / rawNormal.length
    let side: Scalar = Vector3.dot(normal, support.center.applying(motion.start)) + distance >= 0 ? 1 : -1
    let towardPlane = normal * -side
    let angularBound = motion.angularRadius(of: primitive) * motion.angularDisplacement.length
    let closingBound = Vector3.dot(motion.translation - planeMotion.translation, towardPlane) + angularBound
    var fraction: Scalar = 0
    for _ in 0..<Swift.max(maximumIterations, 0) {
        let transformed = _SweepTransformedSupport(base: support, transform: motion.transform(at: fraction))
        let point = transformed.support(towardPlane)
        let signedDistance = Vector3.dot(normal, point - planeMotion.translation * fraction) + distance
        let gap = signedDistance * side
        if gap <= tolerance {
            return .hit(MotionSweepHit(fraction: fraction, pointOnA: point,
                pointOnB: point - normal * signedDistance, normal: towardPlane))
        }
        if closingBound <= 0 { return .miss }
        let advance = gap / closingBound
        if fraction + advance > 1 { return .miss }
        guard advance.isFinite && fraction + advance > fraction else {
            return .inconclusive(safeFraction: fraction)
        }
        fraction += advance
    }
    return .inconclusive(safeFraction: fraction)
}
