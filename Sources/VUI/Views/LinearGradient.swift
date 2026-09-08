//
//  File: LinearGradient.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

public struct LinearGradient: ShapeStyle, View, Sendable {
    var gradient: Gradient
    var startPoint: UnitPoint
    var endPoint: UnitPoint

    public init(gradient: Gradient, startPoint: UnitPoint, endPoint: UnitPoint) {
        self.gradient = gradient
        self.startPoint = startPoint
        self.endPoint = endPoint
    }

    public init(colors: [Color], startPoint: UnitPoint, endPoint: UnitPoint) {
        self.init(gradient: Gradient(colors: colors), startPoint: startPoint, endPoint: endPoint)
    }

    public init(stops: [Gradient.Stop], startPoint: UnitPoint, endPoint: UnitPoint) {
        self.init(gradient: Gradient(stops: stops), startPoint: startPoint, endPoint: endPoint)
    }

    public typealias Body = _ShapeView<Rectangle, LinearGradient>
    public typealias Resolved = Never

    public func _apply(to shape: inout _ShapeStyle_Shape) {
        switch shape.operation {
        case .prepareText:
            shape.result = .preparedText(.foregroundKeyColor)
        case let .resolveStyle(name, levels):
            guard !levels.isEmpty else { return }
            resolvePaint(in: shape.environment).store(in: &shape, name: name, level: levels.lowerBound)
        case .fallbackColor:
            if let color = gradient.stops.first?.color { shape.result = .color(color) }
        case .copyStyle, .modifyBackground, .multiLevel, .primaryStyle:
            break
        }
    }

    public static func _apply(to type: inout _ShapeStyle_ShapeType) {}

    func resolvePaint(in environment: EnvironmentValues) -> _Paint {
        let resolved = gradient.resolve(in: environment)
        return .init(gradient: resolved, startPoint: startPoint, endPoint: endPoint,
                     allowedDynamicRange: (resolved.headroom ?? 1) > 1
                         ? environment.effectiveAllowedDynamicRange(explicitRange: nil) : .standard)
    }

    struct _Paint: Equatable, Animatable, Sendable {
        var gradient: ResolvedGradient
        var startPoint: UnitPoint
        var endPoint: UnitPoint
        var allowedDynamicRange: Image.DynamicRange

        typealias AnimatableData = AnimatablePair<AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>>, ResolvedGradientVector>

        var animatableData: AnimatableData {
            get {
                .init(.init(.init(startPoint.x * 128, startPoint.y * 128),
                            .init(endPoint.x * 128, endPoint.y * 128)), gradient.animatableData)
            }
            set {
                startPoint = UnitPoint(x: newValue.first.first.first / 128, y: newValue.first.first.second / 128)
                endPoint = UnitPoint(x: newValue.first.second.first / 128, y: newValue.first.second.second / 128)
                gradient.animatableData = newValue.second
            }
        }

        func store(in shape: inout _ShapeStyle_Shape, name: _ShapeStyle_Name, level: Int) {
            let paint: AnyResolvedPaint
            if let bounds = shape.bounds {
                paint = _AnyResolvedPaint(AbsolutePaint(
                    gradient: gradient,
                    startPoint: CGPoint(x: bounds.origin.x + startPoint.x * bounds.size.width,
                                        y: bounds.origin.y + startPoint.y * bounds.size.height),
                    endPoint: CGPoint(x: bounds.origin.x + endPoint.x * bounds.size.width,
                                      y: bounds.origin.y + endPoint.y * bounds.size.height),
                    allowedDynamicRange: allowedDynamicRange
                ))
            } else {
                paint = _AnyResolvedPaint(self)
            }
            var style = _ShapeStyle_Pack.Style(.paint(paint))
            style.opacity = shape.opacity(at: level)
            shape.storeStyle(style, name: name, level: level)
        }
    }

    struct AbsolutePaint: Equatable, Animatable, Sendable {
        var gradient: ResolvedGradient
        var startPoint: CGPoint
        var endPoint: CGPoint
        var allowedDynamicRange: Image.DynamicRange

        typealias AnimatableData = AnimatablePair<AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>>, ResolvedGradientVector>

        var animatableData: AnimatableData {
            get {
                .init(.init(.init(startPoint.x, startPoint.y), .init(endPoint.x, endPoint.y)), gradient.animatableData)
            }
            set {
                startPoint = CGPoint(x: newValue.first.first.first, y: newValue.first.first.second)
                endPoint = CGPoint(x: newValue.first.second.first, y: newValue.first.second.second)
                gradient.animatableData = newValue.second
            }
        }
    }
}

extension LinearGradient._Paint: ProtobufEncodableMessage, ProtobufDecodableMessage {
    func encode(to encoder: inout ProtobufEncoder) throws {
        try encoder.encodeMessageField(1, gradient)
        if startPoint.x != 0 || startPoint.y != 0 {
            try encoder.encodeMessageField(2, startPoint)
        }
        if endPoint.x != 0 || endPoint.y != 0 {
            try encoder.encodeMessageField(3, endPoint)
        }
        if allowedDynamicRange != .standard {
            encoder.encodeVarint(4 << 3)
            encoder.encodeVarint(UInt(allowedDynamicRange.storage.rawValue))
        }
    }

    init(from decoder: inout ProtobufDecoder) throws {
        self.init(gradient: .init(stops: [], colorSpace: .default, headroom: nil),
                  startPoint: .init(x: 0, y: 0), endPoint: .init(x: 0, y: 0),
                  allowedDynamicRange: .standard)
        while !decoder.isAtEnd {
            let tag = try decoder.decodeVarint()
            guard tag >= 8 else { throw ProtobufDecoder.DecodingError.failed }
            let wireType = tag & 7
            switch tag >> 3 {
            case 1:
                guard wireType == 2 else { throw ProtobufDecoder.DecodingError.failed }
                gradient = try decoder.decodeMessage(ResolvedGradient.self)
            case 2:
                guard wireType == 2 else { throw ProtobufDecoder.DecodingError.failed }
                startPoint = try decoder.decodeMessage(UnitPoint.self)
            case 3:
                guard wireType == 2 else { throw ProtobufDecoder.DecodingError.failed }
                endPoint = try decoder.decodeMessage(UnitPoint.self)
            case 4:
                let raw = try decoder.decodeUIntField(wireType: wireType)
                allowedDynamicRange = Image.DynamicRange(
                    UInt8(exactly: raw).flatMap(Image.DynamicRange.Storage.init(rawValue:)) ?? .standard
                )
            default:
                try decoder.skipField(wireType: wireType)
            }
        }
    }
}

extension LinearGradient.AbsolutePaint: ProtobufEncodableMessage, ProtobufDecodableMessage {
    func encode(to encoder: inout ProtobufEncoder) throws {
        try encoder.encodeMessageField(1, gradient)
        if startPoint != .zero {
            try encoder.encodeMessageField(2, startPoint)
        }
        if endPoint != .zero {
            try encoder.encodeMessageField(3, endPoint)
        }
        if allowedDynamicRange != .standard {
            encoder.encodeVarint(4 << 3)
            encoder.encodeVarint(UInt(allowedDynamicRange.storage.rawValue))
        }
    }

    init(from decoder: inout ProtobufDecoder) throws {
        self.init(gradient: .init(stops: [], colorSpace: .default, headroom: nil),
                  startPoint: .zero, endPoint: .zero, allowedDynamicRange: .standard)
        while !decoder.isAtEnd {
            let tag = try decoder.decodeVarint()
            guard tag >= 8 else { throw ProtobufDecoder.DecodingError.failed }
            let wireType = tag & 7
            switch tag >> 3 {
            case 1:
                guard wireType == 2 else { throw ProtobufDecoder.DecodingError.failed }
                gradient = try decoder.decodeMessage(ResolvedGradient.self)
            case 2:
                guard wireType == 2 else { throw ProtobufDecoder.DecodingError.failed }
                startPoint = try decoder.decodeMessage(CGPoint.self)
            case 3:
                guard wireType == 2 else { throw ProtobufDecoder.DecodingError.failed }
                endPoint = try decoder.decodeMessage(CGPoint.self)
            case 4:
                let raw = try decoder.decodeUIntField(wireType: wireType)
                allowedDynamicRange = Image.DynamicRange(
                    UInt8(exactly: raw).flatMap(Image.DynamicRange.Storage.init(rawValue:)) ?? .standard
                )
            default:
                try decoder.skipField(wireType: wireType)
            }
        }
    }
}

public struct _AnyLinearGradient: ShapeStyle {
    var gradient: AnyGradient
    var startPoint: UnitPoint
    var endPoint: UnitPoint

    public typealias Resolved = Never

    public func _apply(to shape: inout _ShapeStyle_Shape) {
        switch shape.operation {
        case .prepareText:
            shape.result = .preparedText(.foregroundKeyColor)
        case let .resolveStyle(name, levels):
            guard !levels.isEmpty else { return }
            resolvePaint(in: shape.environment).store(in: &shape, name: name, level: levels.lowerBound)
        case .fallbackColor:
            if let color = gradient.provider.fallbackColor(in: shape.environment) {
                shape.result = .color(color)
            }
        case .copyStyle, .modifyBackground, .multiLevel, .primaryStyle:
            break
        }
    }

    public static func _apply(to type: inout _ShapeStyle_ShapeType) {}

    func resolvePaint(in environment: EnvironmentValues) -> LinearGradient._Paint {
        let resolved = gradient.resolve(in: environment)
        return .init(gradient: resolved, startPoint: startPoint, endPoint: endPoint,
                     allowedDynamicRange: (resolved.headroom ?? 1) > 1
                         ? environment.effectiveAllowedDynamicRange(explicitRange: nil) : .standard)
    }
}

extension ShapeStyle where Self == LinearGradient {
    public static func linearGradient(_ gradient: AnyGradient, startPoint: UnitPoint,
                                      endPoint: UnitPoint) -> some ShapeStyle {
        _AnyLinearGradient(gradient: gradient, startPoint: startPoint, endPoint: endPoint)
    }
}

extension AnyResolvedPaint {
    // Lower the retained paint only at the command encoder's boundary.
    func renderingShading(in bounds: CGRect, opacity: Float) -> GraphicsContext.Shading? {
        let gradient: ResolvedGradient
        let startPoint: CGPoint
        let endPoint: CGPoint
        if let paint = self as? _AnyResolvedPaint<LinearGradient._Paint> {
            gradient = paint.paint.gradient
            startPoint = CGPoint(x: bounds.origin.x + paint.paint.startPoint.x * bounds.size.width,
                                 y: bounds.origin.y + paint.paint.startPoint.y * bounds.size.height)
            endPoint = CGPoint(x: bounds.origin.x + paint.paint.endPoint.x * bounds.size.width,
                               y: bounds.origin.y + paint.paint.endPoint.y * bounds.size.height)
        } else if let paint = self as? _AnyResolvedPaint<LinearGradient.AbsolutePaint> {
            gradient = paint.paint.gradient
            startPoint = paint.paint.startPoint
            endPoint = paint.paint.endPoint
        } else if let paint = self as? _AnyResolvedPaint<MeshGradient._Paint> {
            return .meshGradient(paint.paint.meshGradient)
        } else {
            return nil
        }
        let stops = gradient.stops.map { stop in
            var color = Color.ResolvedHDR(stop.color, headroom: gradient.headroom)
            color.opacity *= opacity
            return Gradient.Stop(color: Color(color), location: stop.location)
        }
        return .linearGradient(Gradient(stops: stops), startPoint: startPoint, endPoint: endPoint)
    }
}
