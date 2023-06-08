//
//  File: Alignment.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import Foundation

public protocol AlignmentID {
    static func defaultValue(in context: ViewDimensions) -> CGFloat
}

struct AlignmentKey: Equatable {
    let bits: UInt
}

public struct HorizontalAlignment: Equatable {
    public init(_ id: AlignmentID.Type) {
        self.key = AlignmentKey(bits: 0)
    }

    let key: AlignmentKey
    init(alignmentKey: UInt) {
        self.key = AlignmentKey(bits: alignmentKey)
    }

    public static let leading = HorizontalAlignment(alignmentKey: 6)
    public static let center = HorizontalAlignment(alignmentKey: 2)
    public static let trailing = HorizontalAlignment(alignmentKey: 8)
}

public struct VerticalAlignment: Equatable {
    public init(_ id: AlignmentID.Type) {
        self.key = AlignmentKey(bits: 0)
    }

    let key: AlignmentKey
    init(alignmentKey: UInt) {
        self.key = AlignmentKey(bits: alignmentKey)
    }

    public static let top = VerticalAlignment(alignmentKey: 11)
    public static let center = VerticalAlignment(alignmentKey: 5)
    public static let bottom = VerticalAlignment(alignmentKey: 13)
    public static let firstTextBaseline = VerticalAlignment(alignmentKey: 15)
    public static let lastTextBaseline = VerticalAlignment(alignmentKey: 17)
}

public struct Alignment: Equatable {
    public var horizontal: HorizontalAlignment
    public var vertical: VerticalAlignment

    public init(horizontal: HorizontalAlignment, vertical: VerticalAlignment) {
        self.horizontal = horizontal
        self.vertical = vertical
    }

    public static let center = Alignment(horizontal: .center, vertical: .center)
    public static let leading = Alignment(horizontal: .leading, vertical: .center)
    public static let trailing = Alignment(horizontal: .trailing, vertical: .center)

    public static let top = Alignment(horizontal: .center, vertical: .top)
    public static let bottom = Alignment(horizontal: .center, vertical: .bottom)

    public static let topLeading = Alignment(horizontal: .leading, vertical: .top)
    public static let topTrailing = Alignment(horizontal: .trailing, vertical: .top)

    public static let bottomLeading = Alignment(horizontal: .leading, vertical: .bottom)
    public static var bottomTrailing = Alignment(horizontal: .trailing, vertical: .bottom)
}
