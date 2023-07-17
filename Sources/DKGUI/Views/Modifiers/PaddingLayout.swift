//
//  File: PaddingLayout.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import Foundation

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

extension _PaddingLayout: _ViewLayoutModifier {
    class _PaddingLayoutViewProxy: ViewProxy {
        let layout: _PaddingLayout
        let view: ViewProxy

        init(layout: _PaddingLayout, view: ViewProxy, inputs: _ViewInputs) {
            self.layout = layout
            self.view = view
            super.init(inputs: inputs, subviews: [self.view])
        }

        override func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
            var size = self.view.sizeThatFits(proposal)
            if let insets = self.layout.insets {
                if self.layout.edges.contains(.leading) {
                    size.width += insets.leading
                }
                if self.layout.edges.contains(.trailing) {
                    size.width += insets.trailing
                }
                if self.layout.edges.contains(.top) {
                    size.height += insets.top
                }
                if self.layout.edges.contains(.bottom) {
                    size.height += insets.bottom
                }
            }
            return size
        }

        override func layoutSubviews() {
            let bounds = self.frame
            var minX = bounds.minX
            var maxX = bounds.maxX
            var minY = bounds.minY
            var maxY = bounds.maxY
            if let insets = self.layout.insets {
                if self.layout.edges.contains(.leading) {
                    minX += insets.leading
                }
                if self.layout.edges.contains(.trailing) {
                    maxX -= insets.trailing
                }
                if self.layout.edges.contains(.top) {
                    minY += insets.top
                }
                if self.layout.edges.contains(.bottom) {
                    maxY -= insets.bottom
                }
            }
            let origin = CGPoint(x: minX, y: minY)
            let width = max(maxX - minX, 0)
            let height = max(maxY - minY, 0)

            let proposal = ProposedViewSize(width: width, height: height)
            self.view.place(at: origin,
                            anchor: .topLeading,
                            proposal: proposal)
        }
    }

    func makeLayoutViewProxy(content view: ViewProxy, inputs: _ViewInputs) -> ViewProxy {
        _PaddingLayoutViewProxy(layout: self, view: view, inputs: inputs)
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
