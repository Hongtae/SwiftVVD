//
//  File: TextDecorationIntersections.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

enum DecorationCurveIntersections {
    static let epsilon = 1e-10

    static func solveQuadratic(_ a: Double, _ b: Double, _ c: Double) -> [Double] {
        if abs(a) < epsilon { return abs(b) < epsilon ? [] : [-c / b] }
        let discriminant = ((a * -4) * c).addingProduct(b, b)
        guard discriminant >= 0 else { return [] }
        let root = sqrt(discriminant)
        return [(-b - root) / (a + a), (root - b) / (a + a)].sorted()
    }

    private static func interpolate(_ a: Double, _ b: Double, _ t: Double) -> Double {
        if (a <= 0 && b >= 0) || (b <= 0 && a >= 0) { return t * b + (1 - t) * a }
        if t == 1 { return b }
        let value = a + t * (b - a)
        return (t > 1) == (b > a) ? max(b, value) : min(b, value)
    }

    static func evaluate(_ points: [CGPoint], at t: Double) -> CGPoint {
        var points = points
        while points.count > 1 {
            points = zip(points, points.dropFirst()).map {
                CGPoint(x: interpolate($0.x, $1.x, t), y: interpolate($0.y, $1.y, t))
            }
        }
        return points[0]
    }

    static func intercepts(_ points: [CGPoint], at y: Double) -> [(x: Double, slope: Double)] {
        let degree = points.count - 1
        if degree == 1 {
            let p = points[0], q = points[1]
            guard (p.y < y && y < q.y) || (q.y < y && y < p.y) else { return [] }
            return [(p.x + ((y - p.y) * (q.x - p.x)) / (q.y - p.y), q.y - p.y)]
        }
        let ys = points.map { Double($0.y) }
        let roots: [Double]
        if degree == 2 {
            let a = ys[0].addingProduct(ys[1], -2) + ys[2]
            let b = (ys[1] + ys[1]).addingProduct(ys[0], -2)
            roots = solveQuadratic(a, b, ys[0] - y)
        } else {
            precondition(degree == 3)
            let a = (-ys[0]).addingProduct(ys[1], 3).addingProduct(ys[2], -3) + ys[3]
            var b = (ys[1] * -6).addingProduct(ys[0], 3).addingProduct(ys[2], 3)
            var c = (ys[1] * 3).addingProduct(ys[0], -3)
            var d = ys[0] - y
            if abs(a) < epsilon {
                roots = solveQuadratic(b, c, d)
            } else {
                b /= a; c /= a; d /= a
                let q = (c * -3).addingProduct(b, b) / 9
                let r = (-c * (b * 9)).addingProduct(b + b, b * b).addingProduct(d, 27) / 54
                let discriminant = (-q * (q * q)).addingProduct(r, r)
                if discriminant < 0 {
                    let angle = acos(r / pow(q, 1.5)), factor = -2 * sqrt(q)
                    roots = [0, 2 * Double.pi, -2 * Double.pi].map {
                        (b / -3).addingProduct(factor, cos((angle + $0) / 3))
                    }.sorted()
                } else {
                    let root = sqrt(discriminant)
                    roots = [cbrt(root - r) + cbrt(-r - root) + b / -3]
                }
            }
        }
        return roots.filter { 0 <= $0 && $0 <= 1 }.map { t in
            let slope = Double(degree) * (evaluate(Array(points.dropFirst()), at: t).y
                - evaluate(Array(points.dropLast()), at: t).y)
            return (evaluate(points, at: t).x, slope)
        }
    }
}

struct PathObserver {
    struct Intersection {
        enum Kind: UInt32 { case descending, interior, ascending }
        enum Side: UInt32 { case lower, upper }
        var x: Double
        var kind: Kind
        var side: Side
        var connection: UInt32
    }

    var lower: Double
    var upper: Double
    private var first = CGPoint(x: CGFloat.infinity, y: CGFloat.infinity)
    private var current = CGPoint(x: CGFloat.infinity, y: CGFloat.infinity)
    private(set) var connectionCount: UInt32 = 0
    // Connection IDs join excursions below the lower boundary across contour closure.
    private var initial: UInt32 = 0
    private var active: UInt32 = 0
    private(set) var intersections: [Intersection] = []

    init(lower: Double, upper: Double) { self.lower = lower; self.upper = upper }

    mutating func cleanUpAfterUnclosedSubpath() {
        if initial != 0 || active != 0 {
            for i in intersections.indices where intersections[i].connection != 0 {
                if intersections[i].connection == initial || intersections[i].connection == active {
                    intersections[i].connection = 0
                }
            }
            initial = 0; active = 0
        }
        first = CGPoint(x: CGFloat.infinity, y: CGFloat.infinity)
        current = first
    }

    mutating func observe(_ element: Path.Element) {
        let points: [CGPoint]
        var evaluatesCurve = true
        var closes = false
        switch element {
        case let .move(to: point):
            cleanUpAfterUnclosedSubpath()
            first = point; points = [point]; evaluatesCurve = false
            if point.y < lower + DecorationCurveIntersections.epsilon {
                connectionCount += 1; initial = connectionCount; active = connectionCount
            }
        case let .line(to: point): points = [point]
        case let .quadCurve(to: point, control: control): points = [control, point]
        case let .curve(to: point, control1: a, control2: b): points = [a, b, point]
        case .closeSubpath: points = [first]; closes = true
        }
        let end = points.last!
        let curve = [current] + points
        let minimum = curve.map(\.y).min()!, maximum = curve.map(\.y).max()!
        if lower < end.y && end.y < upper {
            intersections.append(.init(x: end.x, kind: .interior, side: .lower, connection: 0))
        }
        if evaluatesCurve {
            for (side, limit): (Intersection.Side, Double) in [(.lower, lower), (.upper, upper)] {
                guard minimum <= limit, limit <= maximum else { continue }
                for (x, slope) in DecorationCurveIntersections.intercepts(curve,
                    at: limit + DecorationCurveIntersections.epsilon) {
                    var connection: UInt32 = 0
                    if side == .lower {
                        if active != 0 { connection = active; active = 0 }
                        else { connectionCount += 1; connection = connectionCount; active = connection }
                    }
                    intersections.append(.init(x: x, kind: slope < 0 ? .descending : .ascending,
                                               side: side, connection: connection))
                }
            }
        }
        if closes {
            first = CGPoint(x: CGFloat.infinity, y: CGFloat.infinity); current = first
            if initial != 0 {
                if initial != active, let i = intersections.lastIndex(where: { $0.connection == active }) {
                    intersections[i].connection = initial
                }
                initial = 0; active = 0
            }
        } else { current = end }
    }

    mutating func sortedIntersections() -> [Intersection] {
        cleanUpAfterUnclosedSubpath()
        intersections.sort {
            if $0.x != $1.x { return $0.x < $1.x }
            if $0.kind != $1.kind { return $0.kind.rawValue < $1.kind.rawValue }
            if $0.side != $1.side { return $0.side.rawValue < $1.side.rawValue }
            return $0.connection < $1.connection
        }
        return intersections
    }
}

enum TextDecorationIntersections {
    static func occupiedIntervals(_ rows: [PathObserver.Intersection]) -> [ClosedRange<Double>] {
        // Each boundary has its own winding; contour connections can bridge their gaps.
        var winding = [0, 0]
        var connections = Set<UInt32>()
        var start = 0.0, end = 0.0
        var hasStart = false, hasEnd = false
        var result: [ClosedRange<Double>] = []
        for row in rows {
            let wasInside = winding.contains { $0 != 0 }
            if row.kind != .interior {
                winding[Int(row.side.rawValue)] += row.kind == .descending ? 1 : -1
            }
            let inside = winding.contains { $0 != 0 }
            if !wasInside && inside {
                if hasStart && hasEnd {
                    if connections.isEmpty { result.append(start...end); start = row.x }
                    hasEnd = false
                } else { start = row.x }
                hasStart = true
            } else if !wasInside && !inside && row.kind == .interior {
                if hasStart && hasEnd {
                    if connections.isEmpty { result.append(start...end); start = row.x }
                } else { start = row.x }
                end = row.x; hasStart = true; hasEnd = true
            } else if wasInside && !inside {
                end = row.x; hasEnd = true
            }
            if row.connection != 0 {
                if !connections.insert(row.connection).inserted { connections.remove(row.connection) }
            }
        }
        if hasStart && hasEnd { result.append(start...end) }
        return result
    }

    static func occupiedIntervals(in path: Path, lower: Double, upper: Double) -> [ClosedRange<Double>] {
        var observer = PathObserver(lower: lower, upper: upper)
        path.forEach { observer.observe($0) }
        return occupiedIntervals(observer.sortedIntersections())
    }
}
