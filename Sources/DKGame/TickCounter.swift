import DKGameUtils
import Foundation

public struct TickCounter: Equatable, Comparable {
    public private(set) var timestamp: UInt64
    public static let frequency: UInt64 = DKTimerSystemTickFrequency()

    public static let frequencyUnitFraction: Double = 1.0 / Double(frequency)

    public static var now: TickCounter { TickCounter(timestamp: DKTimerSystemTick()) }

    public init() {
        self.timestamp = DKTimerSystemTick()
    }

    public init(timestamp: UInt64) {
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
        return (Double(self.timestamp) - Double(other.timestamp)) * Self.frequencyUnitFraction
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
