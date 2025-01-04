//
//  File: UnitPoint.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

import Foundation

public struct UnitPoint : Hashable, Sendable {
    public var x: CGFloat
    public var y: CGFloat

    public init() {
        x = 0.0
        y = 0.0
    }

    public init(x: CGFloat, y: CGFloat) {
        self.x = x
        self.y = y
    }

    public static let zero              = UnitPoint(x: 0.0, y: 0.0)
    public static let center            = UnitPoint(x: 0.5, y: 0.5)
    public static let leading           = UnitPoint(x: 0.0, y: 0.5)
    public static let trailing          = UnitPoint(x: 1.0, y: 0.5)
    public static let top               = UnitPoint(x: 0.5, y: 0.0)
    public static let bottom            = UnitPoint(x: 0.5, y: 1.0)
    public static let topLeading        = UnitPoint(x: 0.0, y: 0.0)
    public static let topTrailing       = UnitPoint(x: 1.0, y: 0.0)
    public static let bottomLeading     = UnitPoint(x: 0.0, y: 1.0)
    public static let bottomTrailing    = UnitPoint(x: 1.0, y: 1.0)
}

extension UnitPoint : Animatable {
    public typealias AnimatableData = AnimatablePair<CGFloat, CGFloat>
    public var animatableData: AnimatableData {
        get { .init(x, y) }
        set { (x, y) = newValue[] }
    }
}
