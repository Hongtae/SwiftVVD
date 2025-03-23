//
//  File: FrameLayout.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
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
        override func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
            guard let modifier else { fatalError("Invalid view modifier") }

            var size = self.body.sizeThatFits(proposal)
            if let w = modifier.width { size.width = w }
            if let h = modifier.height { size.height = h }
            return size
        }

        override func layoutSubviews() {
            let frame = self.bounds
            let midX = frame.midX
            let midY = frame.midY
            let width = frame.width
            let height = frame.height

            let proposal = ProposedViewSize(width: width, height: height)
            self.body.place(at: CGPoint(x: midX, y: midY),
                            anchor: .center,
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
