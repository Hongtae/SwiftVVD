//
//  File: PaddingLayout.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

private struct DefaultPaddingKey: EnvironmentKey {
    static var defaultValue: EdgeInsets { EdgeInsets(_all: 16) }
}

extension EnvironmentValues {
    var defaultPadding: EdgeInsets {
        get { self[DefaultPaddingKey.self] }
        set { self[DefaultPaddingKey.self] = newValue }
    }
}

extension CachedEnvironment.ID {
    static let defaultPadding = CachedEnvironment.ID(base: UniqueID())
}

extension _GraphInputs {
    var defaultPadding: Attribute<EdgeInsets> {
        cachedEnvironment.value.attribute(id: .defaultPadding) {
            $0.defaultPadding
        }
    }
}

extension _ViewInputs {
    var defaultPadding: Attribute<EdgeInsets> {
        base.defaultPadding
    }
}

public struct _PaddingLayout: ViewModifier, Animatable {
    public var edges: Edge.Set
    public var insets: EdgeInsets?
    @inlinable public init(edges: Edge.Set = .all, insets: EdgeInsets?) {
        self.edges = edges
        self.insets = insets
    }
    public typealias AnimatableData = EmptyAnimatableData
    public typealias Body = Never
}

extension _PaddingLayout: Sendable {}

extension _PaddingLayout: UnaryLayout {
    private func effectiveInsets(in context: SizeAndSpacingContext) -> EdgeInsets {
        let resolved = insets ?? context.defaultPadding
        return EdgeInsets(
            top: edges.contains(.top) ? resolved.top : 0,
            leading: edges.contains(.leading) ? resolved.leading : 0,
            bottom: edges.contains(.bottom) ? resolved.bottom : 0,
            trailing: edges.contains(.trailing) ? resolved.trailing : 0
        )
    }

    func sizeThatFits(
        in proposal: _ProposedSize,
        context: SizeAndSpacingContext,
        child: LayoutProxy
    ) -> CGSize {
        let insets = effectiveInsets(in: context)
        let horizontal = insets.leading + insets.trailing
        let vertical = insets.top + insets.bottom
        let childProposal = _ProposedSize(
            width: proposal.width.map { max(0, $0 - horizontal) },
            height: proposal.height.map { max(0, $0 - vertical) }
        )
        let childSize = child.dimensions(in: childProposal).size.value
        return CGSize(
            width: max(0, childSize.width + horizontal),
            height: max(0, childSize.height + vertical)
        )
    }

    func placement(of child: LayoutProxy, in context: PlacementContext) -> _Placement {
        let insets = effectiveInsets(in: SizeAndSpacingContext(
            context: context.context,
            owner: context.owner,
            environment: context._environment
        ))
        let horizontal = insets.leading + insets.trailing
        let vertical = insets.top + insets.bottom
        let proposal = _ProposedSize(
            width: context.proposedSize.width.map { max(0, $0 - horizontal) },
            height: context.proposedSize.height.map { max(0, $0 - vertical) }
        )
        return _Placement(
            proposedSize: proposal,
            anchoring: .topLeading,
            at: CGPoint(x: insets.leading, y: insets.top)
        )
    }

    func spacing(
        in context: SizeAndSpacingContext,
        child: LayoutProxy
    ) -> Spacing {
        var spacing = child.layoutComputer.spacing()
        let insets = effectiveInsets(in: context)
        var insetEdges: Edge.Set = []
        if insets.top != 0 { insetEdges.insert(.top) }
        if insets.leading != 0 { insetEdges.insert(.leading) }
        if insets.bottom != 0 { insetEdges.insert(.bottom) }
        if insets.trailing != 0 { insetEdges.insert(.trailing) }
        spacing.reset(insetEdges, layoutDirection: context.layoutDirection)
        return spacing
    }

    func ignoresAutomaticPadding(child: LayoutProxy) -> Bool {
        true
    }

}

extension View {
    @inlinable public func padding(_ insets: EdgeInsets) -> some View {
        return modifier(_PaddingLayout(insets: insets))
    }

    @inlinable public func padding(_ edges: Edge.Set = .all, _ length: CGFloat? = nil) -> some View {
        let insets = length.map { EdgeInsets(_all: $0) }
        return modifier(_PaddingLayout(edges: edges, insets: insets))
    }

    @inlinable public func padding(_ length: CGFloat) -> some View {
        return padding(.all, length)
    }
}
