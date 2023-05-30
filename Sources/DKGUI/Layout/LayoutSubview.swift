//
//  File: LayoutSubview.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import Foundation

public protocol LayoutValueKey {
    associatedtype Value
    static var defaultValue: Self.Value { get }
}

public struct LayoutSubview: Equatable {

    public subscript<K>(key: K.Type) -> K.Value where K: LayoutValueKey {
        viewProxy.layoutValue(key)
    }

    public var priority: Double { 0 }

    public func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        viewProxy.sizeThatFits(proposal)
    }

    public func dimensions(in proposal: ProposedViewSize) -> ViewDimensions {
        let layoutSize = viewProxy.layoutSize
        let size = proposal.replacingUnspecifiedDimensions(by: layoutSize)
        return .init(height: size.width, width: size.height)
    }

    public var spacing: ViewSpacing {
        .init()
    }

    public func place(at position: CGPoint, anchor: UnitPoint = .topLeading, proposal: ProposedViewSize) {
        let px = containerSize.width * anchor.x
        let py = containerSize.height * anchor.y
        let offset = CGPoint(x: px + position.x, y: py + position.y)
        let size = proposal.replacingUnspecifiedDimensions(by: viewProxy.layoutSize)
        let scale = viewProxy.contentScaleFactor
        viewProxy.layout(offset: offset, size: size, scaleFactor: scale)
    }

    public static func == (a: LayoutSubview, b: LayoutSubview) -> Bool {
        a.viewProxy === b.viewProxy
    }

    let viewProxy: any ViewProxy
    let containerSize: CGSize
    init(viewProxy: any ViewProxy, containerSize: CGSize) {
        self.viewProxy = viewProxy
        self.containerSize = containerSize
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
