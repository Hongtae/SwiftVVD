//
//  File: PaddingLayout.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

import Foundation

public struct _PaddingLayout : ViewModifier, Animatable {
    public var edges: Edge.Set
    public var insets: EdgeInsets?
    @inlinable public init(edges: Edge.Set = .all, insets: EdgeInsets?) {
        self.edges = edges
        self.insets = insets
    }
    public typealias AnimatableData = EmptyAnimatableData
    public typealias Body = Never
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

struct DefaultPaddingEdgeInsetsPropertyItem : PropertyItem {
    static var defaultValue: EdgeInsets { .init(_all: 16) }
    let insets: EdgeInsets
    var description: String {
        "DefaultPaddingEdgeInsetsPropertyItem: \(self.insets)"
    }
}

extension _PaddingLayout : _ViewLayoutModifier {
    private class LayoutViewContext : ViewModifierContext<_PaddingLayout> {
        var layoutInsets : EdgeInsets {
            if let insets = self.modifier?.insets {
                return insets
            }
            if let insets = self.inputs.properties.find(type: DefaultPaddingEdgeInsetsPropertyItem.self)?.insets {
                return insets
            }
            return DefaultPaddingEdgeInsetsPropertyItem.defaultValue
        }

        override func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
            guard let modifier else { fatalError("Invalid view modifier") }

            var paddingH: CGFloat = .zero
            var paddingV: CGFloat = .zero

            let insets = self.layoutInsets
            if modifier.edges.contains(.leading) {
                paddingH += insets.leading
            }
            if modifier.edges.contains(.trailing) {
                paddingH += insets.trailing
            }
            if modifier.edges.contains(.top) {
                paddingV += insets.top
            }
            if modifier.edges.contains(.bottom) {
                paddingV += insets.bottom
            }

            var proposal = proposal
            if let w = proposal.width {
                proposal.width = max(w - paddingH, 0)
            }
            if let h = proposal.height {
                proposal.height = max(h - paddingV, 0)
            }
            let size = self.body.sizeThatFits(proposal)
            return CGSize(width: max(size.width + paddingH, 0),
                          height: max(size.height + paddingV, 0))
        }

        override func layoutSubviews() {
            guard let modifier else { fatalError("Invalid view modifier") }

            let frame = self.bounds
            var minX = frame.minX
            var maxX = frame.maxX
            var minY = frame.minY
            var maxY = frame.maxY

            let insets = self.layoutInsets
            if modifier.edges.contains(.leading) {
                minX += insets.leading
            }
            if modifier.edges.contains(.trailing) {
                maxX -= insets.trailing
            }
            if modifier.edges.contains(.top) {
                minY += insets.top
            }
            if modifier.edges.contains(.bottom) {
                maxY -= insets.bottom
            }

            let origin = CGPoint(x: minX, y: minY)
            let width = max(maxX - minX, 0)
            let height = max(maxY - minY, 0)

            let proposal = ProposedViewSize(width: width, height: height)
            self.body.place(at: origin,
                            anchor: .topLeading,
                            proposal: proposal)
        }
    }

    static func _makeLayoutView(modifier: _GraphValue<Self>, inputs: _ViewInputs, content: any ViewGenerator) -> any ViewGenerator {
        let body = content.makeView()
        return UnaryViewGenerator(baseInputs: inputs.base) { inputs in
            LayoutViewContext(graph: modifier, body: body, inputs: inputs)
        }
    }
}
