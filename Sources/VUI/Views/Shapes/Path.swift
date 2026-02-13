//
//  File: Path.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

import Foundation
import VVD

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
            if min(p0.y, p1.y) <= p.y && max(p0.y, p1.y) > p.y && min(p0.x, p1.x) < p.x {
                let dy = p1.y - p0.y
                let dx = p1.x - p0.x
                if max(p0.x, p1.x) <= p.x || abs(dx) < .ulpOfOne {
                    if p0.x <= p.x {
                        if dy > 0 {
                            winding -= 1
                        } else {
                            winding += 1
                        }
                    }
                } else {
                    let a = dx / dy
                    let x = (p.y - p1.y) * a + p1.x
                    if x <= p.x {
                        if a < 0 {
                            winding -= 1
                        } else {
                            winding += 1
                        }
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
                            winding -= 1
                        } else if tangent < 0 {
                            winding += 1
                        }
                    }
                }
            }
        }

        let cubicBezierCheck = { (p0: CGPoint, p1: CGPoint, p2: CGPoint, p3: CGPoint) in
            let bbox = CGRect.boundingRect(p0, p1, p2, p3)
            if bbox.minX <= p.x && bbox.minY <= p.y && bbox.maxY > p.y {
                let curve = CubicBezier(p0: p0, p1: p1, p2: p2, p3: p3)
                curve.intersectLineSegment(CGPoint(x: bbox.minX, y: p.y), p).forEach { t in
                    if t < 1 && curve.interpolate(t).x <= p.x {
                        let tangent = curve.tangent(t).y
                        if tangent > 0 {
                            winding -= 1
                        } else if tangent < 0 {
                            winding += 1
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
    var boundingBox: CGRect = .null
    
    // smallest rectangle completely enclosing all points in the path
    // but not including control points for Bézier and quadratic curves.
    var boundingBoxOfPath: CGRect = .null

    public var boundingRect: CGRect { boundingBoxOfPath }

    public private(set) var initialPoint: CGPoint? = nil
    public private(set) var currentPoint: CGPoint? = nil

    public func forEach(_ body: (Path.Element) -> Void) {
        self.elements.forEach(body)
    }

    public func strokedPath(_ style: StrokeStyle) -> Path {
        let halfWidth = style.lineWidth * 0.5
        if halfWidth < .ulpOfOne { return Path() }

        // Internal Types
        enum Seg {
            case line(from: CGPoint, to: CGPoint)
            case cubic(CubicBezier)

            var startPoint: CGPoint {
                switch self {
                case .line(let from, _): return from
                case .cubic(let c):      return c.p0
                }
            }
            var endPoint: CGPoint {
                switch self {
                case .line(_, let to): return to
                case .cubic(let c):    return c.p3
                }
            }
            var startDir: CGPoint {
                switch self {
                case .line(let from, let to): return (to - from).normalized()
                case .cubic(let c):           return c.startDirection
                }
            }
            var endDir: CGPoint {
                switch self {
                case .line(let from, let to): return (to - from).normalized()
                case .cubic(let c):           return c.endDirection
                }
            }
            var length: CGFloat {
                switch self {
                case .line(let from, let to): return (to - from).magnitude
                case .cubic(let c):           return c.approximateLength(subdivide: 2)
                }
            }

            func split(_ t: CGFloat) -> (Seg, Seg) {
                switch self {
                case .line(let from, let to):
                    let mid = lerp(from, to, t)
                    return (.line(from: from, to: mid), .line(from: mid, to: to))
                case .cubic(let c):
                    let (a, b) = c.split(t)
                    return (.cubic(a), .cubic(b))
                }
            }
        }

        struct SubPath {
            var segments: [Seg]
            var isClosed: Bool
        }

        let normalOf = { (dir: CGPoint) -> CGPoint in
            CGPoint(x: -dir.y, y: dir.x)
        }

        // Offset Helpers
        let offsetSegment = { (seg: Seg, distance: CGFloat) -> [(to: CGPoint, c1: CGPoint?, c2: CGPoint?)] in
            switch seg {
            case .line(let from, let to):
                let dir = (to - from).normalized()
                let n = normalOf(dir)
                return [(to: to + n * distance, c1: nil, c2: nil)]
            case .cubic(let c):
                return c.offsetCurves(by: distance).map {
                    (to: $0.p3, c1: $0.p1, c2: $0.p2)
                }
            }
        }

        let offsetStartPoint = { (seg: Seg, distance: CGFloat) -> CGPoint in
            let n = normalOf(seg.startDir)
            return seg.startPoint + n * distance
        }

        let addOffsetElements = { (path: inout Path, elements: [(to: CGPoint, c1: CGPoint?, c2: CGPoint?)]) in
            for e in elements {
                if let c1 = e.c1, let c2 = e.c2 {
                    path.addCurve(to: e.to, control1: c1, control2: c2)
                } else {
                    path.addLine(to: e.to)
                }
            }
        }

        // Parse path into sub-paths
        var subPaths: [SubPath] = []
        do {
            var spStart: CGPoint? = nil
            var currentPt: CGPoint? = nil
            var segs: [Seg] = []

            let flushOpen = {
                if spStart != nil, !segs.isEmpty {
                    subPaths.append(SubPath(segments: segs, isClosed: false))
                }
                segs = []
            }

            self.forEach { element in
                switch element {
                case .move(let to):
                    flushOpen()
                    spStart = to
                    currentPt = to
                case .line(let to):
                    if let cp = currentPt {
                        if (to - cp).magnitude > .ulpOfOne {
                            segs.append(.line(from: cp, to: to))
                        }
                    }
                    currentPt = to
                case .quadCurve(let to, let control):
                    if let cp = currentPt {
                        let cubic = QuadraticBezier(p0: cp, p1: control, p2: to).toCubic()
                        if cubic.approximateLength() > .ulpOfOne {
                            segs.append(.cubic(cubic))
                        }
                    }
                    currentPt = to
                case .curve(let to, let c1, let c2):
                    if let cp = currentPt {
                        let cubic = CubicBezier(p0: cp, p1: c1, p2: c2, p3: to)
                        if cubic.approximateLength() > .ulpOfOne {
                            segs.append(.cubic(cubic))
                        }
                    }
                    currentPt = to
                case .closeSubpath:
                    if let start = spStart, let cp = currentPt {
                        if (cp - start).magnitude > .ulpOfOne {
                            segs.append(.line(from: cp, to: start))
                        }
                    }
                    if !segs.isEmpty {
                        subPaths.append(SubPath(segments: segs, isClosed: true))
                    }
                    segs = []
                    currentPt = spStart
                }
            }
            flushOpen()
        }

        // Dash pattern
        if !style.dash.isEmpty {
            let dash = style.dash.map { $0.magnitude }
            let numDashes = dash.count
            let patternLen = dash.reduce(0, +)
            if patternLen > .ulpOfOne && numDashes > 0 {
                var dashedPaths: [SubPath] = []
                for sp in subPaths {
                    // compute total length
                    var totalLength: CGFloat = 0
                    for s in sp.segments { totalLength += s.length }
                    if totalLength < .ulpOfOne { continue }

                    // initialize dash phase
                    var dashIdx = 0
                    var dashRemain = dash[0]
                    if style.dashPhase != 0 {
                        var phase = style.dashPhase.truncatingRemainder(dividingBy: patternLen)
                        if phase < 0 { phase += patternLen }
                        while phase > .ulpOfOne {
                            let dl = dash[dashIdx % numDashes]
                            if phase <= dl {
                                dashRemain = dl - phase
                                break
                            }
                            phase -= dl
                            dashIdx += 1
                        }
                        if dashRemain < .ulpOfOne {
                            dashIdx += 1
                            dashRemain = dash[dashIdx % numDashes]
                        }
                    }

                    var currentSegs: [Seg] = []
                    for seg in sp.segments {
                        var remaining = seg
                        var segLen = remaining.length
                        while segLen > .ulpOfOne {
                            let consume = min(dashRemain, segLen)
                            let isVisible = dashIdx % 2 == 0

                            if consume >= segLen - .ulpOfOne {
                                // consume the entire remaining segment
                                if isVisible { currentSegs.append(remaining) }
                                dashRemain -= segLen
                                segLen = 0
                            } else {
                                // split the segment
                                let t = consume / segLen
                                let (head, tail) = remaining.split(t)
                                if isVisible { currentSegs.append(head) }
                                remaining = tail
                                segLen = remaining.length
                                dashRemain = 0
                            }

                            if dashRemain < .ulpOfOne {
                                // end of current dash/gap
                                if !currentSegs.isEmpty {
                                    dashedPaths.append(SubPath(segments: currentSegs, isClosed: false))
                                    currentSegs = []
                                }
                                dashIdx += 1
                                dashRemain = dash[dashIdx % numDashes]
                            }
                        }
                    }
                    if !currentSegs.isEmpty {
                        dashedPaths.append(SubPath(segments: currentSegs, isClosed: false))
                    }
                }
                subPaths = dashedPaths
            }
        }

        // Join helper
        let addJoin = { (path: inout Path, point: CGPoint,
                         d0: CGPoint, d1: CGPoint, side: CGFloat) in
            let n0 = normalOf(d0) * side
            let n1 = normalOf(d1) * side
            let to = point + n1 * halfWidth

            let cross = CGPoint.cross(d0, d1)
            let isOuter = (cross * side) < 0

            if !isOuter || (1.0 - CGPoint.dot(d0, d1)) < .ulpOfOne {
                // inner side or nearly co-linear: just connect
                path.addLine(to: to)
                return
            }

            switch style.lineJoin {
            case .bevel:
                path.addLine(to: to)
            case .round:
                let startAngle = atan2(n0.y, n0.x)
                let endAngle   = atan2(n1.y, n1.x)
                var delta = endAngle - startAngle
                while delta > .pi  { delta -= .pi * 2 }
                while delta < -.pi { delta += .pi * 2 }
                path.addRelativeArc(center: point, radius: halfWidth,
                                    startAngle: .radians(startAngle),
                                    delta: .radians(delta))
            case .miter:
                let dot = CGPoint.dot(d0, d1)
                let angle = acos(clamp(dot, min: -1, max: 1))
                let sinHalf = sin(angle * 0.5)
                if sinHalf > .ulpOfOne {
                    let miterLen = halfWidth / sinHalf
                    if miterLen <= style.miterLimit * style.lineWidth {
                        let from = point + n0 * halfWidth
                        let s = CGPoint.cross(d0, d1)
                        if s.magnitude > .ulpOfOne {
                            let t = CGPoint.cross(to - from, d1) / s
                            let miterPt = from + d0 * t
                            path.addLine(to: miterPt)
                        }
                        path.addLine(to: to)
                    } else {
                        path.addLine(to: to) // fallback bevel
                    }
                } else {
                    path.addLine(to: to)
                }
            @unknown default:
                path.addLine(to: to)
            }
        }

        // Cap helper
        let addCap = { (path: inout Path, point: CGPoint,
                        direction: CGPoint, fromLeftToRight: Bool) in
            let n = normalOf(direction)
            let leftPt  = point + n * halfWidth
            let rightPt = point - n * halfWidth

            switch style.lineCap {
            case .butt:
                path.addLine(to: fromLeftToRight ? rightPt : leftPt)
            case .round:
                let startN = fromLeftToRight ? n : -n
                let startAngle = atan2(startN.y, startN.x)
                path.addRelativeArc(center: point, radius: halfWidth,
                                    startAngle: .radians(startAngle),
                                    delta: .radians(-.pi))
            case .square:
                let ext = direction * halfWidth
                if fromLeftToRight {
                    path.addLine(to: leftPt + ext)
                    path.addLine(to: rightPt + ext)
                    path.addLine(to: rightPt)
                } else {
                    path.addLine(to: rightPt - ext)
                    path.addLine(to: leftPt - ext)
                    path.addLine(to: leftPt)
                }
            @unknown default:
                path.addLine(to: fromLeftToRight ? rightPt : leftPt)
            }
        }

        // Generate outlines
        var result = Path()

        for sp in subPaths {
            if sp.segments.isEmpty { continue }

            let first = sp.segments.first!
            let last  = sp.segments.last!

            if sp.isClosed {
                // Closed path: outer (forward) + inner (backward)

                // Outer (offset +halfWidth, forward direction)
                result.move(to: offsetStartPoint(first, halfWidth))
                for (i, seg) in sp.segments.enumerated() {
                    if i > 0 {
                        let prev = sp.segments[i - 1]
                        addJoin(&result, seg.startPoint, prev.endDir, seg.startDir, 1)
                    }
                    addOffsetElements(&result, offsetSegment(seg, halfWidth))
                }
                addJoin(&result, first.startPoint, last.endDir, first.startDir, 1)
                result.closeSubpath()

                // Inner (reversed direction, offset +halfWidth → opposite winding)
                let revStartDir = -last.endDir
                result.move(to: last.endPoint + normalOf(revStartDir) * halfWidth)
                let n = sp.segments.count
                for i in stride(from: n - 1, through: 0, by: -1) {
                    let seg = sp.segments[i]
                    let revSeg: Seg
                    switch seg {
                    case .line(let from, let to):
                        revSeg = .line(from: to, to: from)
                    case .cubic(let c):
                        revSeg = .cubic(c.reversed())
                    }
                    if i < n - 1 {
                        let next = sp.segments[i + 1]
                        addJoin(&result, seg.endPoint, -next.startDir, -seg.endDir, 1)
                    }
                    addOffsetElements(&result, offsetSegment(revSeg, halfWidth))
                }
                addJoin(&result, first.startPoint, -first.startDir, -last.endDir, 1)
                result.closeSubpath()

            } else {
                // Open path: left → end cap → right (reversed) → start cap

                // Left side forward (+halfWidth)
                result.move(to: offsetStartPoint(first, halfWidth))
                for (i, seg) in sp.segments.enumerated() {
                    if i > 0 {
                        let prev = sp.segments[i - 1]
                        addJoin(&result, seg.startPoint, prev.endDir, seg.startDir, 1)
                    }
                    addOffsetElements(&result, offsetSegment(seg, halfWidth))
                }

                // End cap
                addCap(&result, last.endPoint, last.endDir, true)

                // Right side backward (-halfWidth, reversed)
                for i in stride(from: sp.segments.count - 1, through: 0, by: -1) {
                    let seg = sp.segments[i]
                    let revSeg: Seg
                    switch seg {
                    case .line(let from, let to):
                        revSeg = .line(from: to, to: from)
                    case .cubic(let c):
                        revSeg = .cubic(c.reversed())
                    }
                    if i < sp.segments.count - 1 {
                        let next = sp.segments[i + 1]
                        // reversed directions: prev.endDir becomes -next.startDir
                        addJoin(&result, seg.endPoint, -next.startDir, -seg.endDir, 1)
                    }
                    addOffsetElements(&result, offsetSegment(revSeg, halfWidth))
                }

                // Start cap
                addCap(&result, first.startPoint, -first.startDir, true)

                result.closeSubpath()
            }
        }

        return result
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
        return path
    }
}

// Creating a circle with a cubic Bezier curve
// The cubic bezier curve must be a circular sector of 1/4 of a circle. (pi/2)
// https://stackoverflow.com/a/27863181
// (4/3)*tan(pi/8) = 4*(sqrt(2)-1)/3 = 0.552284749830793
private let _r: Double = 0.552284749830793

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

        if let p0 = self.currentPoint {
            self.currentPoint = p1
            self.boundingBox.expand(by: p0, p1)
            self.boundingBoxOfPath.expand(by: p0, p1)
        }
    }

    public mutating func addQuadCurve(to p2: CGPoint, control p1: CGPoint) {
        self.elements.append(.quadCurve(to: p2, control: p1))

        if let p0 = self.currentPoint {
            self.currentPoint = p2
            self.boundingBox.expand(by: p0, p1, p2)
            self.boundingBoxOfPath.expand(by: QuadraticBezier(p0: p0, p1: p1, p2: p2).boundingBox)
        }
    }

    public mutating func addCurve(to p3: CGPoint, control1 p1: CGPoint, control2 p2: CGPoint) {
        self.elements.append(.curve(to: p3, control1: p1, control2: p2))

        if let p0 = self.currentPoint {
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

}

extension Path {
    public init(_ rect: CGRect) {
        self.addRect(rect)
    }

    public init(roundedRect rect: CGRect,
                cornerSize: CGSize,
                style: RoundedCornerStyle = .circular) {
        self.addRoundedRect(in: rect, cornerSize: cornerSize, style: style)
    }

    public init(roundedRect rect: CGRect,
                cornerRadius: CGFloat,
                style: RoundedCornerStyle = .circular) {
        self.addRoundedRect(in: rect, cornerSize: CGSize(width: cornerRadius, height: cornerRadius), style: style)
    }

    public init(ellipseIn rect: CGRect) {
        self.addEllipse(in: rect)
    }

    public init(_ callback: (inout Path) -> ()) {
        callback(&self)
    }

    public mutating func addRect(_ rect: CGRect,
                                 transform: CGAffineTransform = .identity) {
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

    public mutating func addRoundedRect(in rect: CGRect,
                                        cornerSize: CGSize,
                                        style: RoundedCornerStyle = .circular,
                                        transform: CGAffineTransform = .identity) {
        let midX = rect.midX
        let midY = rect.midY
        let minX = rect.minX
        let maxX = rect.maxX
        let minY = rect.minY
        let maxY = rect.maxY
        let cx = clamp(cornerSize.width, min: 0, max: maxX - midX)
        let cy = clamp(cornerSize.height, min: 0, max: maxY - midY)

        if cx > .ulpOfOne && cy > .ulpOfOne {

            let t1 = CGAffineTransform(scaleX: cx, y: cy)
                .concatenating(CGAffineTransform(translationX: maxX - cx, y: maxY - cy))
                .concatenating(transform)
            let t2 = CGAffineTransform(scaleX: -1, y: 1)
                .concatenating(CGAffineTransform(translationX: 1, y: 0))
                .concatenating(CGAffineTransform(scaleX: cx, y: cy))
                .concatenating(CGAffineTransform(translationX: minX, y: maxY - cy))
                .concatenating(transform)
            let t3 = CGAffineTransform(rotationAngle: .pi)
                .concatenating(CGAffineTransform(translationX: 1, y: 1))
                .concatenating(CGAffineTransform(scaleX: cx, y: cy))
                .concatenating(CGAffineTransform(translationX: minX, y: minY))
                .concatenating(transform)
            let t4 = CGAffineTransform(scaleX: 1, y: -1)
                .concatenating(CGAffineTransform(translationX: 0, y: 1))
                .concatenating(CGAffineTransform(scaleX: cx, y: cy))
                .concatenating(CGAffineTransform(translationX: maxX - cx, y: minY))
                .concatenating(transform)

            self.move(to: CGPoint(x: maxX, y: midY).applying(transform))

            if style == .circular {
                let corner = [CGPoint(x: 1, y: 0),
                              CGPoint(x: 1, y: _r),
                              CGPoint(x: _r, y: 1),
                              CGPoint(x: 0, y: 1)]

                let c1 = corner.map { $0.applying(t1) }
                let c2 = corner.reversed().map { $0.applying(t2) }
                let c3 = corner.map { $0.applying(t3) }
                let c4 = corner.reversed().map { $0.applying(t4) }

                self.addLine(to: c1[0])
                self.addCurve(to: c1[3], control1: c1[1], control2: c1[2])
                self.addLine(to: c2[0])
                self.addCurve(to: c2[3], control1: c2[1], control2: c2[2])
                self.addLine(to: c3[0])
                self.addCurve(to: c3[3], control1: c3[1], control2: c3[2])
                self.addLine(to: c4[0])
                self.addCurve(to: c4[3], control1: c4[1], control2: c4[2])
            } else { /* style == .continuous */
                let rx = min((maxX - midX - cx) / (cx * 0.54), 1.0)
                let ry = min((maxY - midY - cy) / (cy * 0.54), 1.0)

                let corner = [CGPoint(x: 1, y: lerp(0, -0.528665, ry)),
                              CGPoint(x: 1, y: lerp(0.04, -0.08849, ry)),
                              CGPoint(x: 1, y: lerp(0.18, 0.131593, ry)),
                              CGPoint(x: 0.925089, y: 0.368506),
                              CGPoint(x: 0.83094, y: 0.627176),
                              CGPoint(x: 0.627176, y: 0.83094),
                              CGPoint(x: 0.368506, y: 0.925089),
                              CGPoint(x: lerp(0.18, 0.131593, rx), y: 1),
                              CGPoint(x: lerp(0.04, -0.08849, rx), y: 1),
                              CGPoint(x: lerp(0, -0.52866, rx) , y: 1)]

                let c1 = corner.map { $0.applying(t1) }
                let c2 = corner.reversed().map { $0.applying(t2) }
                let c3 = corner.map { $0.applying(t3) }
                let c4 = corner.reversed().map { $0.applying(t4) }

                self.addLine(to: c1[0])
                self.addCurve(to: c1[3], control1: c1[1], control2: c1[2])
                self.addCurve(to: c1[6], control1: c1[4], control2: c1[5])
                self.addCurve(to: c1[9], control1: c1[7], control2: c1[8])

                self.addLine(to: c2[0])
                self.addCurve(to: c2[3], control1: c2[1], control2: c2[2])
                self.addCurve(to: c2[6], control1: c2[4], control2: c2[5])
                self.addCurve(to: c2[9], control1: c2[7], control2: c2[8])

                self.addLine(to: c3[0])
                self.addCurve(to: c3[3], control1: c3[1], control2: c3[2])
                self.addCurve(to: c3[6], control1: c3[4], control2: c3[5])
                self.addCurve(to: c3[9], control1: c3[7], control2: c3[8])

                self.addLine(to: c4[0])
                self.addCurve(to: c4[3], control1: c4[1], control2: c4[2])
                self.addCurve(to: c4[6], control1: c4[4], control2: c4[5])
                self.addCurve(to: c4[9], control1: c4[7], control2: c4[8])
            }
        } else {
            self.move(to: CGPoint(x: minX, y: minY).applying(transform))
            self.addLine(to: CGPoint(x: maxX, y: minY).applying(transform))
            self.addLine(to: CGPoint(x: maxX, y: maxY).applying(transform))
            self.addLine(to: CGPoint(x: minX, y: maxY).applying(transform))
        }
        self.closeSubpath()
    }

    public mutating func addEllipse(in rect: CGRect,
                                    transform: CGAffineTransform = .identity) {
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

    public mutating func addRects(_ rects: [CGRect],
                                  transform: CGAffineTransform = .identity) {
        for rect in rects {
            self.addRect(rect, transform: transform)
        }
    }

    public mutating func addLines(_ lines: [CGPoint]) {
        for line in lines {
            self.addLine(to: line)
        }
    }

    public mutating func addRelativeArc(center: CGPoint,
                                        radius: CGFloat,
                                        startAngle: Angle,
                                        delta: Angle,
                                        transform: CGAffineTransform = .identity) {
        var delta = delta.radians
        if delta.magnitude < .ulpOfOne { return }

        var trans = CGAffineTransform(scaleX: radius, y: radius)
        if delta < 0.0 {
            trans = trans.scaledBy(x: 1, y: -1) // flip
            delta = delta.magnitude
        }
        trans = trans.concatenating(CGAffineTransform(rotationAngle: startAngle.radians))
        trans = trans.concatenating(CGAffineTransform(translationX: center.x, y: center.y))
        trans = trans.concatenating(transform)

        let startPoint = CGPoint(x: 1, y: 0).applying(trans)

        if let last = self.elements.last, last != .closeSubpath {
            self.addLine(to: startPoint)
        } else {
            self.move(to: startPoint)
        }

        let oneQuarter = CubicBezier(p0: CGPoint(x: 1, y: 0),
                                     p1: CGPoint(x: 1, y: _r),
                                     p2: CGPoint(x: _r, y: 1),
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
            rotate = rotate.concatenating(CGAffineTransform(rotationAngle: halfPi))
        }
    }

    public mutating func addArc(center: CGPoint,
                                radius: CGFloat,
                                startAngle: Angle,
                                endAngle: Angle,
                                clockwise: Bool,
                                transform: CGAffineTransform = .identity) {
        let pi2: Double = .pi * 2
        var delta = endAngle.radians - startAngle.radians
        if clockwise {
            if delta > 0 { delta -= pi2 }
        } else {
            if delta < 0 { delta += pi2 }
        }
        if delta.magnitude < .ulpOfOne { return }

        addRelativeArc(center: center,
                       radius: radius,
                       startAngle: startAngle,
                       delta: .radians(delta),
                       transform: transform)
    }

    public mutating func addArc(tangent1End p1: CGPoint,
                                tangent2End p2: CGPoint,
                                radius: CGFloat,
                                transform: CGAffineTransform = .identity) {
        if radius < .ulpOfOne { return }

        // Transform p1, p2 into path space to match currentPoint.
        // After this, all geometry is computed in path space — no transform passed to addRelativeArc.
        let p1 = p1.applying(transform)
        let p2 = p2.applying(transform)
        let current = currentPoint ?? .zero

        // Tangent directions at p1
        let tan1 = (current - p1).normalized()
        let tan2 = (p2 - p1).normalized()
        let d = CGPoint.dot(tan1, tan2)

        // Nearly parallel or opposite — no arc to draw
        if (1.0 - d.magnitude) < .ulpOfOne { return }

        let clockwise = CGPoint.cross(tan1, tan2) < 0

        let halfAngle = acos(clamp(d, min: -1, max: 1)) * 0.5
        let distanceToStart = radius / tan(halfAngle)

        // Tangent points on each line
        let arcStart = p1 + tan1 * distanceToStart
        let arcEnd   = p1 + tan2 * distanceToStart

        // Arc center along the angle bisector
        let bisector = (tan1 + tan2).normalized()
        let distanceToCenter = radius / sin(halfAngle)
        let center = p1 + bisector * distanceToCenter

        let startVec = arcStart - center
        let startAngle = atan2(startVec.y, startVec.x)

        let endVec = arcEnd - center
        var delta = atan2(endVec.y, endVec.x) - startAngle
        if clockwise {
            if delta < 0 { delta += .pi * 2 }
        } else {
            if delta > 0 { delta -= .pi * 2 }
        }

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
        return path
    }

    public func offsetBy(dx: CGFloat, dy: CGFloat) -> Path {
        self.applying(CGAffineTransform(translationX: dx, y: dy))
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
                    self.addQuadCurve(to: CGPoint(x: floats[2], y: floats[3]),
                                      control: CGPoint(x: floats[0], y: floats[1]))
                    floats.removeAll(keepingCapacity: true)
                } else {
                    Log.err("Insufficient arguments to command.")
                    return nil
                }
            } else if str == "c" {
                if floats.count == 6 {
                    self.addCurve(to: CGPoint(x: floats[4], y: floats[5]),
                                  control1: CGPoint(x: floats[0], y: floats[1]),
                                  control2: CGPoint(x: floats[2], y: floats[3]))
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
        let format = { (val: CGFloat) in
            if val.truncatingRemainder(dividingBy: 1) == 0.0 {
                return "\(Int(val))"
            }
            return String(format: "%.4f", val)
        }
        var desc: [String] = []
        self.forEach { element in
            switch element {
            case .move(let to):
                desc.append("\(format(to.x)) \(format(to.y)) m")
            case .line(let to):
                desc.append("\(format(to.x)) \(format(to.y)) l")
            case .quadCurve(let to, let c):
                desc.append("\(format(c.x)) \(format(c.y)) \(format(to.x)) \(format(to.y)) q")
            case .curve(let to, let c1, let c2):
                desc.append("\(format(c1.x)) \(format(c1.y)) \(format(c2.x)) \(format(c2.y)) \(format(to.x)) \(format(to.y)) c")
            case .closeSubpath:
                desc.append("h")
            }
        }
        return desc.joined(separator: " ")
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

    public var body: _ShapeView<Self, ForegroundStyle> {
        _ShapeView<Self, ForegroundStyle>(shape: self, style: ForegroundStyle())
    }
}
