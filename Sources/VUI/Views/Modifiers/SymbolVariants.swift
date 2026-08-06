//
//  File: SymbolVariants.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

public struct SymbolVariants: Hashable, Sendable {
    private struct Flags: OptionSet, Hashable, Sendable {
        var rawValue: UInt8

        static let fill = Self(rawValue: 1 << 0)
        static let slash = Self(rawValue: 1 << 1)
    }

    private enum Shape: UInt8, Hashable, Sendable {
        case circle
        case square
        case rectangle
    }

    private var flags: Flags
    private var shape: Shape?

    private init(flags: Flags = [], shape: Shape? = nil) {
        self.flags = flags
        self.shape = shape
    }

    public static let none = Self()
    public static let circle = Self(shape: .circle)
    public static let square = Self(shape: .square)
    public static let rectangle = Self(shape: .rectangle)
    public static let fill = Self(flags: .fill)
    public static let slash = Self(flags: .slash)

    public var circle: Self {
        Self(flags: flags, shape: .circle)
    }

    public var square: Self {
        Self(flags: flags, shape: .square)
    }

    public var rectangle: Self {
        Self(flags: flags, shape: .rectangle)
    }

    public var fill: Self {
        Self(flags: flags.union(.fill), shape: shape)
    }

    public var slash: Self {
        Self(flags: flags.union(.slash), shape: shape)
    }

    public func contains(_ other: Self) -> Bool {
        flags.isSuperset(of: other.flags)
            && (other.shape == nil || shape == other.shape)
    }

    fileprivate mutating func applyEnvironmentVariant(_ variant: Self) {
        flags.formUnion(variant.flags)
        if let shape = variant.shape {
            self.shape = shape
        }
    }
}

private struct SymbolVariantsKey: EnvironmentKey {
    static let defaultValue: SymbolVariants = .none
}

extension EnvironmentValues {
    public var symbolVariants: SymbolVariants {
        get { self[SymbolVariantsKey.self] }
        set { self[SymbolVariantsKey.self] = newValue }
    }
}

extension View {
    public func symbolVariant(_ variant: SymbolVariants) -> some View {
        transformEnvironment(\.symbolVariants) {
            $0.applyEnvironmentVariant(variant)
        }
    }
}
