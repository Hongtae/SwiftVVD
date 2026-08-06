//
//  File: ControlSize.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

public enum ControlSize: Hashable, CaseIterable, Sendable, Comparable {
    case mini
    case small
    case regular
    case large
    case extraLarge

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.order < rhs.order
    }

    private var order: Int {
        switch self {
        case .mini:
            0
        case .small:
            1
        case .regular:
            2
        case .large:
            3
        case .extraLarge:
            4
        }
    }
}

private struct ControlSizeCollection: Collection {
    var startIndex: ControlSize {
        .mini
    }

    var endIndex: ControlSize {
        .extraLarge
    }

    subscript(position: ControlSize) -> ControlSize {
        position
    }

    func index(after index: ControlSize) -> ControlSize {
        let cases = ControlSize.allCases
        let position = cases.firstIndex(of: index)!
        return cases[Swift.min(position + 1, cases.count - 1)]
    }
}

private extension ControlSize {
    func clamped<R>(
        to range: R
    ) -> ControlSize where R: RangeExpression, R.Bound == ControlSize {
        let relativeRange = range.relative(to: ControlSizeCollection())
        var maximum = relativeRange.upperBound
        if !range.contains(maximum) {
            let cases = ControlSize.allCases
            let position = cases.firstIndex(of: maximum)!
            maximum = cases[Swift.max(position - 1, 0)]
        }

        var result = self
        if result < relativeRange.lowerBound {
            result = relativeRange.lowerBound
        }
        if maximum < result {
            result = maximum
        }
        return result
    }
}

private struct ControlSizeKey: EnvironmentKey {
    static let defaultValue: ControlSize = .regular
}

extension EnvironmentValues {
    public var controlSize: ControlSize {
        get { self[ControlSizeKey.self] }
        set { self[ControlSizeKey.self] = newValue }
    }
}

extension View {
    public func controlSize(_ controlSize: ControlSize) -> some View {
        environment(\.controlSize, controlSize)
    }

    public func controlSize<R>(
        _ range: R
    ) -> some View where R: RangeExpression, R.Bound == ControlSize {
        transformEnvironment(\.controlSize) {
            $0 = $0.clamped(to: range)
        }
    }
}
