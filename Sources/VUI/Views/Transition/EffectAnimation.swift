//
//  File: EffectAnimation.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

protocol _DisplayList_AnyEffectAnimation:
    ProtobufEncodableMessage,
    ProtobufDecodableMessage
{
    static var leafProtobufTag: CodableEffectAnimation.Tag? { get }
    func makeAnimator() -> any _DisplayList_AnyEffectAnimator
}

protocol _DisplayList_AnyEffectAnimator {
    mutating func evaluate(
        _ animation: any _DisplayList_AnyEffectAnimation,
        at time: Time,
        size: CGSize
    ) -> (effect: DisplayList.Effect, finished: Bool)
}

protocol EffectAnimation: _DisplayList_AnyEffectAnimation {
    associatedtype Value: Animatable & ProtobufEncodableMessage & ProtobufDecodableMessage

    var from: Value { get }
    var to: Value { get }
    var animation: Animation { get }

    init(from: Value, to: Value, animation: Animation)
    static func effect(value: Value, size: CGSize) -> DisplayList.Effect
}

extension EffectAnimation {
    func encode(to encoder: inout ProtobufEncoder) throws {
        try encoder.encodeMessageField(1, from)
        try encoder.encodeMessageField(2, to)
        try encoder.encodeMessageField(3, CodableAnimation(animation))
    }

    init(from decoder: inout ProtobufDecoder) throws {
        var from: Value?
        var to: Value?
        var animation: Animation?

        while let field = try decoder.nextField() {
            let fieldNumber = field.tag
            let wireType = field.wireType.rawValue
            switch fieldNumber {
            case 1 where wireType == 2:
                from = try decoder.messageField(field) as Value
            case 2 where wireType == 2:
                to = try decoder.messageField(field) as Value
            case 3 where wireType == 2:
                animation = try (decoder.messageField(field) as CodableAnimation).base
            case 1, 2, 3:
                throw ProtobufDecoder.DecodingError.failed
            default:
                try decoder.skipField(field)
            }
        }

        guard let from, let to, let animation else {
            throw ProtobufDecoder.DecodingError.failed
        }
        self.init(from: from, to: to, animation: animation)
    }

    func makeAnimator() -> any _DisplayList_AnyEffectAnimator {
        EffectAnimator<Self>()
    }
}

extension EffectAnimation where Value: GeometryEffect {
    static func effect(value: Value, size: CGSize) -> DisplayList.Effect {
        let transform = value.effectValue(size: size)
        var inverse = transform
        return inverse.invert() ? .transform(transform) : .identity
    }
}

struct EffectAnimator<AnimationValue: EffectAnimation>:
    _DisplayList_AnyEffectAnimator
{
    private enum State {
        case active(AnimatorState<AnimationValue.Value.AnimatableData>)
        case pending
        case finished
    }

    private var state: State = .pending

    mutating func evaluate(
        _ animation: any _DisplayList_AnyEffectAnimation,
        at time: Time,
        size: CGSize
    ) -> (effect: DisplayList.Effect, finished: Bool) {
        guard let animation = animation as? AnimationValue else {
            state = .finished
            return (.identity, true)
        }

        switch state {
        case .pending:
            var interval = animation.to.animatableData
            interval -= animation.from.animatableData
            state = .active(
                AnimatorState(
                    animation: animation.animation,
                    interval: interval,
                    at: time,
                    in: Transaction(),
                    finishingDefinition: AnimationValue.Value.self as?
                        any AnimationFinishingDefinition<
                            AnimationValue.Value.AnimatableData
                        >.Type
                )
            )
            return (AnimationValue.effect(value: animation.from, size: size), false)

        case let .active(animator):
            var value = animation.to
            var data = value.animatableData
            if !animator.update(&data, at: time, environment: nil) {
                value.animatableData = data
                return (AnimationValue.effect(value: value, size: size), false)
            }
            state = .finished
            return (AnimationValue.effect(value: animation.to, size: size), true)

        case .finished:
            return (AnimationValue.effect(value: animation.to, size: size), true)
        }
    }
}

extension DisplayList {
    struct OffsetAnimation: EffectAnimation {
        static let leafProtobufTag: CodableEffectAnimation.Tag? = .init(rawValue: 1)

        var from: _OffsetEffect
        var to: _OffsetEffect
        var animation: Animation
    }

    struct ScaleAnimation: EffectAnimation {
        static let leafProtobufTag: CodableEffectAnimation.Tag? = .init(rawValue: 2)

        var from: _ScaleEffect
        var to: _ScaleEffect
        var animation: Animation
    }

    struct RotationAnimation: EffectAnimation {
        static let leafProtobufTag: CodableEffectAnimation.Tag? = .init(rawValue: 3)

        var from: _RotationEffect
        var to: _RotationEffect
        var animation: Animation
    }

    struct OpacityAnimation: EffectAnimation {
        static let leafProtobufTag: CodableEffectAnimation.Tag? = .init(rawValue: 4)

        var from: _OpacityEffect
        var to: _OpacityEffect
        var animation: Animation

        static func effect(value: _OpacityEffect, size: CGSize) -> DisplayList.Effect {
            .opacity(Float(value.opacity))
        }
    }
}

struct CodableEffectAnimation: ProtobufEncodableMessage, ProtobufDecodableMessage {
    struct Tag: RawRepresentable, Equatable, Hashable {
        var rawValue: UInt

        init(rawValue: UInt) {
            self.rawValue = rawValue
        }
    }

    var base: any _DisplayList_AnyEffectAnimation
    var size: CGSize

    init(base: any _DisplayList_AnyEffectAnimation, size: CGSize = .zero) {
        self.base = base
        self.size = size
    }

    func encode(to encoder: inout ProtobufEncoder) throws {
        guard let tag = type(of: base).leafProtobufTag else {
            throw ProtobufEncoder.EncodingError.failed
        }
        encoder.encodeVarint((tag.rawValue << 3) | 2)
        encoder.startLengthDelimited()
        try base.encode(to: &encoder)
        encoder.endLengthDelimited()
        if size != .zero {
            try encoder.encodeMessageField(5, size)
        }
    }

    init(from decoder: inout ProtobufDecoder) throws {
        var base: (any _DisplayList_AnyEffectAnimation)?
        var size = CGSize.zero

        while let field = try decoder.nextField() {
            let fieldNumber = field.tag
            let wireType = field.wireType.rawValue
            switch fieldNumber {
            case 1 where wireType == 2:
                base = try decoder.messageField(field) as DisplayList.OffsetAnimation
            case 2 where wireType == 2:
                base = try decoder.messageField(field) as DisplayList.ScaleAnimation
            case 3 where wireType == 2:
                base = try decoder.messageField(field) as DisplayList.RotationAnimation
            case 4 where wireType == 2:
                base = try decoder.messageField(field) as DisplayList.OpacityAnimation
            case 5 where wireType == 2:
                size = try decoder.messageField(field) as CGSize
            case 1, 2, 3, 4, 5:
                throw ProtobufDecoder.DecodingError.failed
            default:
                try decoder.skipField(field)
            }
        }

        guard let base else {
            throw ProtobufDecoder.DecodingError.failed
        }
        self.base = base
        self.size = size
    }
}
