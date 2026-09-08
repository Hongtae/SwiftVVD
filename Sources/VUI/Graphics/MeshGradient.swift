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
        shape.resolvedShading = .meshGradient(self)
    }

    public typealias Resolved = Never
}

extension MeshGradient: View {
    public typealias Body = _ShapeView<Rectangle, MeshGradient>
}

extension MeshGradient.Locations: ProtobufEncodableMessage, ProtobufDecodableMessage {
    func encode(to encoder: inout ProtobufEncoder) throws {
        switch self {
        case let .points(points):
            for point in points {
                encoder.encodeVarint(1 << 3 | 2)
                encoder.startLengthDelimited()
                if point.x != 0 { encoder.encodeFloatFieldAlways(1, point.x) }
                if point.y != 0 { encoder.encodeFloatFieldAlways(2, point.y) }
                encoder.endLengthDelimited()
            }
        case let .bezierPoints(points):
            for point in points {
                encoder.encodeVarint(2 << 3 | 2)
                encoder.startLengthDelimited()
                withUnsafeBytes(of: point) { bytes in
                    // The five SIMD2 values contain ten consecutive Float components.
                    for index in 0..<10 {
                        let value = bytes.load(fromByteOffset: index * MemoryLayout<Float>.stride, as: Float.self)
                        if value != 0 { encoder.encodeFloatFieldAlways(UInt(index + 1), value) }
                    }
                }
                encoder.endLengthDelimited()
            }
        }
    }

    init(from decoder: inout ProtobufDecoder) throws {
        var points: [SIMD2<Float>] = []
        var bezierPoints: [MeshGradient.BezierPoint] = []
        while !decoder.isAtEnd {
            let tag = try decoder.decodeVarint()
            guard tag >= 8 else { throw ProtobufDecoder.DecodingError.failed }
            let wireType = tag & 7
            switch tag >> 3 {
            case 1:
                guard wireType == 2 else { throw ProtobufDecoder.DecodingError.failed }
                let point = try decoder.decodeLengthDelimited { decoder in
                    var point = SIMD2<Float>.zero
                    while !decoder.isAtEnd {
                        let tag = try decoder.decodeVarint()
                        guard tag >= 8 else { throw ProtobufDecoder.DecodingError.failed }
                        let wireType = tag & 7
                        switch tag >> 3 {
                        case 1: point.x = try decoder.decodeFloatField(wireType: wireType)
                        case 2: point.y = try decoder.decodeFloatField(wireType: wireType)
                        default: try decoder.skipField(wireType: wireType)
                        }
                    }
                    return point
                }
                points.append(point)
            case 2:
                guard wireType == 2 else { throw ProtobufDecoder.DecodingError.failed }
                let point = try decoder.decodeLengthDelimited { decoder in
                    var point = MeshGradient.BezierPoint(
                        position: .zero, leadingControlPoint: .zero, topControlPoint: .zero,
                        trailingControlPoint: .zero, bottomControlPoint: .zero
                    )
                    try withUnsafeMutableBytes(of: &point) { bytes in
                        while !decoder.isAtEnd {
                            let tag = try decoder.decodeVarint()
                            guard tag >= 8 else { throw ProtobufDecoder.DecodingError.failed }
                            let field = tag >> 3
                            let wireType = tag & 7
                            if field <= 10 {
                                let value = try decoder.decodeFloatField(wireType: wireType)
                                bytes.storeBytes(of: value, toByteOffset: Int(field - 1) * MemoryLayout<Float>.stride, as: Float.self)
                            } else {
                                try decoder.skipField(wireType: wireType)
                            }
                        }
                    }
                    return point
                }
                bezierPoints.append(point)
            default:
                try decoder.skipField(wireType: wireType)
            }
        }
        self = bezierPoints.isEmpty ? .points(points) : .bezierPoints(bezierPoints)
    }
}

extension MeshGradient._Paint: ProtobufEncodableMessage, ProtobufDecodableMessage {
    func encode(to encoder: inout ProtobufEncoder) throws {
        try encoder.encodeMessageField(1, locations)
        for color in colors { try encoder.encodeMessageField(2, color) }
        if background.linearRed != 0 || background.linearGreen != 0 || background.linearBlue != 0
            || background.opacity != 0 || !background._headroom.isNaN {
            try encoder.encodeMessageField(3, background)
        }
        if width > 0 {
            encoder.encodeVarint(4 << 3)
            encoder.encodeVarint(UInt(width))
        }
        if height > 0 {
            encoder.encodeVarint(5 << 3)
            encoder.encodeVarint(UInt(height))
        }
        if flags.rawValue != 0 {
            encoder.encodeVarint(6 << 3)
            encoder.encodeVarint(UInt(flags.rawValue))
        }
        if allowedDynamicRange != .standard {
            encoder.encodeVarint(7 << 3)
            encoder.encodeVarint(allowedDynamicRange == .constrainedHigh ? 1 : 2)
        }
    }

    init(from decoder: inout ProtobufDecoder) throws {
        var locations = MeshGradient.Locations.points([])
        var colors: [Color.Resolved] = []
        var background = Color.ResolvedHDR(.init(colorSpace: .sRGBLinear, red: 0, green: 0, blue: 0, opacity: 0))
        var width = 0
        var height = 0
        var flags = MeshGradient._PaintFlags(rawValue: 0)
        var allowedDynamicRange = Image.DynamicRange.standard
        while !decoder.isAtEnd {
            let tag = try decoder.decodeVarint()
            guard tag >= 8 else { throw ProtobufDecoder.DecodingError.failed }
            let wireType = tag & 7
            switch tag >> 3 {
            case 1:
                guard wireType == 2 else { throw ProtobufDecoder.DecodingError.failed }
                locations = try decoder.decodeMessage()
            case 2:
                guard wireType == 2 else { throw ProtobufDecoder.DecodingError.failed }
                colors.append(try decoder.decodeMessage())
            case 3:
                guard wireType == 2 else { throw ProtobufDecoder.DecodingError.failed }
                background = try decoder.decodeMessage()
            case 4:
                try decoder.decodeUIntField(wireType: wireType) {
                    if let value = Int(exactly: $0) { width = value }
                }
            case 5:
                try decoder.decodeUIntField(wireType: wireType) {
                    if let value = Int(exactly: $0) { height = value }
                }
            case 6:
                flags = .init(rawValue: UInt32(truncatingIfNeeded: try decoder.decodeUIntField(wireType: wireType)))
            case 7:
                let value = try decoder.decodeUIntField(wireType: wireType)
                allowedDynamicRange = value == 1 ? .constrainedHigh : value == 2 ? .high : .standard
            default:
                try decoder.skipField(wireType: wireType)
            }
        }
        self.init(locations: locations, colors: colors, background: background,
                  width: width, height: height, allowedDynamicRange: allowedDynamicRange, flags: flags)
    }
}

extension MeshGradient {
    struct _PaintFlags: OptionSet, Equatable, Sendable {
        let rawValue: UInt32

        static let smoothsColors = Self(rawValue: 0x10)
        static let perceptualColorSpace = Self(rawValue: 0x03)
    }

    struct _Paint: Equatable, Animatable, Sendable {
        typealias ColorData = Color.Resolved.AnimatableData
        typealias AnimatableData = AnimatablePair<
            AnimatableArray<Float>,
            AnimatablePair<
                AnimatableArray<ColorData>,
                Color.ResolvedHDR._Animatable
            >
        >

        var locations: Locations
        var colors: [Color.Resolved]
        var background: Color.ResolvedHDR
        var width: Int
        var height: Int
        var allowedDynamicRange: Image.DynamicRange
        var flags: _PaintFlags

        var animatableData: AnimatableData {
            get {
                AnimatableData(
                    AnimatableArray(locationComponents),
                    AnimatablePair(
                        AnimatableArray(colors.map(\.animatableData)),
                        background.animatableData
                    )
                )
            }
            set {
                setLocationComponents(newValue.first.elements)
                for index in colors.indices where index < newValue.second.first.elements.count {
                    colors[index].animatableData = newValue.second.first.elements[index]
                }
                background.animatableData = newValue.second.second
            }
        }

        var meshGradient: MeshGradient {
            MeshGradient(
                width: width,
                height: height,
                locations: locations,
                colors: .resolvedColors(colors),
                background: Color(background),
                smoothsColors: flags.contains(.smoothsColors),
                colorSpace: flags.contains(.perceptualColorSpace)
                    ? .perceptual
                    : .device
            )
        }

        private var locationComponents: [Float] {
            switch locations {
            case let .points(points):
                return points.flatMap { [$0.x, $0.y] }
            case let .bezierPoints(points):
                return points.flatMap {
                    [
                        $0.position.x, $0.position.y,
                        $0.leadingControlPoint.x, $0.leadingControlPoint.y,
                        $0.topControlPoint.x, $0.topControlPoint.y,
                        $0.trailingControlPoint.x, $0.trailingControlPoint.y,
                        $0.bottomControlPoint.x, $0.bottomControlPoint.y,
                    ]
                }
            }
        }

        private mutating func setLocationComponents(_ values: [Float]) {
            switch locations {
            case var .points(points):
                for index in points.indices {
                    let offset = index * 2
                    guard offset + 1 < values.count else { break }
                    points[index] = SIMD2(values[offset], values[offset + 1])
                }
                locations = .points(points)
            case var .bezierPoints(points):
                for index in points.indices {
                    let offset = index * 10
                    guard offset + 9 < values.count else { break }
                    points[index] = BezierPoint(
                        position: SIMD2(values[offset], values[offset + 1]),
                        leadingControlPoint: SIMD2(values[offset + 2], values[offset + 3]),
                        topControlPoint: SIMD2(values[offset + 4], values[offset + 5]),
                        trailingControlPoint: SIMD2(values[offset + 6], values[offset + 7]),
                        bottomControlPoint: SIMD2(values[offset + 8], values[offset + 9])
                    )
                }
                locations = .bezierPoints(points)
            }
        }
    }

    func resolvePaint(in environment: EnvironmentValues) -> _Paint {
        let resolvedBackground = background.resolveHDR(in: environment)
        var maximumHeadroom = resolvedBackground._headroom
        let resolvedColors: [Color.Resolved]
        switch colors {
        case let .colors(colors):
            resolvedColors = colors.map {
                let resolved = $0.resolveHDR(in: environment)
                maximumHeadroom = Self.maximumHeadroom(
                    maximumHeadroom,
                    resolved._headroom
                )
                return resolved.base
            }
        case let .resolvedColors(colors):
            resolvedColors = colors
        }
        var flags: _PaintFlags = []
        if smoothsColors {
            flags.insert(.smoothsColors)
        }
        if colorSpace == .perceptual {
            flags.insert(.perceptualColorSpace)
        }
        return _Paint(
            locations: locations,
            colors: resolvedColors,
            background: resolvedBackground,
            width: width,
            height: height,
            allowedDynamicRange: maximumHeadroom > 1
                ? environment.effectiveAllowedDynamicRange(explicitRange: nil)
                : .standard,
            flags: flags
        )
    }

    private static func maximumHeadroom(_ lhs: Float, _ rhs: Float) -> Float {
        if lhs.isNaN {
            return rhs
        }
        if rhs.isNaN {
            return lhs
        }
        return max(lhs, rhs)
    }
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
    let top = ((topLeft + (topRight - topLeft) * u) * (1 - v))
    let bottom = ((bottomLeft + (bottomRight - bottomLeft) * u) * v)
    return top + bottom
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
