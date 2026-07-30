//
//  File: ViewDimensions.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

/// Layout dimensions for a child view: guide-computer + resolved size.
/// Alignment guide subscripts delegate to guideComputer.explicitAlignment, falling back
/// to the default guide position computed from size.
public struct ViewDimensions: Equatable {
    /// The layout computer of the child view, used to compute explicit alignment guides.
    var guideComputer: LayoutComputer

    /// The child's resolved size (actual width/height + proposal).
    var size: ViewSize

    // MARK: - Computed accessors

    public var width:  CGFloat { size.width }
    public var height: CGFloat { size.height }

    // MARK: - Alignment guide subscripts

    public subscript(guide: HorizontalAlignment) -> CGFloat {
        self[guide.key]
    }

    public subscript(guide: VerticalAlignment) -> CGFloat {
        self[guide.key]
    }

    public subscript(explicit guide: HorizontalAlignment) -> CGFloat? {
        self[explicit: guide.key]
    }

    public subscript(explicit guide: VerticalAlignment) -> CGFloat? {
        self[explicit: guide.key]
    }

    subscript(_ key: AlignmentKey) -> CGFloat {
        if let explicit = self[explicit: key] {
            return explicit
        }
        return key.defaultValue(in: self)
    }

    subscript(explicit key: AlignmentKey) -> CGFloat? {
        guideComputer.explicitAlignment(key, at: size)
    }

    // MARK: - Initializers

    /// Primary initializer: direct guideComputer + size storage.
    init(guideComputer: LayoutComputer, size: ViewSize) {
        self.guideComputer = guideComputer
        self.size = size
    }

    /// Convenience init for places that only know width/height (no explicit alignments).
    /// Creates a stub ClosureLayoutEngine that returns the given size.
    public init(width: CGFloat, height: CGFloat) {
        let cgSize = CGSize(width: width, height: height)
        let lc = LayoutComputer.fixed(cgSize)
        self.guideComputer = lc
        self.size = ViewSize(cgSize)
    }

    public static func == (lhs: ViewDimensions, rhs: ViewDimensions) -> Bool {
        lhs.guideComputer == rhs.guideComputer && lhs.size == rhs.size
    }
}
