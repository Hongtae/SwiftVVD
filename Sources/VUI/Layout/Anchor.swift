//
//  File: Anchor.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

/// A geometry value retained in the root coordinate space.
public struct Anchor<Value> {
    let box: AnchorValueBoxBase<Value>

    init<T: AnchorProtocol>(anchor: T, geometry: AnchorGeometry)
        where T.OutputValue == Value {
        box = AnchorValueBox<T>(anchor.prepare(geometry: geometry))
    }
}

extension Anchor: Sendable where Value: Sendable {}

extension Anchor: Equatable where Value: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.box.isEqual(to: rhs.box)
    }
}

extension Anchor: Hashable where Value: Hashable {
    public func hash(into hasher: inout Hasher) {
        box.hash(into: &hasher)
    }
}

class AnchorValueBoxBase<Value> {
    var defaultValue: Value { fatalError("AnchorValueBoxBase requires a concrete value owner.") }
    func convert(to transform: ViewTransform) -> Value {
        fatalError("AnchorValueBoxBase requires a concrete value owner.")
    }
    func isEqual(to other: AnchorValueBoxBase<Value>) -> Bool {
        false
    }
    func hash(into hasher: inout Hasher) {}
}

extension AnchorValueBoxBase: @unchecked Sendable where Value: Sendable {}

private final class AnchorValueBox<T: AnchorProtocol>: AnchorValueBoxBase<T.OutputValue> {
    let value: T.AnchorValue

    init(_ value: T.AnchorValue) {
        self.value = value
    }

    override var defaultValue: T.OutputValue {
        T.outputValue(anchorValue: T.defaultAnchor)
    }

    override func convert(to transform: ViewTransform) -> T.OutputValue {
        var value = value
        value.convert(from: .root, transform: transform)
        return T.outputValue(anchorValue: value)
    }

    override func isEqual(to other: AnchorValueBoxBase<T.OutputValue>) -> Bool {
        guard let other = other as? AnchorValueBox<T> else { return false }
        return T.valueIsEqual(lhs: value, rhs: other.value)
    }

    override func hash(into hasher: inout Hasher) {
        T.hashValue(value, into: &hasher)
    }
}

extension AnchorValueBox: @unchecked Sendable where T.OutputValue: Sendable {}

protocol AnchorProtocol {
    associatedtype AnchorValue: ViewTransformable
    associatedtype OutputValue
    static var defaultAnchor: AnchorValue { get }
    func prepare(geometry: AnchorGeometry) -> AnchorValue
    static func outputValue(anchorValue: AnchorValue) -> OutputValue
    static func valueIsEqual(lhs: AnchorValue, rhs: AnchorValue) -> Bool
    static func hashValue(_ value: AnchorValue, into hasher: inout Hasher)
}

extension AnchorProtocol where AnchorValue == OutputValue {
    static func outputValue(anchorValue: AnchorValue) -> OutputValue { anchorValue }
}

extension AnchorProtocol where AnchorValue: Equatable {
    static func valueIsEqual(lhs: AnchorValue, rhs: AnchorValue) -> Bool { lhs == rhs }
}

struct AnchorGeometry {
    var _position: Attribute<CGPoint>
    var _size: Attribute<CGSize>
    var _transform: Attribute<ViewTransform>

    var size: CGSize { _size.value }

    var transform: ViewTransform {
        var value = _transform.value
        value.appendPosition(_position.value)
        return value
    }
}

extension CGPoint: AnchorProtocol {
    typealias AnchorValue = CGPoint
    typealias OutputValue = CGPoint
    static var defaultAnchor: CGPoint { .zero }

    func prepare(geometry: AnchorGeometry) -> CGPoint {
        var point = self
        point.convert(to: .root, transform: geometry.transform)
        return point
    }

    static func hashValue(_ value: CGPoint, into hasher: inout Hasher) {
        hasher.combine(value.x)
        hasher.combine(value.y)
    }
}

extension UnitPoint: AnchorProtocol {
    typealias AnchorValue = CGPoint
    typealias OutputValue = CGPoint
    static var defaultAnchor: CGPoint { .zero }

    func prepare(geometry: AnchorGeometry) -> CGPoint {
        let size = geometry.size
        return CGPoint(x: x * size.width, y: y * size.height).prepare(geometry: geometry)
    }

    static func hashValue(_ value: CGPoint, into hasher: inout Hasher) {
        CGPoint.hashValue(value, into: &hasher)
    }
}
