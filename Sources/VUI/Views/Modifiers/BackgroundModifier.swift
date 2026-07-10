//
//  File: BackgroundModifier.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

public struct _BackgroundModifier<Background>: ViewModifier where Background: View {
    public var background: Background
    public var alignment: Alignment

    @inlinable public init(background: Background, alignment: Alignment = .center) {
        self.background = background
        self.alignment = alignment
    }

    public static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("\(self)._makeView called outside an active _AGGraph context.")
        }
        let mainOutputs = body(_Graph(), inputs)
        guard let mainLCAttr = mainOutputs._layoutComputer.attribute else {
            return mainOutputs
        }
        let bgPosAttr = graph.makeInput(value: CGPoint.zero)
        let bgSizeAttr = graph.makeInput(value: ViewSize(.zero))
        let bgInputs = _ViewInputs(
            base: inputs.base,
            customInputs: PropertyList(),
            preferences: inputs.preferences,
            transform: inputs.transform,
            position: bgPosAttr,
            containerPosition: inputs.position,
            size: bgSizeAttr,
            safeAreaInsets: inputs.safeAreaInsets,
            containerSize: inputs.containerSize,
            stackOrientation: inputs.stackOrientation
        )
        let zStackAttr: Attribute<ZStackLayout> = graph.makeRule {
            ZStackLayout(alignment: modifier._attribute.value.alignment)
        }
        let zStackGraph = _GraphValue<ZStackLayout>(_attribute: zStackAttr)
        let bgOutputs = ZStackLayout._makeLayoutView(root: zStackGraph, inputs: bgInputs) { _, childInputs in
            Background._makeViewList(view: modifier[\.background], inputs: _ViewListInputs(from: childInputs))
        }
        guard let bgLCAttr = bgOutputs._layoutComputer.attribute else {
            return mainOutputs
        }
        let lcAttr: Attribute<LayoutComputer> = graph.makeRule {
            let m = modifier._attribute.value   // dep: alignment changes
            let mainLC = mainLCAttr.value       // dep: main content changes
            let bgLC = bgLCAttr.value           // dep: background changes
            var pendingPlacementTransaction =
                graph.transaction(for: modifier._attribute.identifier) ??
                graph.transaction(for: mainLCAttr.identifier) ??
                graph.transaction(for: bgLCAttr.identifier)
            return LayoutComputer(
                sizeThatFits: { proposal in mainLC.sizeThatFits(proposal) },
                spacing: mainLC.spacing,
                place: { position, anchor, proposal in
                    mainLC.place(at: position, anchor: anchor, proposal: proposal)
                    let mainSize = mainLC.sizeThatFits(proposal)
                    let ox = position.x - mainSize.width * anchor.x
                    let oy = position.y - mainSize.height * anchor.y
                    let frame = CGRect(x: ox, y: oy, width: mainSize.width, height: mainSize.height)

                    var bgPosition = frame.origin
                    var bgAnchor = UnitPoint()
                    
                    switch m.alignment.horizontal {
                    case .leading:
                        bgPosition.x = frame.minX
                        bgAnchor.x = 0
                    case .center:
                        bgPosition.x = frame.midX
                        bgAnchor.x = 0.5
                    case .trailing:
                        bgPosition.x = frame.maxX
                        bgAnchor.x = 1
                    default:
                        bgPosition.x = frame.midX
                        bgAnchor.x = 0.5
                    }
                    
                    switch m.alignment.vertical {
                    case .top:
                        bgPosition.y = frame.minY
                        bgAnchor.y = 0
                    case .center:
                        bgPosition.y = frame.midY
                        bgAnchor.y = 0.5
                    case .bottom:
                        bgPosition.y = frame.maxY
                        bgAnchor.y = 1
                    default:
                        bgPosition.y = frame.midY
                        bgAnchor.y = 0.5
                    }

                    let bgProposal = ProposedViewSize(width: frame.width, height: frame.height)
                    let bgSize = bgLC.sizeThatFits(bgProposal)
                    
                    let bgOriginX = bgPosition.x - bgSize.width * bgAnchor.x
                    let bgOriginY = bgPosition.y - bgSize.height * bgAnchor.y
                    
                    let placementTransaction =
                        graph.transaction(for: modifier._attribute.identifier) ??
                        graph.transaction(for: mainLCAttr.identifier) ??
                        graph.transaction(for: bgLCAttr.identifier) ??
                        pendingPlacementTransaction ??
                        Transaction.current
                    pendingPlacementTransaction = nil
                    bgPosAttr.setValue(
                        CGPoint(x: bgOriginX, y: bgOriginY),
                        transaction: placementTransaction
                    )
                    bgSizeAttr.setValue(
                        ViewSize(bgSize, proposal: bgProposal),
                        transaction: placementTransaction
                    )
                    withTransaction(placementTransaction) {
                        bgLC.place(at: bgPosition, anchor: bgAnchor, proposal: bgProposal)
                    }
                },
                explicitAlignment: { mainLC.explicitAlignment($0, at: $1) }
            )
        }
        let mergedPreferences = PreferencesOutputs.merge([bgOutputs.preferences, mainOutputs.preferences], in: graph)
        return _ViewOutputs(
            preferences: mergedPreferences,
            layoutComputer: OptionalAttribute(lcAttr)
        )
    }
}

extension _BackgroundModifier: Equatable where Background: Equatable {
}

extension _BackgroundModifier: PrimitiveViewModifier, MultiViewModifier {
    public typealias Body = Never
}

public struct _BackgroundStyleModifier<Style>: ViewModifier where Style: ShapeStyle {
    public var style: Style
    public var ignoresSafeAreaEdges: Edge.Set

    @inlinable public init(style: Style, ignoresSafeAreaEdges: Edge.Set) {
        self.style = style
        self.ignoresSafeAreaEdges = ignoresSafeAreaEdges
    }

    public static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("\(self)._makeView called outside an active _AGGraph context.")
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
                list.appendShapeItem(
                    role: .fill,
                    style: m.style,
                    bounds: frame,
                    fillStyle: FillStyle()
                ) { context in
                    context.fill(path, with: .style(m.style))
                }
            }
            return list
        }
        var bgPreferences = PreferencesOutputs()
        bgPreferences.append(DisplayList.Key.self, node: dlAttr.identifier)
        let mergedPreferences = PreferencesOutputs.merge([bgPreferences, mainOutputs.preferences], in: graph)
        return _ViewOutputs(
            preferences: mergedPreferences,
            layoutComputer: mainOutputs._layoutComputer
        )
    }
}

extension _BackgroundStyleModifier: PrimitiveViewModifier, MultiViewModifier {
    public typealias Body = Never
}

public struct _BackgroundShapeModifier<Style, Bounds>: ViewModifier where Style: ShapeStyle, Bounds: Shape {
    public var style: Style
    public var shape: Bounds
    public var fillStyle: FillStyle

    @inlinable public init(style: Style, shape: Bounds, fillStyle: FillStyle) {
        self.style = style
        self.shape = shape
        self.fillStyle = fillStyle
    }

    public static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("\(self)._makeView called outside an active _AGGraph context.")
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
                list.appendShapeItem(
                    role: .fill,
                    style: m.style,
                    bounds: frame,
                    fillStyle: m.fillStyle
                ) { context in
                    context.fill(path, with: .style(m.style), style: m.fillStyle)
                }
            }
            return list
        }
        var bgPreferences = PreferencesOutputs()
        bgPreferences.append(DisplayList.Key.self, node: dlAttr.identifier)
        let mergedPreferences = PreferencesOutputs.merge([bgPreferences, mainOutputs.preferences], in: graph)
        return _ViewOutputs(
            preferences: mergedPreferences,
            layoutComputer: mainOutputs._layoutComputer
        )
    }
}

extension _BackgroundShapeModifier: PrimitiveViewModifier, MultiViewModifier {
    public typealias Body = Never
}

public struct _InsettableBackgroundShapeModifier<Style, Bounds>: ViewModifier where Style: ShapeStyle, Bounds: InsettableShape {
    public var style: Style
    public var shape: Bounds
    public var fillStyle: FillStyle

    @inlinable public init(style: Style, shape: Bounds, fillStyle: FillStyle) {
        self.style = style
        self.shape = shape
        self.fillStyle = fillStyle
    }

    public static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("\(self)._makeView called outside an active _AGGraph context.")
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
                list.appendShapeItem(
                    role: .fill,
                    style: m.style,
                    bounds: frame,
                    fillStyle: m.fillStyle
                ) { context in
                    context.fill(path, with: .style(m.style), style: m.fillStyle)
                }
            }
            return list
        }
        var bgPreferences = PreferencesOutputs()
        bgPreferences.append(DisplayList.Key.self, node: dlAttr.identifier)
        let mergedPreferences = PreferencesOutputs.merge([bgPreferences, mainOutputs.preferences], in: graph)
        return _ViewOutputs(
            preferences: mergedPreferences,
            layoutComputer: mainOutputs._layoutComputer
        )
    }
}

extension _InsettableBackgroundShapeModifier: PrimitiveViewModifier, MultiViewModifier {
    public typealias Body = Never
}

extension View {
    @inlinable public func background<V>(alignment: Alignment = .center, @ViewBuilder content: () -> V) -> some View where V: View {
        modifier(
            _BackgroundModifier(background: content(), alignment: alignment))
    }

    @inlinable public func background(ignoresSafeAreaEdges edges: Edge.Set = .all) -> some View {
        modifier(_BackgroundStyleModifier(
            style: .background, ignoresSafeAreaEdges: edges))
    }

    @inlinable public func background<S>(_ style: S, ignoresSafeAreaEdges edges: Edge.Set = .all) -> some View where S: ShapeStyle {
        modifier(_BackgroundStyleModifier(
            style: style, ignoresSafeAreaEdges: edges))
    }

    @inlinable public func background<S>(in shape: S, fillStyle: FillStyle = FillStyle()) -> some View where S: Shape {
        modifier(_BackgroundShapeModifier(
            style: .background, shape: shape, fillStyle: fillStyle))
    }

    @inlinable public func background<S, T>(_ style: S, in shape: T, fillStyle: FillStyle = FillStyle()) -> some View where S: ShapeStyle, T: Shape {
        modifier(_BackgroundShapeModifier(
            style: style, shape: shape, fillStyle: fillStyle))
    }

    @inlinable public func background<S>(in shape: S, fillStyle: FillStyle = FillStyle()) -> some View where S: InsettableShape {
        modifier(_InsettableBackgroundShapeModifier(
            style: .background, shape: shape, fillStyle: fillStyle))
    }

    @inlinable public func background<S, T>(_ style: S, in shape: T, fillStyle: FillStyle = FillStyle()) -> some View where S: ShapeStyle, T: InsettableShape {
        modifier(_InsettableBackgroundShapeModifier(
            style: style, shape: shape, fillStyle: fillStyle))
    }
}

private protocol _BackgroundModifierWithAlignment {
    var alignment: Alignment { get }
}

private protocol _BackgroundModifierWithIgnoresSafeAreaEdges {
    var ignoresSafeAreaEdges: Edge.Set { get }
}

extension _BackgroundModifier: _BackgroundModifierWithAlignment {
}

extension _BackgroundStyleModifier: _BackgroundModifierWithIgnoresSafeAreaEdges {
}
