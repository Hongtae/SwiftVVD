//
//  File: Path.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

import Foundation

public enum RoundedCornerStyle: Equatable, Hashable {
    case circular
    case continuous
}

public struct FillStyle: Equatable, Sendable {
    public var isEOFilled: Bool
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

    public var description: String { "Path" }
    public var isEmpty: Bool { fatalError() }
    public var boundingRect: CGRect { fatalError() }

    public func contains(_ p: CGPoint, eoFill: Bool = false) -> Bool {
        fatalError()
    }

    public enum Element : Equatable, Sendable {
        case move(to: CGPoint)
        case line(to: CGPoint)
        case quadCurve(to: CGPoint, control: CGPoint)
        case curve(to: CGPoint, control1: CGPoint, control2: CGPoint)
        case closeSubpath

        public static func == (a: Path.Element, b: Path.Element) -> Bool {
            false
        }
    }

    public func forEach(_ body: (Path.Element) -> Void) {
        fatalError()
    }

    public func strokedPath(_ style: StrokeStyle) -> Path {
        fatalError()
    }

    public func trimmedPath(from: CGFloat, to: CGFloat) -> Path {
        fatalError()
    }

    public static func == (a: Path, b: Path) -> Bool {
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
        fatalError()
    }
    public mutating func addLine(to p: CGPoint) {
        fatalError()
    }
    public mutating func addQuadCurve(to p: CGPoint, control cp: CGPoint) {
        fatalError()
    }
    public mutating func addCurve(to p: CGPoint, control1 cp1: CGPoint, control2 cp2: CGPoint) {
        fatalError()
    }
    public mutating func closeSubpath() {
        fatalError()
    }
    public mutating func addRect(_ rect: CGRect, transform: CGAffineTransform = .identity) {
        fatalError()
    }
    public mutating func addRoundedRect(in rect: CGRect, cornerSize: CGSize, style: RoundedCornerStyle = .circular, transform: CGAffineTransform = .identity) {
        fatalError()
    }
    public mutating func addEllipse(in rect: CGRect, transform: CGAffineTransform = .identity) {
        fatalError()
    }
    public mutating func addRects(_ rects: [CGRect], transform: CGAffineTransform = .identity) {
        fatalError()
    }
    public mutating func addLines(_ lines: [CGPoint]) {
        fatalError()
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
        fatalError()
    }
    public func offsetBy(dx: CGFloat, dy: CGFloat) -> Path {
        fatalError()
    }
}
