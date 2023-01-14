//
//  File: ViewSpacing.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import Foundation

public struct ViewSpacing {
    public static let zero = ViewSpacing()

    public init() {
    }

    public mutating func formUnion(_ other: ViewSpacing, edges: Edge.Set = .all) {
    }

    public func union(_ other: ViewSpacing, edges: Edge.Set = .all) -> ViewSpacing {
        ViewSpacing()
    }

    public func distance(to next: ViewSpacing, along axis: Axis) -> CGFloat {
        return 0
    }
}
