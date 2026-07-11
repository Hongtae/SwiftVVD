//
//  File: ShadowStyle.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

public struct ShadowStyle: Equatable, Sendable {
    struct Kind: OptionSet, Sendable {
        let rawValue: UInt8

        init(rawValue: UInt8) {
            self.rawValue = rawValue
        }

        static let drop: Kind = []
        static let inner = Kind(rawValue: 1 << 0)
        static let only = Kind(rawValue: 1 << 1)
        static let nonOpaque = Kind(rawValue: 1 << 2)
        static let ignoresFill = Kind(rawValue: 1 << 3)
        static let requiresKnockout = Kind(rawValue: 1 << 4)
    }

    enum Storage: Equatable, Sendable {
        case standard(Kind)
        case custom(Kind, Color, CGFloat, CGSize)
    }

    var storage: Storage
    var midpoint: Float

    static var drop: Self {
        Self(storage: .standard(.drop), midpoint: 0.5)
    }

    static var inner: Self {
        Self(storage: .standard(.inner), midpoint: 0.5)
    }

    public static func drop(
        color: Color = Color(.sRGBLinear, white: 0, opacity: 0.33),
        radius: CGFloat,
        x: CGFloat = 0,
        y: CGFloat = 0
    ) -> ShadowStyle {
        ShadowStyle(
            storage: .custom(.drop, color, radius, CGSize(width: x, height: y)),
            midpoint: 0.5
        )
    }

    public static func inner(
        color: Color = Color(.sRGBLinear, white: 0, opacity: 0.55),
        radius: CGFloat,
        x: CGFloat = 0,
        y: CGFloat = 0
    ) -> ShadowStyle {
        ShadowStyle(
            storage: .custom(.inner, color, radius, CGSize(width: x, height: y)),
            midpoint: 0.5
        )
    }

    func ignoresFill(_ ignoresFill: Bool) -> Self {
        mapKind { kind in
            if ignoresFill {
                kind.insert(.ignoresFill)
            } else {
                kind.remove(.ignoresFill)
            }
        }
    }

    func ignoresFill(_ ignoresFill: Bool, knockout: Bool) -> Self {
        mapKind { kind in
            if ignoresFill {
                kind.insert(.ignoresFill)
            } else {
                kind.remove(.ignoresFill)
            }
            if knockout {
                kind.insert(.requiresKnockout)
            } else {
                kind.remove(.requiresKnockout)
            }
        }
    }

    func midpoint(_ midpoint: Double) -> Self {
        var result = self
        result.midpoint = Float(midpoint)
        return result
    }

    func resolve(in environment: EnvironmentValues) -> ResolvedShadowStyle {
        switch storage {
        case .standard:
            fatalError("Standard ShadowStyle requires shape-style resolution context.")
        case let .custom(kind, color, radius, offset):
            return ResolvedShadowStyle(
                color: Color.ResolvedHDR(color.resolve(in: environment)),
                radius: radius,
                offset: offset,
                midpoint: midpoint,
                kind: kind
            )
        }
    }

    private func mapKind(_ transform: (inout Kind) -> Void) -> Self {
        var result = self
        switch result.storage {
        case .standard(var kind):
            transform(&kind)
            result.storage = .standard(kind)
        case .custom(var kind, let color, let radius, let offset):
            transform(&kind)
            result.storage = .custom(kind, color, radius, offset)
        }
        return result
    }
}

struct ResolvedShadowStyle: Equatable, Sendable, Animatable {
    var color: Color.ResolvedHDR
    var radius: CGFloat
    var offset: CGSize
    var midpoint: Float
    var kind: ShadowStyle.Kind

    init(
        color: Color.ResolvedHDR,
        radius: CGFloat,
        offset: CGSize,
        midpoint: Float = 0.5,
        kind: ShadowStyle.Kind = .drop
    ) {
        self.color = color
        self.radius = radius
        self.offset = offset
        self.midpoint = midpoint
        self.kind = kind
    }

    typealias AnimatableData = AnimatablePair<
        Color.Resolved.AnimatableData,
        AnimatablePair<CGFloat, CGSize.AnimatableData>
    >

    var animatableData: AnimatableData {
        get {
            AnimatableData(
                color.base.animatableData,
                AnimatablePair(radius, offset.animatableData)
            )
        }
        set {
            color.base.animatableData = newValue.first
            radius = newValue.second.first
            offset.animatableData = newValue.second.second
        }
    }
}
