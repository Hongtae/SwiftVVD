//
//  File: Spacer.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import Foundation

public struct Spacer: View {
    public var minLength: CGFloat?
    public init(minLength: CGFloat? = nil) {
        self.minLength = minLength
    }

    public typealias Body = Never
}

extension Spacer: _PrimitiveView {
}

extension Spacer: _ViewProxyProvider {
    func makeViewProxy(inputs: _ViewInputs) -> ViewProxy {
        SpacerProxy(view: self, inputs: inputs)
    }
}

class SpacerProxy: ViewProxy {
    var view: Spacer
    var stackOrientation: Axis = .vertical

    init(view: Spacer, inputs: _ViewInputs) {
        self.view = inputs.environmentValues._resolve(view)
        super.init(inputs: inputs)
    }

    override func setLayoutProperties(_ prop: LayoutProperties) {
        self.stackOrientation = prop.stackOrientation ?? .vertical
    }

    override func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        if proposal == .zero { return .zero }

        var size: CGSize = .zero
        if let minLength = view.minLength {
            size = proposal.replacingUnspecifiedDimensions(by: CGSize(width: minLength, height: minLength))
            size.width = max(size.width, minLength)
            size.height = max(size.height, minLength)
        } else {
            size = proposal.replacingUnspecifiedDimensions()
        }

        if self.stackOrientation == .horizontal {
            size.height = 0
        } else {
            size.width = 0
        }
        return size
    }
}

public struct Divider: View {
    public init() {
    }

    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        let view = view.value.makeViewProxy(inputs: inputs)
        return _ViewOutputs(item: .view(view))
    }

    public typealias Body = Never
}

extension Divider: _PrimitiveView {
}

extension Divider: _ViewProxyProvider {
    func makeViewProxy(inputs: _ViewInputs) -> ViewProxy {
        DividerProxy(view: self, inputs: inputs)
    }
}

class DividerProxy: ViewProxy {
    var view: Divider
    var stackOrientation: Axis = .vertical

    init(view: Divider, inputs: _ViewInputs) {
        self.view = inputs.environmentValues._resolve(view)
        super.init(inputs: inputs)
    }

    override func setLayoutProperties(_ prop: LayoutProperties) {
        self.stackOrientation = prop.stackOrientation ?? .vertical
    }

    override func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        var s = proposal.replacingUnspecifiedDimensions()
        if self.stackOrientation == .horizontal {
            s.width = 1
        } else {
            s.height = 1
        }
        return s
    }

    override func draw(frame: CGRect, context: GraphicsContext) {
        var path = Path()
        if self.stackOrientation == .horizontal {
            path.move(to: CGPoint(x: frame.midX, y: frame.minY))
            path.addLine(to: CGPoint(x: frame.midX, y: frame.maxY))
        } else {
            path.move(to: CGPoint(x: frame.minX, y: frame.midY))
            path.addLine(to: CGPoint(x: frame.maxX, y: frame.midY))
        }
        context.stroke(path, with: .color(.gray), style: StrokeStyle())
    }
}
