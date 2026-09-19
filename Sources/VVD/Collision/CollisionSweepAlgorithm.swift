//
//  File: CollisionSweepAlgorithm.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

/// A translational time-of-impact algorithm for one ordered primitive pair.
///
/// `frame` maps B-local points into A's start-local space. `translation` moves
/// A in that same space while B remains fixed. Results use A's start-local
/// space and must report the first fraction in `0...1`. Initial overlap returns
/// fraction zero.
public protocol CollisionSweepAlgorithm {
    associatedtype PrimitiveA: CollisionPrimitive
    associatedtype PrimitiveB: CollisionPrimitive

    func timeOfImpact(_ a: PrimitiveA,
                      _ b: PrimitiveB,
                      frame: Transform,
                      translation: Vector3) -> TimeOfImpact?
}
