//
//  File: LayoutSubview.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

/// Internal backing storage for a single `LayoutSubview`.
/// Holds the child's `LayoutComputer` AG node and an optional AG-backed ViewList for traits.
struct LayoutSubviewProxy {
    /// The child's layout-computation node.
    /// Reading `.value` inside a parent layout rule registers a re-layout dependency.
    var layoutComputerAttr: Attribute<LayoutComputer>
    /// AG-backed ViewList for this subview's trait collection.
    /// The ViewList's first generator carries `traitListAttr: OptionalAttribute<ViewTraitCollection>`,
    /// which is the final computed `ViewTraitCollection` for this child.
    /// Non-null whenever `_TraitWritingModifier` is in the `_makeViewList` chain;
    /// also created for children without traits so Layout can uniformly read `_trait(key:)`.
    /// Reading inside a layout rule registers a dependency, so trait changes trigger re-layout.
    var _traitsList: OptionalAttribute<ViewList>

    init(layoutComputerAttr: Attribute<LayoutComputer>,
         traitsList: OptionalAttribute<ViewList> = OptionalAttribute()) {
        self.layoutComputerAttr = layoutComputerAttr
        self._traitsList = traitsList
    }
}

/// A proxy for a single child view, providing the sizing and placement API
/// used by `Layout` implementations.
public struct LayoutSubview: Equatable {

    var proxy: LayoutSubviewProxy

    /// Returns the trait value for the given key.
    /// Reads from the AG-backed ViewList → first generator's traitListAttr → ViewTraitCollection.
    /// Reading inside a layout rule registers a dependency so trait changes trigger re-layout.
    public func _trait<K>(key: K.Type) -> K.Value where K: _ViewTraitKey {
        guard let viewList = proxy._traitsList.attribute?.value else { return K.defaultValue }
        return viewList.generators.first?.traitListAttr.attribute?.value[key] ?? K.defaultValue
    }

    public subscript<K>(key: K.Type) -> K.Value where K: LayoutValueKey {
        _trait(key: _LayoutTrait<K>.self)
    }

    /// The view's layout priority.
    /// Read from the `LayoutComputer` node, which is set by `LayoutPriorityLayout`.
    public var priority: Double {
        proxy.layoutComputerAttr.value.priority
    }

    /// Asks the child for the size that best fits `proposal`.
    /// Reading this inside a parent layout rule registers a dependency on the
    /// child's `LayoutComputer` AG node.
    public func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        proxy.layoutComputerAttr.value.sizeThatFits(proposal)
    }

    /// Returns the child's layout dimensions for `proposal`.
    public func dimensions(in proposal: ProposedViewSize) -> ViewDimensions {
        proxy.layoutComputerAttr.value.dimensions(in: proposal)
    }

    /// The child's preferred spacing to neighbouring views.
    public var spacing: ViewSpacing {
        proxy.layoutComputerAttr.value.spacing
    }

    /// Assigns a final position to the child.
    /// Forwards the call into the child's own `LayoutComputer` for further propagation
    /// and writing to the child's position and size AG nodes.
    public func place(at position: CGPoint, anchor: UnitPoint = .topLeading, proposal: ProposedViewSize) {
        proxy.layoutComputerAttr.value.place(at: position, anchor: anchor, proposal: proposal)
    }

    public static func == (a: LayoutSubview, b: LayoutSubview) -> Bool {
        a.proxy.layoutComputerAttr.identifier == b.proxy.layoutComputerAttr.identifier
    }

    var traitListAttr: OptionalAttribute<ViewTraitCollection> {
        guard let viewList = proxy._traitsList.attribute?.value else { return OptionalAttribute() }
        return viewList.generators.first?.traitListAttr ?? OptionalAttribute()
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
