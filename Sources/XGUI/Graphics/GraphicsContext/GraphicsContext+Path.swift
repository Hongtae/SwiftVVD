//
//  File: GraphicsContext+Path.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2024 Hongtae Kim. All rights reserved.
//

import Foundation
import VVD

extension GraphicsContext {
    public struct Shading {
        enum Property {
            case color(color: Color)
            case style(style: any ShapeStyle)
            case linearGradient(gradient: Gradient, startPoint: CGPoint, endPoint: CGPoint, options: GradientOptions)
            case radialGradient(gradient: Gradient, center: CGPoint, startRadius: CGFloat, endRadius: CGFloat, options: GradientOptions)
            case conicGradient(gradient: Gradient, center: CGPoint, angle: Angle, options: GradientOptions)
            case tiledImage(image: Image, origin: CGPoint, sourceRect: CGRect, scale: CGFloat)
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
        if let renderPass = self.beginRenderPass(enableStencil: true) {
            if self.encodeStencilPathFillCommand(renderPass: renderPass,
                                                 path: path) {

                let stencil: _Stencil = style.isEOFilled ? .testEven : .testNonZero
                self.encodeShadingBoxCommand(renderPass: renderPass,
                                             shading: shading,
                                             stencil: stencil,
                                             blendState: .opaque)
                renderPass.end()
                self.drawSource()
            } else {
                renderPass.end()
            }
        }
    }

    public func stroke(_ path: Path, with shading: Shading, style: StrokeStyle) {
        if shading.properties.isEmpty { return }

        if let renderPass = self.beginRenderPass(enableStencil: true) {
            if self.encodeStencilPathStrokeCommand(renderPass: renderPass,
                                                   path: path,
                                                   style: style) {
                self.encodeShadingBoxCommand(renderPass: renderPass,
                                             shading: shading,
                                             stencil: .testNonZero,
                                             blendState: .opaque)
                renderPass.end()
                self.drawSource()
            } else {
                renderPass.end()
            }
        }
    }

    public func stroke(_ path: Path, with shading: Shading, lineWidth: CGFloat = 1) {
        stroke(path, with: shading, style: StrokeStyle(lineWidth: lineWidth))
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
        if dash.isEmpty == false {
            if style.dashPhase > 0 {
                let phase = style.dashPhase
                dashRemain = dashLength(dashIndex)
                while phase > dashRemain {
                    dashIndex += 1
                    dashRemain += dashLength(dashIndex)
                }
                dashRemain -= phase
            } else {
                var phase = style.dashPhase
                while phase < 0 {
                    if dashIndex == 0 { dashIndex += dash.count * 2 }
                    dashIndex -= 1
                    let f = dashLength(dashIndex)
                    phase += f
                }
                dashRemain = dashLength(dashIndex) - phase
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

            let box = [Vector2(0, -0.5).applying(t0),
                       Vector2(0, -0.5).applying(t1),
                       Vector2(0,  0.5).applying(t0),
                       Vector2(0,  0.5).applying(t1)].map {
                $0.applying(transform)
            }

            vertexData.append(contentsOf: [
                box[2].float2, box[0].float2, box[3].float2,
                box[3].float2, box[0].float2, box[1].float2])
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

                    vertexData.append(contentsOf: [center.float2,
                                                   pt0.float2,
                                                   pt1.float2])
                    pt0 = pt1
                    progress += step
                }
                let pt1 = Vector2(0, halfWidth).applying(trans)
                vertexData.append(contentsOf: [center.float2,
                                               pt0.float2,
                                               pt1.float2])
            case .square:
                let trans = CGAffineTransform(a: lineWidth * d.x,
                                              b: lineWidth * d.y,
                                              c: lineWidth * -d.y,
                                              d: lineWidth * d.x,
                                              tx: p.x, ty: p.y)
                    .concatenating(transform)

                let pt = [Vector2(0.0,  0.5),
                          Vector2(0.0, -0.5),
                          Vector2(0.5,  0.5),
                          Vector2(0.5, -0.5)].map {
                    $0.applying(trans).float2
                }
                vertexData.append(contentsOf: [pt[0], pt[1], pt[2],
                                             pt[2], pt[1], pt[3]])
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
                    let pt = [Vector2(p),
                              Vector2(0,  0.5).applying(t0),
                              Vector2(0,  0.5).applying(t1)].map {
                        $0.applying(transform).float2
                    }
                    vertexData.append(contentsOf: [pt[0], pt[2], pt[1]])

                } else {
                    let pt = [Vector2(p),
                              Vector2(0, -0.5).applying(t0),
                              Vector2(0, -0.5).applying(t1)].map {
                        $0.applying(transform).float2
                    }
                    vertexData.append(contentsOf: [pt[0], pt[1], pt[2]])
                }
            case .round:
                let step = 1.0 / lineWidth
                var progress: CGFloat = step
                let p0 = Vector2(p)
                if r1 > r2 {
                    var p1 = Vector2(0, halfWidth).rotated(by: r1)
                    while progress < 1.0 {
                        let r = lerp(r1, r2, progress)
                        let p2 = Vector2(0, halfWidth).rotated(by: r)
                        vertexData.append(contentsOf: [p0, p2 + p0, p1 + p0].map {
                            $0.applying(transform).float2
                        })
                        progress += step
                        p1 = p2
                    }
                    let p2 = Vector2(0, halfWidth).rotated(by: r2)
                    vertexData.append(contentsOf: [p0, p2 + p0, p1 + p0].map {
                        $0.applying(transform).float2
                    })
                } else {
                    var p1 = Vector2(0, -halfWidth).rotated(by: r1)
                    while progress < 1.0 {
                        let r = lerp(r1, r2, progress)
                        let p2 = Vector2(0, -halfWidth).rotated(by: r)
                        vertexData.append(contentsOf: [p0, p1 + p0, p2 + p0].map {
                            $0.applying(transform).float2
                        })
                        progress += step
                        p1 = p2
                    }
                    let p2 = Vector2(0, -halfWidth).rotated(by: r2)
                    vertexData.append(contentsOf: [p0, p1 + p0, p2 + p0].map {
                        $0.applying(transform).float2
                    })
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
                    let pt = [Vector2(0, 0.5).applying(t0),
                              Vector2(0, 0.5).applying(t1)]

                    let p0 = Vector2(p)
                    let s = Vector2.cross(dir0, dir1)
                    let t = Vector2.cross(pt[1] - pt[0], dir1) / s
                    let p1 = pt[0] + dir0 * t

                    let triangles = [p0, p1, pt[0], p0, pt[1], p1].map {
                        $0.applying(transform).float2
                    }
                    vertexData.append(contentsOf: triangles)
                } else {
                    let pt = [Vector2(0, -0.5).applying(t0),
                              Vector2(0, -0.5).applying(t1)]

                    let p0 = Vector2(p)
                    let s = Vector2.cross(dir0, dir1)
                    let t = Vector2.cross(pt[1] - pt[0], dir1) / s
                    let p1 = pt[0] + dir0 * t

                    let triangles = [p0, pt[0], p1, p0, p1, pt[1]].map {
                        $0.applying(transform).float2
                    }
                    vertexData.append(contentsOf: triangles)
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
                        let step = 1.0 / curve.approximateLength()
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
                        let step = 1.0 / curve.approximateLength()
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
                    let d = (p1 - p0).normalized()
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

        // pipeline states for generate polgon winding numbers
        guard let pipelineState = pipeline.renderState(
            shader: .stencil,
            colorFormat: renderPass.colorFormat,
            depthFormat: renderPass.depthFormat,
            blendState: BlendState(writeMask: [])) else {
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
        encoder.setFrontFacing(.clockwise)
        encoder.setStencilReferenceValue(0)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.draw(vertexStart: 0,
                     vertexCount: vertexData.count,
                     instanceCount: 1,
                     baseInstance: 0)
        return true
    }

    func encodeStencilPathFillCommand(renderPass: RenderPass,
                                      path: Path) -> Bool {
        if path.isEmpty { return false }

        struct PolygonElement {
            var vertices: [CGPoint] = []
        }
        var polygons: [PolygonElement] = []
        if true {
            var initialPoint: CGPoint? = nil
            var currentPoint: CGPoint? = nil
            var polygon = PolygonElement()
            path.forEach { element in
                // make polygon array from path
                switch element {
                case .move(let to):
                    polygons.append(polygon)
                    polygon = PolygonElement()
                    initialPoint = to
                    currentPoint = to
                case .line(let p1):
                    if let p0 = currentPoint {
                        if polygon.vertices.isEmpty {
                            polygon.vertices.append(p0)
                        }
                        polygon.vertices.append(p1)
                    }
                    currentPoint = p1
                case .quadCurve(let p2, let p1):
                    if let p0 = currentPoint {
                        let curve = QuadraticBezier(p0: p0, p1: p1, p2: p2)
                        let length = curve.approximateLength()
                        if length > .ulpOfOne {
                            let step = 1.0 / curve.approximateLength()
                            var t = step
                            while t < 1.0 {
                                let pt = curve.interpolate(t)
                                polygon.vertices.append(pt)
                                t += step
                            }
                            polygon.vertices.append(p2)
                        }
                    }
                    currentPoint = p2
                case .curve(let p3, let p1, let p2):
                    if let p0 = currentPoint {
                        let curve = CubicBezier(p0: p0, p1: p1, p2: p2, p3: p3)
                        let length = curve.approximateLength()
                        if length > .ulpOfOne {
                            let step = 1.0 / curve.approximateLength()
                            var t = step
                            while t < 1.0 {
                                let pt = curve.interpolate(t)
                                polygon.vertices.append(pt)
                                t += step
                            }
                            polygon.vertices.append(p3)
                        }
                    }
                    currentPoint = p3
                case .closeSubpath:
                    polygons.append(polygon)
                    polygon = PolygonElement()
                    currentPoint = initialPoint
                }
            }
            polygons.append(polygon)
        }

        let transform = self.transform.concatenating(self.viewTransform)
        var numVertices = 0
        polygons.forEach {
            numVertices += $0.vertices.count + 2
        }
        var vertexData: [Float2] = []
        vertexData.reserveCapacity(numVertices)

        var indexData: [UInt32] = []
        indexData.reserveCapacity(numVertices * 3)

        polygons.forEach { element in
            // make vertex, index data.
            if element.vertices.count < 2 { return }

            let baseIndex = UInt32(vertexData.count)
            var center: Vector2 = .zero
            element.vertices.forEach { pt in
                let v = Vector2(pt.applying(transform))
                vertexData.append(v.float2)
                center += v
            }
            center = center / Scalar(element.vertices.count)
            let pivotIndex = UInt32(vertexData.count)
            vertexData.append(center.float2)

            for i in (baseIndex + 1)..<pivotIndex {
                indexData.append(i - 1)
                indexData.append(i)
                indexData.append(pivotIndex)
            }
            indexData.append(pivotIndex - 1)
            indexData.append(baseIndex)
            indexData.append(pivotIndex)
        }
        if vertexData.count < 3 { return false }
        if indexData.count < 3 { return false }

        guard let vertexBuffer = self.makeBuffer(vertexData) else {
            Log.err("GraphicsContext error: _makeBuffer failed.")
            return false
        }
        guard let indexBuffer = self.makeBuffer(indexData) else {
            Log.err("GraphicsContext error: _makeBuffer failed.")
            return false
        }

        // pipeline states for generate polygon winding numbers
        guard let pipelineState = pipeline.renderState(
            shader: .stencil,
            colorFormat: renderPass.colorFormat,
            depthFormat: renderPass.depthFormat,
            blendState: BlendState(writeMask: [])) else {
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
        encoder.setFrontFacing(.clockwise)
        encoder.setStencilReferenceValue(0)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.drawIndexed(indexCount: indexData.count,
                            indexType: .uint32,
                            indexBuffer: indexBuffer,
                            indexBufferOffset: 0,
                            instanceCount: 1,
                            baseVertex: 0,
                            baseInstance: 0)
        return true
    }

    func encodeShadingBoxCommand(renderPass: RenderPass,
                                 shading: GraphicsContext.Shading,
                                 stencil: _Stencil,
                                 blendState: BlendState) {

        if shading.properties.isEmpty { return }

        var vertices: [_Vertex] = []
        var shader: _Shader = .vertexColor

        var property = shading.properties.first
        if case let .style(style) = property {
            var shape = _ShapeStyle_Shape()
            style._apply(to: &shape)
            property = shape.shading?.properties.first
        }

        if let property {
            switch property {
            case let .color(c):
                shader = .vertexColor
                let makeVertex = { (x: Scalar, y: Scalar) in
                    _Vertex(position: Vector2(x, y).float2,
                            texcoord: Vector2.zero.float2,
                            color: c.dkColor.float4)
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
                                                        blendState: blendState)
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

                let viewportExtents = [CGPoint(x: -1, y: -1),   // left-bottom
                                       CGPoint(x: -1, y: 1),    // left-top
                                       CGPoint(x: 1, y: 1),     // right-top
                                       CGPoint(x: 1, y: -1)]    // right-bottom
                    .map { $0.applying(viewportToGradientTransform) }
                let maxX = viewportExtents.max { $0.x < $1.x }!.x
                let minX = viewportExtents.min { $0.x < $1.x }!.x
                let maxY = viewportExtents.max { $0.y < $1.y }!.y
                let minY = viewportExtents.min { $0.y < $1.y }!.y

                let gradientToViewportTransform = gradientTransform
                    .concatenating(self.viewTransform)

                let addGradientBox = { (x1: CGFloat, x2: CGFloat, c1: VVD.Color, c2: VVD.Color) in
                    let verts = [_Vertex(position: Vector2(x1, maxY).applying(gradientToViewportTransform).float2,
                                         texcoord: Vector2.zero.float2,
                                         color: c1.float4),
                                 _Vertex(position: Vector2(x1, minY).applying(gradientToViewportTransform).float2,
                                         texcoord: Vector2.zero.float2,
                                         color: c1.float4),
                                 _Vertex(position: Vector2(x2, maxY).applying(gradientToViewportTransform).float2,
                                         texcoord: Vector2.zero.float2,
                                         color: c2.float4),
                                 _Vertex(position: Vector2(x2, minY).applying(gradientToViewportTransform).float2,
                                         texcoord: Vector2.zero.float2,
                                         color: c2.float4)]
                    vertices.append(contentsOf: [verts[0], verts[1], verts[2]])
                    vertices.append(contentsOf: [verts[2], verts[1], verts[3]])
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
                                               s1.color.dkColor,
                                               s2.color.dkColor)
                            }
                        } else {
                            for i in 0..<(stops.count-1) {
                                let s1 = stops[i]
                                let s2 = stops[i+1]

                                if s1.location + pos > maxX { break }
                                if s2.location + pos < minX { continue }
                                addGradientBox(s1.location + pos,
                                               s2.location + pos,
                                               s1.color.dkColor,
                                               s2.color.dkColor)
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
                                           s1.color.dkColor,
                                           s2.color.dkColor)
                        }
                        pos += 1
                    }
                } else {
                    for i in 0..<(stops.count-1) {
                        let s1 = stops[i]
                        let s2 = stops[i+1]

                        addGradientBox(s1.location, s2.location,
                                       s1.color.dkColor, s2.color.dkColor)
                    }
                    if let first = stops.first, first.location > minX {
                        addGradientBox(minX, first.location,
                                       first.color.dkColor, first.color.dkColor)
                    }
                    if let last = stops.last, last.location < maxX {
                        addGradientBox(last.location, maxX,
                                       last.color.dkColor, last.color.dkColor)
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
                            blendState: blendState)
                    } else {
                        return self.encodeShadingBoxCommand(
                            renderPass: renderPass,
                            shading: .color(stops.first!.color),
                            stencil: stencil,
                            blendState: blendState)
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
                        c2 = .lerp(c1, c2, (x2 - scale)/(x2 - x1))
                        x2 = scale
                    }
                    if (x2 - x1) < .ulpOfOne { return }
                    assert(x2 > x1)

                    let p0 = Vector2(x1, 0)
                    let p1 = p0.rotated(by: step)
                    let p2 = Vector2(x2, 0)
                    let p3 = p2.rotated(by: step)

                    let verts: [Vector2]
                    let colors: [Color]
                    if (p1 - p0).magnitudeSquared < .ulpOfOne {
                        verts = [p0, p2, p3]
                        colors = [c1, c2, c2]
                    } else {
                        verts = [p1, p0, p3, p3, p0, p2]
                        colors = [c1, c1, c2, c2, c1, c2]
                    }
                    let numVertices = Int((CGFloat.pi * 2) / step) + 1
                    vertices.reserveCapacity(vertices.count + numVertices * verts.count)
                    var progress: CGFloat = .zero
                    while progress < .pi * 2  {
                        for (i, p) in verts.enumerated() {
                            vertices.append(_Vertex(position: p.rotated(by: progress).applying(transform).float2,
                                                    texcoord: texCoord,
                                                    color: colors[i].dkColor.float4))
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
                while progress < .pi * 2 {
                    let p0 = Vector2(1, 0).rotated(by: progress).applying(transform)
                    let p1 = Vector2(1, 0).rotated(by: progress + step).applying(transform)
                    let color1 = gradient._linearInterpolatedColor(at: progress / (.pi * 2))
                    let color2 = gradient._linearInterpolatedColor(at: (progress + step) / (.pi * 2))

                    vertices.append(_Vertex(position: center.float2,
                                            texcoord: texCoord,
                                            color: color1.dkColor.float4))
                    vertices.append(_Vertex(position: p0.float2,
                                            texcoord: texCoord,
                                            color: color1.dkColor.float4))
                    vertices.append(_Vertex(position: p1.float2,
                                            texcoord: texCoord,
                                            color: color2.dkColor.float4))

                    progress += step
                }
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
