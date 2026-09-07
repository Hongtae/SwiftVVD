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

    struct _Paint: Equatable, Sendable {
        var gradient: ResolvedGradient
        var startPoint: UnitPoint
        var endPoint: UnitPoint
        var allowedDynamicRange: Image.DynamicRange

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

    struct AbsolutePaint: Equatable, Sendable {
        var gradient: ResolvedGradient
        var startPoint: CGPoint
        var endPoint: CGPoint
        var allowedDynamicRange: Image.DynamicRange
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
