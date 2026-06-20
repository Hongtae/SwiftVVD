//
//  File: VoxelRayHit.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

public struct VoxelRayHit: Sendable {
    public enum Option: Sendable {
        case any
        case closest
        case longest
    }

    public var t: Scalar
    public var location: (x: UInt32, y: UInt32, z: UInt32)
    public var depth: UInt32
    public var voxel: Voxel

    public init(t: Scalar,
                location: (x: UInt32, y: UInt32, z: UInt32),
                depth: UInt32,
                voxel: Voxel) {
        self.t = t
        self.location = location
        self.depth = depth
        self.voxel = voxel
    }
}
