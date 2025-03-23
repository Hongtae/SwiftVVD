//
//  File: Spacer.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

import Foundation

public struct Spacer : View {
    public var minLength: CGFloat?
    public init(minLength: CGFloat? = nil) {
        self.minLength = minLength
    }

    public typealias Body = Never
}

extension Spacer : Sendable {
}

extension Spacer : _PrimitiveView {
    static func _makeView(view: _GraphValue<Self>) -> _ViewOutputs {
        let baseInputs = _GraphInputs(environment: .init())
        let view = UnaryViewGenerator(baseInputs: baseInputs) { inputs in
            SpacerViewContext(graph: view, inputs: inputs)
        }
        return _ViewOutputs(view: view)
    }
}

public struct Divider : View {
    public init() {
    }

    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        let view = UnaryViewGenerator(baseInputs: inputs.base) { inputs in
            DividerViewContext(graph: view, inputs: inputs)
        }
        return _ViewOutputs(view: view)
    }

    public typealias Body = Never
}

extension Divider : _PrimitiveView {
}

private class SpacerViewContext : PrimitiveViewContext<Spacer> {
    var stackOrientation: Axis = .vertical

    override func setLayoutProperties(_ prop: LayoutProperties) {
        self.stackOrientation = prop.stackOrientation ?? .vertical
    }

    override func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        if proposal == .zero { return .zero }
        guard let view else { return .zero }

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

private class DividerViewContext : PrimitiveViewContext<Divider> {
    var stackOrientation: Axis = .vertical

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
        super.draw(frame: frame, context: context)

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
