//
//  File: FrameLayout.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import Foundation

public struct _FrameLayout: ViewModifier, Animatable {
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

extension _FrameLayout: _ViewLayoutModifier {
    class _FrameLayoutViewProxy: GenericViewProxy {
        let layout: _FrameLayout
        let view: ViewProxy

        init(layout: _FrameLayout, view: ViewProxy, inputs: _ViewInputs) {
            self.layout = layout
            self.view = view
            super.init(inputs: inputs, body: self.view)
        }

        override func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
            var size = self.view.sizeThatFits(proposal)
            if let w = self.layout.width { size.width = w }
            if let h = self.layout.height { size.height = h }
            return size
        }

        override func layoutSubviews() {
            let midX = frame.midX
            let midY = frame.midY
            let width = frame.width
            let height = frame.height

            let proposal = ProposedViewSize(width: width, height: height)
            self.view.place(at: CGPoint(x: midX, y: midY),
                            anchor: .center,
                            proposal: proposal)
        }
    }

    func makeLayoutViewProxy(content view: ViewProxy, inputs: _ViewInputs) -> ViewProxy {
        _FrameLayoutViewProxy(layout: self, view: view, inputs: inputs)
    }
}

extension View {
    @inlinable public func frame(width: CGFloat? = nil,
                                 height: CGFloat? = nil,
                                 alignment: Alignment = .center) -> some View {
        return modifier(
            _FrameLayout(width: width, height: height, alignment: alignment))
    }
}
