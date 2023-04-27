//
//  File: BlendState.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

public enum BlendFactor {
    case zero
    case one
    case sourceColor
    case oneMinusSourceColor
    case sourceAlpha
    case oneMinusSourceAlpha
    case destinationColor
    case oneMinusDestinationColor
    case destinationAlpha
    case oneMinusDestinationAlpha
    case sourceAlphaSaturated
    case blendColor
    case oneMinusBlendColor
    case blendAlpha
    case oneMinusBlendAlpha
    case source1Color
    case oneMinusSource1Color
    case source1Alpha
    case oneMinusSource1Alpha
}

public enum BlendOperation {
    case add
    case subtract
    case reverseSubtract
    case min
    case max
}

public struct ColorWriteMask: OptionSet, Hashable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }

    public static let red      = ColorWriteMask(rawValue: 0x1 << 3)
    public static let green    = ColorWriteMask(rawValue: 0x1 << 2)
    public static let blue     = ColorWriteMask(rawValue: 0x1 << 1)
    public static let alpha    = ColorWriteMask(rawValue: 0x1)
    public static let all      = ColorWriteMask(rawValue: 0xf)
}

public struct BlendState: Hashable {
    public var enabled : Bool

    public var sourceRGBBlendFactor : BlendFactor
    public var sourceAlphaBlendFactor : BlendFactor

    public var destinationRGBBlendFactor : BlendFactor
    public var destinationAlphaBlendFactor : BlendFactor

    public var rgbBlendOperation : BlendOperation
    public var alphaBlendOperation : BlendOperation

    public var writeMask : ColorWriteMask

    public init(sourceRGBBlendFactor : BlendFactor = .one,
                sourceAlphaBlendFactor : BlendFactor = .one,
                destinationRGBBlendFactor : BlendFactor = .zero,
                destinationAlphaBlendFactor : BlendFactor = .zero,
                rgbBlendOperation : BlendOperation = .add,
                alphaBlendOperation : BlendOperation = .add,
                writeMask : ColorWriteMask = .all) {
        self.enabled = true
        self.sourceRGBBlendFactor = sourceRGBBlendFactor
        self.sourceAlphaBlendFactor = sourceAlphaBlendFactor
        self.destinationRGBBlendFactor = destinationRGBBlendFactor
        self.destinationAlphaBlendFactor = destinationAlphaBlendFactor
        self.rgbBlendOperation = rgbBlendOperation
        self.alphaBlendOperation = alphaBlendOperation
        self.writeMask = writeMask
    }

    public init(sourceBlendFactor: BlendFactor,
                destinationBlendFactor: BlendFactor,
                blendOperation: BlendOperation,
                writeMask: ColorWriteMask = .all) {
        self.enabled = true
        self.sourceRGBBlendFactor = sourceBlendFactor
        self.sourceAlphaBlendFactor = sourceBlendFactor
        self.destinationRGBBlendFactor = destinationBlendFactor
        self.destinationAlphaBlendFactor = destinationBlendFactor
        self.rgbBlendOperation = blendOperation
        self.alphaBlendOperation = blendOperation
        self.writeMask = writeMask
    }

    public init(enabled: Bool = false) {
        self.enabled = enabled
        self.sourceRGBBlendFactor = .one
        self.sourceAlphaBlendFactor = .one
        self.destinationRGBBlendFactor = .zero
        self.destinationAlphaBlendFactor = .zero
        self.rgbBlendOperation = .add
        self.alphaBlendOperation = .add
        self.writeMask = .all   
    }

    // preset
    public static let opaque = BlendState(enabled: false)
    public static let alphaBlend = BlendState(
        sourceRGBBlendFactor: .sourceAlpha,
        sourceAlphaBlendFactor: .one,
        destinationRGBBlendFactor: .oneMinusSourceAlpha,
        destinationAlphaBlendFactor: .oneMinusSourceAlpha,
        rgbBlendOperation: .add,
        alphaBlendOperation: .add)
    public static let multiply = BlendState(
        sourceRGBBlendFactor: .destinationColor,
        sourceAlphaBlendFactor: .destinationAlpha,
        destinationRGBBlendFactor: .zero,
        destinationAlphaBlendFactor: .zero,
        rgbBlendOperation: .add,
        alphaBlendOperation: .add)
    public static let screen = BlendState(
        sourceRGBBlendFactor: .oneMinusDestinationColor,
        sourceAlphaBlendFactor: .oneMinusDestinationColor,
        destinationRGBBlendFactor: .one,
        destinationAlphaBlendFactor: .one,
        rgbBlendOperation: .add,
        alphaBlendOperation: .add)
    public static let darken = BlendState(
        sourceRGBBlendFactor: .one,
        sourceAlphaBlendFactor: .one,
        destinationRGBBlendFactor: .one,
        destinationAlphaBlendFactor: .one,
        rgbBlendOperation: .min,
        alphaBlendOperation: .min)
    public static let lighten = BlendState(
        sourceRGBBlendFactor: .one,
        sourceAlphaBlendFactor: .one,
        destinationRGBBlendFactor: .one,
        destinationAlphaBlendFactor: .one,
        rgbBlendOperation: .max,
        alphaBlendOperation: .max)
    public static let linearBurn = BlendState(
        sourceRGBBlendFactor: .one,
        sourceAlphaBlendFactor: .one,
        destinationRGBBlendFactor: .oneMinusDestinationColor,
        destinationAlphaBlendFactor: .oneMinusDestinationColor,
        rgbBlendOperation: .subtract,
        alphaBlendOperation: .subtract)
    public static let linearDodge = BlendState(
        sourceRGBBlendFactor: .one,
        sourceAlphaBlendFactor: .one,
        destinationRGBBlendFactor: .one,
        destinationAlphaBlendFactor: .one,
        rgbBlendOperation: .add,
        alphaBlendOperation: .add)
}
