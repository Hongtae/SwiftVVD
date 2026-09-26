//
//  File: CGColor.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

#if canImport(CoreGraphics)
public typealias CGColor = CoreGraphics.CGColor
#else
public class CGColor: Hashable, @unchecked Sendable, Codable {
    private enum Model: Hashable {
        case genericGray
        case genericRGB
    }

    private enum CodingKeys: String, CodingKey {
        case components = "kCGColorComponents"
        case contentHeadroom = "kCGColorContentHeadroom"
        case colorSpace = "kCGColorSpace"
    }

    private let model: Model

    private static let whiteColor = CGColor(gray: 1, alpha: 1)
    private static let blackColor = CGColor(gray: 0, alpha: 1)
    private static let clearColor = CGColor(gray: 0, alpha: 0)

    public let components: [CGFloat]?
    public var numberOfComponents: Int { components?.count ?? 0 }
    public var alpha: CGFloat { components?.last ?? 1 }

    public class var white: CGColor {
        whiteColor
    }

    public class var black: CGColor {
        blackColor
    }

    public class var clear: CGColor {
        clearColor
    }

    public init(gray: CGFloat, alpha: CGFloat) {
        model = .genericGray
        components = [gray, alpha]
    }

    public init(
        red: CGFloat,
        green: CGFloat,
        blue: CGFloat,
        alpha: CGFloat
    ) {
        model = .genericRGB
        components = [red, green, blue, alpha]
    }

    public static func == (lhs: CGColor, rhs: CGColor) -> Bool {
        lhs.model == rhs.model
            && lhs.components == rhs.components
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(model)
        hasher.combine(components)
    }

    public required init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let components = try container.decode(
            [CGFloat].self,
            forKey: .components
        )
        let contentHeadroom = try container.decodeIfPresent(
            Float.self,
            forKey: .contentHeadroom
        ) ?? 1
        guard contentHeadroom == 1 else {
            throw DecodingError.dataCorruptedError(
                forKey: .contentHeadroom,
                in: container,
                debugDescription: "Only standard-dynamic-range colors are supported."
            )
        }

        if let colorSpace = try? container.decode(
            Int.self,
            forKey: .colorSpace
        ), colorSpace == 1, components.count == 2 {
            model = .genericGray
            self.components = components
        } else if let colorSpace = try? container.decode(
            String.self,
            forKey: .colorSpace
        ), colorSpace == "kCGColorSpaceGenericRGB", components.count == 4 {
            model = .genericRGB
            self.components = components
        } else {
            throw DecodingError.dataCorruptedError(
                forKey: .colorSpace,
                in: container,
                debugDescription: "Unsupported color space or component count."
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(components ?? [], forKey: .components)
        try container.encode(Float(1), forKey: .contentHeadroom)
        switch model {
        case .genericGray:
            try container.encode(1, forKey: .colorSpace)
        case .genericRGB:
            try container.encode(
                "kCGColorSpaceGenericRGB",
                forKey: .colorSpace
            )
        }
    }
}
#endif
