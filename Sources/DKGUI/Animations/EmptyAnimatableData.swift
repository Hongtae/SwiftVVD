//
//  File: EmptyAnimatableData.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

public struct EmptyAnimatableData: VectorArithmetic, Equatable, Sendable {
    public init() {}

    public static var zero: EmptyAnimatableData { .init() }

    public static func += (lhs: inout EmptyAnimatableData, rhs: EmptyAnimatableData) {}

    public static func -= (lhs: inout EmptyAnimatableData, rhs: EmptyAnimatableData) {}

    public static func + (lhs: EmptyAnimatableData, rhs: EmptyAnimatableData) -> EmptyAnimatableData {
        .init()
    }

    public static func - (lhs: EmptyAnimatableData, rhs: EmptyAnimatableData) -> EmptyAnimatableData {
        .init()
    }

    public mutating func scale(by rhs: Double) {}

    public var magnitudeSquared: Double { 0.0 }

    public static func == (a: EmptyAnimatableData, b: EmptyAnimatableData) -> Bool {
        true
    }
}
