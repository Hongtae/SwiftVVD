//
//  File: GraphicsDeviceFeatures.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

/// Optional features enabled on a graphics device.
public struct GraphicsDeviceFeatures: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }

    /// Shader arithmetic using 16-bit floating-point types.
    public static let float16Arithmetic = GraphicsDeviceFeatures(rawValue: 0x1)
    /// 16-bit floating-point types in shader stage inputs and outputs.
    /// This does not imply support for 16-bit arithmetic or buffer storage.
    public static let float16InputOutput = GraphicsDeviceFeatures(rawValue: 0x2)
}
