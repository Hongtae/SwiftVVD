//
//  File: ScrollPosition.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

/// Source-visible scroll target value used by scroll position bindings and requests.
public struct ScrollPosition: Sendable {
    private struct AnySendableHashable: @unchecked Sendable, Equatable {
        var base: any Hashable
        private var erased: AnyHashable

        init<Value>(_ value: Value) where Value: Hashable {
            self.base = value
            self.erased = AnyHashable(value)
        }

        func value<Value>(as type: Value.Type) -> Value? where Value: Hashable {
            base as? Value
        }

        static func == (lhs: AnySendableHashable, rhs: AnySendableHashable) -> Bool {
            lhs.erased == rhs.erased
        }
    }

    private struct ViewID: Sendable, Equatable {
        var id: AnySendableHashable
        var anchor: UnitPoint?
    }

    private enum Storage: Sendable, Equatable {
        case automatic
        case positionedByUser
        case viewID(ViewID)
        case edge(Edge)
        case point(CGPoint)
        case x(CGFloat)
        case y(CGFloat)
    }

    private var storage: Storage
    private var idType: Any.Type
    private var seed: UInt32

    public init(id: some Hashable & Sendable, anchor: UnitPoint? = nil) {
        self.storage = .viewID(ViewID(id: AnySendableHashable(id), anchor: anchor))
        self.idType = type(of: id)
        self.seed = 0
    }

    init(_scrollPositionID id: some Hashable, anchor: UnitPoint? = nil) {
        self.storage = .viewID(ViewID(id: AnySendableHashable(id), anchor: anchor))
        self.idType = type(of: id)
        self.seed = 0
    }

    public init(idType: (some Hashable & Sendable).Type = Never.self) {
        self.storage = .automatic
        self.idType = idType
        self.seed = 0
    }

    init<ID>(_scrollPositionIDType idType: ID.Type) where ID: Hashable {
        self.storage = .automatic
        self.idType = idType
        self.seed = 0
    }

    public init(idType: (some Hashable & Sendable).Type = Never.self, edge: Edge) {
        self.storage = .edge(edge)
        self.idType = idType
        self.seed = 0
    }

    public init(idType: (some Hashable & Sendable).Type = Never.self, point: CGPoint) {
        self.storage = .point(point)
        self.idType = idType
        self.seed = 0
    }

    public init(idType: (some Hashable & Sendable).Type = Never.self, x: CGFloat, y: CGFloat) {
        self.storage = .point(CGPoint(x: x, y: y))
        self.idType = idType
        self.seed = 0
    }

    public init(idType: (some Hashable & Sendable).Type = Never.self, x: CGFloat) {
        self.storage = .x(x)
        self.idType = idType
        self.seed = 0
    }

    public init(idType: (some Hashable & Sendable).Type = Never.self, y: CGFloat) {
        self.storage = .y(y)
        self.idType = idType
        self.seed = 0
    }

    public mutating func scrollTo(id: some Hashable & Sendable, anchor: UnitPoint? = nil) {
        storage = .viewID(ViewID(id: AnySendableHashable(id), anchor: anchor))
        idType = type(of: id)
        seed &+= 1
    }

    mutating func _scrollTo(id: some Hashable, anchor: UnitPoint? = nil) {
        storage = .viewID(ViewID(id: AnySendableHashable(id), anchor: anchor))
        idType = type(of: id)
        seed &+= 1
    }

    public mutating func scrollTo(edge: Edge) {
        storage = .edge(edge)
        seed &+= 1
    }

    public mutating func scrollTo(point: CGPoint) {
        storage = .point(point)
        seed &+= 1
    }

    public mutating func scrollTo(x: CGFloat, y: CGFloat) {
        storage = .point(CGPoint(x: x, y: y))
        seed &+= 1
    }

    public mutating func scrollTo(x: CGFloat) {
        storage = .x(x)
        seed &+= 1
    }

    public mutating func scrollTo(y: CGFloat) {
        storage = .y(y)
        seed &+= 1
    }

    public var isPositionedByUser: Bool {
        get {
            if case .positionedByUser = storage {
                return true
            }
            return false
        }
        set {
            if newValue {
                storage = .positionedByUser
            }
        }
    }

    public var edge: Edge? {
        if case let .edge(edge) = storage {
            return edge
        }
        return nil
    }

    public var point: CGPoint? {
        if case let .point(point) = storage {
            return point
        }
        return nil
    }

    public var x: CGFloat? {
        if case let .x(x) = storage {
            return x
        }
        return nil
    }

    public var y: CGFloat? {
        if case let .y(y) = storage {
            return y
        }
        return nil
    }

    public var viewID: (any Hashable & Sendable)? {
        if case let .viewID(viewID) = storage {
            return unsafeBitCast(
                viewID.id.base,
                to: (any Hashable & Sendable).self
            )
        }
        return nil
    }

    public func viewID<T>(type: T.Type) -> T? where T: Hashable, T: Sendable {
        _viewID(type: type)
    }

    func _viewID<T>(type: T.Type) -> T? where T: Hashable {
        if case let .viewID(viewID) = storage {
            return viewID.id.value(as: type)
        }
        return nil
    }

    var _anyViewID: AnyHashable? {
        if case let .viewID(viewID) = storage {
            return AnyHashable(viewID.id.base)
        }
        return nil
    }

    func matches<ID>(id: ID) -> Bool where ID: Hashable {
        _viewID(type: ID.self) == id
    }

    func hasSameStorage(as other: ScrollPosition) -> Bool {
        storage == other.storage
    }

    func wantsUpdate(toPosition newPosition: ScrollPosition) -> Bool {
        switch (storage, newPosition.storage) {
        case let (.viewID(current), .viewID(new)):
            return current != new
        default:
            return true
        }
    }
}

extension ScrollPosition: Equatable {
    public static func == (lhs: ScrollPosition, rhs: ScrollPosition) -> Bool {
        lhs.storage == rhs.storage &&
        ObjectIdentifier(lhs.idType) == ObjectIdentifier(rhs.idType) &&
        lhs.seed == rhs.seed
    }
}
