//
//  File: ScaledMetric.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

@propertyWrapper public struct ScaledMetric<Value>: DynamicProperty
where Value: BinaryFloatingPoint {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.pixelLength) private var pixelLength
    private var value: Value
    private var textStyle: Font.TextStyle

    public init(
        wrappedValue: Value,
        relativeTo textStyle: Font.TextStyle
    ) {
        self.value = wrappedValue
        self.textStyle = textStyle
    }

    public init(wrappedValue: Value) {
        self.init(wrappedValue: wrappedValue, relativeTo: .body)
    }

    public var wrappedValue: Value {
        let scale = Value(
            Font.scaleFactor(
                textStyle: textStyle,
                in: dynamicTypeSize
            )
        )
        return (value * scale).rounded(
            toMultipleOf: Value(pixelLength)
        )
    }
}

extension ScaledMetric: Sendable where Value: Sendable {}

private extension FloatingPoint {
    func rounded(toMultipleOf multiple: Self) -> Self {
        (self / multiple).rounded() * multiple
    }
}

extension Font {
    static func scaleFactor(
        textStyle: TextStyle,
        in dynamicTypeSize: DynamicTypeSize
    ) -> CGFloat {
        _ = textStyle
        _ = dynamicTypeSize
        return 1
    }
}
