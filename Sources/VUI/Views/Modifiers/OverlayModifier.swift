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
        let ovSizeAttr = graph.makeInput(value: ViewSize(.zero))
        let ovInputs = _ViewInputs(
            base: inputs.base,
            customInputs: PropertyList(),
            preferences: inputs.preferences,
            transform: inputs.transform,
            position: ovPosAttr,
            containerPosition: inputs.position,
            size: ovSizeAttr,
            safeAreaInsets: inputs.safeAreaInsets,
            containerSize: inputs.containerSize
        )
        let zStackAttr: Attribute<ZStackLayout> = graph.makeRule {
            ZStackLayout(alignment: modifier._attribute.value.alignment)
        }
        let zStackGraph = _GraphValue<ZStackLayout>(_attribute: zStackAttr)
        let ovOutputs = ZStackLayout._makeLayoutView(root: zStackGraph, inputs: ovInputs) { _, childInputs in
            Overlay._makeViewList(view: modifier[\.overlay], inputs: _ViewListInputs(from: childInputs))
        }
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
                place: { position, anchor, proposal in
                    mainLC.place(at: position, anchor: anchor, proposal: proposal)
                    let mainSize = mainLC.sizeThatFits(proposal)
                    let ox = position.x - mainSize.width * anchor.x
                    let oy = position.y - mainSize.height * anchor.y
                    let frame = CGRect(x: ox, y: oy, width: mainSize.width, height: mainSize.height)

                    var ovPosition = frame.origin
                    var ovAnchor = UnitPoint()
                    
                    switch m.alignment.horizontal {
                    case .leading:
                        ovPosition.x = frame.minX
                        ovAnchor.x = 0
                    case .center:
                        ovPosition.x = frame.midX
                        ovAnchor.x = 0.5
                    case .trailing:
                        ovPosition.x = frame.maxX
                        ovAnchor.x = 1
                    default:
                        ovPosition.x = frame.midX
                        ovAnchor.x = 0.5
                    }
                    
                    switch m.alignment.vertical {
                    case .top:
                        ovPosition.y = frame.minY
                        ovAnchor.y = 0
                    case .center:
                        ovPosition.y = frame.midY
                        ovAnchor.y = 0.5
                    case .bottom:
                        ovPosition.y = frame.maxY
                        ovAnchor.y = 1
                    default:
                        ovPosition.y = frame.midY
                        ovAnchor.y = 0.5
                    }

                    let ovProposal = ProposedViewSize(width: frame.width, height: frame.height)
                    let ovSize = ovLC.sizeThatFits(ovProposal)
                    
                    let ovOriginX = ovPosition.x - ovSize.width * ovAnchor.x
                    let ovOriginY = ovPosition.y - ovSize.height * ovAnchor.y
                    
                    ovPosAttr.setValue(CGPoint(x: ovOriginX, y: ovOriginY))
                    ovSizeAttr.setValue(ViewSize(ovSize))
                    ovLC.place(at: ovPosition, anchor: ovAnchor, proposal: ovProposal)
                },
                explicitAlignment: { mainLC.explicitAlignment($0, at: $1) }
            )
        }
        let mergedPreferences = PreferencesOutputs.merge([mainOutputs.preferences, ovOutputs.preferences], in: graph)
        return _ViewOutputs(
            preferences: mergedPreferences,
            layoutComputer: OptionalAttribute(lcAttr)
        )
    }
}

extension _OverlayModifier: Equatable where Overlay: Equatable {
}

extension _OverlayModifier: PrimitiveViewModifier, MultiViewModifier {
    public typealias Body = Never
}

public struct _OverlayStyleModifier<Style>: ViewModifier where Style: ShapeStyle {
    public var style: Style
    public var ignoresSafeAreaEdges: Edge.Set

    @inlinable public init(style: Style, ignoresSafeAreaEdges: Edge.Set) {
        self.style = style
        self.ignoresSafeAreaEdges = ignoresSafeAreaEdges
    }

    public static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        guard let graph = AttributeGraph.current else {
            fatalError("\(self)._makeView called outside an active AttributeGraph context.")
        }
        let mainOutputs = body(_Graph(), inputs)
        let sizeAttr = inputs.size
        let positionAttr = inputs.position
        let dlAttr: Attribute<DisplayList> = graph.makeRule {
            let m = modifier._attribute.value
            let viewSize = sizeAttr.value.value
            let position = positionAttr.value
            var list = DisplayList()
            if viewSize.width > 0 && viewSize.height > 0 {
                let frame = CGRect(origin: position, size: viewSize)
                let path = Rectangle().path(in: frame)
                list.items.append { context in
                    context.fill(path, with: .style(m.style))
                }
            }
            return list
        }
        var ovPreferences = PreferencesOutputs()
        ovPreferences.append(DisplayList.Key.self, node: dlAttr.identifier)
        let mergedPreferences = PreferencesOutputs.merge([mainOutputs.preferences, ovPreferences], in: graph)
        return _ViewOutputs(
            preferences: mergedPreferences,
            layoutComputer: mainOutputs._layoutComputer
        )
    }
}

extension _OverlayStyleModifier: PrimitiveViewModifier, MultiViewModifier {
    public typealias Body = Never
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

    public static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        guard let graph = AttributeGraph.current else {
            fatalError("\(self)._makeView called outside an active AttributeGraph context.")
        }
        let mainOutputs = body(_Graph(), inputs)
        let sizeAttr = inputs.size
        let positionAttr = inputs.position
        let dlAttr: Attribute<DisplayList> = graph.makeRule {
            let m = modifier._attribute.value
            let viewSize = sizeAttr.value.value
            let position = positionAttr.value
            var list = DisplayList()
            if viewSize.width > 0 && viewSize.height > 0 {
                let frame = CGRect(origin: position, size: viewSize)
                let path = m.shape.path(in: frame)
                list.items.append { context in
                    context.fill(path, with: .style(m.style), style: m.fillStyle)
                }
            }
            return list
        }
        var ovPreferences = PreferencesOutputs()
        ovPreferences.append(DisplayList.Key.self, node: dlAttr.identifier)
        let mergedPreferences = PreferencesOutputs.merge([mainOutputs.preferences, ovPreferences], in: graph)
        return _ViewOutputs(
            preferences: mergedPreferences,
            layoutComputer: mainOutputs._layoutComputer
        )
    }
}

extension _OverlayShapeModifier: PrimitiveViewModifier, MultiViewModifier {
    public typealias Body = Never
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

