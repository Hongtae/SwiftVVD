//
//  File: ViewDimensions.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

public struct ViewDimensions: Equatable {
    public internal(set) var width: CGFloat = 0
    public internal(set) var height: CGFloat = 0

    var explicitAlignments: [AlignmentKey: CGFloat] = [:]

    init(width: CGFloat = 0, height: CGFloat = 0, alignments: [AlignmentKey: CGFloat] = [:]) {
        self.width = width
        self.height = height
        self.explicitAlignments = alignments
    }

    public subscript(guide: HorizontalAlignment) -> CGFloat {
        if let value = explicitAlignments[guide.key] {
            return value
        }
        if guide == .leading { return 0 }
        if guide == .center { return width * 0.5 }
        if guide == .trailing { return width }
        return width * 0.5
    }

    public subscript(guide: VerticalAlignment) -> CGFloat {
        if let value = explicitAlignments[guide.key] {
            return value
        }
        if guide == .top { return 0 }
        if guide == .center { return height * 0.5 }
        if guide == .bottom { return height }
        if guide == .firstTextBaseline { return height }
        if guide == .lastTextBaseline { return height }
        return height * 0.5
    }

    public subscript(explicit guide: HorizontalAlignment) -> CGFloat? {
        explicitAlignments[guide.key]
    }
    public subscript(explicit guide: VerticalAlignment) -> CGFloat? {
        explicitAlignments[guide.key]
    }
}
