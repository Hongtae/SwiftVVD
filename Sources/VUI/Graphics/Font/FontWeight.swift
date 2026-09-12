//
//  File: FontWeight.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

extension Font {
    public struct Weight: Hashable, Sendable {
        public var value: CGFloat

        public static let ultraLight = Weight(value: -0.8)
        public static let thin = Weight(value: -0.6)
        public static let light = Weight(value: -0.4)
        public static let regular = Weight(value: 0)
        public static let medium = Weight(value: 0.23)
        public static let semibold = Weight(value: 0.3)
        public static let bold = Weight(value: 0.4)
        public static let heavy = Weight(value: 0.56)
        public static let black = Weight(value: 0.62)
    }
}

extension Font.Weight: CodableByProxy {
    var codingProxy: CodableFontWeight { CodableFontWeight(base: self) }
}

struct CodableFontWeight: CodableProxy {
    var base: Font.Weight

    init(base: Font.Weight) { self.base = base }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        base = Font.Weight(value: try container.decode(CGFloat.self))
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(base.value)
    }
}

/// Converts numeric resource coordinates at the font backend boundary.
enum FontWeightScale {
    private static let values: [Float] = [
        -0.9, -0.6, -0.4, -0.23, 0, 0.2, 0.3, 0.4, 0.6, 0.8, 1
    ]

    static func weightClass(for weight: CGFloat) -> CGFloat {
        guard !weight.isNaN, weight >= CGFloat(values[0]) else { return 0 }
        guard weight < CGFloat(values[10]) else { return 1000 }
        for index in 0..<10 {
            let lower = CGFloat(values[index])
            let upper = CGFloat(values[index + 1])
            if abs(weight - lower) < 0.001 { return CGFloat(index * 100) }
            if abs(weight - upper) < 0.001 { return CGFloat((index + 1) * 100) }
            if weight < upper {
                let fraction = CGFloat(Float((weight - lower) / (upper - lower)))
                return (CGFloat(index * 100) + fraction * 100).rounded()
            }
        }
        return 1000
    }

    static func logicalWeight(forClass value: CGFloat) -> CGFloat {
        // Resource tables and variation axes may extend beyond the standard range.
        let value = value.isFinite ? min(max(value, 0), 1000) : 400
        let lower = min(Int(value / 100), 9)
        let fraction = Float((value - CGFloat(lower * 100)) / 100)
        let start = values[lower]
        let end = values[lower + 1]
        // Keep one rounding step for the product and sum at weight boundaries.
        if start <= 0 && end >= 0 {
            return CGFloat((start * (1 - fraction)).addingProduct(fraction, end))
        }
        if fraction == 1 { return CGFloat(end) }
        return CGFloat(min(start.addingProduct(fraction, end - start), end))
    }
}

extension Font.Weight {
    var weightClass: CGFloat { FontWeightScale.weightClass(for: value) }
}
