//
//  File: VectorTransformer.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import Foundation

public protocol VectorTransformer: Equatable {
    associatedtype Vector

    static var identity: Self { get }

    static func * (_: Self.Vector, _: Self) -> Self.Vector
    static func *= (_: inout Self.Vector, _: Self)
    static func == (_: Self, _: Self) -> Bool
    static func != (_: Self, _: Self) -> Bool
}

public extension VectorTransformer {
    static func *= (lhs: inout Self.Vector, rhs: Self)  { lhs = lhs * rhs }
    static func != (lhs: Self, rhs: Self) -> Bool       { !(lhs == rhs) }
}

public protocol Interpolatable {
    static func interpolate(_: Self, _: Self, t: any BinaryFloatingPoint) -> Self
}
