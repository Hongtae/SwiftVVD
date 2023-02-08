//
//  File: Path.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import Foundation
import DKGame

public enum RoundedCornerStyle: Equatable, Hashable {
    case circular
    case continuous
}

public struct FillStyle: Equatable, Sendable {
    public var isEOFilled: Bool // true: even-odd rule, false: non-zero winding number rule.
    public var isAntialiased: Bool

    public init(eoFill: Bool = false, antialiased: Bool = true) {
        self.isEOFilled = eoFill
        self.isAntialiased = antialiased
    }
}

public struct Path: Equatable {
    public init() {
    }

    public var isEmpty: Bool { self.elements.isEmpty }

    public func contains(_ p: CGPoint, eoFill: Bool = false) -> Bool {
        var winding: Int = 0

        let lineCheck = { (p0: CGPoint, p1: CGPoint) in
            if min(p0.y, p1.y) <= p.y && max(p0.y, p1.y) > p.y {
                let a = (p1.y - p1.y) / (p0.x - p0.x)
                let b = p1.y - a * p1.x
                let x = (p.y - b) / a
                if x <= p.x {
                    if a > 0 {
                        winding += 1
                    } else if a < 0 {
                        winding -= 1
                    }
                }
            }
        }

        let quadraticBezierCheck = { (p0: CGPoint, p1: CGPoint, p2: CGPoint) in
            let bbox = CGRect.boundingRect(p0, p1, p2)
            if bbox.minX <= p.x && bbox.minY <= p.y && bbox.maxY > p.y {
                let curve = QuadraticBezier(p0: p0, p1: p1, p2: p2)
                curve.intersectLineSegment(CGPoint(x: bbox.minX, y: p.y), p).forEach { t in
                    if t < 1 && curve.interpolate(t).x <= p.x {
                        let tangent = curve.tangent(t).y
                        if tangent > 0 {
                            winding += 1
                        } else if tangent < 0 {
                            winding -= 1
                        }
                    }
                }
            }
        }

        let cubicBezierCheck = { (p0: CGPoint, p1: CGPoint, p2: CGPoint, p3: CGPoint) in
            let bbox = CGRect.boundingRect(p0, p1, p2)
            if bbox.minX <= p.x && bbox.minY <= p.y && bbox.maxY > p.y {
                let curve = CubicBezier(p0: p0, p1: p1, p2: p2, p3: p3)
                curve.intersectLineSegment(CGPoint(x: bbox.minX, y: p.y), p).forEach { t in
                    if t < 1 && curve.interpolate(t).x <= p.x {
                        let tangent = curve.tangent(t).y
                        if tangent > 0 {
                            winding += 1
                        } else if tangent < 0 {
                            winding -= 1
                        }
                    }
                }
            }
        }

        var startPoint: CGPoint? = nil
        var currentPoint: CGPoint? = nil
        self.elements.forEach {
            switch $0 {
            case .move(let to):
                startPoint = to
                currentPoint = to
            case .line(let p1):
                if let p0 = currentPoint {
                    lineCheck(p0, p1)
                    currentPoint = p1
                }
            case .quadCurve(let p2, let p1):
                if let p0 = currentPoint {
                    quadraticBezierCheck(p0, p1, p2)
                    currentPoint = p2
                }
            case .curve(let p3, let p1, let p2):
                if let p0 = currentPoint {
                    cubicBezierCheck(p0, p1, p2, p3)
                    currentPoint = p3
                }
            case .closeSubpath:
                if let p0 = currentPoint, let p1 = startPoint {
                    lineCheck(p0, p1)
                }
                currentPoint = startPoint
            }
        }

        if eoFill { return winding % 2 != 0 }
        return winding != 0 // non zero fill
    }

    public enum Element: Equatable, Sendable {
        case move(to: CGPoint)
        case line(to: CGPoint)
        case quadCurve(to: CGPoint, control: CGPoint)
        case curve(to: CGPoint, control1: CGPoint, control2: CGPoint)
        case closeSubpath
    }
    private var elements: [Element] = []

    // smallest rectangle completely enclosing all points in the path,
    // including control points for Bézier and quadratic curves.
    private var boundingBox: CGRect = .null

    // smallest rectangle completely enclosing all points in the path
    // but not including control points for Bézier and quadratic curves.
    private var boundingBoxOfPath: CGRect = .null

    public var boundingRect: CGRect { boundingBox }

    public private(set) var initialPoint: CGPoint? = nil
    public private(set) var currentPoint: CGPoint? = nil

    public func forEach(_ body: (Path.Element) -> Void) {
        self.elements.forEach(body)
    }

    private var _strokeStyle: StrokeStyle? = nil

    public func strokedPath(_ style: StrokeStyle) -> Path {
        var path = self
        path._strokeStyle = style
        return path
    }

    public func trimmedPath(from: CGFloat, to: CGFloat) -> Path {
        let from = clamp(from, min: 0, max: 1)
        let to = clamp(to, min: 0, max: 1)

        let quadraticBezierSubdivision = 2
        let cubicBezierSubdivision = 3

        var path = Path()
        if to > from {
            // calculate total length
            var length: Double = 0

            var startPoint: CGPoint? = nil
            var currentPoint: CGPoint? = nil
            self.elements.forEach {
                switch $0 {
                case .move(let to):
                    startPoint = to
                    currentPoint = to
                case .line(let p1):
                    if let p0 = currentPoint {
                        length += (p1 - p0).magnitude
                        currentPoint = p1
                    }
                case .quadCurve(let p2, let p1):
                    if let p0 = currentPoint {
                        let curve = QuadraticBezier(p0: p0, p1: p1, p2: p2)
                        length += curve.approximateLength(subdivide: quadraticBezierSubdivision)
                        currentPoint = p2
                    }
                case .curve(let p3, let p1, let p2):
                    if let p0 = currentPoint {
                        let curve = CubicBezier(p0: p0, p1: p1, p2: p2, p3: p3)
                        length += curve.approximateLength(subdivide: cubicBezierSubdivision)
                        currentPoint = p3
                    }
                case .closeSubpath:
                    currentPoint = startPoint
                }
            }

            let start = length * from
            let end = length * to

            startPoint = nil
            currentPoint = nil
            var progress: Double = 0

            let pathElementFraction = {
                (d: Double, progress: Double) -> (t0: Double, t1: Double) in

                var t0: Double = 0
                var t1: Double = 1
                if start <= progress { t0 = 0 }
                else { t0 = (start - progress) / d }
                if end >= progress + d { t1 = 1 }
                else { t1 = (progress + d - end) / d }
                return (t0, t1)
            }

            elementLoop: for c in self.elements {
                switch c {
                case .move(let to):
                    startPoint = to
                    currentPoint = to
                    if progress >= start {
                        path.move(to: to)
                    }
                case .line(let p1):
                    if let p0 = currentPoint {
                        currentPoint = p1
                        let d = (p1 - p0).magnitude
                        if start >= progress + d {
                            progress += d
                            continue
                        }

                        let (t0, t1) = pathElementFraction(d, progress)
                        if t0 > 0 {
                            path.move(to: lerp(p0, p1, t0))
                        }
                        if t1 < 1 {
                            path.addLine(to: lerp(p0, p1, t1))
                            break elementLoop
                        } else {
                            path.addLine(to: p1)
                        }
                        progress += (t1 - t0) * d
                    }
                case .quadCurve(let p2, let p1):
                    if let p0 = currentPoint {
                        currentPoint = p2
                        var curve = QuadraticBezier(p0: p0, p1: p1, p2: p2)
                        var d = curve.approximateLength(subdivide: quadraticBezierSubdivision)
                        if start >= progress + d {
                            progress += d
                            continue
                        }

                        var (t0, t1) = pathElementFraction(d, progress)
                        if t0 > 0 {
                            path.move(to: curve.interpolate(t0))
                            curve = curve.split(t0).1
                            // rescale curve length
                            let tmp = (t1 - t0) * d
                            d = d - d * t0
                            t1 = tmp / d
                            t0 = 0
                        }
                        if t1 < 1 {
                            curve = curve.split(t1).0
                            path.addQuadCurve(to: curve.p2, control: curve.p1)
                            break elementLoop
                        } else {
                            path.addQuadCurve(to: curve.p2, control: curve.p1)
                        }
                        progress += (t1 - t0) * d
                    }
                case .curve(let p3, let p1, let p2):
                    if let p0 = currentPoint {
                        currentPoint = p3
                        var curve = CubicBezier(p0: p0, p1: p1, p2: p2, p3: p3)
                        var d = curve.approximateLength(subdivide: cubicBezierSubdivision)
                        if start >= progress + d {
                            progress += d
                            continue
                        }

                        var (t0, t1) = pathElementFraction(d, progress)
                        if t0 > 0 {
                            path.move(to: curve.interpolate(t0))
                            curve = curve.split(t0).1
                            // rescale curve length
                            let tmp = (t1 - t0) * d
                            d = d - d * t0
                            t1 = tmp / d
                            t0 = 0
                        }
                        if t1 < 1 {
                            curve = curve.split(t1).0
                            path.addCurve(to: curve.p3, control1: curve.p1, control2: curve.p2)
                            break elementLoop
                        } else {
                            path.addCurve(to: curve.p3, control1: curve.p1, control2: curve.p2)
                        }
                        progress += (t1 - t0) * d
                    }
                case .closeSubpath:
                    currentPoint = startPoint
                    if progress > start {
                        path.closeSubpath()
                    }
                }
            }
        }
        path._strokeStyle = self._strokeStyle
        return path
    }
}

extension Path: Shape {
    public func path(in frame: CGRect) -> Path {
        let frame = frame.standardized
        if frame.isNull == false && frame.width > 0 && frame.height > 0 {
            let bbox = self.boundingBoxOfPath.standardized
            if bbox.isNull == false && bbox.width > 0 && bbox.height > 0 {
                let scaleX = frame.width / bbox.width
                let scaleY = frame.height / bbox.height

                var transform = CGAffineTransform(scaleX: scaleX, y: scaleY)
                transform = transform.translatedBy(x: frame.origin.x, y: frame.origin.y)

                return self.applying(transform)
            }
        }
        return Path()
    }

    public typealias AnimatableData = EmptyAnimatableData

    public var animatableData: EmptyAnimatableData {
        get { EmptyAnimatableData() }
        set { fatalError() }
    }

//    public typealias Body
}

private let _r: Double = 0.552285 // cubic bezier control point ratio for circle

extension Path {
    public mutating func move(to p: CGPoint) {
        if case .move(_) = self.elements.last {
            self.elements.removeLast()
        }
        self.elements.append(.move(to: p))
        self.initialPoint = p
        self.currentPoint = p
    }

    public mutating func addLine(to p1: CGPoint) {
        self.elements.append(.line(to: p1))

        if let p0 = self.initialPoint {
            self.currentPoint = p1
            self.boundingBox.expand(by: p0, p1)
            self.boundingBoxOfPath.expand(by: p0, p1)
        }
    }

    public mutating func addQuadCurve(to p2: CGPoint, control p1: CGPoint) {
        self.elements.append(.quadCurve(to: p2, control: p1))

        if let p0 = self.initialPoint {
            self.currentPoint = p2
            self.boundingBox.expand(by: p0, p1, p2)
            self.boundingBoxOfPath.expand(by: QuadraticBezier(p0: p0, p1: p1, p2: p2).boundingBox)
        }
    }

    public mutating func addCurve(to p3: CGPoint, control1 p1: CGPoint, control2 p2: CGPoint) {
        self.elements.append(.curve(to: p3, control1: p1, control2: p2))

        if let p0 = self.initialPoint {
            self.currentPoint = p3
            self.boundingBox.expand(by: p0, p1, p2, p3)
            self.boundingBoxOfPath.expand(by: CubicBezier(p0: p0, p1: p1, p2: p2, p3: p3).boundingBox)
        }
    }

    public mutating func closeSubpath() {
        if let last = self.elements.last, last != .closeSubpath {
            self.elements.append(.closeSubpath)
        }
        self.currentPoint = self.initialPoint
    }

    private mutating func _extendBounds(by pt: CGPoint) {
        if self.boundingBox.isNull {
            self.boundingBox = CGRect(x: pt.x, y: pt.y, width: 0, height: 0)
        } else {
            let minX = min(self.boundingBox.minX, pt.x)
            let maxX = max(self.boundingBox.maxX, pt.x)
            let minY = min(self.boundingBox.minY, pt.y)
            let maxY = max(self.boundingBox.maxY, pt.y)
            self.boundingBox = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        }
    }

    private mutating func _extendPathBounds(by pt: CGPoint) {
        if self.boundingBox.isNull {
            self.boundingBox = CGRect(x: pt.x, y: pt.y, width: 0, height: 0)
        } else {
            let minX = min(self.boundingBox.minX, pt.x)
            let maxX = max(self.boundingBox.maxX, pt.x)
            let minY = min(self.boundingBox.minY, pt.y)
            let maxY = max(self.boundingBox.maxY, pt.y)
            self.boundingBox = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        }
    }

    private mutating func _extendPathBounds(by rect: CGRect) {
        self.boundingBoxOfPath = self.boundingBoxOfPath.union(rect)
    }
}

extension Path: LosslessStringConvertible {
    public init?(_ string: String) {
        let commands = string.components(separatedBy: .whitespacesAndNewlines)
        var floats: [Double] = []
        for str in commands {
            if str == "m" {
                if floats.count == 2 {
                    self.move(to: CGPoint(x: floats[0], y: floats[1]))
                    floats.removeAll(keepingCapacity: true)
                } else {
                    Log.err("Insufficient arguments to command.")
                    return nil
                }
            } else if str == "l" {
                if floats.count == 2 {
                    self.addLine(to: CGPoint(x: floats[0], y: floats[1]))
                    floats.removeAll(keepingCapacity: true)
                } else {
                    Log.err("Insufficient arguments to command.")
                    return nil
                }
            } else if str == "q" {
                if floats.count == 4 {
                    self.addQuadCurve(to: CGPoint(x: floats[0], y: floats[1]),
                                      control: CGPoint(x: floats[2], y: floats[3]))
                    floats.removeAll(keepingCapacity: true)
                } else {
                    Log.err("Insufficient arguments to command.")
                    return nil
                }
            } else if str == "c" {
                if floats.count == 6 {
                    self.addCurve(to: CGPoint(x: floats[0], y: floats[1]),
                                  control1: CGPoint(x: floats[2], y: floats[3]),
                                  control2: CGPoint(x: floats[4], y: floats[5]))
                    floats.removeAll(keepingCapacity: true)
                } else {
                    Log.err("Insufficient arguments to command.")
                    return nil
                }
            } else if str == "h" {
                if floats.count == 0 {
                    self.closeSubpath()
                } else {
                    Log.err("There are unknown arguments to this command.")
                    return nil
                }
            } else {
                if let d = Double(str) {
                    floats.append(d)
                } else {
                    Log.err("Unable to parse as numeric: \(str)")
                    return nil
                }
            }
        }
    }

    public var description: String {
        var desc: [String] = []
        self.forEach { element in
            switch element {
            case .move(let to):
                desc.append("\(to.x) \(to.y) m")
            case .line(let to):
                desc.append("\(to.x) \(to.y) l")
            case .quadCurve(let to, let c):
                desc.append("\(c.x) \(c.y) \(to.x) \(to.y) q")
            case .curve(let to, let c1, let c2):
                desc.append("\(c1.x) \(c1.y) \(c2.x) \(c2.y) \(to.x) \(to.y) c")
            case .closeSubpath:
                desc.append("h")
            }
        }
        return desc.joined(separator: " ")
    }
}

extension Path {
    public init(_ rect: CGRect) {
        self.addRect(rect)
    }

    public init(roundedRect rect: CGRect, cornerSize: CGSize, style: RoundedCornerStyle = .circular) {
        self.addRoundedRect(in: rect, cornerSize: cornerSize, style: style)
    }

    public init(roundedRect rect: CGRect, cornerRadius: CGFloat, style: RoundedCornerStyle = .circular) {
        self.addRoundedRect(in: rect, cornerSize: CGSize(width: cornerRadius, height: cornerRadius), style: style)
    }

    public init(ellipseIn rect: CGRect) {
        self.addEllipse(in: rect)
    }

    public init(_ callback: (inout Path) -> ()) {
        callback(&self)
    }

    public mutating func addRect(_ rect: CGRect, transform: CGAffineTransform = .identity) {
        let pt = [
            CGPoint(x: rect.minX, y: rect.minY).applying(transform),
            CGPoint(x: rect.maxX, y: rect.minY).applying(transform),
            CGPoint(x: rect.maxX, y: rect.maxY).applying(transform),
            CGPoint(x: rect.minX, y: rect.maxY).applying(transform),
        ]
        self.move(to: pt[0])
        self.addLine(to: pt[1])
        self.addLine(to: pt[2])
        self.addLine(to: pt[3])
        self.closeSubpath()
    }

    public mutating func addRoundedRect(in rect: CGRect, cornerSize: CGSize, style: RoundedCornerStyle = .circular, transform: CGAffineTransform = .identity) {
        let midX = rect.midX
        let midY = rect.midY
        let minX = rect.minX
        let maxX = rect.maxX
        let minY = rect.minY
        let maxY = rect.maxY
        let cx = clamp(cornerSize.width, min: 0, max: (maxX - midX))
        let cy = clamp(cornerSize.height, min: 0, max: (maxY - midY))

        let pt: [CGPoint] = [
            CGPoint(x: maxX, y: midY).applying(transform),
            CGPoint(x: maxX, y: maxY - cy).applying(transform),

            CGPoint(x: maxX, y: lerp(maxY - cy, maxY, _r)).applying(transform),
            CGPoint(x: lerp(maxX - cx, maxX, _r), y: maxY).applying(transform),

            CGPoint(x: maxX - cx, y: maxY).applying(transform),
            CGPoint(x: minX + cx, y: maxY).applying(transform),

            CGPoint(x: lerp(minX + cx, minX, _r), y: maxY).applying(transform),
            CGPoint(x: minX, y: lerp(maxY - cy, maxY, _r)).applying(transform),

            CGPoint(x: minX, y: maxY - cy).applying(transform),
            CGPoint(x: minX, y: minY + cy).applying(transform),

            CGPoint(x: minX, y: lerp(minY + cy, minY, _r)).applying(transform),
            CGPoint(x: lerp(minX + cx, minX, _r), y: minY).applying(transform),

            CGPoint(x: minX + cx, y: minY).applying(transform),
            CGPoint(x: maxX - cx, y: minY).applying(transform),

            CGPoint(x: lerp(maxX - cx, maxX, _r), y: minY).applying(transform),
            CGPoint(x: maxX, y: lerp(minY + cy, minY, _r)).applying(transform),

            CGPoint(x: maxX, y: minY + cy).applying(transform),
        ]
        self.move(to: pt[0])
        self.addLine(to: pt[1])
        self.addCurve(to: pt[4], control1: pt[2], control2: pt[3])
        self.addLine(to: pt[5])
        self.addCurve(to: pt[8], control1: pt[6], control2: pt[7])
        self.addLine(to: pt[9])
        self.addCurve(to: pt[12], control1: pt[10], control2: pt[11])
        self.addLine(to: pt[13])
        self.addCurve(to: pt[16], control1: pt[14], control2: pt[15])
        self.closeSubpath()
    }

    public mutating func addEllipse(in rect: CGRect, transform: CGAffineTransform = .identity) {
        let midX = rect.midX
        let midY = rect.midY
        let minX = rect.minX
        let maxX = rect.maxX
        let minY = rect.minY
        let maxY = rect.maxY
        let pt = [
            CGPoint(x: maxX, y: midY).applying(transform),
            CGPoint(x: maxX, y: lerp(midY, maxY, _r)).applying(transform),
            CGPoint(x: lerp(midX, maxX, _r), y: maxY).applying(transform),

            CGPoint(x: midX, y: maxY).applying(transform),
            CGPoint(x: lerp(midX, minX, _r), y: maxY).applying(transform),
            CGPoint(x: minX, y: lerp(midY, maxY, _r)).applying(transform),

            CGPoint(x: minX, y: midY).applying(transform),
            CGPoint(x: minX, y: lerp(midY, minY, _r)).applying(transform),
            CGPoint(x: lerp(midX, minX, _r), y: minY).applying(transform),

            CGPoint(x: midX, y: minY).applying(transform),
            CGPoint(x: lerp(midX, maxX, _r), y: minY).applying(transform),
            CGPoint(x: maxX, y: lerp(midY, minY, _r)).applying(transform),
        ]
        self.move(to: pt[0])
        self.addCurve(to: pt[3], control1: pt[1], control2: pt[2])
        self.addCurve(to: pt[6], control1: pt[4], control2: pt[5])
        self.addCurve(to: pt[9], control1: pt[7], control2: pt[8])
        self.addCurve(to: pt[0], control1: pt[10], control2: pt[11])
        self.closeSubpath()
    }

    public mutating func addRects(_ rects: [CGRect], transform: CGAffineTransform = .identity) {
        for rect in rects {
            self.addRect(rect, transform: transform)
        }
    }

    public mutating func addLines(_ lines: [CGPoint]) {
        for line in lines {
            self.addLine(to: line)
        }
    }

    public mutating func addRelativeArc(center: CGPoint, radius: CGFloat, startAngle: Angle, delta: Angle, transform: CGAffineTransform = .identity) {
        var delta = delta.radians
        if delta.magnitude < .ulpOfOne { return }

        var trans = CGAffineTransform(scaleX: radius, y: radius)
        if delta < 0.0 {
            trans = trans.scaledBy(x: 1, y: -1) // flip
            delta = delta.magnitude
        }
        trans = trans.rotated(by: startAngle.radians)
        trans = trans.translatedBy(x: center.x, y: center.y)
        trans = trans.concatenating(transform)

        let startPoint = CGPoint(x: 1, y: 0).applying(trans)

        if let last = self.elements.last, last != .closeSubpath {
            self.addLine(to: startPoint)
        } else {
            self.move(to: startPoint)
        }

        let oneQuarter = CubicBezier(p0: CGPoint(x: 1, y: 0),
                                     p1: CGPoint(x: 1, y: lerp(0, 1, _r)),
                                     p2: CGPoint(x: lerp(0, 1, _r), y: 1),
                                     p3: CGPoint(x: 0, y: 1))

        let halfPi: Double = .pi * 0.5
        var rotate = CGAffineTransform.identity
        while delta > 0 {
            let t = rotate.concatenating(trans)
            if delta >= halfPi {
                let to = oneQuarter.p3.applying(t)
                let c1 = oneQuarter.p1.applying(t)
                let c2 = oneQuarter.p2.applying(t)
                self.addCurve(to: to, control1: c1, control2: c2)
            } else {
                let curve = oneQuarter.split(delta / halfPi).0
                let to = curve.p3.applying(t)
                let c1 = curve.p1.applying(t)
                let c2 = curve.p2.applying(t)
                self.addCurve(to: to, control1: c1, control2: c2)
                break
            }
            delta = delta - halfPi
            rotate = rotate.rotated(by: halfPi)
        }
    }

    public mutating func addArc(center: CGPoint, radius: CGFloat, startAngle: Angle, endAngle: Angle, clockwise: Bool, transform: CGAffineTransform = .identity) {
        var angle: Double = 0.0

        let normalizeRadian = { (r: Double) -> Double in
            let pi2: Double = .pi * 2
            var r = r
            while r < 0.0 { r += pi2 }
            while r > pi2 { r -= pi2 }
            return r
        }

        if clockwise {
            let r = startAngle.radians - endAngle.radians
            angle = normalizeRadian(r)
        } else {
            let r = endAngle.radians - startAngle.radians
            angle = normalizeRadian(r)
        }

        if angle.magnitude < .ulpOfOne { return }

        var trans = CGAffineTransform(scaleX: radius, y: radius)
        if clockwise {
            trans = trans.scaledBy(x: 1, y: -1) // flip
        }
        trans = trans.rotated(by: startAngle.radians)
        trans = trans.translatedBy(x: center.x, y: center.y)
        trans = trans.concatenating(transform)

        let startPoint = CGPoint(x: 1, y: 0).applying(trans)

        if let last = self.elements.last, last != .closeSubpath {
            self.addLine(to: startPoint)
        } else {
            self.move(to: startPoint)
        }

        let oneQuarter = CubicBezier(p0: CGPoint(x: 1, y: 0),
                                     p1: CGPoint(x: 1, y: lerp(0, 1, _r)),
                                     p2: CGPoint(x: lerp(0, 1, _r), y: 1),
                                     p3: CGPoint(x: 0, y: 1))

        let halfPi: Double = .pi * 0.5
        var rotate = CGAffineTransform.identity
        while angle > 0 {
            let t = rotate.concatenating(trans)
            if angle >= halfPi {
                let to = oneQuarter.p3.applying(t)
                let c1 = oneQuarter.p1.applying(t)
                let c2 = oneQuarter.p2.applying(t)
                self.addCurve(to: to, control1: c1, control2: c2)
            } else {
                let curve = oneQuarter.split(angle / halfPi).0
                let to = curve.p3.applying(t)
                let c1 = curve.p1.applying(t)
                let c2 = curve.p2.applying(t)
                self.addCurve(to: to, control1: c1, control2: c2)
                break
            }
            angle = angle - halfPi
            rotate = rotate.rotated(by: halfPi)
        }
    }

    public mutating func addArc(tangent1End p1: CGPoint, tangent2End p2: CGPoint, radius: CGFloat, transform: CGAffineTransform = .identity) {
        if radius < .ulpOfOne { return }

        let current = currentPoint ?? .zero

        // tangent-vector1 = -p1
        // tangent-vector2 = p2 - (p1 + pivot)

        let pivot = current + p1
        let tan1 = (-p1).normalized()
        let tan2 = (p2 - pivot).normalized()
        let d = CGPoint.dot(tan1, tan2) // cos of two vectors

        if d == 0.0 { return }
        if d == .pi * 2 { return }

        var clockwise = false
        if d < 0.0 { clockwise = true }

        let r = acos(d) * 0.5
        let distanceToCircleCenter = radius / sin(r)
        let distanceToStart = radius / tan(r)

        let center = (tan1 + tan2).normalized() * distanceToCircleCenter + pivot
        let startPoint = tan1 * distanceToStart + pivot
        //let endPoint = tan2 * distanceToStart + pivot
        var delta = (.pi - r) * 2.0
        if clockwise {
            delta = -delta
        }
        let startAngle = acos(CGPoint.dot(CGPoint(x: 1, y: 0), (startPoint - center).normalized()))

        self.addRelativeArc(center: center,
                            radius: radius,
                            startAngle: .radians(startAngle),
                            delta: .radians(delta))
    }

    public mutating func addPath(_ path: Path, transform: CGAffineTransform = .identity) {
        self.elements.reserveCapacity(self.elements.count + path.elements.count)
        path.elements.forEach {
            switch $0 {
            case .move(let to):
                self.move(to: to.applying(transform))
            case .line(let to):
                self.addLine(to: to.applying(transform))
            case .quadCurve(let to, let cp):
                self.addQuadCurve(to: to.applying(transform),
                                  control: cp.applying(transform))
            case .curve(let to, let cp1, let cp2):
                self.addCurve(to: to.applying(transform),
                              control1: cp1.applying(transform),
                              control2: cp2.applying(transform))
            case .closeSubpath:
                self.closeSubpath()
            }
        }
    }

    public func applying(_ transform: CGAffineTransform) -> Path {
        if transform.isIdentity {
            return self
        }

        var path = Path()
        path.addPath(self, transform: transform)
        path._strokeStyle = self._strokeStyle
        return path
    }

    public func offsetBy(dx: CGFloat, dy: CGFloat) -> Path {
        self.applying(CGAffineTransform(translationX: dx, y: dy))
    }
}

extension Path: _PrimitiveView {
}
