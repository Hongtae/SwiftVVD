//
//  File: Spacer.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2024 Hongtae Kim. All rights reserved.
//

import Foundation

public struct Spacer : View {
    public var minLength: CGFloat?
    public init(minLength: CGFloat? = nil) {
        self.minLength = minLength
    }

    public typealias Body = Never
}

extension Spacer : Sendable {}
extension Spacer : _PrimitiveView {
    static func _makeView(view: _GraphValue<Self>, sharedContext: SharedContext) -> _ViewOutputs {
        struct Generator : ViewGenerator {
            let graph: _GraphValue<Spacer>
            var baseInputs: _GraphInputs
            var acceptsModifiers: Bool { false }

            func makeView<T>(encloser: T, graph: _GraphValue<T>) -> ViewContext? {
                if let view = graph.value(atPath: self.graph, from: encloser) {
                    return SpacerViewContext(view: view, inputs: baseInputs, graph: self.graph)
                }
                fatalError("Unable to recover view")
            }

            func mergeInputs(_ inputs: _GraphInputs) {}
        }
        let baseInputs = _GraphInputs(environment: .init(), sharedContext: sharedContext)
        let generator = Generator(graph: view, baseInputs: baseInputs)
        return _ViewOutputs(view: generator, preferences: PreferenceOutputs(preferences: []))
    }
}

public struct Divider : View {
    public init() {
    }

    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        struct Generator : ViewGenerator {
            let graph: _GraphValue<Divider>
            var baseInputs: _GraphInputs
            var acceptsModifiers: Bool { false }

            func makeView<T>(encloser: T, graph: _GraphValue<T>) -> ViewContext? {
                if let view = graph.value(atPath: self.graph, from: encloser) {
                    return DividerViewContext(view: view, inputs: baseInputs, graph: self.graph)
                }
                fatalError("Unable to recover view")
            }

            func mergeInputs(_ inputs: _GraphInputs) {}
        }
        let generator = Generator(graph: view, baseInputs: inputs.base)
        return _ViewOutputs(view: generator, preferences: PreferenceOutputs(preferences: []))
    }

    public typealias Body = Never
}

extension Divider : _PrimitiveView {}

private class SpacerViewContext : ViewContext {
    var view: Spacer
    var stackOrientation: Axis = .vertical

    init(view: Spacer, inputs: _GraphInputs, graph: _GraphValue<Spacer>) {
        self.view = view
        super.init(inputs: inputs, graph: graph)
    }

    override func validatePath<T>(encloser: T, graph: _GraphValue<T>) -> Bool {
        graph.value(atPath: self.graph, from: encloser) is Spacer
    }

    override func updateContent<T>(encloser: T, graph: _GraphValue<T>) {
        if let view = graph.value(atPath: self.graph, from: encloser) as? Spacer {
            self.view = view
        } else {
            fatalError("Unable to recover Spacer")
        }
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

private class DividerViewContext : ViewContext {
    var view: Divider
    var stackOrientation: Axis = .vertical

    init(view: Divider, inputs: _GraphInputs, graph: _GraphValue<Divider>) {
        self.view = view
        super.init(inputs: inputs, graph: graph)
    }

    override func validatePath<T>(encloser: T, graph: _GraphValue<T>) -> Bool {
        graph.value(atPath: self.graph, from: encloser) is Divider
    }

    override func updateContent<T>(encloser: T, graph: _GraphValue<T>) {
        if let view = graph.value(atPath: self.graph, from: encloser) as? Divider {
            self.view = view
        } else {
            fatalError("Unable to recover Divider")
        }
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
