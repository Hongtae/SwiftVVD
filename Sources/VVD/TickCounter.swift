//
//  File: TickCounter.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2024 Hongtae Kim. All rights reserved.
//

import Foundation

public struct TickCounter: Equatable, Comparable {
    public private(set) var timestamp: UInt64

    public static let frequency: UInt64 = Platform.tickFrequency()
    public static let frequencyUnitFraction: Double = 1.0 / Double(frequency)

    public static var now: TickCounter { TickCounter(timestamp: Platform.tick()) }

    private init(timestamp: UInt64) {
        self.timestamp = timestamp
    }

    @discardableResult
    public mutating func reset() -> Double {
        let t: Double = Double(self.timestamp)
        self.timestamp = Self.now.timestamp
        return (Double(self.timestamp) - t) * Self.frequencyUnitFraction
    }

    public var elapsed: Double { Self.now.distance(to: self) }

    public func distance(to other: TickCounter) -> Double {
        if self.timestamp > other.timestamp {
            return Double(self.timestamp - other.timestamp) * Self.frequencyUnitFraction
        } else {
            var d = Double(other.timestamp - self.timestamp)
            d.negate()
            return d * Self.frequencyUnitFraction
        }
    }

    // Equatable
    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.timestamp == rhs.timestamp }
    public static func != (lhs: Self, rhs: Self) -> Bool { lhs.timestamp != rhs.timestamp }
    // Comparable
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.timestamp < rhs.timestamp }
    public static func <= (lhs: Self, rhs: Self) -> Bool { lhs.timestamp <= rhs.timestamp }
    public static func > (lhs: Self, rhs: Self) -> Bool { lhs.timestamp > rhs.timestamp }
    public static func >= (lhs: Self, rhs: Self) -> Bool { lhs.timestamp >= rhs.timestamp }
}
