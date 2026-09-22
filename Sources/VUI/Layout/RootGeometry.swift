//
//  File: RootGeometry.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

/// Carries root safe-area reductions and the deferred inset value for descendants.
struct _SafeAreaInsetsModifier: Equatable {
    var elements: [SafeAreaInsets.Element]
    var nextInsets: SafeAreaInsets.OptionalValue?

    init() {
        elements = []
        nextInsets = nil
    }

    init(
        elements: [SafeAreaInsets.Element],
        nextInsets: SafeAreaInsets.OptionalValue?
    ) {
        self.elements = elements
        self.nextInsets = nextInsets
    }
}

extension _SafeAreaInsetsModifier {
    struct Transform: Rule, AsyncAttribute {
        var space: CoordinateSpace.ID
        var _transform: Attribute<ViewTransform>
        var _position: Attribute<CGPoint>
        var _size: Attribute<ViewSize>

        var value: ViewTransform {
            var value = _transform.value
            value.appendPosition(_position.value)
            value.appendSizedSpace(id: space, size: _size.value.value)
            return value
        }
    }
}

/// Measures the root child inside safe-area bounds and publishes its initial geometry.
struct RootGeometry: Rule, AsyncAttribute {
    var layoutDirection: OptionalAttribute<LayoutDirection>
    var proposedSize: Attribute<ViewSize>
    var safeAreaInsets: OptionalAttribute<_SafeAreaInsetsModifier>
    var childLayoutComputer: OptionalAttribute<LayoutComputer>

    init(
        layoutDirection: OptionalAttribute<LayoutDirection> = OptionalAttribute(),
        proposedSize: Attribute<ViewSize>,
        safeAreaInsets: OptionalAttribute<_SafeAreaInsetsModifier> = OptionalAttribute(),
        childLayoutComputer: OptionalAttribute<LayoutComputer> = OptionalAttribute()
    ) {
        self.layoutDirection = layoutDirection
        self.proposedSize = proposedSize
        self.safeAreaInsets = safeAreaInsets
        self.childLayoutComputer = childLayoutComputer
    }

    var value: ViewGeometry {
        let layoutComputer =
            childLayoutComputer.value ?? LayoutComputer.defaultValue
        let direction = layoutDirection.value

        var top: CGFloat = 0
        var leading: CGFloat = 0
        var bottom: CGFloat = 0
        var trailing: CGFloat = 0
        if let safeAreaInsets = safeAreaInsets.value {
            for element in safeAreaInsets.elements {
                top += element.insets.top
                leading += element.insets.leading
                bottom += element.insets.bottom
                trailing += element.insets.trailing
            }
        }
        if direction == .rightToLeft {
            swap(&leading, &trailing)
        }

        let proposedSize = proposedSize.value
        let availableSize = CGSize(
            width: max(proposedSize.width - leading - trailing, 0),
            height: max(proposedSize.height - top - bottom, 0)
        )
        let proposal = _ProposedSize(availableSize)
        let fittedSize = layoutComputer.sizeThatFits(proposal)
        var geometry = ViewGeometry(
            origin: CGPoint(x: leading, y: top),
            dimensions: ViewDimensions(
                guideComputer: layoutComputer,
                size: ViewSize(fittedSize, proposal: proposal)
            )
        )

        guard let viewGraph = GraphHost.currentHost as? ViewGraph else {
            fatalError("RootGeometry requires an active ViewGraph host.")
        }
        if viewGraph.centersRootView {
            geometry.origin.x += (availableSize.width - fittedSize.width) * 0.5
            geometry.origin.y += (availableSize.height - fittedSize.height) * 0.5
        }
        if let direction {
            geometry.finalizeLayoutDirection(
                direction,
                parentSize: proposedSize.value
            )
        }
        return geometry
    }
}

extension Attribute where Value == ViewGeometry {
    func origin() -> Attribute<CGPoint> {
        unsafeOffset(at: 0, as: CGPoint.self)
    }

    func size() -> Attribute<ViewSize> {
        unsafeOffset(at: 32, as: ViewSize.self)
    }
}

extension ViewGeometry {
    mutating func finalizeLayoutDirection(
        _ layoutDirection: LayoutDirection,
        parentSize: CGSize
    ) {
        guard layoutDirection == .rightToLeft else {
            return
        }
        origin.x = parentSize.width - origin.x - dimensions.width
    }
}

extension CachedEnvironment.ID {
    static let layoutDirection = CachedEnvironment.ID(base: UniqueID())
}
