//
//  File: PrimitiveRayIntersection.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

func _quadraticRayParameters(a: Scalar,
                             b: Scalar,
                             c: Scalar) -> (near: Scalar, far: Scalar)? {
    guard abs(a) > .ulpOfOne else { return nil }

    let discriminant = b * b - a * c
    guard discriminant >= .zero else { return nil }

    let root = discriminant.squareRoot()
    let first = (-b - root) / a
    let second = (-b + root) / a
    return first <= second ? (first, second) : (second, first)
}

func _updateClosestRayHit(ray: Ray,
                          parameter: Scalar,
                          normal: Vector3,
                          closest: inout PrimitiveRayHit?) {
    guard parameter >= .zero && parameter.isFinite else { return }
    if let closest, closest.parameter <= parameter { return }

    let resolvedNormal = normal.lengthSquared > .ulpOfOne
        ? normal.normalized()
        : -ray.direction.normalized()
    closest = PrimitiveRayHit(parameter: parameter,
                              position: ray.point(at: parameter),
                              normal: resolvedNormal)
}
