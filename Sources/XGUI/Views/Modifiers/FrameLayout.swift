//
//  File: FrameLayout.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2024 Hongtae Kim. All rights reserved.
//

import Foundation

public struct _FrameLayout : ViewModifier, Animatable {
    var width: CGFloat?
    var height: CGFloat?
    var alignment: Alignment

    @usableFromInline
    init(width: CGFloat?, height: CGFloat?, alignment: Alignment) {
        self.width = width
        self.height = height
        self.alignment = alignment
    }

    public typealias AnimatableData = EmptyAnimatableData
    public typealias Body = Never
}

extension View {
    @inlinable public func frame(width: CGFloat? = nil,
                                 height: CGFloat? = nil,
                                 alignment: Alignment = .center) -> some View {
        return modifier(
            _FrameLayout(width: width, height: height, alignment: alignment))
    }
}

extension _FrameLayout : _ViewLayoutModifier {
    private class LayoutViewContext : ViewModifierContext<_FrameLayout> {
        var layout: _FrameLayout { modifier }

        override init(content: ViewContext, modifier: _FrameLayout, inputs: _GraphInputs, graph: _GraphValue<_FrameLayout>) {
            super.init(content: content, modifier: modifier, inputs: inputs, graph: graph)
        }

        override func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
            var size = self.content.sizeThatFits(proposal)
            if let w = self.layout.width { size.width = w }
            if let h = self.layout.height { size.height = h }
            return size
        }

        override func layoutSubviews() {
            let frame = self.bounds
            let midX = frame.midX
            let midY = frame.midY
            let width = frame.width
            let height = frame.height

            let proposal = ProposedViewSize(width: width, height: height)
            self.content.place(at: CGPoint(x: midX, y: midY),
                               anchor: .center,
                               proposal: proposal)
        }
    }

    private struct LayoutViewGenerator : ViewGenerator {
        var content: any ViewGenerator
        let graph: _GraphValue<_FrameLayout>
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

    static func _makeView(modifier: _GraphValue<_FrameLayout>, content: any ViewGenerator, inputs: _GraphInputs) -> any ViewGenerator {
        LayoutViewGenerator(content: content, graph: modifier, baseInputs: inputs)
    }

    static func _makeViewList(modifier: _GraphValue<_FrameLayout>, content: any ViewListGenerator, inputs: _GraphInputs) -> any ViewListGenerator {
        struct Generator : ViewListGenerator {
            var content: any ViewListGenerator
            let graph: _GraphValue<_FrameLayout>
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
