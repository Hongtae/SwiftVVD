//
//  File: Voxel.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

public struct Voxel: Hashable, Sendable {
    var packedColor: UInt32
    public var metallic: UInt8
    public var roughness: UInt8

    public typealias Color = LinearSRGBColor

    public var color: Color {
        get { Color(rgba8: rgba8) }
        set { rgba8 = newValue.rgba8 }
    }

    public var rgba8: Color.RGBA8 {
        get {
            .init(r: UInt8(packedColor & 0xff),
                  g: UInt8((packedColor >> 8) & 0xff),
                  b: UInt8((packedColor >> 16) & 0xff),
                  a: UInt8((packedColor >> 24) & 0xff))
        }
        set {
            packedColor = UInt32(newValue.r) |
                          (UInt32(newValue.g) << 8) |
                          (UInt32(newValue.b) << 16) |
                          (UInt32(newValue.a) << 24)
        }
    }

    public init(color: Color = .clear,
                metallic: UInt8 = 0,
                roughness: UInt8 = 0) {
        self.packedColor = 0
        self.metallic = metallic
        self.roughness = roughness
        self.color = color
    }

    public init(rgba8: Color.RGBA8, metallic: UInt8 = 0, roughness: UInt8 = 0) {
        self.packedColor = 0
        self.metallic = metallic
        self.roughness = roughness
        self.rgba8 = rgba8
    }
}
