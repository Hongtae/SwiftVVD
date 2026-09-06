//
//  File: Path.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
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

struct FixedRoundedRect: Equatable {
    var rect: CGRect
    var cornerSize: CGSize
    var style: RoundedCornerStyle
}

public struct Path: Equatable {
    public enum Element: Equatable, Sendable {
        case move(to: CGPoint)
        case line(to: CGPoint)
        case quadCurve(to: CGPoint, control: CGPoint)
        case curve(to: CGPoint, control1: CGPoint, control2: CGPoint)
        case closeSubpath
    }

    struct PathData: Equatable {
        var elements: [Element] = []
        var boundingBox: CGRect = .null
        var boundingBoxOfPath: CGRect = .null
        var initialPoint: CGPoint?
        var currentPoint: CGPoint?

        mutating func reserveCapacity(_ minimumCapacity: Int) {
            elements.reserveCapacity(minimumCapacity)
        }

        private static func pointBounds(
            _ first: CGPoint,
            _ second: CGPoint
        ) -> (minimum: CGPoint, maximum: CGPoint) {
            (.minimum(first, second), .maximum(first, second))
        }

        private static func pointBounds(
            _ first: CGPoint,
            _ second: CGPoint,
            _ third: CGPoint
        ) -> (minimum: CGPoint, maximum: CGPoint) {
            (
                .minimum(.minimum(first, second), third),
                .maximum(.maximum(first, second), third)
            )
        }

        private static func pointBounds(
            _ first: CGPoint,
            _ second: CGPoint,
            _ third: CGPoint,
            _ fourth: CGPoint
        ) -> (minimum: CGPoint, maximum: CGPoint) {
            (
                .minimum(.minimum(first, second), .minimum(third, fourth)),
                .maximum(.maximum(first, second), .maximum(third, fourth))
            )
        }

        private static func expand(
            _ rect: inout CGRect,
            minimum: CGPoint,
            maximum: CGPoint
        ) {
            guard !rect.isInfinite else { return }
            if rect.isNull {
                rect = CGRect(
                    origin: minimum,
                    size: CGSize(maximum - minimum)
                )
            } else {
                let minX = min(minimum.x, rect.minX)
                let minY = min(minimum.y, rect.minY)
                let maxX = max(maximum.x, rect.maxX)
                let maxY = max(maximum.y, rect.maxY)
                rect = CGRect(
                    x: minX,
                    y: minY,
                    width: maxX - minX,
                    height: maxY - minY
                )
            }
        }

        mutating func move(to point: CGPoint) {
            elements.append(.move(to: point))
            initialPoint = point
            currentPoint = point
            Self.expand(&boundingBox, minimum: point, maximum: point)
            Self.expand(&boundingBoxOfPath, minimum: point, maximum: point)
        }

        mutating func addLine(to point: CGPoint) {
            elements.append(.line(to: point))

            if let currentPoint {
                self.currentPoint = point
                let bounds = Self.pointBounds(currentPoint, point)
                Self.expand(
                    &boundingBox,
                    minimum: bounds.minimum,
                    maximum: bounds.maximum
                )
                Self.expand(
                    &boundingBoxOfPath,
                    minimum: bounds.minimum,
                    maximum: bounds.maximum
                )
            }
        }

        mutating func addQuadCurve(to point: CGPoint, control: CGPoint) {
            elements.append(.quadCurve(to: point, control: control))

            if let currentPoint {
                self.currentPoint = point
                let bounds = Self.pointBounds(currentPoint, control, point)
                Self.expand(
                    &boundingBox,
                    minimum: bounds.minimum,
                    maximum: bounds.maximum
                )
                boundingBoxOfPath = boundingBoxOfPath.union(
                    QuadraticBezier(
                        p0: currentPoint,
                        p1: control,
                        p2: point
                    ).boundingBox
                )
            }
        }

        mutating func addCurve(
            to point: CGPoint,
            control1: CGPoint,
            control2: CGPoint
        ) {
            elements.append(
                .curve(
                    to: point,
                    control1: control1,
                    control2: control2
                )
            )

            if let currentPoint {
                self.currentPoint = point
                let bounds = Self.pointBounds(
                    currentPoint,
                    control1,
                    control2,
                    point
                )
                Self.expand(
                    &boundingBox,
                    minimum: bounds.minimum,
                    maximum: bounds.maximum
                )
                boundingBoxOfPath = boundingBoxOfPath.union(
                    CubicBezier(
                        p0: currentPoint,
                        p1: control1,
                        p2: control2,
                        p3: point
                    ).boundingBox
                )
            }
        }

        mutating func closeSubpath() {
            if let last = elements.last, last != .closeSubpath {
                elements.append(.closeSubpath)
            }
            currentPoint = initialPoint
        }

        mutating func addRect(
            _ rect: CGRect,
            transform: CGAffineTransform
        ) {
            elements.reserveCapacity(elements.count + 5)
            appendRect(rect, transform: transform)
        }

        mutating func appendRect(
            _ rect: CGRect,
            transform: CGAffineTransform
        ) {
            let p0 = CGPoint(x: rect.minX, y: rect.minY)
                .applying(transform)
            let p1 = CGPoint(x: rect.maxX, y: rect.minY)
                .applying(transform)
            let p2 = CGPoint(x: rect.maxX, y: rect.maxY)
                .applying(transform)
            let p3 = CGPoint(x: rect.minX, y: rect.maxY)
                .applying(transform)

            elements.append(.move(to: p0))
            elements.append(.line(to: p1))
            elements.append(.line(to: p2))
            elements.append(.line(to: p3))
            elements.append(.closeSubpath)

            let bounds = Self.pointBounds(p0, p1, p2, p3)
            Self.expand(
                &boundingBox,
                minimum: bounds.minimum,
                maximum: bounds.maximum
            )
            Self.expand(
                &boundingBoxOfPath,
                minimum: bounds.minimum,
                maximum: bounds.maximum
            )
            initialPoint = p0
            currentPoint = p0
        }

        mutating func addEllipse(
            in rect: CGRect,
            transform: CGAffineTransform
        ) {
            let midX = rect.midX
            let midY = rect.midY
            let minX = rect.minX
            let maxX = rect.maxX
            let minY = rect.minY
            let maxY = rect.maxY
            elements.reserveCapacity(elements.count + 6)

            let p0 = CGPoint(x: maxX, y: midY).applying(transform)
            let p1 = CGPoint(
                x: maxX,
                y: lerp(midY, maxY, _r)
            ).applying(transform)
            let p2 = CGPoint(
                x: lerp(midX, maxX, _r),
                y: maxY
            ).applying(transform)
            let p3 = CGPoint(x: midX, y: maxY).applying(transform)
            let p4 = CGPoint(
                x: lerp(midX, minX, _r),
                y: maxY
            ).applying(transform)
            let p5 = CGPoint(
                x: minX,
                y: lerp(midY, maxY, _r)
            ).applying(transform)
            let p6 = CGPoint(x: minX, y: midY).applying(transform)
            let p7 = CGPoint(
                x: minX,
                y: lerp(midY, minY, _r)
            ).applying(transform)
            let p8 = CGPoint(
                x: lerp(midX, minX, _r),
                y: minY
            ).applying(transform)
            let p9 = CGPoint(x: midX, y: minY).applying(transform)
            let p10 = CGPoint(
                x: lerp(midX, maxX, _r),
                y: minY
            ).applying(transform)
            let p11 = CGPoint(
                x: maxX,
                y: lerp(midY, minY, _r)
            ).applying(transform)

            if Path.preservesAxisAlignment(transform) {
                elements.append(.move(to: p0))
                elements.append(
                    .curve(to: p3, control1: p1, control2: p2)
                )
                elements.append(
                    .curve(to: p6, control1: p4, control2: p5)
                )
                elements.append(
                    .curve(to: p9, control1: p7, control2: p8)
                )
                elements.append(
                    .curve(to: p0, control1: p10, control2: p11)
                )
                elements.append(.closeSubpath)

                let bounds = rect.applying(transform).standardized
                boundingBox = boundingBox.union(bounds)
                boundingBoxOfPath = boundingBoxOfPath.union(bounds)
                initialPoint = p0
                currentPoint = p0
                return
            }

            move(to: p0)
            addCurve(to: p3, control1: p1, control2: p2)
            addCurve(to: p6, control1: p4, control2: p5)
            addCurve(to: p9, control1: p7, control2: p8)
            addCurve(to: p0, control1: p10, control2: p11)
            closeSubpath()
        }

        mutating func addRelativeArc(
            center: CGPoint,
            radius: CGFloat,
            startAngle: Angle,
            delta: Angle,
            transform: CGAffineTransform
        ) {
            var delta = delta.radians
            if delta.magnitude < .ulpOfOne { return }

            var arcTransform = CGAffineTransform(
                scaleX: radius,
                y: radius
            )
            if delta < 0 {
                arcTransform = arcTransform.scaledBy(x: 1, y: -1)
                delta = delta.magnitude
            }
            arcTransform = arcTransform.concatenating(
                CGAffineTransform(rotationAngle: startAngle.radians)
            )
            arcTransform = arcTransform.concatenating(
                CGAffineTransform(
                    translationX: center.x,
                    y: center.y
                )
            )
            arcTransform = arcTransform.concatenating(transform)

            let startPoint = CGPoint(x: 1, y: 0)
                .applying(arcTransform)
            let oneQuarter = CubicBezier(
                p0: CGPoint(x: 1, y: 0),
                p1: CGPoint(x: 1, y: _r),
                p2: CGPoint(x: _r, y: 1),
                p3: CGPoint(x: 0, y: 1)
            )

            let halfPi: Double = .pi * 0.5
            if let last = elements.last, last != .closeSubpath {
                addLine(to: startPoint)
            } else {
                move(to: startPoint)
            }

            var rotation = CGAffineTransform.identity
            while delta > 0 {
                let curveTransform = rotation.concatenating(arcTransform)
                if delta >= halfPi {
                    addCurve(
                        to: oneQuarter.p3.applying(curveTransform),
                        control1: oneQuarter.p1.applying(curveTransform),
                        control2: oneQuarter.p2.applying(curveTransform)
                    )
                } else {
                    let curve = oneQuarter.split(delta / halfPi).0
                    addCurve(
                        to: curve.p3.applying(curveTransform),
                        control1: curve.p1.applying(curveTransform),
                        control2: curve.p2.applying(curveTransform)
                    )
                    break
                }
                delta -= halfPi
                rotation = rotation.concatenating(
                    CGAffineTransform(rotationAngle: halfPi)
                )
            }
        }

        mutating func appendCircularCorner(
            transform: CGAffineTransform,
            reversed: Bool,
            tracksBounds: Bool = true
        ) {
            let p0 = CGPoint(x: 1, y: 0).applying(transform)
            let p1 = CGPoint(x: 1, y: _r).applying(transform)
            let p2 = CGPoint(x: _r, y: 1).applying(transform)
            let p3 = CGPoint(x: 0, y: 1).applying(transform)
            if reversed {
                if tracksBounds {
                    addLine(to: p3)
                    addCurve(
                        to: p0,
                        control1: p2,
                        control2: p1
                    )
                } else {
                    elements.append(.line(to: p3))
                    elements.append(
                        .curve(to: p0, control1: p2, control2: p1)
                    )
                }
            } else {
                if tracksBounds {
                    addLine(to: p0)
                    addCurve(
                        to: p3,
                        control1: p1,
                        control2: p2
                    )
                } else {
                    elements.append(.line(to: p0))
                    elements.append(
                        .curve(to: p3, control1: p1, control2: p2)
                    )
                }
            }
        }

        mutating func appendContinuousCorner(
            transform: CGAffineTransform,
            radiusFactors: CGPoint,
            reversed: Bool
        ) {
            let rx = radiusFactors.x
            let ry = radiusFactors.y
            let p0 = CGPoint(x: 1, y: lerp(0, -0.528665, ry))
            let p1 = CGPoint(x: 1, y: lerp(0.04, -0.08849, ry))
            let p2 = CGPoint(x: 1, y: lerp(0.18, 0.131593, ry))
            let p3 = CGPoint(x: 0.925089, y: 0.368506)
            let p4 = CGPoint(x: 0.83094, y: 0.627176)
            let p5 = CGPoint(x: 0.627176, y: 0.83094)
            let p6 = CGPoint(x: 0.368506, y: 0.925089)
            let p7 = CGPoint(x: lerp(0.18, 0.131593, rx), y: 1)
            let p8 = CGPoint(x: lerp(0.04, -0.08849, rx), y: 1)
            let p9 = CGPoint(x: lerp(0, -0.52866, rx), y: 1)

            if reversed {
                addLine(to: p9.applying(transform))
                addCurve(
                    to: p6.applying(transform),
                    control1: p8.applying(transform),
                    control2: p7.applying(transform)
                )
                addCurve(
                    to: p3.applying(transform),
                    control1: p5.applying(transform),
                    control2: p4.applying(transform)
                )
                addCurve(
                    to: p0.applying(transform),
                    control1: p2.applying(transform),
                    control2: p1.applying(transform)
                )
            } else {
                addLine(to: p0.applying(transform))
                addCurve(
                    to: p3.applying(transform),
                    control1: p1.applying(transform),
                    control2: p2.applying(transform)
                )
                addCurve(
                    to: p6.applying(transform),
                    control1: p4.applying(transform),
                    control2: p5.applying(transform)
                )
                addCurve(
                    to: p9.applying(transform),
                    control1: p7.applying(transform),
                    control2: p8.applying(transform)
                )
            }
        }

        mutating func append(
            contentsOf source: PathData,
            transform: CGAffineTransform
        ) {
            guard let first = source.elements.first else { return }
            elements.reserveCapacity(elements.count + source.elements.count)

            if case .move = first,
               Path.preservesAxisAlignment(transform) {
                appendWellFormed(
                    contentsOf: source,
                    transform: transform
                )
                return
            }

            source.elements.withUnsafeBufferPointer { sourceElements in
                var index = 0
                if transform.isIdentity {
                    while index < sourceElements.count {
                        append(sourceElements[index])
                        index += 1
                    }
                } else {
                    while index < sourceElements.count {
                        append(
                            sourceElements[index],
                            transform: transform
                        )
                        index += 1
                    }
                }
            }
        }

        private mutating func appendWellFormed(
            contentsOf source: PathData,
            transform: CGAffineTransform
        ) {
            if transform.isIdentity {
                elements.append(contentsOf: source.elements)
            } else {
                source.elements.withUnsafeBufferPointer { sourceElements in
                    var index = 0
                    while index < sourceElements.count {
                        switch sourceElements[index] {
                        case .move(let point):
                            elements.append(
                                .move(to: point.applying(transform))
                            )
                        case .line(let point):
                            elements.append(
                                .line(to: point.applying(transform))
                            )
                        case .quadCurve(let point, let control):
                            elements.append(
                                .quadCurve(
                                    to: point.applying(transform),
                                    control: control.applying(transform)
                                )
                            )
                        case .curve(let point, let control1, let control2):
                            elements.append(
                                .curve(
                                    to: point.applying(transform),
                                    control1: control1.applying(transform),
                                    control2: control2.applying(transform)
                                )
                            )
                        case .closeSubpath:
                            elements.append(.closeSubpath)
                        }
                        index += 1
                    }
                }
            }

            if !source.boundingBox.isNull {
                boundingBox = boundingBox.union(
                    source.boundingBox.applying(transform).standardized
                )
            }
            if !source.boundingBoxOfPath.isNull {
                boundingBoxOfPath = boundingBoxOfPath.union(
                    source.boundingBoxOfPath
                        .applying(transform)
                        .standardized
                )
            }
            initialPoint = source.initialPoint?.applying(transform)
            currentPoint = source.currentPoint?.applying(transform)
        }

        private mutating func append(_ element: Element) {
            switch element {
            case .move(let point):
                move(to: point)
            case .line(let point):
                addLine(to: point)
            case .quadCurve(let point, let control):
                addQuadCurve(to: point, control: control)
            case .curve(let point, let control1, let control2):
                addCurve(
                    to: point,
                    control1: control1,
                    control2: control2
                )
            case .closeSubpath:
                closeSubpath()
            }
        }

        private mutating func append(
            _ element: Element,
            transform: CGAffineTransform
        ) {
            switch element {
            case .move(let point):
                move(to: point.applying(transform))
            case .line(let point):
                addLine(to: point.applying(transform))
            case .quadCurve(let point, let control):
                addQuadCurve(
                    to: point.applying(transform),
                    control: control.applying(transform)
                )
            case .curve(let point, let control1, let control2):
                addCurve(
                    to: point.applying(transform),
                    control1: control1.applying(transform),
                    control2: control2.applying(transform)
                )
            case .closeSubpath:
                closeSubpath()
            }
        }
    }

    final class PathBox: Equatable {
        enum Kind: Equatable {
            case buffer
        }

        var kind: Kind
        var data: PathData

        init(kind: Kind = .buffer, data: PathData = PathData()) {
            self.kind = kind
            self.data = data
        }

        static func == (lhs: PathBox, rhs: PathBox) -> Bool {
            lhs === rhs || (lhs.kind == rhs.kind && lhs.data == rhs.data)
        }
    }

    enum Storage: Equatable {
        case empty
        case rect(CGRect)
        case ellipse(CGRect)
        indirect case roundedRect(FixedRoundedRect)
        case path(PathBox)
    }

    var storage: Storage

    public init() {
        storage = .empty
    }

    private init(storage: Storage) {
        self.storage = storage
    }

    public var isEmpty: Bool {
        switch storage {
        case .empty:
            return true
        case .path(let box):
            return box.data.elements.isEmpty
        case .rect, .ellipse, .roundedRect:
            return false
        }
    }

    private static func rectContains(_ rect: CGRect, point: CGPoint) -> Bool {
        rect.contains(point)
    }

    private static func ellipseContains(_ rect: CGRect, point: CGPoint) -> Bool {
        guard !rect.isNull else { return false }
        let radiusX = rect.size.width * 0.5
        let radiusY = rect.size.height * 0.5
        guard radiusX > 0, radiusY > 0 else { return false }
        let x = (point.x - rect.midX) / radiusX
        let y = (point.y - rect.midY) / radiusY
        return x * x + y * y < 1.0
    }

    @inline(__always)
    private static func controlBounds(
        _ p0: CGPoint,
        _ p1: CGPoint,
        _ p2: CGPoint
    ) -> CGRect {
        let minX = min(min(p0.x, p1.x), p2.x)
        let minY = min(min(p0.y, p1.y), p2.y)
        let maxX = max(max(p0.x, p1.x), p2.x)
        let maxY = max(max(p0.y, p1.y), p2.y)
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    @inline(__always)
    private static func controlBounds(
        _ p0: CGPoint,
        _ p1: CGPoint,
        _ p2: CGPoint,
        _ p3: CGPoint
    ) -> CGRect {
        let minX = min(min(min(p0.x, p1.x), p2.x), p3.x)
        let minY = min(min(min(p0.y, p1.y), p2.y), p3.y)
        let maxX = max(max(max(p0.x, p1.x), p2.x), p3.x)
        let maxY = max(max(max(p0.y, p1.y), p2.y), p3.y)
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    @inline(__always)
    private static func accumulateLineWinding(
        from p0: CGPoint,
        to p1: CGPoint,
        at point: CGPoint,
        into winding: inout Int
    ) {
        if min(p0.y, p1.y) <= point.y
            && max(p0.y, p1.y) > point.y
            && min(p0.x, p1.x) < point.x {
            let dy = p1.y - p0.y
            let dx = p1.x - p0.x
            if max(p0.x, p1.x) <= point.x || abs(dx) < .ulpOfOne {
                if p0.x <= point.x {
                    if dy > 0 {
                        winding -= 1
                    } else {
                        winding += 1
                    }
                }
            } else {
                let a = dx / dy
                let x = (point.y - p1.y) * a + p1.x
                if x <= point.x {
                    if a < 0 {
                        winding -= 1
                    } else {
                        winding += 1
                    }
                }
            }
        }
    }

    @inline(__always)
    private static func accumulateQuadraticWinding(
        from p0: CGPoint,
        control p1: CGPoint,
        to p2: CGPoint,
        at point: CGPoint,
        into winding: inout Int
    ) {
        let bbox = controlBounds(p0, p1, p2)
        if bbox.minX <= point.x && bbox.minY <= point.y && bbox.maxY > point.y {
            let curve = QuadraticBezier(p0: p0, p1: p1, p2: p2)
            let intersections = curve.intersectLineSegment(
                CGPoint(x: bbox.minX, y: point.y),
                point
            )
            var index = 0
            while index < intersections.count {
                let t = intersections[index]
                if t < 1 && curve.interpolate(t).x <= point.x {
                    let tangent = curve.tangent(t).y
                    if tangent > 0 {
                        winding -= 1
                    } else if tangent < 0 {
                        winding += 1
                    }
                }
                index += 1
            }
        }
    }

    @inline(__always)
    private static func accumulateCubicWinding(
        from p0: CGPoint,
        control1 p1: CGPoint,
        control2 p2: CGPoint,
        to p3: CGPoint,
        at point: CGPoint,
        into winding: inout Int
    ) {
        let bbox = controlBounds(p0, p1, p2, p3)
        if bbox.minX <= point.x && bbox.minY <= point.y && bbox.maxY > point.y {
            let curve = CubicBezier(p0: p0, p1: p1, p2: p2, p3: p3)
            let intersections = curve.intersectLineSegment(
                CGPoint(x: bbox.minX, y: point.y),
                point
            )
            var index = 0
            while index < intersections.count {
                let t = intersections[index]
                if t < 1 && curve.interpolate(t).x <= point.x {
                    let tangent = curve.tangent(t).y
                    if tangent > 0 {
                        winding -= 1
                    } else if tangent < 0 {
                        winding += 1
                    }
                }
                index += 1
            }
        }
    }

    public func contains(_ p: CGPoint, eoFill: Bool = false) -> Bool {
        switch storage {
        case .empty:
            return false
        case .rect(let rect):
            return Self.rectContains(rect, point: p)
        case .ellipse(let rect):
            return Self.ellipseContains(rect, point: p)
        case .roundedRect, .path:
            break
        }

        return contains(p, eoFill: eoFill, data: materializedData())
    }

    private func contains(
        _ p: CGPoint,
        eoFill: Bool,
        data: PathData
    ) -> Bool {
        let bounds = data.boundingBoxOfPath
        guard !bounds.isNull,
              p.x >= bounds.minX, p.x <= bounds.maxX,
              p.y >= bounds.minY, p.y <= bounds.maxY else {
            return false
        }

        var winding: Int = 0

        var startPoint: CGPoint? = nil
        var currentPoint: CGPoint? = nil
        data.elements.withUnsafeBufferPointer { elements in
            var index = 0
            while index < elements.count {
                switch elements[index] {
                case .move(let to):
                    startPoint = to
                    currentPoint = to
                case .line(let p1):
                    if let p0 = currentPoint {
                        Self.accumulateLineWinding(
                            from: p0,
                            to: p1,
                            at: p,
                            into: &winding
                        )
                        currentPoint = p1
                    }
                case .quadCurve(let p2, let p1):
                    if let p0 = currentPoint {
                        Self.accumulateQuadraticWinding(
                            from: p0,
                            control: p1,
                            to: p2,
                            at: p,
                            into: &winding
                        )
                        currentPoint = p2
                    }
                case .curve(let p3, let p1, let p2):
                    if let p0 = currentPoint {
                        Self.accumulateCubicWinding(
                            from: p0,
                            control1: p1,
                            control2: p2,
                            to: p3,
                            at: p,
                            into: &winding
                        )
                        currentPoint = p3
                    }
                case .closeSubpath:
                    if let p0 = currentPoint, let p1 = startPoint {
                        Self.accumulateLineWinding(
                            from: p0,
                            to: p1,
                            at: p,
                            into: &winding
                        )
                    }
                    currentPoint = startPoint
                }
                index += 1
            }
        }

        if eoFill { return winding % 2 != 0 }
        return winding != 0 // non zero fill
    }

    func contains(
        points: UnsafeBufferPointer<CGPoint>,
        eoFill: Bool,
        origin: CGPoint
    ) -> BitVector64 {
        let pointCount = min(points.count, 64)
        guard pointCount > 0 else { return BitVector64() }

        switch storage {
        case .empty:
            return BitVector64()
        case .rect(let rect):
            var result = BitVector64()
            for index in 0..<pointCount {
                let point = CGPoint(
                    x: points[index].x - origin.x,
                    y: points[index].y - origin.y
                )
                result[index] = Self.rectContains(rect, point: point)
            }
            return result
        case .ellipse(let rect):
            var result = BitVector64()
            for index in 0..<pointCount {
                let point = CGPoint(
                    x: points[index].x - origin.x,
                    y: points[index].y - origin.y
                )
                result[index] = Self.ellipseContains(rect, point: point)
            }
            return result
        case .roundedRect, .path:
            guard pointCloudIntersectsPathBounds(
                points: points,
                count: pointCount,
                origin: origin
            ) else {
                return BitVector64()
            }
        }

        let data = materializedData()
        var result = BitVector64()
        for index in 0..<pointCount {
            let point = points[index]
            result[index] = contains(
                CGPoint(
                    x: point.x - origin.x,
                    y: point.y - origin.y
                ),
                eoFill: eoFill,
                data: data
            )
        }
        return result
    }

    private func pointCloudIntersectsPathBounds(
        points: UnsafeBufferPointer<CGPoint>,
        count: Int,
        origin: CGPoint
    ) -> Bool {
        let bounds = boundingRect
        guard !bounds.isNull else { return false }

        var minimumX = Float.infinity
        var minimumY = Float.infinity
        var maximumX = -Float.infinity
        var maximumY = -Float.infinity
        for index in 0..<count {
            let x = Float(points[index].x - origin.x)
            let y = Float(points[index].y - origin.y)
            minimumX = min(minimumX, x)
            minimumY = min(minimumY, y)
            maximumX = max(maximumX, x)
            maximumY = max(maximumY, y)
        }

        let standardizedBounds = bounds.standardized
        let boundsMinimumX = Float(standardizedBounds.minX)
        let boundsMinimumY = Float(standardizedBounds.minY)
        let boundsMaximumX = Float(standardizedBounds.maxX)
        let boundsMaximumY = Float(standardizedBounds.maxY)

        if minimumX == maximumX && minimumY == maximumY {
            return minimumX >= boundsMinimumX && minimumX <= boundsMaximumX
                && minimumY >= boundsMinimumY && minimumY <= boundsMaximumY
        }

        guard minimumX < maximumX, minimumY < maximumY else {
            return false
        }
        return minimumX < boundsMaximumX && maximumX > boundsMinimumX
            && minimumY < boundsMaximumY && maximumY > boundsMinimumY
    }

    // Smallest rectangle enclosing all points, including curve controls.
    private var boundingBox: CGRect {
        materializedData().boundingBox
    }

    // Smallest rectangle enclosing the path geometry, excluding controls.
    var boundingBoxOfPath: CGRect {
        materializedData().boundingBoxOfPath
    }

    public var boundingRect: CGRect {
        switch storage {
        case .empty:
            return .null
        case .rect(let rect), .ellipse(let rect):
            return rect
        case .roundedRect(let roundedRect):
            return roundedRect.rect
        case .path(let box):
            return box.data.boundingBoxOfPath
        }
    }

    public var initialPoint: CGPoint? {
        materializedData().initialPoint
    }

    public var currentPoint: CGPoint? {
        switch storage {
        case .empty:
            return nil
        case .rect(let rect):
            return rect.origin
        case .ellipse(let rect):
            let rect = rect.standardized
            return CGPoint(x: rect.maxX, y: rect.midY)
        case .roundedRect(let roundedRect):
            guard roundedRect.cornerSize.width > 0,
                  roundedRect.cornerSize.height > 0 else {
                return roundedRect.rect.origin
            }
            let rect = roundedRect.rect.standardized
            return CGPoint(x: rect.maxX, y: rect.midY)
        case .path(let box):
            return box.data.currentPoint
        }
    }

    private func materializedData() -> PathData {
        switch storage {
        case .empty:
            return PathData()
        case .path(let box):
            return box.data
        case .rect(let rect):
            var path = Path(storage: .path(PathBox()))
            path.addRect(rect)
            guard case .path(let box) = path.storage else {
                preconditionFailure("rect materialization must use path storage")
            }
            var data = box.data
            data.boundingBox = rect
            data.boundingBoxOfPath = rect
            return data
        case .ellipse(let rect):
            var path = Path(storage: .path(PathBox()))
            path.addEllipse(in: rect)
            guard case .path(let box) = path.storage else {
                preconditionFailure("ellipse materialization must use path storage")
            }
            var data = box.data
            data.boundingBox = rect
            data.boundingBoxOfPath = rect
            return data
        case .roundedRect(let roundedRect):
            var path = Path(storage: .path(PathBox()))
            path.addRoundedRect(
                in: roundedRect.rect,
                cornerSize: roundedRect.cornerSize,
                style: roundedRect.style
            )
            guard case .path(let box) = path.storage else {
                preconditionFailure("rounded-rect materialization must use path storage")
            }
            var data = box.data
            data.boundingBox = roundedRect.rect
            data.boundingBoxOfPath = roundedRect.rect
            return data
        }
    }

    @discardableResult
    private mutating func ensureUniquePathBox() -> PathBox {
        if case .path(var box) = storage {
            storage = .empty
            if !isKnownUniquelyReferenced(&box) {
                box = PathBox(kind: box.kind, data: box.data)
            }
            storage = .path(box)
            return box
        }

        let box = PathBox(data: materializedData())
        storage = .path(box)
        return box
    }

    @discardableResult
    private mutating func withMutableBuffer<Result>(
        _ body: (inout PathData) throws -> Result
    ) rethrows -> Result {
        let box = ensureUniquePathBox()
        return try body(&box.data)
    }

    private func append(
        to data: inout PathData,
        transform: CGAffineTransform
    ) {
        data.append(contentsOf: materializedData(), transform: transform)
    }

    public func forEach(_ body: (Path.Element) -> Void) {
        let elements: [Element]
        if case .path(let box) = storage {
            elements = box.data.elements
        } else {
            elements = materializedData().elements
        }
        elements.withUnsafeBufferPointer { elements in
            var index = 0
            while index < elements.count {
                body(elements[index])
                index += 1
            }
        }
    }

    public func strokedPath(_ style: StrokeStyle) -> Path {
        let halfWidth = style.lineWidth * 0.5
        if isEmpty { return Path() }

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
        let addOffsetSegment = { (path: inout PathData, seg: Seg, distance: CGFloat) in
            switch seg {
            case .line(let from, let to):
                let dir = (to - from).normalized()
                let n = normalOf(dir)
                path.addLine(to: to + n * distance)
            case .cubic(let c):
                c.forEachOffsetCurve(by: distance) { curve in
                    path.addCurve(
                        to: curve.p3,
                        control1: curve.p1,
                        control2: curve.p2
                    )
                }
            }
        }

        let offsetStartPoint = { (seg: Seg, distance: CGFloat) -> CGPoint in
            let n = normalOf(seg.startDir)
            return seg.startPoint + n * distance
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
        let addJoin = { (path: inout PathData, point: CGPoint,
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
                path.addRelativeArc(
                    center: point,
                    radius: halfWidth,
                    startAngle: .radians(startAngle),
                    delta: .radians(delta),
                    transform: .identity
                )
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
        let addCap = { (path: inout PathData, point: CGPoint,
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
                path.addRelativeArc(
                    center: point,
                    radius: halfWidth,
                    startAngle: .radians(startAngle),
                    delta: .radians(-.pi),
                    transform: .identity
                )
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
        var result = PathData()

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
                    addOffsetSegment(&result, seg, halfWidth)
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
                    addOffsetSegment(&result, revSeg, halfWidth)
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
                    addOffsetSegment(&result, seg, halfWidth)
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
                    addOffsetSegment(&result, revSeg, halfWidth)
                }

                // Start cap
                addCap(&result, first.startPoint, -first.startDir, true)

                result.closeSubpath()
            }
        }

        guard !result.elements.isEmpty else { return Path() }
        return Path(storage: .path(PathBox(data: result)))
    }

    @inline(__always)
    private static func trimmedElementFractions(
        distance: Double,
        progress: Double,
        start: Double,
        end: Double
    ) -> (start: Double, end: Double) {
        let startFraction = start <= progress
            ? 0
            : (start - progress) / distance
        let endFraction = end >= progress + distance
            ? 1
            : (end - progress) / distance
        return (startFraction, endFraction)
    }

    public func trimmedPath(from: CGFloat, to: CGFloat) -> Path {
        let from = clamp(from, min: 0, max: 1)
        let to = clamp(to, min: 0, max: 1)

        if from == 0, to == 1 {
            return self
        }

        let quadraticBezierSubdivision = 2
        let cubicBezierSubdivision = 3

        var path = PathData()
        let sourceElements = materializedData().elements
        if to > from {
            path.reserveCapacity(sourceElements.count + 1)

            // calculate total length
            var length: Double = 0
            var sourceLengths = [Double](
                repeating: 0,
                count: sourceElements.count
            )

            var startPoint: CGPoint? = nil
            var currentPoint: CGPoint? = nil
            sourceLengths.withUnsafeMutableBufferPointer { lengths in
                sourceElements.withUnsafeBufferPointer { elements in
                    var index = 0
                    while index < elements.count {
                        let sourceLength: Double
                        switch elements[index] {
                        case .move(let to):
                            startPoint = to
                            currentPoint = to
                            sourceLength = 0
                        case .line(let p1):
                            if let p0 = currentPoint {
                                sourceLength = (p1 - p0).magnitude
                                length += sourceLength
                                currentPoint = p1
                            } else {
                                sourceLength = 0
                            }
                        case .quadCurve(let p2, let p1):
                            if let p0 = currentPoint {
                                let curve = QuadraticBezier(
                                    p0: p0,
                                    p1: p1,
                                    p2: p2
                                )
                                sourceLength = curve.approximateLength(
                                    subdivide: quadraticBezierSubdivision
                                )
                                length += sourceLength
                                currentPoint = p2
                            } else {
                                sourceLength = 0
                            }
                        case .curve(let p3, let p1, let p2):
                            if let p0 = currentPoint {
                                let curve = CubicBezier(
                                    p0: p0,
                                    p1: p1,
                                    p2: p2,
                                    p3: p3
                                )
                                sourceLength = curve.approximateLength(
                                    subdivide: cubicBezierSubdivision
                                )
                                length += sourceLength
                                currentPoint = p3
                            } else {
                                sourceLength = 0
                            }
                        case .closeSubpath:
                            currentPoint = startPoint
                            sourceLength = 0
                        }
                        lengths[index] = sourceLength
                        index += 1
                    }
                }
            }

            let start = length * from
            let end = length * to

            startPoint = nil
            currentPoint = nil
            var progress: Double = 0

            sourceLengths.withUnsafeBufferPointer { lengths in
                sourceElements.withUnsafeBufferPointer { elements in
                    var index = 0
                    elementLoop: while index < elements.count {
                        let element = elements[index]
                        let sourceLength = lengths[index]
                        index += 1
                        switch element {
                        case .move(let to):
                            startPoint = to
                            currentPoint = to
                            if progress >= start {
                                path.move(to: to)
                            }
                        case .line(let p1):
                            if let p0 = currentPoint {
                                if end <= progress { break elementLoop }
                                currentPoint = p1
                                if start >= progress + sourceLength {
                                    progress += sourceLength
                                    continue
                                }

                                let (t0, t1) = Self.trimmedElementFractions(
                                    distance: sourceLength,
                                    progress: progress,
                                    start: start,
                                    end: end
                                )
                                if t0 > 0 {
                                    path.move(to: lerp(p0, p1, t0))
                                } else if path.currentPoint != p0 {
                                    path.move(to: p0)
                                }
                                if t1 < 1 {
                                    path.addLine(to: lerp(p0, p1, t1))
                                    break elementLoop
                                } else {
                                    path.addLine(to: p1)
                                }
                                // `progress` tracks the source path, not the
                                // emitted portion of this element. The next
                                // element therefore starts after the full
                                // source segment even when this one was
                                // trimmed at its leading edge.
                                progress += sourceLength
                            }
                        case .quadCurve(let p2, let p1):
                            if let p0 = currentPoint {
                                if end <= progress { break elementLoop }
                                currentPoint = p2
                                var curve = QuadraticBezier(
                                    p0: p0,
                                    p1: p1,
                                    p2: p2
                                )
                                if start >= progress + sourceLength {
                                    progress += sourceLength
                                    continue
                                }

                                let (t0, originalT1) = Self.trimmedElementFractions(
                                    distance: sourceLength,
                                    progress: progress,
                                    start: start,
                                    end: end
                                )
                                var t1 = originalT1
                                let endsWithinElement = t1 < 1
                                if t0 > 0 {
                                    path.move(to: curve.interpolate(t0))
                                    curve = curve.split(t0).1
                                    t1 = clamp(
                                        (t1 - t0) / (1 - t0),
                                        min: 0,
                                        max: 1
                                    )
                                } else if path.currentPoint != p0 {
                                    path.move(to: p0)
                                }
                                if endsWithinElement {
                                    curve = curve.split(t1).0
                                    path.addQuadCurve(
                                        to: curve.p2,
                                        control: curve.p1
                                    )
                                    break elementLoop
                                } else {
                                    path.addQuadCurve(
                                        to: curve.p2,
                                        control: curve.p1
                                    )
                                }
                                progress += sourceLength
                            }
                        case .curve(let p3, let p1, let p2):
                            if let p0 = currentPoint {
                                if end <= progress { break elementLoop }
                                currentPoint = p3
                                var curve = CubicBezier(
                                    p0: p0,
                                    p1: p1,
                                    p2: p2,
                                    p3: p3
                                )
                                if start >= progress + sourceLength {
                                    progress += sourceLength
                                    continue
                                }

                                let (t0, originalT1) = Self.trimmedElementFractions(
                                    distance: sourceLength,
                                    progress: progress,
                                    start: start,
                                    end: end
                                )
                                var t1 = originalT1
                                let endsWithinElement = t1 < 1
                                if t0 > 0 {
                                    path.move(to: curve.interpolate(t0))
                                    curve = curve.split(t0).1
                                    t1 = clamp(
                                        (t1 - t0) / (1 - t0),
                                        min: 0,
                                        max: 1
                                    )
                                } else if path.currentPoint != p0 {
                                    path.move(to: p0)
                                }
                                if endsWithinElement {
                                    curve = curve.split(t1).0
                                    path.addCurve(
                                        to: curve.p3,
                                        control1: curve.p1,
                                        control2: curve.p2
                                    )
                                    break elementLoop
                                } else {
                                    path.addCurve(
                                        to: curve.p3,
                                        control1: curve.p1,
                                        control2: curve.p2
                                    )
                                }
                                progress += sourceLength
                            }
                        case .closeSubpath:
                            currentPoint = startPoint
                            if progress > start {
                                path.closeSubpath()
                            }
                        }
                    }
                }
            }
        }
        guard !path.elements.isEmpty else { return Path() }
        return Path(storage: .path(PathBox(data: path)))
    }

    var approximateLength: CGFloat {
        var length: CGFloat = 0
        var subpathStart: CGPoint?
        var current: CGPoint?
        let data = materializedData()
        data.elements.withUnsafeBufferPointer { elements in
            var index = 0
            while index < elements.count {
                switch elements[index] {
                case let .move(to: point):
                    subpathStart = point
                    current = point
                case let .line(to: point):
                    if let current {
                        length += (point - current).magnitude
                    }
                    current = point
                case let .quadCurve(to: point, control: control):
                    if let current {
                        length += QuadraticBezier(
                            p0: current,
                            p1: control,
                            p2: point
                        ).approximateLength(subdivide: 2)
                    }
                    current = point
                case let .curve(
                    to: point,
                    control1: control1,
                    control2: control2
                ):
                    if let current {
                        length += CubicBezier(
                            p0: current,
                            p1: control1,
                            p2: control2,
                            p3: point
                        ).approximateLength(subdivide: 3)
                    }
                    current = point
                case .closeSubpath:
                    current = subpathStart
                }
                index += 1
            }
        }
        return length
    }
}

// Creating a circle with a cubic Bezier curve
// The cubic bezier curve must be a circular sector of 1/4 of a circle. (pi/2)
// https://stackoverflow.com/a/27863181
// (4/3)*tan(pi/8) = 4*(sqrt(2)-1)/3 = 0.552284749830793
private let _r: Double = 0.552284749830793

extension Path {
    public mutating func move(to p: CGPoint) {
        withMutableBuffer { data in
            data.move(to: p)
        }
    }

    public mutating func addLine(to p1: CGPoint) {
        withMutableBuffer { data in
            data.addLine(to: p1)
        }
    }

    public mutating func addQuadCurve(to p2: CGPoint, control p1: CGPoint) {
        withMutableBuffer { data in
            data.addQuadCurve(to: p2, control: p1)
        }
    }

    public mutating func addCurve(to p3: CGPoint, control1 p1: CGPoint, control2 p2: CGPoint) {
        withMutableBuffer { data in
            data.addCurve(to: p3, control1: p1, control2: p2)
        }
    }

    public mutating func closeSubpath() {
        withMutableBuffer { data in
            data.closeSubpath()
        }
    }

}

extension Path {
    public init(_ rect: CGRect) {
        if rect.isNull {
            storage = .empty
        } else {
            storage = .rect(rect)
        }
    }

    public init(roundedRect rect: CGRect,
                cornerSize: CGSize,
                style: RoundedCornerStyle = .circular) {
        if rect.isNull {
            storage = .empty
        } else if cornerSize == .zero {
            storage = .rect(rect)
        } else {
            storage = .roundedRect(FixedRoundedRect(
                rect: rect,
                cornerSize: cornerSize,
                style: style
            ))
        }
    }

    public init(roundedRect rect: CGRect,
                cornerRadius: CGFloat,
                style: RoundedCornerStyle = .circular) {
        self.init(
            roundedRect: rect,
            cornerSize: CGSize(width: cornerRadius, height: cornerRadius),
            style: style
        )
    }

    public init(ellipseIn rect: CGRect) {
        if rect.isNull {
            storage = .empty
        } else {
            storage = .ellipse(rect)
        }
    }

    public init(_ callback: (inout Path) -> ()) {
        self.init()
        callback(&self)
    }

    private static func preservesAxisAlignment(
        _ transform: CGAffineTransform
    ) -> Bool {
        (transform.b == 0 && transform.c == 0)
            || (transform.a == 0 && transform.d == 0)
    }

    private static func transformedCornerSize(
        _ cornerSize: CGSize,
        by transform: CGAffineTransform
    ) -> CGSize {
        if transform.b == 0 && transform.c == 0 {
            return CGSize(
                width: cornerSize.width * abs(transform.a),
                height: cornerSize.height * abs(transform.d)
            )
        }
        return CGSize(
            width: cornerSize.height * abs(transform.c),
            height: cornerSize.width * abs(transform.b)
        )
    }

    public mutating func addRect(_ rect: CGRect,
                                 transform: CGAffineTransform = .identity) {
        if rect.isNull { return }
        if case .empty = storage,
           Self.preservesAxisAlignment(transform) {
            storage = .rect(rect.applying(transform).standardized)
            return
        }
        withMutableBuffer { data in
            data.addRect(rect, transform: transform)
        }
    }

    public mutating func addRoundedRect(in rect: CGRect,
                                        cornerSize: CGSize,
                                        style: RoundedCornerStyle = .circular,
                                        transform: CGAffineTransform = .identity) {
        if rect.isNull { return }
        let sourceRect = rect
        let rect = sourceRect.standardized
        let midX = rect.midX
        let midY = rect.midY
        let minX = rect.minX
        let maxX = rect.maxX
        let minY = rect.minY
        let maxY = rect.maxY
        let cx = clamp(cornerSize.width, min: 0, max: maxX - midX)
        let cy = clamp(cornerSize.height, min: 0, max: maxY - midY)

        if case .empty = storage,
           Self.preservesAxisAlignment(transform) {
            let transformedRect = sourceRect.applying(transform).standardized
            let transformedCornerSize = Self.transformedCornerSize(
                cornerSize,
                by: transform
            )
            if transformedCornerSize == .zero {
                storage = .rect(transformedRect)
            } else {
                storage = .roundedRect(FixedRoundedRect(
                    rect: transformedRect,
                    cornerSize: transformedCornerSize,
                    style: style
                ))
            }
            return
        }

        withMutableBuffer { data in
            data.reserveCapacity(data.elements.count + 18)
            if cornerSize != .zero {
                let usesKnownBounds = style == .circular
                    && Self.preservesAxisAlignment(transform)
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

                let startPoint = CGPoint(x: maxX, y: midY)
                    .applying(transform)
                if usesKnownBounds {
                    data.elements.append(.move(to: startPoint))
                } else {
                    data.move(to: startPoint)
                }

                if style == .circular {
                    data.appendCircularCorner(
                        transform: t1,
                        reversed: false,
                        tracksBounds: !usesKnownBounds
                    )
                    data.appendCircularCorner(
                        transform: t2,
                        reversed: true,
                        tracksBounds: !usesKnownBounds
                    )
                    data.appendCircularCorner(
                        transform: t3,
                        reversed: false,
                        tracksBounds: !usesKnownBounds
                    )
                    data.appendCircularCorner(
                        transform: t4,
                        reversed: true,
                        tracksBounds: !usesKnownBounds
                    )
                } else { /* style == .continuous */
                    let rx = min((maxX - midX - cx) / (cx * 0.54), 1.0)
                    let ry = min((maxY - midY - cy) / (cy * 0.54), 1.0)
                    let radiusFactors = CGPoint(x: rx, y: ry)
                    data.appendContinuousCorner(
                        transform: t1,
                        radiusFactors: radiusFactors,
                        reversed: false
                    )
                    data.appendContinuousCorner(
                        transform: t2,
                        radiusFactors: radiusFactors,
                        reversed: true
                    )
                    data.appendContinuousCorner(
                        transform: t3,
                        radiusFactors: radiusFactors,
                        reversed: false
                    )
                    data.appendContinuousCorner(
                        transform: t4,
                        radiusFactors: radiusFactors,
                        reversed: true
                    )
                }
                if usesKnownBounds {
                    data.elements.append(.closeSubpath)
                    let bounds = rect.applying(transform).standardized
                    data.boundingBox = data.boundingBox.union(bounds)
                    data.boundingBoxOfPath = data.boundingBoxOfPath.union(
                        bounds
                    )
                    data.initialPoint = startPoint
                    data.currentPoint = startPoint
                    return
                }
            } else {
                data.move(to: CGPoint(x: minX, y: minY).applying(transform))
                data.addLine(to: CGPoint(x: maxX, y: minY).applying(transform))
                data.addLine(to: CGPoint(x: maxX, y: maxY).applying(transform))
                data.addLine(to: CGPoint(x: minX, y: maxY).applying(transform))
            }
            data.closeSubpath()
        }
    }

    public mutating func addEllipse(in rect: CGRect,
                                    transform: CGAffineTransform = .identity) {
        if rect.isNull { return }
        if case .empty = storage,
           Self.preservesAxisAlignment(transform) {
            storage = .ellipse(rect.applying(transform).standardized)
            return
        }
        let rect = rect.standardized
        withMutableBuffer { data in
            data.addEllipse(in: rect, transform: transform)
        }
    }

    public mutating func addRects(_ rects: [CGRect],
                                  transform: CGAffineTransform = .identity) {
        guard let firstIndex = rects.firstIndex(where: { !$0.isNull }) else {
            return
        }
        addRect(rects[firstIndex], transform: transform)

        let remainingStart = rects.index(after: firstIndex)
        guard remainingStart != rects.endIndex,
              let secondIndex = rects[remainingStart...].firstIndex(
                where: { !$0.isNull }
              ) else {
            return
        }

        withMutableBuffer { data in
            data.reserveCapacity(
                data.elements.count + (rects.count - secondIndex) * 5
            )
            rects.withUnsafeBufferPointer { rects in
                var index = secondIndex
                while index < rects.count {
                    let rect = rects[index]
                    if !rect.isNull {
                        data.appendRect(rect, transform: transform)
                    }
                    index += 1
                }
            }
        }
    }

    public mutating func addLines(_ lines: [CGPoint]) {
        guard let first = lines.first else { return }
        withMutableBuffer { data in
            data.reserveCapacity(data.elements.count + lines.count)
            data.move(to: first)
            lines.withUnsafeBufferPointer { lines in
                var index = 1
                while index < lines.count {
                    data.addLine(to: lines[index])
                    index += 1
                }
            }
        }
    }

    public mutating func addRelativeArc(center: CGPoint,
                                        radius: CGFloat,
                                        startAngle: Angle,
                                        delta: Angle,
                                        transform: CGAffineTransform = .identity) {
        withMutableBuffer { data in
            data.addRelativeArc(
                center: center,
                radius: radius,
                startAngle: startAngle,
                delta: delta,
                transform: transform
            )
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
        guard !path.isEmpty else { return }
        if case .empty = storage {
            if transform.isIdentity {
                self = path
                return
            }
            switch path.storage {
            case .empty:
                return
            case .rect(let rect):
                addRect(rect, transform: transform)
                return
            case .ellipse(let rect):
                addEllipse(in: rect, transform: transform)
                return
            case .roundedRect(let roundedRect):
                addRoundedRect(
                    in: roundedRect.rect,
                    cornerSize: roundedRect.cornerSize,
                    style: roundedRect.style,
                    transform: transform
                )
                return
            case .path:
                break
            }
        }
        withMutableBuffer { data in
            path.append(to: &data, transform: transform)
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
        self.init()
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
