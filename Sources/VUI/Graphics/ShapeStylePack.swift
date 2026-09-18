//
//  File: ShapeStylePack.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

enum _ShapeStyle_Name: UInt8, Comparable, Sendable {
    case foreground
    case background
    case multicolor

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

class AnyResolvedPaint: Equatable, @unchecked Sendable {
    static func == (lhs: AnyResolvedPaint, rhs: AnyResolvedPaint) -> Bool {
        lhs.isEqual(to: rhs)
    }

    func isEqual(to other: AnyResolvedPaint) -> Bool {
        fatalError("AnyResolvedPaint subclasses must implement equality.")
    }
}

final class _AnyResolvedPaint<Paint: Equatable & Sendable>: AnyResolvedPaint, @unchecked Sendable {
    let paint: Paint

    init(_ paint: Paint) {
        self.paint = paint
    }

    override func isEqual(to other: AnyResolvedPaint) -> Bool {
        guard let other = other as? _AnyResolvedPaint<Paint> else {
            return false
        }
        return paint == other.paint
    }
}

struct _ShapeStyle_Pack: Animatable, @unchecked Sendable {
    struct Key: Hashable, Comparable, Sendable {
        var name: _ShapeStyle_Name
        var _level: UInt8

        init(_ name: _ShapeStyle_Name, _ level: Int) {
            precondition((0...Int(UInt8.max)).contains(level))
            self.name = name
            self._level = UInt8(level)
        }

        static func < (lhs: Self, rhs: Self) -> Bool {
            if lhs.name != rhs.name {
                return lhs.name < rhs.name
            }
            return lhs._level < rhs._level
        }
    }

    enum Fill: Equatable, Sendable {
        typealias MeshGradientData = MeshGradient._Paint.AnimatableData

        enum AnimatableData: VectorArithmetic, Sendable {
            case color(Color.ResolvedHDR._Animatable)
            case linearGradient(LinearGradient._Paint.AnimatableData)
            case meshGradient(MeshGradientData)
            case zero

            init(_ fill: Fill) {
                switch fill {
                case let .color(color):
                    self = .color(color.animatableData)
                case let .paint(paint):
                    if let paint = paint as? _AnyResolvedPaint<LinearGradient._Paint> {
                        self = .linearGradient(paint.paint.animatableData)
                    } else if let paint = paint as? _AnyResolvedPaint<MeshGradient._Paint> {
                        self = .meshGradient(paint.paint.animatableData)
                    } else {
                        self = .zero
                    }
                }
            }

            static func += (lhs: inout Self, rhs: Self) {
                switch (lhs, rhs) {
                case (.zero, _):
                    lhs = rhs
                case (_, .zero):
                    break
                case let (.color(lhsValue), .color(rhsValue)):
                    lhs = .color(lhsValue + rhsValue)
                case let (.linearGradient(lhsValue), .linearGradient(rhsValue)):
                    lhs = .linearGradient(lhsValue + rhsValue)
                case let (.meshGradient(lhsValue), .meshGradient(rhsValue)):
                    lhs = .meshGradient(lhsValue + rhsValue)
                default:
                    break
                }
            }

            static func -= (lhs: inout Self, rhs: Self) {
                switch (lhs, rhs) {
                case (_, .zero):
                    break
                case (.zero, let value):
                    lhs = value
                case let (.color(lhsValue), .color(rhsValue)):
                    lhs = .color(lhsValue - rhsValue)
                case let (.linearGradient(lhsValue), .linearGradient(rhsValue)):
                    lhs = .linearGradient(lhsValue - rhsValue)
                case let (.meshGradient(lhsValue), .meshGradient(rhsValue)):
                    lhs = .meshGradient(lhsValue - rhsValue)
                default:
                    break
                }
            }

            static func + (lhs: Self, rhs: Self) -> Self {
                var result = lhs
                result += rhs
                return result
            }

            static func - (lhs: Self, rhs: Self) -> Self {
                var result = lhs
                result -= rhs
                return result
            }

            mutating func scale(by rhs: Double) {
                switch self {
                case var .color(value):
                    value.scale(by: rhs)
                    self = .color(value)
                case var .linearGradient(value):
                    value.scale(by: rhs)
                    self = .linearGradient(value)
                case var .meshGradient(value):
                    value.scale(by: rhs)
                    self = .meshGradient(value)
                case .zero:
                    break
                }
            }

            var magnitudeSquared: Double {
                switch self {
                case let .color(value):
                    value.magnitudeSquared
                case let .linearGradient(value):
                    value.magnitudeSquared
                case let .meshGradient(value):
                    value.magnitudeSquared
                case .zero:
                    0
                }
            }

            func set(fill: inout Fill) {
                switch (fill, self) {
                case let (.color(original), .color(data)):
                    var color = original
                    color.animatableData = data
                    fill = .color(color)
                case let (.paint(paint), .linearGradient(data)):
                    guard let paint = paint as? _AnyResolvedPaint<LinearGradient._Paint> else {
                        return
                    }
                    var resolved = paint.paint
                    resolved.animatableData = data
                    fill = .paint(_AnyResolvedPaint(resolved))
                case let (.paint(paint), .meshGradient(data)):
                    guard let paint = paint as? _AnyResolvedPaint<MeshGradient._Paint> else {
                        return
                    }
                    var resolved = paint.paint
                    resolved.animatableData = data
                    fill = .paint(_AnyResolvedPaint(resolved))
                default:
                    break
                }
            }
        }

        case color(Color.ResolvedHDR)
        case paint(AnyResolvedPaint)

        var animatableData: AnimatableData {
            get { AnimatableData(self) }
            set { newValue.set(fill: &self) }
        }
    }

    mutating func adjustLevelIndices(
        of name: _ShapeStyle_Name,
        by offset: Int
    ) {
        for index in styles.indices where styles[index].key.name == name {
            let level = Int(styles[index].key._level) + offset
            precondition((0...Int(UInt8.max)).contains(level))
            styles[index].key._level = UInt8(level)
        }
    }

    struct Effect: Equatable, Sendable {
        enum Kind: Equatable, Sendable {
            enum AnimatableData: VectorArithmetic, Sendable {
                case shadow(ResolvedShadowStyle.AnimatableData)
                case zero

                init(_ kind: Kind) {
                    switch kind {
                    case let .shadow(shadow):
                        self = .shadow(shadow.animatableData)
                    case .none:
                        self = .zero
                    }
                }

                static func += (lhs: inout Self, rhs: Self) {
                    switch (lhs, rhs) {
                    case (.zero, _):
                        lhs = rhs
                    case (_, .zero):
                        break
                    case let (.shadow(lhsValue), .shadow(rhsValue)):
                        lhs = .shadow(lhsValue + rhsValue)
                    }
                }

                static func -= (lhs: inout Self, rhs: Self) {
                    switch (lhs, rhs) {
                    case (_, .zero):
                        break
                    case (.zero, let value):
                        var value = value
                        value.scale(by: -1)
                        lhs = value
                    case let (.shadow(lhsValue), .shadow(rhsValue)):
                        lhs = .shadow(lhsValue - rhsValue)
                    }
                }

                static func + (lhs: Self, rhs: Self) -> Self {
                    var result = lhs
                    result += rhs
                    return result
                }

                static func - (lhs: Self, rhs: Self) -> Self {
                    var result = lhs
                    result -= rhs
                    return result
                }

                mutating func scale(by rhs: Double) {
                    if case var .shadow(value) = self {
                        value.scale(by: rhs)
                        self = .shadow(value)
                    }
                }

                var magnitudeSquared: Double {
                    switch self {
                    case let .shadow(value):
                        value.magnitudeSquared
                    case .zero:
                        0
                    }
                }

                func set(kind: inout Kind) {
                    guard case var .shadow(shadow) = kind,
                          case let .shadow(data) = self else {
                        return
                    }
                    shadow.animatableData = data
                    kind = .shadow(shadow)
                }
            }

            case shadow(ResolvedShadowStyle)
            case none

            var animatableData: AnimatableData {
                get { AnimatableData(self) }
                set { newValue.set(kind: &self) }
            }
        }

        var kind: Kind
        var opacity: Float
        var _blend: GraphicsContext.BlendMode?

        typealias AnimatableData = AnimatablePair<Float, Kind.AnimatableData>

        var animatableData: AnimatableData {
            get { AnimatableData(opacity, kind.animatableData) }
            set {
                opacity = newValue.first
                kind.animatableData = newValue.second
            }
        }
    }

    struct Style: Equatable, Sendable {
        var fill: Fill
        var opacity: Float
        var _blend: GraphicsContext.BlendMode?
        var effects: [Effect]

        init(_ fill: Fill) {
            self.fill = fill
            self.opacity = 1
            self._blend = nil
            self.effects = []
        }

        mutating func applyBlend(_ blend: GraphicsContext.BlendMode) {
            // An explicit normal blend also owns its slot; fill only unset values.
            if _blend == nil { _blend = blend }
            for index in effects.indices where effects[index]._blend == nil {
                effects[index]._blend = blend
            }
        }

        typealias AnimatableData = AnimatablePair<
            Fill.AnimatableData,
            AnimatablePair<Float, AnimatableArray<Effect.AnimatableData>>
        >

        var animatableData: AnimatableData {
            get {
                AnimatableData(
                    fill.animatableData,
                    AnimatablePair(
                        opacity,
                        AnimatableArray(effects.map(\.animatableData))
                    )
                )
            }
            set {
                fill.animatableData = newValue.first
                opacity = newValue.second.first
                for index in effects.indices
                    where index < newValue.second.second.elements.count {
                    effects[index].animatableData =
                        newValue.second.second.elements[index]
                }
            }
        }
    }

    var styles: [(key: Key, style: Style)]

    init(styles: [(key: Key, style: Style)] = []) {
        self.styles = styles
    }

    typealias AnimatableData = KeyedAnimatableArray<Key, Style.AnimatableData>

    var animatableData: AnimatableData {
        get {
            AnimatableData(styles.map {
                AnimatableData.Element(
                    key: $0.key,
                    data: $0.style.animatableData
                )
            })
        }
        set {
            newValue.extract(
                into: &styles,
                key: { $0.key },
                set: { $0.style.animatableData = $1 }
            )
        }
    }

    static func fill(
        _ fill: Fill,
        name: _ShapeStyle_Name = .foreground,
        level: Int = 0
    ) -> _ShapeStyle_Pack {
        _ShapeStyle_Pack(styles: [(Key(name, level), Style(fill))])
    }

    func isClear(name: _ShapeStyle_Name) -> Bool {
        !styles.contains { entry in
            guard entry.key.name == name, entry.style.opacity > 0 else {
                return false
            }
            switch entry.style.fill {
            case .color(let color):
                return color.opacity > 0
            case .paint(let paint):
                guard let paint = paint as? _AnyResolvedPaint<MeshGradient._Paint> else {
                    return true
                }
                return paint.paint.background.opacity > 0 ||
                    paint.paint.colors.contains { $0.opacity > 0 }
            }
        }
    }

    func shapeStyle(
        name: _ShapeStyle_Name = .foreground,
        level: Int = 0
    ) -> AnyShapeStyle? {
        guard let entry = styles.first(where: {
            $0.key.name == name && $0.key._level == UInt8(level)
        }) else {
            return nil
        }
        switch entry.style.fill {
        case let .color(color):
            return AnyShapeStyle(Color(color))
        case let .paint(paint):
            guard let paint = paint as? _AnyResolvedPaint<MeshGradient._Paint> else {
                return nil
            }
            return AnyShapeStyle(paint.paint.meshGradient)
        }
    }
}
