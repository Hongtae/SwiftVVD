//
//  File: ViewFrame.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

/// Animated view frame snapshot passed through the animation system.
struct ViewFrame: Equatable {
    var origin: CGPoint
    var size: ViewSize

    init(size: ViewSize) {
        self.origin = .zero
        self.size = size
    }
    init(origin: CGPoint, size: ViewSize) {
        self.origin = origin
        self.size = size
    }

    mutating func round(toMultipleOf value: CGFloat) {
        let half = value * 0.5
        let maximum = CGPoint(
            x: origin.x + size.value.width,
            y: origin.y + size.value.height
        )
        let roundedOrigin = CGPoint(
            x: floor((origin.x + half) / value) * value,
            y: floor((origin.y + half) / value) * value
        )
        let roundedMaximum = CGPoint(
            x: floor((maximum.x + half) / value) * value,
            y: floor((maximum.y + half) / value) * value
        )
        origin = roundedOrigin
        size.value.width =
            ((roundedMaximum.x - roundedOrigin.x) / value).rounded() * value
        size.value.height =
            ((roundedMaximum.y - roundedOrigin.y) / value).rounded() * value
    }
}

extension ViewFrame: ExtendedAnimatable {
    typealias AnimatableData = AnimatablePair<CGPoint.AnimatableData, ViewSize.AnimatableData>

    var animatableData: AnimatableData {
        get { AnimatableData(origin.animatableData, size.animatableData) }
        set {
            origin.animatableData = newValue.first
            size.animatableData = newValue.second
        }
    }

    static func shouldFinishEarly(in context: AnimationSettlingContext<AnimatableData>) -> Bool {
        let pixelLength = context.environment.animationPixelLength
        let doublePixelLength = pixelLength * 2
        return componentSettled(
            delta: context.delta.first.first,
            velocity: context.velocity.first.first,
            threshold: pixelLength
        ) && componentSettled(
            delta: context.delta.first.second,
            velocity: context.velocity.first.second,
            threshold: pixelLength
        ) && componentSettled(
            delta: context.delta.second.first,
            velocity: context.velocity.second.first,
            threshold: doublePixelLength
        ) && componentSettled(
            delta: context.delta.second.second,
            velocity: context.velocity.second.second,
            threshold: doublePixelLength
        )
    }

    private static func componentSettled(
        delta: CGFloat,
        velocity: CGFloat,
        threshold: CGFloat
    ) -> Bool {
        let thresholdSquared = threshold * threshold
        return delta * delta + velocity * velocity < thresholdSquared
    }
}
