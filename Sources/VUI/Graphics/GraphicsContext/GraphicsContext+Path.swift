//
//  File: GraphicsContext+Path.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import VVD

@inline(__always)
private func _premultipliedVertexColor(_ color: BackendColor) -> Float4 {
    let alpha = Float32(color.a)
    return (Float32(color.r) * alpha,
            Float32(color.g) * alpha,
            Float32(color.b) * alpha,
            alpha)
}

@inline(__always)
private func _pathElement(
    _ element: Path.Element,
    applying transform: CGAffineTransform
) -> Path.Element {
    switch element {
    case .move(let point):
        .move(to: point.applying(transform))
    case .line(let point):
        .line(to: point.applying(transform))
    case .quadCurve(let point, let control):
        .quadCurve(
            to: point.applying(transform),
            control: control.applying(transform)
        )
    case .curve(let point, let control1, let control2):
        .curve(
            to: point.applying(transform),
            control1: control1.applying(transform),
            control2: control2.applying(transform)
        )
    case .closeSubpath:
        .closeSubpath
    }
}

private struct StencilPathFillGeometryBuilder {
    let transform: CGAffineTransform

    var vertices: [Float2] = []
    var triangleIndices: [GraphicsContext.StencilPathFillGeometry.TriangleIndices] = []

    private var initialPoint: CGPoint?
    private var currentPoint: CGPoint?
    private var contourStart = 0
    private var centerX: Scalar = 0
    private var centerY: Scalar = 0

    init(transform: CGAffineTransform) {
        self.transform = transform
    }

    mutating func build(path: Path, pathTransform: CGAffineTransform?) {
        if let pathTransform, !pathTransform.isIdentity {
            path.forEach {
                append(_pathElement($0, applying: pathTransform))
            }
        } else {
            path.forEach { append($0) }
        }
        finish()
    }

    mutating func append(_ element: Path.Element) {
        switch element {
        case .move(let to):
            finishContour()
            initialPoint = to
            currentPoint = to

        case .line(let p1):
            if let p0 = currentPoint {
                if contourStart == vertices.count {
                    appendVertex(p0)
                }
                appendVertex(p1)
            }
            currentPoint = p1

        case .quadCurve(let p2, let p1):
            if let p0 = currentPoint {
                let curve = QuadraticBezier(p0: p0, p1: p1, p2: p2)
                let length = curve.approximateLength()
                if length > .ulpOfOne {
                    if contourStart == vertices.count {
                        appendVertex(p0)
                    }
                    let step = 1.0 / length
                    var t = step
                    while t < 1.0 {
                        appendVertex(curve.interpolate(t))
                        t += step
                    }
                    appendVertex(p2)
                }
            }
            currentPoint = p2

        case .curve(let p3, let p1, let p2):
            if let p0 = currentPoint {
                let curve = CubicBezier(p0: p0, p1: p1, p2: p2, p3: p3)
                let length = curve.approximateLength()
                if length > .ulpOfOne {
                    if contourStart == vertices.count {
                        appendVertex(p0)
                    }
                    let step = 1.0 / length
                    var t = step
                    while t < 1.0 {
                        appendVertex(curve.interpolate(t))
                        t += step
                    }
                    appendVertex(p3)
                }
            }
            currentPoint = p3

        case .closeSubpath:
            finishContour()
            currentPoint = initialPoint
        }
    }

    mutating func finish() {
        finishContour()
    }

    private mutating func appendVertex(_ point: CGPoint) {
        let point = point.applying(transform)
        vertices.append((Float32(point.x), Float32(point.y)))
        centerX += point.x
        centerY += point.y
    }

    private mutating func finishContour() {
        let count = vertices.count - contourStart
        guard count >= 2 else {
            if count > 0 {
                vertices.removeLast(count)
            }
            contourStart = vertices.count
            centerX = 0
            centerY = 0
            return
        }

        let baseIndex = UInt32(contourStart)
        let pivotIndex = UInt32(vertices.count)
        let inverseCount = Scalar(1) / Scalar(count)
        vertices.append((
            Float32(centerX * inverseCount),
            Float32(centerY * inverseCount)
        ))

        var index = baseIndex + 1
        while index < pivotIndex {
            triangleIndices.append((index - 1, index, pivotIndex))
            index += 1
        }
        triangleIndices.append((pivotIndex - 1, baseIndex, pivotIndex))

        contourStart = vertices.count
        centerX = 0
        centerY = 0
    }
}

extension GraphicsContext {
    struct StencilPathFillGeometry {
        typealias TriangleIndices = (UInt32, UInt32, UInt32)

        let vertices: [Float2]
        let triangleIndices: [TriangleIndices]

        var indexCount: Int { triangleIndices.count * 3 }

        init(
            path: Path,
            transform: CGAffineTransform,
            pathTransform: CGAffineTransform? = nil
        ) {
            var builder = StencilPathFillGeometryBuilder(transform: transform)
            builder.build(path: path, pathTransform: pathTransform)
            self.init(vertices: builder.vertices, triangleIndices: builder.triangleIndices)
        }

        fileprivate init(vertices: [Float2], triangleIndices: [TriangleIndices]) {
            // The triangle array is uploaded directly as tightly packed indices.
            precondition(
                MemoryLayout<TriangleIndices>.stride == MemoryLayout<UInt32>.stride * 3
            )
            self.vertices = vertices
            self.triangleIndices = triangleIndices
        }
    }

    final class StencilPathGeometryScratch {
        fileprivate var vertices: [Float2] = []
        private var triangleIndices: [StencilPathFillGeometry.TriangleIndices] = []

        func makeGeometry(
            path: Path,
            transform: CGAffineTransform,
            pathTransform: CGAffineTransform? = nil
        ) -> StencilPathFillGeometry {
            var builder = StencilPathFillGeometryBuilder(transform: transform)
            // Move storage into the builder before clearing it. A retained geometry
            // snapshot stays independent through ordinary Array copy-on-write.
            swap(&vertices, &builder.vertices)
            swap(&triangleIndices, &builder.triangleIndices)
            builder.vertices.removeAll(keepingCapacity: true)
            builder.triangleIndices.removeAll(keepingCapacity: true)
            builder.build(path: path, pathTransform: pathTransform)

            let geometry = StencilPathFillGeometry(
                vertices: builder.vertices,
                triangleIndices: builder.triangleIndices
            )
            swap(&vertices, &builder.vertices)
            swap(&triangleIndices, &builder.triangleIndices)
            return geometry
        }
    }

    public struct Shading {
        enum Property {
            case color(color: Color)
            case style(style: any ShapeStyle)
            case linearGradient(gradient: Gradient, startPoint: CGPoint, endPoint: CGPoint, options: GradientOptions)
            case radialGradient(gradient: Gradient, center: CGPoint, startRadius: CGFloat, endRadius: CGFloat, options: GradientOptions)
            case conicGradient(gradient: Gradient, center: CGPoint, angle: Angle, options: GradientOptions)
            case tiledImage(image: Image, origin: CGPoint, sourceRect: CGRect, scale: CGFloat)
            case shader(shader: Shader, bounds: CGRect)
            case meshGradient(mesh: MeshGradient)
        }
        let properties: [Property]

        init(property: Property) {
            self.properties = [property]
        }
        init(palette: [Shading]) {
            self.properties = palette.flatMap { $0.properties }
        }

        public static var backdrop: Shading     { .color(.black) }
        public static var foreground: Shading   { .color(.black) }

        public static func palette(_ array: [Shading]) -> Shading {
            Shading(palette: array)
        }
        public static func color(_ color: Color) -> Shading {
            Shading(property: .color(color: color))
        }
        public static func color(_ colorSpace: Color.RGBColorSpace = .sRGB, red: Double, green: Double, blue: Double, opacity: Double = 1) -> Shading {
            color(Color(colorSpace, red: red, green: green, blue: blue, opacity: opacity))
        }
        public static func color(_ colorSpace: Color.RGBColorSpace = .sRGB, white: Double, opacity: Double = 1) -> Shading {
            color(Color(colorSpace, white: white, opacity: opacity))
        }
        public static func style<S>(_ style: S) -> Shading where S: ShapeStyle {
            Shading(property: .style(style: style))
        }
        public static func linearGradient(_ gradient: Gradient, startPoint: CGPoint, endPoint: CGPoint, options: GradientOptions = GradientOptions()) -> Shading {
            Shading(property: .linearGradient(gradient: gradient, startPoint: startPoint, endPoint: endPoint, options: options))
        }
        public static func radialGradient(_ gradient: Gradient, center: CGPoint, startRadius: CGFloat, endRadius: CGFloat, options: GradientOptions = GradientOptions()) -> Shading {
            Shading(property: .radialGradient(gradient: gradient, center: center, startRadius: startRadius, endRadius: endRadius, options: options))
        }
        public static func conicGradient(_ gradient: Gradient, center: CGPoint, angle: Angle = Angle(), options: GradientOptions = GradientOptions()) -> Shading {
            Shading(property: .conicGradient(gradient: gradient, center: center, angle: angle, options: options))
        }
        public static func tiledImage(_ image: Image, origin: CGPoint = .zero, sourceRect: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1), scale: CGFloat = 1) -> Shading {
            Shading(property: .tiledImage(image: image, origin: origin, sourceRect: sourceRect, scale: scale))
        }
        public static func shader(_ shader: Shader, bounds: CGRect = .zero) -> Shading {
            Shading(property: .shader(shader: shader, bounds: bounds))
        }
        public static func meshGradient(_ mesh: MeshGradient) -> Shading {
            Shading(property: .meshGradient(mesh: mesh))
        }
    }

    public func resolve(_ shading: Shading) -> Shading {
        shading
    }

    public struct GradientOptions: OptionSet, Sendable {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }

        public static var `repeat`      : GradientOptions { .init(rawValue: 1) }
        public static var mirror        : GradientOptions { .init(rawValue: 2) }
        public static var linearColor   : GradientOptions { .init(rawValue: 4) }
    }

    public func fill(_ path: Path, with shading: Shading, style: FillStyle = FillStyle()) {
        if shading.properties.isEmpty { return }
        if recording != nil, record(bounds: path.boundingBoxOfPath, {
            $0.fill(path, with: shading, style: style)
        }) { return }

        let isAntialiased = self.environment.disableMSAA == false && style.isAntialiased
        if let renderPass = self.beginRenderPass(enableStencil: true, enableMSAA: isAntialiased) {
            if self.encodeStencilPathFillCommand(renderPass: renderPass,
                                                 path: path) {

                let stencil: _Stencil = style.isEOFilled ? .testEven : .testNonZero
                self.encodeShadingBoxCommand(renderPass: renderPass,
                                             shading: shading,
                                             stencil: stencil,
                                             blendState: .opaque,
                                             bounds: path.boundingBoxOfPath)
                renderPass.end()
                self.drawSource()
                self.recordContentBounds(path.boundingBoxOfPath)
            } else {
                renderPass.end()
            }
        }
    }

    public func stroke(_ path: Path, with shading: Shading, style: StrokeStyle, isAntialiased: Bool) {
        if shading.properties.isEmpty { return }
        let halfWidth = style.lineWidth * 0.5
        if recording != nil, record(bounds: path.boundingBoxOfPath.insetBy(dx: -halfWidth, dy: -halfWidth), {
            $0.stroke(path, with: shading, style: style, isAntialiased: isAntialiased)
        }) { return }
        
        let isAntialiased = self.environment.disableMSAA == false && isAntialiased
        if let renderPass = self.beginRenderPass(enableStencil: true, enableMSAA: isAntialiased) {
            if self.encodeStencilPathStrokeCommand(renderPass: renderPass,
                                                   path: path,
                                                   style: style) {
                self.encodeShadingBoxCommand(renderPass: renderPass,
                                             shading: shading,
                                             stencil: .testNonZero,
                                             blendState: .opaque,
                                             bounds: path.boundingBoxOfPath)
                renderPass.end()
                self.drawSource()
                let halfWidth = style.lineWidth * 0.5
                self.recordContentBounds(
                    path.boundingBoxOfPath.insetBy(dx: -halfWidth, dy: -halfWidth)
                )
            } else {
                renderPass.end()
            }
        }
    }

    public func stroke(_ path: Path, with shading: Shading, style: StrokeStyle) {
        let isAntialiased = self.environment.pathStrokeAntialiasing
        stroke(path, with: shading, style: style, isAntialiased: isAntialiased)
    }

    public func stroke(_ path: Path, with shading: Shading, lineWidth: CGFloat = 1) {
        stroke(path, with: shading, style: StrokeStyle(lineWidth: lineWidth))
    }

    public func stroke(_ path: Path, with shading: Shading, lineWidth: CGFloat = 1, isAntialiased: Bool) {
        stroke(path, with: shading, style: StrokeStyle(lineWidth: lineWidth), isAntialiased: isAntialiased)
    }

    func encodeStencilPathStrokeCommand(renderPass: RenderPass,
                                        path: Path,
                                        style: StrokeStyle) -> Bool {
        if path.isEmpty { return false }
        if style.lineWidth < .ulpOfOne { return false }

        let minVisibleDashes = 1.0 / self.contentScaleFactor

        let lineWidth = style.lineWidth
        let halfWidth = lineWidth * 0.5

        let dash = style.dash.map { $0.magnitude }
        let numDashes = dash.count
        let dashPatternLength = dash.reduce(0, +)
//        let dashesLength = stride(from: 0, to: dash.count, by: 2).map { dash[$0] }.reduce(0, +)
//        let gapsLength = stride(from: 1, to: dash.count, by: 2).map { dash[$0] }.reduce(0, +)

        let dashLength = { index in dash[index % numDashes] }
        let dashAvailable = (numDashes > 0 && (dashPatternLength / CGFloat(numDashes)) >= minVisibleDashes)

        var dashIndex: Int = 0      // even: dash, odd: gap
        var dashRemain: CGFloat = 0 // remaining length of the current dash(gap)
        if dash.isEmpty == false && dashPatternLength > .ulpOfOne {
            let fullCycleLength = dash.count.isMultiple(of: 2)
                ? dashPatternLength
                : dashPatternLength * 2
            var phase = style.dashPhase.truncatingRemainder(dividingBy: fullCycleLength)
            if phase < 0 { phase += fullCycleLength }
            dashRemain = dashLength(dashIndex)
            if phase > .ulpOfOne {
                while phase > dashRemain {
                    dashIndex += 1
                    dashRemain += dashLength(dashIndex)
                }
                dashRemain -= phase
            }
            while dashRemain < .ulpOfOne {
                dashIndex += 1
                dashRemain += dashLength(dashIndex)
            }
        }
        let _initialDashIndex = dashIndex
        let _initialDashRemain = dashRemain
        let resetDashPhase = {
            dashIndex = _initialDashIndex
            dashRemain = _initialDashRemain
        }

        var vertexData: [Float2] = []
        // Borrow only CPU capacity; all exits return it after any upload has copied the bytes.
        swap(&pathGeometryScratch.vertices, &vertexData)
        vertexData.removeAll(keepingCapacity: true)
        defer { swap(&pathGeometryScratch.vertices, &vertexData) }

        let transform = self.transform.concatenating(self.viewTransform)
        let drawLineSegment = { (start: CGPoint, end: CGPoint, dir0: CGPoint, dir1: CGPoint) in
            let t0 = CGAffineTransform(a: dir0.x, b: dir0.y,
                                       c: -lineWidth * dir0.y,
                                       d: lineWidth * dir0.x,
                                       tx: start.x, ty: start.y)

            let t1 = CGAffineTransform(a: dir1.x, b: dir1.y,
                                       c: -lineWidth * dir1.y,
                                       d: lineWidth * dir1.x,
                                       tx: end.x, ty: end.y)

            let p0 = Vector2(0, -0.5).applying(t0).applying(transform).float2
            let p1 = Vector2(0, -0.5).applying(t1).applying(transform).float2
            let p2 = Vector2(0,  0.5).applying(t0).applying(transform).float2
            let p3 = Vector2(0,  0.5).applying(t1).applying(transform).float2

            vertexData.append(p2)
            vertexData.append(p0)
            vertexData.append(p3)
            vertexData.append(p3)
            vertexData.append(p0)
            vertexData.append(p1)
        }

        let addStrokeCap = { (p: CGPoint, d: CGPoint) in
            switch style.lineCap {
            case .round:
                let trans = CGAffineTransform(a: d.x, b: d.y,
                                              c: -d.y, d: d.x,
                                              tx: p.x, ty: p.y)
                    .concatenating(transform)

                let step = CGFloat.pi / lineWidth
                var progress = CGFloat.zero

                let center = Vector2(p).applying(transform)
                var pt0 = Vector2(0, -halfWidth).applying(trans)
                while progress < .pi {
                    let pt1 = Vector2(0, -halfWidth).applying(
                            CGAffineTransform(rotationAngle: progress)
                                .concatenating(trans))

                    vertexData.append(center.float2)
                    vertexData.append(pt0.float2)
                    vertexData.append(pt1.float2)
                    pt0 = pt1
                    progress += step
                }
                let pt1 = Vector2(0, halfWidth).applying(trans)
                vertexData.append(center.float2)
                vertexData.append(pt0.float2)
                vertexData.append(pt1.float2)
            case .square:
                let trans = CGAffineTransform(a: lineWidth * d.x,
                                              b: lineWidth * d.y,
                                              c: lineWidth * -d.y,
                                              d: lineWidth * d.x,
                                              tx: p.x, ty: p.y)
                    .concatenating(transform)

                let p0 = Vector2(0.0,  0.5).applying(trans).float2
                let p1 = Vector2(0.0, -0.5).applying(trans).float2
                let p2 = Vector2(0.5,  0.5).applying(trans).float2
                let p3 = Vector2(0.5, -0.5).applying(trans).float2
                vertexData.append(p0)
                vertexData.append(p1)
                vertexData.append(p2)
                vertexData.append(p2)
                vertexData.append(p1)
                vertexData.append(p3)
            default:
                return
            }
        }

        let addStrokeLine = { (p0: CGPoint, p1: CGPoint, d0: CGPoint, d1: CGPoint) in
            let d = p1 - p0
            let length = d.magnitude
            if length < .ulpOfOne { return }
            if dashAvailable {
                var drawn: CGFloat = 0
                var start = p0
                var dir0 = d0
                var drawLineCap = false
                while drawn < length {

                    while dashRemain < .ulpOfOne {
                        dashIndex += 1
                        dashRemain += dashLength(dashIndex)
                        drawLineCap = true
                    }

                    let remains = length - drawn
                    let len = min(remains, dashRemain)

                    if len > .ulpOfOne {
                        let t = (drawn + len) / length
                        let end = lerp(p0, p1, t)
                        let dir1 = lerp(d0, d1, t)

                        if dashIndex % 2 == 0 {
                            if drawLineCap {
                                addStrokeCap(start, -dir1)
                                drawLineCap = false
                            }
                            drawLineSegment(start, end, dir0, dir1)
                            if len == dashRemain {
                                addStrokeCap(end, dir1)
                            }
                        }
                        start = end
                        dir0 = dir1
                    }
                    drawn += len
                    dashRemain -= len
                }
            } else {
                drawLineSegment(p0, p1, d0, d1)
            }
        }
        let addStrokeJoin = { (p: CGPoint, dir0: CGPoint, dir1: CGPoint) in

            if 1.0 - CGPoint.dot(dir0, dir1) < .ulpOfOne { return }

            var join = style.lineJoin
            if join == .miter {
                let dot = CGPoint.dot(-dir0, dir1)
                let angle = acos(dot)
                let s = sin(angle * 0.5)
                if s > .ulpOfOne {
                    let miterLength = lineWidth / s
                    if miterLength > style.miterLimit * lineWidth {
                        join = .bevel
                    }
                } else {
                    join = .bevel
                }
            }

            let angle = { (d: CGPoint) -> CGFloat in
                if d.y < 0 {
                    return .pi * 2 - acos(d.x)
                }
                return acos(d.x)
            }
            var r1 = angle(dir0)
            var r2 = angle(dir1)
            if (r1 - r2).magnitude > .pi {
                if r1 > r2 { r2 += .pi * 2 }
                else { r1 += .pi * 2}
            }

            switch join {
            case .bevel:
                let t0 = CGAffineTransform(a: dir0.x, b: dir0.y,
                                           c: -lineWidth * dir0.y,
                                           d: lineWidth * dir0.x,
                                           tx: p.x, ty: p.y)

                let t1 = CGAffineTransform(a: dir1.x, b: dir1.y,
                                           c: -lineWidth * dir1.y,
                                           d: lineWidth * dir1.x,
                                           tx: p.x, ty: p.y)
                if r1 > r2 {
                    let p0 = Vector2(p).applying(transform).float2
                    let p1 = Vector2(0,  0.5).applying(t0).applying(transform).float2
                    let p2 = Vector2(0,  0.5).applying(t1).applying(transform).float2
                    vertexData.append(p0)
                    vertexData.append(p2)
                    vertexData.append(p1)

                } else {
                    let p0 = Vector2(p).applying(transform).float2
                    let p1 = Vector2(0, -0.5).applying(t0).applying(transform).float2
                    let p2 = Vector2(0, -0.5).applying(t1).applying(transform).float2
                    vertexData.append(p0)
                    vertexData.append(p1)
                    vertexData.append(p2)
                }
            case .round:
                let step = 1.0 / lineWidth
                var progress: CGFloat = step
                // Adjacent triangles share their transformed center and endpoint.
                let p0 = Vector2(p)
                let center = p0.applying(transform)
                if r1 > r2 {
                    var p1 = (Vector2(0, halfWidth).rotated(by: r1) + p0)
                        .applying(transform)
                    while progress < 1.0 {
                        let r = lerp(r1, r2, progress)
                        let p2 = (Vector2(0, halfWidth).rotated(by: r) + p0)
                            .applying(transform)
                        vertexData.append(center.float2)
                        vertexData.append(p2.float2)
                        vertexData.append(p1.float2)
                        progress += step
                        p1 = p2
                    }
                    let p2 = (Vector2(0, halfWidth).rotated(by: r2) + p0)
                        .applying(transform)
                    vertexData.append(center.float2)
                    vertexData.append(p2.float2)
                    vertexData.append(p1.float2)
                } else {
                    var p1 = (Vector2(0, -halfWidth).rotated(by: r1) + p0)
                        .applying(transform)
                    while progress < 1.0 {
                        let r = lerp(r1, r2, progress)
                        let p2 = (Vector2(0, -halfWidth).rotated(by: r) + p0)
                            .applying(transform)
                        vertexData.append(center.float2)
                        vertexData.append(p1.float2)
                        vertexData.append(p2.float2)
                        progress += step
                        p1 = p2
                    }
                    let p2 = (Vector2(0, -halfWidth).rotated(by: r2) + p0)
                        .applying(transform)
                    vertexData.append(center.float2)
                    vertexData.append(p1.float2)
                    vertexData.append(p2.float2)
                }
            case .miter:
                let t0 = CGAffineTransform(a: dir0.x, b: dir0.y,
                                           c: -lineWidth * dir0.y,
                                           d: lineWidth * dir0.x,
                                           tx: p.x, ty: p.y)

                let t1 = CGAffineTransform(a: dir1.x, b: dir1.y,
                                           c: -lineWidth * dir1.y,
                                           d: lineWidth * dir1.x,
                                           tx: p.x, ty: p.y)
                let dir0 = Vector2(dir0)
                let dir1 = Vector2(dir1)
                if r1 > r2 {
                    let pt0 = Vector2(0, 0.5).applying(t0)
                    let pt1 = Vector2(0, 0.5).applying(t1)

                    let p0 = Vector2(p)
                    let s = Vector2.cross(dir0, dir1)
                    let t = Vector2.cross(pt1 - pt0, dir1) / s
                    let p1 = pt0 + dir0 * t

                    let v0 = p0.applying(transform).float2
                    let v1 = p1.applying(transform).float2
                    let v2 = pt0.applying(transform).float2
                    let v3 = pt1.applying(transform).float2
                    vertexData.append(v0)
                    vertexData.append(v1)
                    vertexData.append(v2)
                    vertexData.append(v0)
                    vertexData.append(v3)
                    vertexData.append(v1)
                } else {
                    let pt0 = Vector2(0, -0.5).applying(t0)
                    let pt1 = Vector2(0, -0.5).applying(t1)

                    let p0 = Vector2(p)
                    let s = Vector2.cross(dir0, dir1)
                    let t = Vector2.cross(pt1 - pt0, dir1) / s
                    let p1 = pt0 + dir0 * t

                    let v0 = p0.applying(transform).float2
                    let v1 = p1.applying(transform).float2
                    let v2 = pt0.applying(transform).float2
                    let v3 = pt1.applying(transform).float2
                    vertexData.append(v0)
                    vertexData.append(v2)
                    vertexData.append(v1)
                    vertexData.append(v0)
                    vertexData.append(v1)
                    vertexData.append(v3)
                }
            @unknown default:
                fatalError("Unknown value")
            }
        }

        var initialPoint: CGPoint? = nil
        var currentPoint: CGPoint? = nil
        var initialDir: CGPoint? = nil
        var currentDir: CGPoint? = nil
        path.forEach { element in
            switch element {
            case .move(let to):
                if let p0 = initialPoint, let d0 = initialDir,
                   let p1 = currentPoint, let d1 = currentDir {

                    if dashIndex % 2 == 0 {
                        // line cap current point
                        addStrokeCap(p1, d1)
                    }
                    resetDashPhase()
                    if dashIndex % 2 == 0 {
                        // line cap initial point
                        addStrokeCap(p0, -d0)
                    }
                }

                initialPoint = to
                currentPoint = to
                initialDir = nil
                currentDir = nil
                resetDashPhase()
            case .line(let p1):
                if let p0 = currentPoint {
                    let d = p1 - p0
                    let length = d.magnitude
                    if length > .ulpOfOne {
                        let d1 = d / length
                        if let d0 = currentDir, dashIndex % 2 == 0 {
                            addStrokeJoin(p0, d0, d1)
                        }
                        addStrokeLine(p0, p1, d1, d1)
                        currentDir = d1
                        initialDir = initialDir ?? currentDir
                    }
                }
                currentPoint = p1
            case .quadCurve(let p2, let p1):
                if let p0 = currentPoint {
                    let curve = QuadraticBezier(p0: p0, p1: p1, p2: p2)
                    let length = curve.approximateLength()
                    if length > .ulpOfOne {
                        let step = 1.0 / length
                        var t = step
                        var pt0 = p0
                        var d0 = currentDir ?? (p1 - p0).normalized()
                        while t < 1.0 {
                            let pt1 = curve.interpolate(t)
                            let d1 = curve.tangent(t).normalized()
                            addStrokeLine(pt0, pt1, d0, d1)
                            pt0 = pt1
                            d0 = d1
                            t += step
                        }
                        let d1 = (p2 - p1).normalized()
                        addStrokeLine(pt0, p2, d0, d1)
                        currentDir = d1
                        initialDir = initialDir ?? currentDir
                    }
                }
                currentPoint = p2
            case .curve(let p3, let p1, let p2):
                if let p0 = currentPoint {
                    let curve = CubicBezier(p0: p0, p1: p1, p2: p2, p3: p3)
                    let length = curve.approximateLength()
                    if length > .ulpOfOne {
                        let step = 1.0 / length
                        var t = step
                        var pt0 = p0
                        var d0 = currentDir ?? (p1 - p0).normalized()
                        while t < 1.0 {
                            let pt1 = curve.interpolate(t)
                            let d1 = curve.tangent(t).normalized()
                            addStrokeLine(pt0, pt1, d0, d1)
                            pt0 = pt1
                            d0 = d1
                            t += step
                        }
                        let d1 = (p3 - p2).normalized()
                        addStrokeLine(pt0, p3, d0, d1)
                        currentDir = d1
                        initialDir = initialDir ?? currentDir
                    }
                }
                currentPoint = p3
            case .closeSubpath:
                if let p0 = currentPoint, let p1 = initialPoint {
                    let diff = p1 - p0
                    let length = diff.magnitude
                    if length > .ulpOfOne {
                        let d = diff / length
                        if let d0 = currentDir, dashIndex % 2 == 0 {
                            addStrokeJoin(p0, d0, d)
                        }
                        addStrokeLine(p0, p1, d, d)
                        if let d1 = initialDir {
                            if dashIndex % 2 == 0 {
                                resetDashPhase()
                                if dashIndex % 2 == 0 {
                                    // join with initial point
                                    addStrokeJoin(p1, d, d1)
                                } else {
                                    // line cap current point
                                    addStrokeCap(p1, d)
                                }
                            } else {
                                resetDashPhase()
                                if dashIndex % 2 == 0 {
                                    // line cap initial point
                                    addStrokeCap(p1, -d1)
                                }
                            }
                        }
                    } else if let d0 = currentDir, let d1 = initialDir {
                        resetDashPhase()
                        if dashIndex % 2 == 0 {
                            addStrokeJoin(p1, d0, d1)
                        }
                    }
                }
                currentPoint = initialPoint
                initialDir = nil
                currentDir = nil
                resetDashPhase()
            }
        }
        if let p0 = initialPoint, let d0 = initialDir,
           let p1 = currentPoint, let d1 = currentDir {
            if dashIndex % 2 == 0 {
                addStrokeCap(p1, d1)
            }
            resetDashPhase()
            if dashIndex % 2 == 0 {
                addStrokeCap(p0, -d0)
            }
        }

        if vertexData.count < 3 { return false }

        guard let vertexBuffer = self.makeBuffer(vertexData) else {
            Log.err("GraphicsContext error: _makeBuffer failed.")
            return false
        }

        // pipeline states for generate polygon winding numbers
        guard let pipelineState = pipeline.renderState(
            shader: .stencil,
            colorFormat: renderPass.colorFormat,
            depthFormat: renderPass.depthFormat,
            blendState: BlendState(writeMask: []),
            sampleCount: renderPass.sampleCount) else {
            Log.err("GraphicsContext error: pipeline.renderState failed.")
            return false
        }
        guard let depthState = pipeline.depthStencilState(.makeStroke) else {
            Log.err("GraphicsContext error: pipeline.depthStencilState failed.")
            return false
        }

        let encoder = renderPass.encoder

        // pass1: Generate polygon winding numbers to stencil buffer
        encoder.setRenderPipelineState(pipelineState)
        encoder.setDepthStencilState(depthState)

        encoder.setCullMode(.back)
        encoder.setVertexBuffer(
            vertexBuffer.buffer,
            offset: vertexBuffer.offset,
            index: 0
        )
        encoder.draw(vertexStart: 0,
                     vertexCount: vertexData.count,
                     instanceCount: 1,
                     baseInstance: 0)
        return true
    }

    func encodeStencilPathFillCommand(
        renderPass: RenderPass,
        path: Path,
        pathTransform: CGAffineTransform? = nil
    ) -> Bool {
        if path.isEmpty { return false }

        let transform = self.transform.concatenating(self.viewTransform)
        let geometry = pathGeometryScratch.makeGeometry(
            path: path,
            transform: transform,
            pathTransform: pathTransform
        )
        if geometry.vertices.count < 3 { return false }
        if geometry.triangleIndices.isEmpty { return false }

        guard let vertexBuffer = self.makeBuffer(geometry.vertices) else {
            Log.err("GraphicsContext error: _makeBuffer failed.")
            return false
        }
        guard let indexBuffer = self.makeBuffer(geometry.triangleIndices) else {
            Log.err("GraphicsContext error: _makeBuffer failed.")
            return false
        }

        // pipeline states for generate polygon winding numbers
        guard let pipelineState = pipeline.renderState(
            shader: .stencil,
            colorFormat: renderPass.colorFormat,
            depthFormat: renderPass.depthFormat,
            blendState: BlendState(writeMask: []),
            sampleCount: renderPass.sampleCount) else {
            Log.err("GraphicsContext error: pipeline.renderState failed.")
            return false
        }
        guard let depthState = pipeline.depthStencilState(.makeFill) else {
            Log.err("GraphicsContext error: pipeline.depthStencilState failed.")
            return false
        }

        let encoder = renderPass.encoder

        // pass1: Generate polygon winding numbers to stencil buffer
        encoder.setRenderPipelineState(pipelineState)
        encoder.setDepthStencilState(depthState)

        encoder.setCullMode(.none)
        encoder.setVertexBuffer(
            vertexBuffer.buffer,
            offset: vertexBuffer.offset,
            index: 0
        )
        encoder.drawIndexed(indexCount: geometry.indexCount,
                            indexType: .uint32,
                            indexBuffer: indexBuffer.buffer,
                            indexBufferOffset: indexBuffer.offset,
                            instanceCount: 1,
                            baseVertex: 0,
                            baseInstance: 0)
        return true
    }

    func encodeShadingBoxCommand(renderPass: RenderPass,
                                 shading: GraphicsContext.Shading,
                                 stencil: _Stencil,
                                 blendState: BlendState,
                                 bounds: CGRect = .null) {

        if shading.properties.isEmpty { return }

        var vertices: [_Vertex] = []
        var shader: _Shader = .vertexColor

        var property = shading.properties.first
        if case let .style(style) = property {
            var shape = _ShapeStyle_Shape(
                operation: .fallbackColor(level: 0),
                environment: environment
            )
            style._apply(to: &shape)
            property = shape.resolvedShading?.properties.first
        }

        if let property {
            switch property {
            case let .color(c):
                shader = .vertexColor
                let color = _premultipliedVertexColor(c.backendColor(in: self.environment))
                let makeVertex = { (x: Scalar, y: Scalar) in
                    _Vertex(position: Vector2(x, y).float2,
                            texcoord: Vector2.zero.float2,
                            color: color)
                }
                vertices = [
                    makeVertex(-1, -1), makeVertex(-1, 1), makeVertex(1, -1),
                    makeVertex(1, -1), makeVertex(-1, 1), makeVertex(1, 1)
                ]
            case let .style(style):
                Log.err("ShapeStyle:\(style) not supported.")
                fatalError("ShapeStyle:\(style) should be resolved to GraphicsContext.Shading")

            case let .linearGradient(gradient, startPoint, endPoint, options):
                let stops = gradient.normalized().stops
                if stops.isEmpty { return }
                let gradientVector = endPoint - startPoint
                let length = gradientVector.magnitude
                if length < .ulpOfOne {
                    return self.encodeShadingBoxCommand(renderPass: renderPass,
                                                        shading: .color(stops[0].color),
                                                        stencil: stencil,
                                                        blendState: blendState,
                                                        bounds: bounds)
                }
                let dir = gradientVector.normalized()
                // transform gradient space to world space
                // ie: (0, 0) -> startPoint, (1, 0) -> endPoint
                let gradientTransform = CGAffineTransform(
                    a: dir.x * length, b: dir.y * length,
                    c: -dir.y, d: dir.x,
                    tx: startPoint.x, ty: startPoint.y)

                let viewportToGradientTransform = self.viewTransform.inverted()
                    .concatenating(gradientTransform.inverted())

                let p0 = CGPoint(x: -1, y: -1).applying(viewportToGradientTransform)
                let p1 = CGPoint(x: -1, y: 1).applying(viewportToGradientTransform)
                let p2 = CGPoint(x: 1, y: 1).applying(viewportToGradientTransform)
                let p3 = CGPoint(x: 1, y: -1).applying(viewportToGradientTransform)
                // Preserve the first corner on ties and the original comparison order.
                var xMax = p0.x
                if xMax < p1.x { xMax = p1.x }
                if xMax < p2.x { xMax = p2.x }
                if xMax < p3.x { xMax = p3.x }
                var xMin = p0.x
                if p1.x < xMin { xMin = p1.x }
                if p2.x < xMin { xMin = p2.x }
                if p3.x < xMin { xMin = p3.x }
                var yMax = p0.y
                if yMax < p1.y { yMax = p1.y }
                if yMax < p2.y { yMax = p2.y }
                if yMax < p3.y { yMax = p3.y }
                var yMin = p0.y
                if p1.y < yMin { yMin = p1.y }
                if p2.y < yMin { yMin = p2.y }
                if p3.y < yMin { yMin = p3.y }
                // Keep the box emitter's captured bounds immutable.
                let maxX = xMax
                let minX = xMin
                let maxY = yMax
                let minY = yMin

                let gradientToViewportTransform = gradientTransform
                    .concatenating(self.viewTransform)

                let addGradientBox = { (x1: CGFloat, x2: CGFloat, c1: BackendColor, c2: BackendColor) in
                    // Reserve the first six-vertex box; later boxes use normal Array growth.
                    if vertices.isEmpty {
                        vertices.reserveCapacity(6)
                    }
                    let color1 = _premultipliedVertexColor(c1)
                    let color2 = _premultipliedVertexColor(c2)
                    let v0 = _Vertex(position: Vector2(x1, maxY).applying(gradientToViewportTransform).float2,
                                     texcoord: Vector2.zero.float2, color: color1)
                    let v1 = _Vertex(position: Vector2(x1, minY).applying(gradientToViewportTransform).float2,
                                     texcoord: Vector2.zero.float2, color: color1)
                    let v2 = _Vertex(position: Vector2(x2, maxY).applying(gradientToViewportTransform).float2,
                                     texcoord: Vector2.zero.float2, color: color2)
                    let v3 = _Vertex(position: Vector2(x2, minY).applying(gradientToViewportTransform).float2,
                                     texcoord: Vector2.zero.float2, color: color2)
                    vertices.append(v0)
                    vertices.append(v1)
                    vertices.append(v2)
                    vertices.append(v2)
                    vertices.append(v1)
                    vertices.append(v3)
                }
                if options.contains(.mirror) {
                    var pos = floor(minX)
                    let rstops = stops.reversed()
                    while pos < ceil(maxX) {
                        if pos.magnitude.truncatingRemainder(dividingBy: 2).rounded() == 1.0 {
                            for i in 0..<(rstops.count-1) {
                                let s1 = stops[i]
                                let s2 = stops[i+1]

                                let loc1 = (1.0 - s1.location)
                                let loc2 = (1.0 - s2.location)
                                if loc1 + pos > maxX { break }
                                if loc2 + pos < minX { continue }
                                addGradientBox(loc1 + pos,
                                               loc2 + pos,
                                               s1.color.backendColor(in: self.environment),
                                               s2.color.backendColor(in: self.environment))
                            }
                        } else {
                            for i in 0..<(stops.count-1) {
                                let s1 = stops[i]
                                let s2 = stops[i+1]

                                if s1.location + pos > maxX { break }
                                if s2.location + pos < minX { continue }
                                addGradientBox(s1.location + pos,
                                               s2.location + pos,
                                               s1.color.backendColor(in: self.environment),
                                               s2.color.backendColor(in: self.environment))
                            }
                        }
                        pos += 1
                    }
                } else if options.contains(.repeat) {
                    var pos = floor(minX)
                    while pos < ceil(maxX) {
                        for i in 0..<(stops.count-1) {
                            let s1 = stops[i]
                            let s2 = stops[i+1]

                            if s1.location + pos > maxX { break }
                            if s2.location + pos < minX { continue }
                            addGradientBox(s1.location + pos,
                                           s2.location + pos,
                                           s1.color.backendColor(in: self.environment),
                                           s2.color.backendColor(in: self.environment))
                        }
                        pos += 1
                    }
                } else {
                    for i in 0..<(stops.count-1) {
                        let s1 = stops[i]
                        let s2 = stops[i+1]

                        addGradientBox(s1.location, s2.location,
                                       s1.color.backendColor(in: self.environment),
                                       s2.color.backendColor(in: self.environment))
                    }
                    if let first = stops.first, first.location > minX {
                        addGradientBox(minX, first.location,
                                       first.color.backendColor(in: self.environment),
                                       first.color.backendColor(in: self.environment))
                    }
                    if let last = stops.last, last.location < maxX {
                        addGradientBox(last.location, maxX,
                                       last.color.backendColor(in: self.environment),
                                       last.color.backendColor(in: self.environment))
                    }
                }
            case let .radialGradient(gradient, center, startRadius, endRadius, options):
                let stops = gradient.normalized().stops
                if stops.isEmpty { return }

                let length = (endRadius - startRadius).magnitude
                if length < .ulpOfOne {
                    if options.contains(.repeat) && !options.contains(.mirror) {
                        return self.encodeShadingBoxCommand(
                            renderPass: renderPass,
                            shading: .color(stops.last!.color),
                            stencil: stencil,
                            blendState: blendState,
                            bounds: bounds)
                    } else {
                        return self.encodeShadingBoxCommand(
                            renderPass: renderPass,
                            shading: .color(stops.first!.color),
                            stencil: stencil,
                            blendState: blendState,
                            bounds: bounds)
                    }
                }
                let invViewTransform = self.viewTransform.inverted()
                let scale = [CGPoint(x: -1, y: -1),     // left-bottom
                             CGPoint(x: -1, y: 1),      // left-top
                             CGPoint(x: 1, y: 1),       // right-top
                             CGPoint(x: 1, y: -1)]      // right-bottom
                    .map { ($0.applying(invViewTransform) - center).magnitudeSquared }
                    .max()!.squareRoot()

                let transform = CGAffineTransform(translationX: center.x, y: center.y)
                    .concatenating(self.viewTransform)

                let texCoord = Vector2.zero.float2
                let step = CGFloat.pi / 45.0
                let addCircularArc = {
                    (x1: CGFloat, x2: CGFloat, c1: Color, c2: Color) in

                    if x1 >= scale && x2 >= scale { return }
                    if x1 <= 0 && x2 <= 0 { return }
                    if (x2 - x1).magnitude < .ulpOfOne { return }

                    var x1 = x1, x2 = x2
                    var c1 = c1, c2 = c2
                    if x1 > x2 {
                        (x1, x2) = (x2, x1)
                        (c1, c2) = (c2, c1)
                    }
                    if x1 < 0 {
                        c1 = .lerp(c1, c2, (0 - x1)/(x2 - x1))
                        x1 = 0
                    }
                    if x2 > scale {
                        c2 = .lerp(c1, c2, (scale - x1)/(x2 - x1))
                        x2 = scale
                    }
                    if (x2 - x1) < .ulpOfOne { return }
                    assert(x2 > x1)

                    let p0 = Vector2(x1, 0)
                    let p1 = p0.rotated(by: step)
                    let p2 = Vector2(x2, 0)
                    let p3 = p2.rotated(by: step)

                    // Resolve the final clipped endpoints once for the whole arc.
                    let color1 = _premultipliedVertexColor(c1.backendColor(in: self.environment))
                    let color2 = _premultipliedVertexColor(c2.backendColor(in: self.environment))
                    let isTriangle = (p1 - p0).magnitudeSquared < .ulpOfOne
                    // Reserve the first arc; later appends keep geometric growth across arcs.
                    if vertices.isEmpty {
                        let numVertices = Int((CGFloat.pi * 2) / step) + 1
                        vertices.reserveCapacity(numVertices * (isTriangle ? 3 : 6))
                    }
                    var progress: CGFloat = .zero
                    while progress < .pi * 2 {
                        // Share this angle's coefficients without changing rotation arithmetic.
                        let angle = Scalar(progress)
                        let cosR = cos(angle)
                        let sinR = sin(angle)
                        let rotated = { (point: Vector2) in
                            Vector2(point.x * cosR - point.y * sinR,
                                    point.x * sinR + point.y * cosR)
                        }
                        if isTriangle {
                            vertices.append(_Vertex(position: rotated(p0).applying(transform).float2,
                                                    texcoord: texCoord, color: color1))
                            vertices.append(_Vertex(position: rotated(p2).applying(transform).float2,
                                                    texcoord: texCoord, color: color2))
                            vertices.append(_Vertex(position: rotated(p3).applying(transform).float2,
                                                    texcoord: texCoord, color: color2))
                        } else {
                            // Reuse v0 and v3 between the two triangles at this angle.
                            let v1 = _Vertex(position: rotated(p1).applying(transform).float2,
                                             texcoord: texCoord, color: color1)
                            let v0 = _Vertex(position: rotated(p0).applying(transform).float2,
                                             texcoord: texCoord, color: color1)
                            let v3 = _Vertex(position: rotated(p3).applying(transform).float2,
                                             texcoord: texCoord, color: color2)
                            let v2 = _Vertex(position: rotated(p2).applying(transform).float2,
                                             texcoord: texCoord, color: color2)
                            vertices.append(v1)
                            vertices.append(v0)
                            vertices.append(v3)
                            vertices.append(v3)
                            vertices.append(v0)
                            vertices.append(v2)
                        }
                        progress += step
                    }
                }

                if options.contains(.mirror) {
                    var startRadius = startRadius
                    var reverse = false
                    while startRadius > 0 {
                        startRadius = startRadius - length
                        reverse = !reverse
                    }
                    while startRadius < scale {
                        if reverse {
                            for i in 0..<(stops.count - 1) {
                                let s1 = stops[i]
                                let s2 = stops[i+1]
                                let loc1 = startRadius + length - (s1.location * length)
                                let loc2 = startRadius + length - (s2.location * length)
                                if loc1 <= 0 && loc2 <= 0 { break }
                                addCircularArc(loc1, loc2, s1.color, s2.color)
                            }
                        } else {
                            for i in 0..<(stops.count - 1) {
                                let s1 = stops[i]
                                let s2 = stops[i+1]
                                let loc1 = (s1.location * length) + startRadius
                                let loc2 = (s2.location * length) + startRadius
                                if loc1 >= scale && loc2 >= scale { break }
                                addCircularArc(loc1, loc2, s1.color, s2.color)
                            }
                        }
                        startRadius += length
                        reverse = !reverse
                    }
                } else if options.contains(.repeat) {
                    var startRadius = startRadius
                    let reverse = endRadius < startRadius
                    while startRadius > 0 {
                        startRadius = startRadius - length
                    }
                    if reverse {
                        while startRadius < scale {
                            for i in 0..<(stops.count - 1) {
                                let s1 = stops[i]
                                let s2 = stops[i+1]
                                let loc1 = startRadius + length - (s1.location * length)
                                let loc2 = startRadius + length - (s2.location * length)
                                if loc1 <= 0 && loc2 <= 0 { break }
                                addCircularArc(loc1, loc2, s1.color, s2.color)
                            }
                            startRadius += length
                        }
                    } else {
                        while startRadius < scale {
                            for i in 0..<(stops.count - 1) {
                                let s1 = stops[i]
                                let s2 = stops[i+1]
                                let loc1 = (s1.location * length) + startRadius
                                let loc2 = (s2.location * length) + startRadius
                                if loc1 >= scale && loc2 >= scale { break }
                                addCircularArc(loc1, loc2, s1.color, s2.color)
                            }
                            startRadius += length
                        }
                    }
                } else {
                    if endRadius > startRadius {
                        addCircularArc(0, startRadius, stops[0].color, stops[0].color)
                        for i in 0..<(stops.count - 1) {
                            let s1 = stops[i]
                            let s2 = stops[i+1]
                            let loc1 = (s1.location * length) + startRadius
                            let loc2 = (s2.location * length) + startRadius
                            if loc1 >= scale && loc2 >= scale { break }
                            addCircularArc(loc1, loc2, s1.color, s2.color)
                        }
                        addCircularArc(endRadius, scale, stops.last!.color, stops.last!.color)
                    } else {
                        addCircularArc(0, endRadius, stops.last!.color, stops.last!.color)
                        for i in 0..<(stops.count - 1) {
                            let s1 = stops[i]
                            let s2 = stops[i+1]
                            let loc1 = startRadius - (s1.location * length)
                            let loc2 = startRadius - (s2.location * length)
                            if loc1 <= 0 && loc2 <= 0 { break }
                            addCircularArc(loc1, loc2, s1.color, s2.color)
                        }
                        addCircularArc(startRadius, scale, stops[0].color, stops[0].color)
                    }
                }
            case let .conicGradient(gradient, center, angle, _):
                let gradient = gradient.normalized()
                if gradient.stops.isEmpty { return }
                let invViewTransform = self.viewTransform.inverted()
                let scale = [CGPoint(x: -1, y: -1),     // left-bottom
                             CGPoint(x: -1, y: 1),      // left-top
                             CGPoint(x: 1, y: 1),       // right-top
                             CGPoint(x: 1, y: -1)]      // right-bottom
                    .map { ($0.applying(invViewTransform) - center).magnitudeSquared }
                    .max()!.squareRoot()

                let transform = CGAffineTransform(rotationAngle: angle.radians)
                    .concatenating(CGAffineTransform(scaleX: scale, y: scale))
                    .concatenating(CGAffineTransform(translationX: center.x, y: center.y))
                    .concatenating(self.viewTransform)

                let step = CGFloat.pi / 180.0
                var progress: CGFloat = .zero
                let texCoord = Vector2.zero.float2
                let center = Vector2(0, 0).applying(transform)
                let numTriangles = Int((CGFloat.pi * 2) / step) + 1
                vertices.reserveCapacity(numTriangles * 3)

                // Sample locations increase, so passed stops cannot be upper endpoints again.
                let firstStop = gradient.stops[0]
                var currentStop = firstStop
                var nextStopIndex = 1
                let interpolatedColor = { (location: CGFloat) -> Color in
                    if location > firstStop.location {
                        while nextStopIndex < gradient.stops.count {
                            let nextStop = gradient.stops[nextStopIndex]
                            if nextStop.location > location {
                                return .lerp(currentStop.color, nextStop.color,
                                             (location - currentStop.location) /
                                             (nextStop.location - currentStop.location))
                            }
                            currentStop = nextStop
                            nextStopIndex += 1
                        }
                        return currentStop.color
                    }
                    return firstStop.color
                }
                var p0 = Vector2(1, 0).rotated(by: progress).applying(transform)
                var color1 = _premultipliedVertexColor(interpolatedColor(
                    progress / (.pi * 2)
                ).backendColor(in: self.environment))
                while progress < .pi * 2 {
                    let nextProgress = progress + step
                    let p1 = Vector2(1, 0).rotated(by: nextProgress).applying(transform)
                    let color2 = _premultipliedVertexColor(interpolatedColor(
                        nextProgress / (.pi * 2)
                    ).backendColor(in: self.environment))

                    vertices.append(_Vertex(position: center.float2,
                                            texcoord: texCoord,
                                            color: color1))
                    vertices.append(_Vertex(position: p0.float2,
                                            texcoord: texCoord,
                                            color: color1))
                    vertices.append(_Vertex(position: p1.float2,
                                            texcoord: texCoord,
                                            color: color2))

                    // The next triangle starts at this same accumulated angle.
                    p0 = p1
                    color1 = color2
                    progress = nextProgress
                }
            case let .shader(shader, shaderBounds):
                _ = encodeCustomShaderShadingCommand(
                    renderPass: renderPass,
                    shader: shader,
                    boundingRect: shaderBounds.isNull ? bounds : shaderBounds,
                    stencil: stencil,
                    blendState: blendState
                )
                return
            case let .meshGradient(mesh):
                vertices = meshGradientVertices(mesh, bounds: bounds)
            default:
                Log.err("Not implemented yet (\(property))")
                fatalError("Not implemented yet")
            }
        }

        self.encodeDrawCommand(renderPass: renderPass,
                               shader: shader,
                               stencil: stencil,
                               vertices: vertices,
                               texture: nil,
                               blendState: blendState)
    }
}

// (default) antialiase option for path-stroke
private struct PathStrokeAntialiasingKey: EnvironmentKey {
    static let defaultValue: Bool = true
}

extension EnvironmentValues {
    public var pathStrokeAntialiasing: Bool {
        get { self[PathStrokeAntialiasingKey.self] }
        set { self[PathStrokeAntialiasingKey.self] = newValue }
    }
}

// Option to disable MSAA for all drawings.
private struct DisableMSAAKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    public var disableMSAA: Bool {
        get { self[DisableMSAAKey.self] }
        set { self[DisableMSAAKey.self] = newValue }
    }
}
