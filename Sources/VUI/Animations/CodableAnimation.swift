//
//  File: CodableAnimation.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

protocol EncodableAnimation: ProtobufEncodableMessage {
    static var leafProtobufTag: CodableAnimation.Tag? { get }
}

extension EncodableAnimation {
    static var leafProtobufTag: CodableAnimation.Tag? {
        nil
    }

    func encodeAnimation(to encoder: inout ProtobufEncoder) throws {
        if let tag = Self.leafProtobufTag {
            try encoder.encodeMessageField(tag.rawValue, self)
        } else {
            try encode(to: &encoder)
        }
    }
}

extension UnitCurve.CubicSolver: ProtobufEncodableMessage, ProtobufDecodableMessage {
    func encode(to encoder: inout ProtobufEncoder) throws {
        let points = controlPointsForAnimation
        let values = [
            Double(points.startControlPoint.x),
            Double(points.startControlPoint.y),
            Double(points.endControlPoint.x),
            Double(points.endControlPoint.y),
        ]
        for (offset, value) in values.enumerated() where value != 0 {
            encoder.encodeDoubleFieldAlways(UInt(offset + 1), value)
        }
    }

    init(from decoder: inout ProtobufDecoder) throws {
        var values = Array(repeating: 0.0, count: 4)
        while !decoder.isAtEnd {
            let tag = try decoder.decodeVarint()
            let fieldNumber = tag >> 3
            let wireType = tag & 0x7
            if (1...4).contains(fieldNumber) {
                values[Int(fieldNumber - 1)] = try decoder.decodeDoubleField(wireType: wireType)
            } else {
                try decoder.skipField(wireType: wireType)
            }
        }
        self.init(
            startControlPoint: UnitPoint(x: values[0], y: values[1]),
            endControlPoint: UnitPoint(x: values[2], y: values[3])
        )
    }
}

extension DefaultAnimation: EncodableAnimation, ProtobufDecodableMessage {
    static var leafProtobufTag: CodableAnimation.Tag? {
        .init(rawValue: 7)
    }

    func encode(to encoder: inout ProtobufEncoder) throws {
    }

    init(from decoder: inout ProtobufDecoder) throws {
        self.init()
    }
}

extension BezierAnimation: EncodableAnimation, ProtobufDecodableMessage {
    static var leafProtobufTag: CodableAnimation.Tag? {
        .init(rawValue: 1)
    }

    private static var defaultCurve: UnitCurve.CubicSolver {
        UnitCurve.CubicSolver(
            startControlPoint: .zero,
            endControlPoint: UnitPoint(x: 1, y: 1)
        )
    }

    func encode(to encoder: inout ProtobufEncoder) throws {
        if duration != 0 {
            encoder.encodeDoubleFieldAlways(1, duration)
        }
        if curve != Self.defaultCurve {
            try encoder.encodeMessageField(2, curve)
        }
    }

    init(from decoder: inout ProtobufDecoder) throws {
        var duration = 0.0
        var curve = Self.defaultCurve
        while !decoder.isAtEnd {
            let tag = try decoder.decodeVarint()
            let fieldNumber = tag >> 3
            let wireType = tag & 0x7
            switch fieldNumber {
            case 1:
                duration = try decoder.decodeDoubleField(wireType: wireType)
            case 2 where wireType == 2:
                curve = try decoder.decodeMessage(UnitCurve.CubicSolver.self)
            case 2:
                throw ProtobufDecoder.DecodingError.failed
            default:
                try decoder.skipField(wireType: wireType)
            }
        }
        self.init(duration: duration, curve: curve)
    }
}

extension SpringAnimation: EncodableAnimation, ProtobufDecodableMessage {
    static var leafProtobufTag: CodableAnimation.Tag? {
        .init(rawValue: 2)
    }

    func encode(to encoder: inout ProtobufEncoder) throws {
        if mass != 1 {
            encoder.encodeDoubleFieldAlways(1, mass)
        }
        if stiffness != 100 {
            encoder.encodeDoubleFieldAlways(2, stiffness)
        }
        if damping != 20 {
            encoder.encodeDoubleFieldAlways(3, damping)
        }
        if initialVelocity.valuePerSecond != 0 {
            encoder.encodeDoubleFieldAlways(4, initialVelocity.valuePerSecond)
        }
    }

    init(from decoder: inout ProtobufDecoder) throws {
        var mass = 1.0
        var stiffness = 100.0
        var damping = 20.0
        var initialVelocity = 0.0
        while !decoder.isAtEnd {
            let tag = try decoder.decodeVarint()
            let fieldNumber = tag >> 3
            let wireType = tag & 0x7
            switch fieldNumber {
            case 1:
                mass = try decoder.decodeDoubleField(wireType: wireType)
            case 2:
                stiffness = try decoder.decodeDoubleField(wireType: wireType)
            case 3:
                damping = try decoder.decodeDoubleField(wireType: wireType)
            case 4:
                initialVelocity = try decoder.decodeDoubleField(wireType: wireType)
            default:
                try decoder.skipField(wireType: wireType)
            }
        }
        self.init(
            mass: mass,
            stiffness: stiffness,
            damping: damping,
            initialVelocity: _Velocity(valuePerSecond: initialVelocity)
        )
    }
}

extension FluidSpringAnimation: EncodableAnimation, ProtobufDecodableMessage {
    static var leafProtobufTag: CodableAnimation.Tag? {
        .init(rawValue: 3)
    }

    func encode(to encoder: inout ProtobufEncoder) throws {
        if response != 0 {
            encoder.encodeDoubleFieldAlways(1, response)
        }
        if dampingFraction != 0 {
            encoder.encodeDoubleFieldAlways(2, dampingFraction)
        }
        if blendDuration != 0 {
            encoder.encodeDoubleFieldAlways(3, blendDuration)
        }
    }

    init(from decoder: inout ProtobufDecoder) throws {
        var response = 0.0
        var dampingFraction = 0.0
        var blendDuration = 0.0
        while !decoder.isAtEnd {
            let tag = try decoder.decodeVarint()
            let fieldNumber = tag >> 3
            let wireType = tag & 0x7
            switch fieldNumber {
            case 1:
                response = try decoder.decodeDoubleField(wireType: wireType)
            case 2:
                dampingFraction = try decoder.decodeDoubleField(wireType: wireType)
            case 3:
                blendDuration = try decoder.decodeDoubleField(wireType: wireType)
            default:
                try decoder.skipField(wireType: wireType)
            }
        }
        self.init(
            response: response,
            dampingFraction: dampingFraction,
            blendDuration: blendDuration
        )
    }
}

extension DelayAnimation: ProtobufEncodableMessage {
    func encode(to encoder: inout ProtobufEncoder) throws {
        if encoder.archiveVersion >= 4 {
            encoder.encodeVarint(0x42)
            encoder.startLengthDelimited()
            if delay != 0 {
                encoder.encodeDoubleFieldAlways(1, delay)
            }
            encoder.endLengthDelimited()
        } else if delay != 0 {
            encoder.encodeDoubleFieldAlways(4, delay)
        }
    }
}

extension SpeedAnimation: ProtobufEncodableMessage {
    func encode(to encoder: inout ProtobufEncoder) throws {
        if encoder.archiveVersion >= 4 {
            encoder.encodeVarint(0x42)
            encoder.startLengthDelimited()
            if speed != 0 {
                encoder.encodeDoubleFieldAlways(3, speed)
            }
            encoder.endLengthDelimited()
        } else if speed != 0 {
            encoder.encodeDoubleFieldAlways(6, speed)
        }
    }
}

extension RepeatAnimation: ProtobufEncodableMessage {
    func encode(to encoder: inout ProtobufEncoder) throws {
        let fieldNumber: UInt = encoder.archiveVersion >= 4 ? 8 : 5
        encoder.encodeVarint((fieldNumber << 3) | 2)
        encoder.startLengthDelimited()
        if encoder.archiveVersion >= 4 {
            encoder.encodeVarint(0x12)
            encoder.startLengthDelimited()
        }
        if let repeatCount, repeatCount != .min {
            encoder.encodeVarint(0x08)
            encoder.encodeSignedVarint(repeatCount)
        }
        if autoreverses {
            encoder.encodeVarint(0x10)
            encoder.encodeVarint(1)
        }
        if encoder.archiveVersion >= 4 {
            encoder.endLengthDelimited()
        }
        encoder.endLengthDelimited()
    }
}

extension CustomAnimationModifiedContent: EncodableAnimation {
    func encode(to encoder: inout ProtobufEncoder) throws {
        let encodableBase =
            (base as? any EncodableAnimation) ?? DefaultAnimation()
        try encodableBase.encodeAnimation(to: &encoder)

        if let encodableModifier = modifier as? any ProtobufEncodableMessage {
            try encodableModifier.encode(to: &encoder)
        }
    }
}

extension InternalCustomAnimationModifiedContent: EncodableAnimation {
    func encode(to encoder: inout ProtobufEncoder) throws {
        try _base.encode(to: &encoder)
    }
}

struct CodableAnimation: ProtobufEncodableMessage, ProtobufDecodableMessage {
    struct Tag: RawRepresentable, Equatable, Hashable {
        var rawValue: UInt

        init(rawValue: UInt) {
            self.rawValue = rawValue
        }
    }

    var base: Animation

    init(_ base: Animation) {
        self.base = base
    }

    func encode(to encoder: inout ProtobufEncoder) throws {
        let encodableBase =
            (base.base as? any EncodableAnimation) ?? DefaultAnimation()
        try encodableBase.encodeAnimation(to: &encoder)
    }

    init(from decoder: inout ProtobufDecoder) throws {
        var animation: Animation?
        while !decoder.isAtEnd {
            let tag = try decoder.decodeVarint()
            let fieldNumber = tag >> 3
            let wireType = tag & 0x7
            switch fieldNumber {
            case 1 where wireType == 2:
                let value = try decoder.decodeMessage(BezierAnimation.self)
                animation = Animation(box: value.animationBox)
            case 2 where wireType == 2:
                let value = try decoder.decodeMessage(SpringAnimation.self)
                animation = Animation(box: value.animationBox)
            case 3 where wireType == 2:
                let value = try decoder.decodeMessage(FluidSpringAnimation.self)
                animation = Animation(box: value.animationBox)
            case 4:
                guard let current = animation else {
                    throw ProtobufDecoder.DecodingError.failed
                }
                animation = current.delay(try decoder.decodeDoubleField(wireType: wireType))
            case 5 where wireType == 2:
                guard let current = animation else {
                    throw ProtobufDecoder.DecodingError.failed
                }
                let repeatValue = try decoder.decodeLengthDelimited { nested in
                    try Self.decodeRepeatMessage(from: &nested)
                }
                animation = Self.applying(repeatValue, to: current)
            case 6:
                guard let current = animation else {
                    throw ProtobufDecoder.DecodingError.failed
                }
                animation = current.speed(try decoder.decodeDoubleField(wireType: wireType))
            case 7 where wireType == 2:
                _ = try decoder.decodeMessage(DefaultAnimation.self)
                animation = .default
            case 8 where wireType == 2:
                animation = try decoder.decodeLengthDelimited { nested in
                    try Self.decodeModifierEnvelope(from: &nested, applyingTo: animation)
                }
            case 1, 2, 3, 5, 7, 8:
                throw ProtobufDecoder.DecodingError.failed
            default:
                try decoder.skipField(wireType: wireType)
            }
        }
        guard let animation else {
            throw ProtobufDecoder.DecodingError.failed
        }
        self.base = animation
    }

    private static func decodeModifierEnvelope(
        from decoder: inout ProtobufDecoder,
        applyingTo initialAnimation: Animation?
    ) throws -> Animation {
        guard var animation = initialAnimation else {
            throw ProtobufDecoder.DecodingError.failed
        }
        while !decoder.isAtEnd {
            let tag = try decoder.decodeVarint()
            let fieldNumber = tag >> 3
            let wireType = tag & 0x7
            switch fieldNumber {
            case 1:
                animation = animation.delay(
                    try decoder.decodeDoubleField(wireType: wireType)
                )
            case 2 where wireType == 2:
                let repeatValue = try decoder.decodeLengthDelimited { nested in
                    try decodeRepeatMessage(from: &nested)
                }
                animation = applying(repeatValue, to: animation)
            case 2:
                throw ProtobufDecoder.DecodingError.failed
            case 3:
                animation = animation.speed(
                    try decoder.decodeDoubleField(wireType: wireType)
                )
            default:
                try decoder.skipField(wireType: wireType)
            }
        }
        return animation
    }

    private static func decodeRepeatMessage(
        from decoder: inout ProtobufDecoder
    ) throws -> (count: Int?, autoreverses: Bool) {
        var count: Int?
        var autoreverses = false
        while !decoder.isAtEnd {
            let tag = try decoder.decodeVarint()
            let fieldNumber = tag >> 3
            let wireType = tag & 0x7
            switch fieldNumber {
            case 1 where wireType == 0:
                count = try decoder.decodeSignedVarint()
            case 2 where wireType == 0:
                autoreverses = try decoder.decodeVarint() != 0
            case 1, 2:
                throw ProtobufDecoder.DecodingError.failed
            default:
                try decoder.skipField(wireType: wireType)
            }
        }
        return (count, autoreverses)
    }

    private static func applying(
        _ repeatValue: (count: Int?, autoreverses: Bool),
        to animation: Animation
    ) -> Animation {
        if let count = repeatValue.count {
            return animation.repeatCount(count, autoreverses: repeatValue.autoreverses)
        }
        return animation.repeatForever(autoreverses: repeatValue.autoreverses)
    }
}
