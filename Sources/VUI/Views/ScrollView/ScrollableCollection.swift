//
//  File: ScrollableCollection.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import CoreGraphics

/// Bitset describing scrollable child groups that should stay pinned.
struct PinnedScrollableViews: OptionSet, Hashable, Sendable {
    var rawValue: UInt32

    init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    static let sectionHeaders = PinnedScrollableViews(rawValue: 1)
    static let sectionFooters = PinnedScrollableViews(rawValue: 2)
}

/// Accessibility grouping role exposed by scrollable collection hosts.
enum AccessibilityLayoutRole: Hashable, Sendable {
    case stack
    case grid
}

/// Geometry snapshot for one visible subview in a scrollable collection.
struct ScrollableCollectionSubview {
    var id: _ViewList_ID
    var frame: CGRect
    var frameInContent: CGRect
    var transform: ViewTransform

    init(
        id: _ViewList_ID,
        frame: CGRect,
        frameInContent: CGRect,
        transform: ViewTransform
    ) {
        self.id = id
        self.frame = frame
        self.frameInContent = frameInContent
        self.transform = transform
    }
}

/// Scrollable host that can enumerate and address collection-style child views.
protocol ScrollableCollection: Scrollable {
    var visibleCollectionViewIDs: [_ViewList_ID.Canonical] { get }
    func forEachVisibleSubview(_ body: (ScrollableCollectionSubview, inout Bool) -> Void)
    func subviewClosest(to rect: CGRect) -> ScrollableCollectionSubview?
    func nextVisibleCollectionViewID(
        towards point: UnitPoint,
        from id: _ViewList_ID.Canonical,
        border: CGSize,
        ignoring pinnedViews: PinnedScrollableViews
    ) -> _ViewList_ID.Canonical?
    static func hasMultipleViews(in axis: Axis) -> Bool
    func firstCollectionViewIndex(of id: _ViewList_ID.Canonical) -> Int?
    func applyCollectionViewIDs(
        from index: inout Int,
        to body: (_ViewList_ID.Canonical, inout Bool) -> Void
    ) -> Bool
    func collectionViewID(for subgraph: AGSubgraph) -> _ViewList_ID.Canonical?
    func scroll(toCollectionViewID id: _ViewList_ID.Canonical, anchor: UnitPoint?) -> Bool
    static var accessibilityRole: AccessibilityLayoutRole? { get }
    var isLazy: Bool { get }
}

extension ScrollableCollection {
    static var accessibilityRole: AccessibilityLayoutRole? { nil }

    var isLazy: Bool { false }

    var visibleSubviews: [ScrollableCollectionSubview] {
        var subviews: [ScrollableCollectionSubview] = []
        forEachVisibleSubview { subview, stop in
            subviews.append(subview)
            stop = false
        }
        return subviews
    }

    func scroll<ID>(to id: ID) -> Bool where ID: Hashable {
        scroll(
            toCollectionViewID: _ViewList_ID(explicitID: AnyHashable(id)).canonicalID,
            anchor: Transaction.current.scrollTargetAnchor
        )
    }
}

/// Collects scrollable hosts exposed by descendants.
struct ScrollablePreferenceKey: PreferenceKey {
    static var defaultValue: [any Scrollable] { [] }

    static func reduce(value: inout [any Scrollable], nextValue: () -> [any Scrollable]) {
        value.append(contentsOf: nextValue())
    }
}

/// Publishes a single scrollable host as a preference value.
struct UnaryScrollablePreferenceProvider: Rule {
    typealias Value = [any Scrollable]

    var scrollable: Attribute<any Scrollable>

    init(scrollable: Attribute<any Scrollable>) {
        self.scrollable = scrollable
    }

    func updateValue() -> [any Scrollable] {
        [scrollable.value]
    }
}
