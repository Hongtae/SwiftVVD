//
//  File: MeshGradient.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import VVD

public struct MeshGradient: ShapeStyle, Equatable, Sendable {
    public enum Locations: Equatable, Sendable {
        case points([SIMD2<Float>])
        case bezierPoints([BezierPoint])
    }

    public enum Colors: Equatable, Sendable {
        case colors([Color])
        case resolvedColors([Color.Resolved])
    }

    public struct BezierPoint: Equatable, Sendable {
        public var position: SIMD2<Float>
        public var leadingControlPoint: SIMD2<Float>
        public var topControlPoint: SIMD2<Float>
        public var trailingControlPoint: SIMD2<Float>
        public var bottomControlPoint: SIMD2<Float>

        public init(
            position: SIMD2<Float>,
            leadingControlPoint: SIMD2<Float>,
            topControlPoint: SIMD2<Float>,
            trailingControlPoint: SIMD2<Float>,
            bottomControlPoint: SIMD2<Float>
        ) {
            self.position = position
            self.leadingControlPoint = leadingControlPoint
            self.topControlPoint = topControlPoint
            self.trailingControlPoint = trailingControlPoint
            self.bottomControlPoint = bottomControlPoint
        }
    }

    public var width: Int
    public var height: Int
    public var locations: Locations
    public var colors: Colors
    public var background: Color
    public var smoothsColors: Bool
    public var colorSpace: Gradient.ColorSpace

    public init(
        width: Int,
        height: Int,
        locations: Locations,
        colors: Colors,
        background: Color = .clear,
        smoothsColors: Bool = true,
        colorSpace: Gradient.ColorSpace = .device
    ) {
        self.width = width
        self.height = height
        self.locations = locations
        self.colors = colors
        self.background = background
        self.smoothsColors = smoothsColors
        self.colorSpace = colorSpace
    }

    public init(
        width: Int,
        height: Int,
        points: [SIMD2<Float>],
        colors: [Color],
        background: Color = .clear,
        smoothsColors: Bool = true,
        colorSpace: Gradient.ColorSpace = .device
    ) {
        self.init(
            width: width,
            height: height,
            locations: .points(points),
            colors: .colors(colors),
            background: background,
            smoothsColors: smoothsColors,
            colorSpace: colorSpace
        )
    }

    public init(
        width: Int,
        height: Int,
        points: [SIMD2<Float>],
        resolvedColors: [Color.Resolved],
        background: Color = .clear,
        smoothsColors: Bool = true,
        colorSpace: Gradient.ColorSpace = .device
    ) {
        self.init(
            width: width,
            height: height,
            locations: .points(points),
            colors: .resolvedColors(resolvedColors),
            background: background,
            smoothsColors: smoothsColors,
            colorSpace: colorSpace
        )
    }

    public init(
        width: Int,
        height: Int,
        bezierPoints: [BezierPoint],
        colors: [Color],
        background: Color = .clear,
        smoothsColors: Bool = true,
        colorSpace: Gradient.ColorSpace = .device
    ) {
        self.init(
            width: width,
            height: height,
            locations: .bezierPoints(bezierPoints),
            colors: .colors(colors),
            background: background,
            smoothsColors: smoothsColors,
            colorSpace: colorSpace
        )
    }

    public init(
        width: Int,
        height: Int,
        bezierPoints: [BezierPoint],
        resolvedColors: [Color.Resolved],
        background: Color = .clear,
        smoothsColors: Bool = true,
        colorSpace: Gradient.ColorSpace = .device
    ) {
        self.init(
            width: width,
            height: height,
            locations: .bezierPoints(bezierPoints),
            colors: .resolvedColors(resolvedColors),
            background: background,
            smoothsColors: smoothsColors,
            colorSpace: colorSpace
        )
    }

    public static func _makeView<S>(
        view: _GraphValue<_ShapeView<S, MeshGradient>>,
        inputs: _ViewInputs
    ) -> _ViewOutputs where S: Shape {
        _ShapeView<S, MeshGradient>._makeView(view: view, inputs: inputs)
    }

    public func _apply(to shape: inout _ShapeStyle_Shape) {
        shape.shading = .meshGradient(self)
    }

    public typealias Resolved = Never
}

extension MeshGradient: View {
    public typealias Body = _ShapeView<Rectangle, MeshGradient>
}

private struct MeshGradientSampleColor {
    var components: SIMD3<Double>
    var opacity: Double
}

extension GraphicsContext {
    func meshGradientVertices(_ mesh: MeshGradient, bounds: CGRect) -> [_Vertex] {
        let bounds = meshGradientBounds(bounds)
        guard !bounds.isNull, !bounds.isEmpty else { return [] }

        var vertices = meshGradientBackgroundVertices(mesh.background, bounds: bounds)
        guard mesh.width > 1,
              mesh.height > 1,
              mesh.width <= Int.max / mesh.height else {
            return vertices
        }
        let count = mesh.width * mesh.height
        let locations: [MeshGradient.BezierPoint]
        let usesBezierLocations: Bool
        switch mesh.locations {
        case let .points(points):
            guard points.count == count else { return vertices }
            locations = points.map {
                MeshGradient.BezierPoint(
                    position: $0,
                    leadingControlPoint: $0,
                    topControlPoint: $0,
                    trailingControlPoint: $0,
                    bottomControlPoint: $0
                )
            }
            usesBezierLocations = false
        case let .bezierPoints(points):
            guard points.count == count else { return vertices }
            locations = points
            usesBezierLocations = true
        }

        var resolvedColors: [Color.Resolved]
        switch mesh.colors {
        case let .colors(colors):
            resolvedColors = colors.map { $0.resolve(in: environment) }
        case let .resolvedColors(colors):
            resolvedColors = colors
        }
        if resolvedColors.count < count {
            resolvedColors.append(
                contentsOf: repeatElement(
                    Color.Resolved(
                        colorSpace: .sRGBLinear,
                        red: 0,
                        green: 0,
                        blue: 0,
                        opacity: 0
                    ),
                    count: count - resolvedColors.count
                )
            )
        } else if resolvedColors.count > count {
            resolvedColors.removeLast(resolvedColors.count - count)
        }

        let perceptual = mesh.colorSpace == .perceptual
        let sampleColors = resolvedColors.map { color in
            MeshGradientSampleColor(
                components: perceptual
                    ? meshGradientOklab(
                        SIMD3(
                            Double(color.linearRed),
                            Double(color.linearGreen),
                            Double(color.linearBlue)
                        )
                    )
                    : SIMD3(
                        Double(color.red),
                        Double(color.green),
                        Double(color.blue)
                    ),
                opacity: Double(color.opacity)
            )
        }

        let subdivisions = 16
        let transform = self.transform.concatenating(viewTransform)
        vertices.reserveCapacity(
            vertices.count
                + (mesh.width - 1) * (mesh.height - 1)
                * subdivisions * subdivisions * 6
        )

        func location(_ x: Int, _ y: Int) -> MeshGradient.BezierPoint {
            locations[y * mesh.width + x]
        }
        func color(_ x: Int, _ y: Int) -> MeshGradientSampleColor {
            sampleColors[y * mesh.width + x]
        }
        func vertex(
            x: Int,
            y: Int,
            u: Double,
            v: Double
        ) -> _Vertex {
            let topLeft = location(x, y)
            let topRight = location(x + 1, y)
            let bottomLeft = location(x, y + 1)
            let bottomRight = location(x + 1, y + 1)
            let normalizedPosition = usesBezierLocations
                ? meshGradientCoonsPosition(
                    topLeft: topLeft,
                    topRight: topRight,
                    bottomLeft: bottomLeft,
                    bottomRight: bottomRight,
                    u: u,
                    v: v
                )
                : meshGradientBilinear(
                    topLeft.position,
                    topRight.position,
                    bottomLeft.position,
                    bottomRight.position,
                    u: u,
                    v: v
                )
            let point = CGPoint(
                x: bounds.minX + CGFloat(normalizedPosition.x) * bounds.width,
                y: bounds.minY + CGFloat(normalizedPosition.y) * bounds.height
            ).applying(transform)

            let colorU = mesh.smoothsColors ? meshGradientSmoothstep(u) : u
            let colorV = mesh.smoothsColors ? meshGradientSmoothstep(v) : v
            let sample = meshGradientBilinear(
                color(x, y),
                color(x + 1, y),
                color(x, y + 1),
                color(x + 1, y + 1),
                u: colorU,
                v: colorV
            )
            let encoded: SIMD3<Double>
            if perceptual {
                encoded = meshGradientEncodedSRGB(
                    meshGradientLinearSRGB(fromOklab: sample.components)
                )
            } else {
                encoded = sample.components
            }
            let alpha = Float(sample.opacity)
            return _Vertex(
                position: Vector2(point).float2,
                texcoord: (0, 0),
                color: (
                    Float(encoded.x) * alpha,
                    Float(encoded.y) * alpha,
                    Float(encoded.z) * alpha,
                    alpha
                )
            )
        }

        for y in 0..<(mesh.height - 1) {
            for x in 0..<(mesh.width - 1) {
                for row in 0..<subdivisions {
                    let v0 = Double(row) / Double(subdivisions)
                    let v1 = Double(row + 1) / Double(subdivisions)
                    for column in 0..<subdivisions {
                        let u0 = Double(column) / Double(subdivisions)
                        let u1 = Double(column + 1) / Double(subdivisions)
                        let topLeft = vertex(x: x, y: y, u: u0, v: v0)
                        let topRight = vertex(x: x, y: y, u: u1, v: v0)
                        let bottomLeft = vertex(x: x, y: y, u: u0, v: v1)
                        let bottomRight = vertex(x: x, y: y, u: u1, v: v1)
                        vertices.append(contentsOf: [
                            topLeft, bottomLeft, topRight,
                            topRight, bottomLeft, bottomRight,
                        ])
                    }
                }
            }
        }
        return vertices
    }

    private func meshGradientBounds(_ bounds: CGRect) -> CGRect {
        if !bounds.isNull, !bounds.isEmpty, !bounds.isInfinite {
            return bounds.standardized
        }
        return CGRect(
            origin: -contentOffset,
            size: viewport.size / contentScaleFactor
        ).standardized
    }

    private func meshGradientBackgroundVertices(
        _ color: Color,
        bounds: CGRect
    ) -> [_Vertex] {
        let transform = self.transform.concatenating(viewTransform)
        let color = color.backendColor(in: environment)
        let alpha = Float(color.a)
        let vertexColor: Float4 = (
            Float(color.r) * alpha,
            Float(color.g) * alpha,
            Float(color.b) * alpha,
            alpha
        )
        func vertex(_ x: CGFloat, _ y: CGFloat) -> _Vertex {
            _Vertex(
                position: Vector2(CGPoint(x: x, y: y).applying(transform)).float2,
                texcoord: (0, 0),
                color: vertexColor
            )
        }
        let topLeft = vertex(bounds.minX, bounds.minY)
        let topRight = vertex(bounds.maxX, bounds.minY)
        let bottomLeft = vertex(bounds.minX, bounds.maxY)
        let bottomRight = vertex(bounds.maxX, bounds.maxY)
        return [
            topLeft, bottomLeft, topRight,
            topRight, bottomLeft, bottomRight,
        ]
    }
}

private func meshGradientBilinear(
    _ topLeft: SIMD2<Float>,
    _ topRight: SIMD2<Float>,
    _ bottomLeft: SIMD2<Float>,
    _ bottomRight: SIMD2<Float>,
    u: Double,
    v: Double
) -> SIMD2<Float> {
    let u = Float(u)
    let v = Float(v)
    return (topLeft + (topRight - topLeft) * u) * (1 - v)
        + (bottomLeft + (bottomRight - bottomLeft) * u) * v
}

private func meshGradientBilinear(
    _ topLeft: MeshGradientSampleColor,
    _ topRight: MeshGradientSampleColor,
    _ bottomLeft: MeshGradientSampleColor,
    _ bottomRight: MeshGradientSampleColor,
    u: Double,
    v: Double
) -> MeshGradientSampleColor {
    let topComponents = topLeft.components
        + (topRight.components - topLeft.components) * u
    let bottomComponents = bottomLeft.components
        + (bottomRight.components - bottomLeft.components) * u
    let topOpacity = topLeft.opacity + (topRight.opacity - topLeft.opacity) * u
    let bottomOpacity = bottomLeft.opacity + (bottomRight.opacity - bottomLeft.opacity) * u
    return MeshGradientSampleColor(
        components: topComponents + (bottomComponents - topComponents) * v,
        opacity: topOpacity + (bottomOpacity - topOpacity) * v
    )
}

private func meshGradientCubic(
    _ p0: SIMD2<Float>,
    _ p1: SIMD2<Float>,
    _ p2: SIMD2<Float>,
    _ p3: SIMD2<Float>,
    t: Double
) -> SIMD2<Float> {
    let t = Float(t)
    let oneMinusT = 1 - t
    return p0 * (oneMinusT * oneMinusT * oneMinusT)
        + p1 * (3 * oneMinusT * oneMinusT * t)
        + p2 * (3 * oneMinusT * t * t)
        + p3 * (t * t * t)
}

private func meshGradientCoonsPosition(
    topLeft: MeshGradient.BezierPoint,
    topRight: MeshGradient.BezierPoint,
    bottomLeft: MeshGradient.BezierPoint,
    bottomRight: MeshGradient.BezierPoint,
    u: Double,
    v: Double
) -> SIMD2<Float> {
    let top = meshGradientCubic(
        topLeft.position,
        topLeft.trailingControlPoint,
        topRight.leadingControlPoint,
        topRight.position,
        t: u
    )
    let bottom = meshGradientCubic(
        bottomLeft.position,
        bottomLeft.trailingControlPoint,
        bottomRight.leadingControlPoint,
        bottomRight.position,
        t: u
    )
    let left = meshGradientCubic(
        topLeft.position,
        topLeft.bottomControlPoint,
        bottomLeft.topControlPoint,
        bottomLeft.position,
        t: v
    )
    let right = meshGradientCubic(
        topRight.position,
        topRight.bottomControlPoint,
        bottomRight.topControlPoint,
        bottomRight.position,
        t: v
    )
    let bilinear = meshGradientBilinear(
        topLeft.position,
        topRight.position,
        bottomLeft.position,
        bottomRight.position,
        u: u,
        v: v
    )
    return top * Float(1 - v) + bottom * Float(v)
        + left * Float(1 - u) + right * Float(u) - bilinear
}

private func meshGradientSmoothstep(_ value: Double) -> Double {
    value * value * (3 - 2 * value)
}

private func meshGradientOklab(_ color: SIMD3<Double>) -> SIMD3<Double> {
    func signedCubeRoot(_ value: Double) -> Double {
        value.sign == .minus
            ? -pow(-value, 1.0 / 3.0)
            : pow(value, 1.0 / 3.0)
    }
    let l = signedCubeRoot(
        0.4122214708 * color.x + 0.5363325363 * color.y + 0.0514459929 * color.z
    )
    let m = signedCubeRoot(
        0.2119034982 * color.x + 0.6806995451 * color.y + 0.1073969566 * color.z
    )
    let s = signedCubeRoot(
        0.0883024619 * color.x + 0.2817188376 * color.y + 0.6299787005 * color.z
    )
    return SIMD3(
        0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
        1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
        0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
    )
}

private func meshGradientLinearSRGB(fromOklab color: SIMD3<Double>) -> SIMD3<Double> {
    let l = pow(color.x + 0.3963377774 * color.y + 0.2158037573 * color.z, 3)
    let m = pow(color.x - 0.1055613458 * color.y - 0.0638541728 * color.z, 3)
    let s = pow(color.x - 0.0894841775 * color.y - 1.2914855480 * color.z, 3)
    return SIMD3(
        4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
        -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
        -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
    )
}

private func meshGradientEncodedSRGB(_ color: SIMD3<Double>) -> SIMD3<Double> {
    func encode(_ value: Double) -> Double {
        let magnitude = abs(value)
        let encoded = magnitude <= 0.0031308
            ? magnitude * 12.92
            : 1.055 * pow(magnitude, 1.0 / 2.4) - 0.055
        return value.sign == .minus ? -encoded : encoded
    }
    return SIMD3(encode(color.x), encode(color.y), encode(color.z))
}
