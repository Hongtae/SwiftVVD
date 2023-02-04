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

public struct Path: Equatable, LosslessStringConvertible {
    public init() {
    }

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

    public init?(_ string: String) {
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

    public var isEmpty: Bool { self.elements.isEmpty }

    public var boundingRect: CGRect { bounds }

    public func contains(_ p: CGPoint, eoFill: Bool = false) -> Bool {
        fatalError()
    }

    public enum Element: Equatable, Sendable {
        case move(to: CGPoint)
        case line(to: CGPoint)
        case quadCurve(to: CGPoint, control: CGPoint)
        case curve(to: CGPoint, control1: CGPoint, control2: CGPoint)
        case closeSubpath
    }
    private var elements: [Element] = []
    private var bounds: CGRect = .null

    public func forEach(_ body: (Path.Element) -> Void) {
        self.elements.forEach(body)
    }

    public func strokedPath(_ style: StrokeStyle) -> Path {
        fatalError()
    }

    public func trimmedPath(from: CGFloat, to: CGFloat) -> Path {
        fatalError()
    }
}

extension Path: Shape {
    public func path(in _: CGRect) -> Path {
        fatalError()
    }

    public typealias AnimatableData = EmptyAnimatableData

    public var animatableData: EmptyAnimatableData {
        get { EmptyAnimatableData() }
        set { fatalError() }
    }

//    public typealias Body
}

extension Path: _PrimitiveView {
}

private let _r: Double = 0.552285 // cubic bezier control point ratio for circle

extension Path {
    public mutating func move(to p: CGPoint) {
        if case .move(_) = self.elements.last {
            self.elements.removeLast()
            self._updateBounds()
        }
        self.elements.append(.move(to: p))
        self._extendBounds(by: p)
    }

    public mutating func addLine(to p: CGPoint) {
        self.elements.append(.line(to: p))
        self._extendBounds(by: p)
    }

    public mutating func addQuadCurve(to p: CGPoint, control cp: CGPoint) {
        self.elements.append(.quadCurve(to: p, control: cp))
        self._extendBounds(by: p)
        self._extendBounds(by: cp)
    }

    public mutating func addCurve(to p: CGPoint, control1 cp1: CGPoint, control2 cp2: CGPoint) {
        self.elements.append(.curve(to: p, control1: cp1, control2: cp2))
        self._extendBounds(by: p)
        self._extendBounds(by: cp1)
        self._extendBounds(by: cp2)
    }

    public mutating func closeSubpath() {
        if let last = self.elements.last, last != .closeSubpath {
            self.elements.append(.closeSubpath)
        }
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
            CGPoint(x: maxX, y: midY).applying(transform),      // right-middle
            CGPoint(x: maxX, y: maxY - cy).applying(transform), // right-bottom

            CGPoint(x: maxX, y: lerp(maxY - cy, maxY, _r)).applying(transform),
            CGPoint(x: lerp(maxX - cx, maxX, _r), y: maxY).applying(transform),

            CGPoint(x: maxX - cx, y: maxY).applying(transform), // bottom-right
            CGPoint(x: minX + cx, y: maxY).applying(transform), // bottom-left

            CGPoint(x: lerp(minX + cx, minX, _r), y: maxY).applying(transform),
            CGPoint(x: minX, y: lerp(maxY - cy, maxY, _r)).applying(transform),

            CGPoint(x: minX, y: maxY - cy).applying(transform), // left-bottom
            CGPoint(x: minX, y: minY + cy).applying(transform), // left-upper

            CGPoint(x: minX, y: lerp(minY + cy, minY, _r)).applying(transform),
            CGPoint(x: lerp(minX + cx, minX, _r), y: minY).applying(transform),

            CGPoint(x: minX + cx, y: minY).applying(transform), // top-left
            CGPoint(x: maxX - cx, y: minY).applying(transform), // top-right

            CGPoint(x: lerp(maxX - cx, maxX, _r), y: minY).applying(transform),
            CGPoint(x: maxX, y: lerp(minY + cy, minY, _r)).applying(transform),

            CGPoint(x: maxX, y: minY + cy).applying(transform), // right-upper
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
            CGPoint(x: maxX, y: midY).applying(transform),  // right
            CGPoint(x: maxX, y: lerp(midY, maxY, _r)).applying(transform),
            CGPoint(x: lerp(midX, maxX, _r), y: maxY).applying(transform),

            CGPoint(x: midX, y: maxY).applying(transform),  // bottom
            CGPoint(x: lerp(midX, minX, _r), y: maxY).applying(transform),
            CGPoint(x: minX, y: lerp(midY, maxY, _r)).applying(transform),

            CGPoint(x: minX, y: midY).applying(transform),  // left
            CGPoint(x: minX, y: lerp(midY, minY, _r)).applying(transform),
            CGPoint(x: lerp(midX, minX, _r), y: minY).applying(transform),

            CGPoint(x: midX, y: minY).applying(transform),  // top
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

        let current = Vector2(currentPoint ?? .zero)

        // tangent-vector1 = -p1
        // tangent-vector2 = p2 - (p1 + pivot)

        let p1 = Vector2(p1)
        let p2 = Vector2(p2)
        let pivot = current + p1
        let tan1 = Vector2(-p1).normalized()
        let tan2 = Vector2(p2 - pivot).normalized()
        let d = Vector2.dot(tan1, tan2) // cos of two vectors

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
        var delta = (Double.pi - r) * 2.0
        if clockwise {
            delta = -delta
        }
        let startAngle = acos(Vector2.dot(Vector2(1, 0), (startPoint - center).normalized()))

        self.addRelativeArc(center: CGPoint(center),
                            radius: radius,
                            startAngle: .radians(startAngle),
                            delta: .radians(delta))
    }

    public mutating func addPath(_ path: Path, transform: CGAffineTransform = .identity) {
        let path = path.applying(transform)
        self.elements.append(contentsOf: path.elements)
        self._updateBounds()
    }

    public var currentPoint: CGPoint? {
        var start: CGPoint? = nil
        var current: CGPoint? = nil

        self.elements.forEach {
            switch $0 {
            case .move(let to):
                start = to
                current = to
            case .line(let to), .quadCurve(let to, _), .curve(let to, _, _):
                if current != nil {
                    current = to
                } else {
                    Log.error("no current point.")
                }
            case .closeSubpath:
                current = start
            }
        }
        return current
    }

    public func applying(_ transform: CGAffineTransform) -> Path {
        if transform.isIdentity {
            return self
        }

        var path = Path()
        path.elements.reserveCapacity(self.elements.count)
        self.elements.forEach {
            switch $0 {
            case .move(let to):
                path.elements.append(.move(to: to.applying(transform)))
            case .line(let to):
                path.elements.append(.line(to: to.applying(transform)))
            case .quadCurve(let to, let c):
                path.elements.append(.quadCurve(to: to.applying(transform),
                                                control: c.applying(transform)))
            case .curve(let to, let c1, let c2):
                path.elements.append(.curve(to: to.applying(transform),
                                            control1: c1.applying(transform),
                                            control2: c2.applying(transform)))
            case .closeSubpath:
                path.elements.append(.closeSubpath)
            }
        }
        path._updateBounds()
        return path
    }

    public func offsetBy(dx: CGFloat, dy: CGFloat) -> Path {
        self.applying(CGAffineTransform(translationX: dx, y: dy))
    }

    private mutating func _extendBounds(by pt: CGPoint) {
        if self.bounds.isNull {
            self.bounds = CGRect(x: pt.x, y: pt.y, width: 0, height: 0)
        } else {
            let minX = min(self.bounds.minX, pt.x)
            let maxX = max(self.bounds.maxX, pt.x)
            let minY = min(self.bounds.minY, pt.y)
            let maxY = max(self.bounds.maxY, pt.y)
            self.bounds = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        }
    }

    private mutating func _updateBounds() {
        if self.elements.isEmpty {
            self.bounds = .null
            return
        }
        var minX: CGFloat = .greatestFiniteMagnitude
        var maxX: CGFloat = -(.greatestFiniteMagnitude)
        var minY: CGFloat = .greatestFiniteMagnitude
        var maxY: CGFloat = -(.greatestFiniteMagnitude)

        let update = { (_ pt: CGPoint) in
            minX = .minimum(minX, pt.x)
            minY = .minimum(minY, pt.y)
            maxX = .maximum(maxX, pt.x)
            maxY = .maximum(maxY, pt.y)
        }
        self.elements.forEach {
            switch $0 {
            case .move(let to):
                update(to)
            case .line(let to):
                update(to)
            case .quadCurve(let to, let c):
                update(to)
                update(c)
            case .curve(let to, let c1, let c2):
                update(to)
                update(c1)
                update(c2)
            case .closeSubpath:
                break
            }
        }
        self.bounds = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
