//
//  File: LayoutSubview.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

import Foundation

public struct LayoutSubview: Equatable {

    public func _trait<K>(key: K.Type) -> K.Value where K: _ViewTraitKey {
        view.trait(key: key)
    }

    public subscript<K>(key: K.Type) -> K.Value where K: LayoutValueKey {
        _trait(key: _LayoutTrait<K>.self)
    }

    public var priority: Double {
        _trait(key: LayoutPriorityTraitKey.self)
    }

    public func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        view.sizeThatFits(proposal)
    }

    public func dimensions(in proposal: ProposedViewSize) -> ViewDimensions {
        view.dimensions(in: proposal)
    }

    public var spacing: ViewSpacing {
        view.spacing
    }

    public func place(at position: CGPoint, anchor: UnitPoint = .topLeading, proposal: ProposedViewSize) {
        view.place(at: position, anchor: anchor, proposal: proposal)
    }

    public static func == (a: LayoutSubview, b: LayoutSubview) -> Bool {
        a.view === b.view
    }

    let view: ViewContext
    init(view: ViewContext) {
        self.view = view
    }
}

public struct LayoutSubviews: Equatable, RandomAccessCollection {
    public typealias SubSequence = LayoutSubviews
    public typealias Element = LayoutSubview
    public typealias Index = Int
    public typealias Indices = Range<LayoutSubviews.Index>
    public typealias Iterator = IndexingIterator<LayoutSubviews>

    public var layoutDirection: LayoutDirection
    public var startIndex: Int { subviews.startIndex }
    public var endIndex: Int { subviews.endIndex }

    let subviews: [LayoutSubview]
    init<S>(subviews: S, layoutDirection: LayoutDirection) where S: Sequence, S.Element == Self.Element {
        self.subviews = .init(subviews)
        self.layoutDirection = layoutDirection
    }

    public subscript(index: Int) -> LayoutSubviews.Element {
        subviews[index]
    }

    public subscript(bounds: Range<Int>) -> LayoutSubviews {
        .init(subviews: subviews[bounds], layoutDirection: layoutDirection)
    }

    public subscript<S>(indices: S) -> LayoutSubviews where S: Sequence, S.Element == Int {
        var items: [LayoutSubview] = []
        for i in indices {
            items.append(self.subviews[i])
        }
        return .init(subviews: items, layoutDirection: layoutDirection)
    }
}
