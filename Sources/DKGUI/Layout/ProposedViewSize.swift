//
//  File: ProposedViewSize.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import Foundation

public struct ProposedViewSize: Equatable, Sendable {
    public var width: CGFloat?
    public var height: CGFloat?

    public static let zero = ProposedViewSize(width: 0, height: 0)
    public static let unspecified = ProposedViewSize(width: nil, height: nil)
    public static let infinity = ProposedViewSize(width: .infinity, height: .infinity)

    @inlinable public init(width: CGFloat? = nil, height: CGFloat? = nil) {
        self.width = width
        self.height = height
    }

    @inlinable public init(_ size: CGSize) {
        self.width = size.width
        self.height = size.height
    }

    @inlinable public func replacingUnspecifiedDimensions(by size: CGSize = CGSize(width: 10, height: 10)) -> CGSize {
        CGSize(width: self.width ?? size.width, height: self.height ?? size.height)
    }
}
