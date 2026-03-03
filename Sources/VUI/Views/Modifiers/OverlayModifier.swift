//
//  File: OverlayModifier.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

public struct _OverlayModifier<Overlay>: ViewModifier where Overlay: View {
    public let overlay: Overlay
    public let alignment: Alignment

    @inlinable public init(overlay: Overlay, alignment: Alignment = .center) {
        self.overlay = overlay
        self.alignment = alignment
    }

    public static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        guard let graph = AttributeGraph.current else {
            fatalError("\(self)._makeView called outside an active AttributeGraph context.")
        }
        let mainOutputs = body(_Graph(), inputs)
        guard let mainLCAttr = mainOutputs._layoutComputer.attribute else {
            return mainOutputs
        }
        let ovPosAttr = graph.makeInput(value: CGPoint.zero)
        let ovInputs = _ViewInputs(
            base: inputs.base,
            preferences: inputs.preferences,
            transform: inputs.transform,
            position: ovPosAttr,
            containerPosition: inputs.position,
            size: inputs.size,
            safeAreaInsets: inputs.safeAreaInsets,
            containerSize: inputs.containerSize
        )
        let ovOutputs = Overlay._makeView(view: modifier[\.overlay], inputs: ovInputs)
        guard let ovLCAttr = ovOutputs._layoutComputer.attribute else {
            return mainOutputs
        }
        let lcAttr: Attribute<LayoutComputer> = graph.makeRule {
            let m = modifier._attribute.value   // dep: alignment changes
            let mainLC = mainLCAttr.value       // dep: main content changes
            let ovLC = ovLCAttr.value           // dep: overlay changes
            return LayoutComputer(
                sizeThatFits: { proposal in mainLC.sizeThatFits(proposal) },
                spacing: mainLC.spacing,
                dimensions: { proposal in mainLC.dimensions(in: proposal) },
                place: { position, anchor, proposal in
                    mainLC.place(at: position, anchor: anchor, proposal: proposal)
                    let mainSize = mainLC.sizeThatFits(proposal)
                    let ox = position.x - mainSize.width * anchor.x
                    let oy = position.y - mainSize.height * anchor.y
                    let mainDims = mainLC.dimensions(in: proposal)
                    let ovProposal = ProposedViewSize(width: mainSize.width, height: mainSize.height)
                    let ovDims = ovLC.dimensions(in: ovProposal)
                    let ovX = ox + mainDims[m.alignment.horizontal] - ovDims[m.alignment.horizontal]
                    let ovY = oy + mainDims[m.alignment.vertical] - ovDims[m.alignment.vertical]
                    let ovOrigin = CGPoint(x: ovX, y: ovY)
                    ovPosAttr.setValue(ovOrigin)
                    ovLC.place(at: ovOrigin, anchor: .topLeading, proposal: ovProposal)
                }
            )
        }
        return _ViewOutputs(
            preferences: mainOutputs.preferences,
            layoutComputer: OptionalAttribute(lcAttr)
        )
    }
}

extension _OverlayModifier: Equatable where Overlay: Equatable {
}

extension _OverlayModifier {
    public typealias Body = Never

    public static func _makeViewList(modifier: _GraphValue<Self>, inputs: _ViewListInputs, body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs) -> _ViewListOutputs {
        body(_Graph(), inputs)
    }
}

public struct _OverlayStyleModifier<Style>: ViewModifier where Style: ShapeStyle {
    public var style: Style
    public var ignoresSafeAreaEdges: Edge.Set

    @inlinable public init(style: Style, ignoresSafeAreaEdges: Edge.Set) {
        self.style = style
        self.ignoresSafeAreaEdges = ignoresSafeAreaEdges
    }

    // TODO: Wire style fill as an overlay layer once rendering context is available.
    public static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        body(_Graph(), inputs)
    }
}

extension _OverlayStyleModifier {
    public typealias Body = Never

    public static func _makeViewList(modifier: _GraphValue<Self>, inputs: _ViewListInputs, body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs) -> _ViewListOutputs {
        body(_Graph(), inputs)
    }
}

public struct _OverlayShapeModifier<Style, Bounds>: ViewModifier where Style: ShapeStyle, Bounds: Shape {
    public var style: Style
    public var shape: Bounds
    public var fillStyle: FillStyle

    @inlinable public init(style: Style, shape: Bounds, fillStyle: FillStyle) {
        self.style = style
        self.shape = shape
        self.fillStyle = fillStyle
    }

    // TODO: Wire shape fill as an overlay layer once rendering context is available.
    public static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        body(_Graph(), inputs)
    }
}

extension _OverlayShapeModifier {
    public typealias Body = Never

    public static func _makeViewList(modifier: _GraphValue<Self>, inputs: _ViewListInputs, body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs) -> _ViewListOutputs {
        body(_Graph(), inputs)
    }
}

extension View {
    @inlinable public func overlay<V>(alignment: Alignment = .center, @ViewBuilder content: () -> V) -> some View where V: View {
          modifier(_OverlayModifier(overlay: content(), alignment: alignment))
      }

    @inlinable public func overlay<S>(_ style: S, ignoresSafeAreaEdges edges: Edge.Set = .all) -> some View where S: ShapeStyle {
          modifier(_OverlayStyleModifier(
              style: style, ignoresSafeAreaEdges: edges))
      }

    @inlinable public func overlay<S, T>(_ style: S, in shape: T, fillStyle: FillStyle = FillStyle()) -> some View where S: ShapeStyle, T: Shape {
          modifier(_OverlayShapeModifier(
              style: style, shape: shape, fillStyle: fillStyle))
      }

    @inlinable public func border<S>(_ content: S, width: CGFloat = 1) -> some View where S: ShapeStyle {
        return overlay {
            Rectangle().strokeBorder(content, lineWidth: width)
        }
    }
}


private protocol _OverlayModifierWithAlignment {
    var alignment: Alignment { get }
}

private protocol _OverlayModifierWithIgnoresSafeAreaEdges {
    var ignoresSafeAreaEdges: Edge.Set { get }
}

extension _OverlayModifier: _OverlayModifierWithAlignment {
}

extension _OverlayStyleModifier: _OverlayModifierWithIgnoresSafeAreaEdges {
}

