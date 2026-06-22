//
//  File: CollisionFilter.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

public struct CollisionGroup: OptionSet, Hashable, Sendable {
    public let rawValue: UInt64

    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public static let none: Self = []
    public static let all = Self(rawValue: UInt64.max)
    public static let `default` = Self.bit(0)

    public static func bit(_ index: Int) -> Self {
        precondition((0..<UInt64.bitWidth).contains(index), "Collision group bit index is out of range.")
        return Self(rawValue: UInt64(1) << index)
    }
}

public struct CollisionMask: OptionSet, Hashable, Sendable {
    public let rawValue: UInt64

    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public init(_ groups: CollisionGroup) {
        self.init(rawValue: groups.rawValue)
    }

    public static let none: Self = []
    public static let all = Self(rawValue: UInt64.max)
    public static let `default` = Self(.default)

    public func contains(_ group: CollisionGroup) -> Bool {
        rawValue & group.rawValue == group.rawValue
    }

    public func intersects(_ group: CollisionGroup) -> Bool {
        rawValue & group.rawValue != 0
    }
}

public struct CollisionFilter: Hashable, Sendable {
    public let group: CollisionGroup
    public let mask: CollisionMask

    public init(group: CollisionGroup = .default, mask: CollisionMask = .all) {
        self.group = group
        self.mask = mask
    }

    public func allowsCollision(with other: Self) -> Bool {
        mask.intersects(other.group) && other.mask.intersects(group)
    }
}
