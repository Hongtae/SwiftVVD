//
//  File: Ray.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

public struct Ray: Hashable, Sendable {
    public var origin: Vector3
    public var direction: Vector3

    public init(origin: Vector3 = .zero, direction: Vector3 = .zero) {
        self.origin = origin
        self.direction = direction
    }

    public var isValid: Bool {
        direction.lengthSquared > .ulpOfOne
    }

    public func point(at parameter: Scalar) -> Vector3 {
        origin + direction * parameter
    }
}
