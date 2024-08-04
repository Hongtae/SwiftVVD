//
//  File: PaddingLayout.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2024 Hongtae Kim. All rights reserved.
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

extension _PaddingLayout: _ViewLayoutModifier {
    private class LayoutViewContext : ViewModifierContext<_PaddingLayout> {
        var layout: _PaddingLayout { modifier }

        override init(content: ViewContext, modifier: _PaddingLayout, inputs: _GraphInputs, graph: _GraphValue<_PaddingLayout>) {
            super.init(content: content, modifier: modifier, inputs: inputs, graph: graph)
        }

        override func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
            var paddingH: CGFloat = .zero
            var paddingV: CGFloat = .zero
            if let insets = self.layout.insets {
                if self.layout.edges.contains(.leading) {
                    paddingH += insets.leading
                }
                if self.layout.edges.contains(.trailing) {
                    paddingH += insets.trailing
                }
                if self.layout.edges.contains(.top) {
                    paddingV += insets.top
                }
                if self.layout.edges.contains(.bottom) {
                    paddingV += insets.bottom
                }
            }
            var proposal = proposal
            if let w = proposal.width {
                proposal.width = max(w - paddingH, 0)
            }
            if let h = proposal.height {
                proposal.height = max(h - paddingV, 0)
            }
            let size = self.content.sizeThatFits(proposal)
            return CGSize(width: max(size.width + paddingH, 0),
                          height: max(size.height + paddingV, 0))
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
            self.content.place(at: origin,
                               anchor: .topLeading,
                               proposal: proposal)
        }
    }

    private struct LayoutViewGenerator : ViewGenerator {
        var content: any ViewGenerator
        let graph: _GraphValue<_PaddingLayout>
        var baseInputs: _GraphInputs

        func makeView<T>(encloser: T, graph: _GraphValue<T>) -> ViewContext? {
            if let content = self.content.makeView(encloser: encloser, graph: graph) {
                if let modifier = graph.value(atPath: self.graph, from: encloser) {
                    return LayoutViewContext(content: content, modifier: modifier, inputs: baseInputs, graph: self.graph)
                }
                fatalError("Unable to recover modifier")
            }
            return nil
        }
        
        mutating func mergeInputs(_ inputs: _GraphInputs) {
            content.mergeInputs(inputs)
            baseInputs.mergedInputs.append(inputs)
        }
    }

    static func _makeView(modifier: _GraphValue<_PaddingLayout>, content: any ViewGenerator, inputs: _GraphInputs) -> any ViewGenerator {
        LayoutViewGenerator(content: content, graph: modifier, baseInputs: inputs)
    }

    static func _makeViewList(modifier: _GraphValue<_PaddingLayout>, content: any ViewListGenerator, inputs: _GraphInputs) -> any ViewListGenerator {
        struct Generator : ViewListGenerator {
            var content: any ViewListGenerator
            let graph: _GraphValue<_PaddingLayout>
            var baseInputs: _GraphInputs

            func makeViewList<T>(encloser: T, graph: _GraphValue<T>) -> [any ViewGenerator] {
                content.makeViewList(encloser: encloser, graph: graph).map {
                    LayoutViewGenerator(content: $0, graph: self.graph, baseInputs: self.baseInputs)
                }
            }

            mutating func mergeInputs(_ inputs: _GraphInputs) {
                content.mergeInputs(inputs)
                baseInputs.mergedInputs.append(inputs)
            }
        }
        return Generator(content: content, graph: modifier, baseInputs: inputs)
    }
}
