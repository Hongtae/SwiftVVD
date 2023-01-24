//
//  File: Path.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import Foundation

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
    }
    public init(roundedRect rect: CGRect, cornerSize: CGSize, style: RoundedCornerStyle = .circular) {
    }
    public init(roundedRect rect: CGRect, cornerRadius: CGFloat, style: RoundedCornerStyle = .circular) {
    }
    public init(ellipseIn rect: CGRect) {
    }
    public init(_ callback: (inout Path) -> ()) {
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
                desc.append("\(to.x) \(to.y) \(c.x) \(c.y) q")
            case .curve(let to, let c1, let c2):
                desc.append("\(to.x) \(to.y) \(c1.x) \(c1.y) \(c2.x) \(c2.y) c")
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
    var elements: [Element] = []
    var bounds: CGRect = .null

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

extension Path {
    public mutating func move(to p: CGPoint) {
        if case .move(_) = self.elements.last {
            self.elements.removeLast()
        }
        self.elements.append(.move(to: p))
    }
    public mutating func addLine(to p: CGPoint) {
        self.elements.append(.line(to: p))
    }
    public mutating func addQuadCurve(to p: CGPoint, control cp: CGPoint) {
        fatalError()
    }
    public mutating func addCurve(to p: CGPoint, control1 cp1: CGPoint, control2 cp2: CGPoint) {
        fatalError()
    }
    public mutating func closeSubpath() {
        self.elements.append(.closeSubpath)
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
        fatalError()
    }
    public mutating func addEllipse(in rect: CGRect, transform: CGAffineTransform = .identity) {
        fatalError()
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
        fatalError()
    }
    public mutating func addArc(center: CGPoint, radius: CGFloat, startAngle: Angle, endAngle: Angle, clockwise: Bool, transform: CGAffineTransform = .identity) {
        fatalError()
    }
    public mutating func addArc(tangent1End p1: CGPoint, tangent2End p2: CGPoint, radius: CGFloat, transform: CGAffineTransform = .identity) {
        fatalError()
    }
    public mutating func addPath(_ path: Path, transform: CGAffineTransform = .identity) {
        fatalError()
    }

    public var currentPoint: CGPoint? {
        fatalError()
    }
    public func applying(_ transform: CGAffineTransform) -> Path {
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
        //FIXME: update bounds!
        return path
    }

    public func offsetBy(dx: CGFloat, dy: CGFloat) -> Path {
        self.applying(CGAffineTransform(translationX: dx, y: dy))
    }
}
