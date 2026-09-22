//
//  File: OverlayModifier.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

private func resolveSecondaryLayerGeometry(
    alignment: Alignment,
    layoutDirection: LayoutDirection,
    primaryPosition: CGPoint,
    primarySize: ViewSize,
    primaryComputer: LayoutComputer,
    secondaryComputer: LayoutComputer
) -> ViewGeometry {
    let primaryDimensions = ViewDimensions(
        guideComputer: primaryComputer,
        size: primarySize
    )
    let secondaryDimensions = secondaryComputer.dimensions(
        in: _ProposedSize(primarySize.value)
    )
    var origin = CGPoint(
        x: primaryPosition.x + primaryDimensions[alignment.horizontal]
            - secondaryDimensions[alignment.horizontal],
        y: primaryPosition.y + primaryDimensions[alignment.vertical]
            - secondaryDimensions[alignment.vertical]
    )
    if layoutDirection == .rightToLeft {
        let centeredOrigin = primaryPosition.x
            + primaryDimensions[HorizontalAlignment.center]
            - secondaryDimensions[HorizontalAlignment.center]
        origin.x = centeredOrigin * 2 - origin.x
    }
    return ViewGeometry(origin: origin, dimensions: secondaryDimensions)
}

struct SecondaryLayerGeometryQuery: Rule, AsyncAttribute {
    var _alignment: OptionalAttribute<Alignment>
    var _layoutDirection: Attribute<LayoutDirection>
    var _primaryPosition: Attribute<CGPoint>
    var _primarySize: Attribute<ViewSize>
    var _primaryLayoutComputer: OptionalAttribute<LayoutComputer>
    var _secondaryLayoutComputer: OptionalAttribute<LayoutComputer>

    var value: ViewGeometry {
        let primaryComputer =
            _primaryLayoutComputer.attribute?.value ?? LayoutComputer.defaultValue
        let primarySize = _primarySize.value
        let alignment = _alignment.attribute?.value ?? .center
        let primaryPosition = _primaryPosition.value
        let secondaryComputer =
            _secondaryLayoutComputer.attribute?.value ?? LayoutComputer.defaultValue
        return resolveSecondaryLayerGeometry(
            alignment: alignment,
            layoutDirection: _layoutDirection.value,
            primaryPosition: primaryPosition,
            primarySize: primarySize,
            primaryComputer: primaryComputer,
            secondaryComputer: secondaryComputer
        )
    }
}

func makeSecondaryLayerView<Secondary: View>(
    secondaryLayer: Attribute<Secondary>,
    alignment: Attribute<Alignment>?,
    inputs: _ViewInputs,
    body: (_Graph, _ViewInputs) -> _ViewOutputs,
    flipOrder: Bool
) -> _ViewOutputs {
    guard let graph = _AGGraph.current else {
        fatalError("makeSecondaryLayerView called outside an active _AGGraph context.")
    }

    let primaryOutputs = body(_Graph(), inputs)
    let primaryLayoutComputer = primaryOutputs._layoutComputer

    let environment = inputs.base.cachedEnvironment.value.environment
    let layoutDirection: Attribute<LayoutDirection> = graph.makeRule {
        environment.value.layoutDirection
    }
    let geometry = graph.makeRule(
        SecondaryLayerGeometryQuery(
            _alignment: alignment.map(OptionalAttribute.init) ?? OptionalAttribute(),
            _layoutDirection: layoutDirection,
            _primaryPosition: inputs.position,
            _primarySize: inputs.size,
            _primaryLayoutComputer: primaryLayoutComputer,
            _secondaryLayoutComputer: OptionalAttribute()
        )
    )
    var secondaryInputs = inputs
    secondaryInputs.copyCaches()
    secondaryInputs.implicitRootType = _ZStackLayout.self

    let secondaryPosition = graph.subscriptNode(
        parent: geometry,
        keyPath: \ViewGeometry.origin
    )
    let secondarySize = graph.subscriptNode(
        parent: geometry,
        keyPath: \ViewGeometry.dimensions.size
    )
    secondaryInputs.position = secondaryPosition
    secondaryInputs.size = secondarySize
    let parentTransform = inputs.transform
    secondaryInputs.transform = graph.makeRule {
        var transform = parentTransform.value
        transform.appendPosition(secondaryPosition.value)
        return transform
    }

    let secondaryOutputs = Secondary._makeView(
        view: _GraphValue(_attribute: secondaryLayer),
        inputs: secondaryInputs
    )
    graph.mutateRule(
        geometry.identifier,
        as: SecondaryLayerGeometryQuery.self,
        invalidating: true
    ) { query in
        query._secondaryLayoutComputer = secondaryOutputs._layoutComputer
    }
    let orderedPreferences = flipOrder
        ? [secondaryOutputs.preferences, primaryOutputs.preferences]
        : [primaryOutputs.preferences, secondaryOutputs.preferences]
    return _ViewOutputs(
        preferences: PreferencesOutputs.merge(orderedPreferences, in: graph),
        layoutComputer: primaryLayoutComputer
    )
}

public struct _OverlayModifier<Overlay>: MultiViewModifier, PrimitiveViewModifier where Overlay: View {
    public let overlay: Overlay
    public let alignment: Alignment

    @inlinable public init(overlay: Overlay, alignment: Alignment = .center) {
        self.overlay = overlay
        self.alignment = alignment
    }

    public static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        guard _AGGraph.current != nil else {
            fatalError("\(self)._makeView called outside an active _AGGraph context.")
        }
        return makeSecondaryLayerView(
            secondaryLayer: modifier[\.overlay]._attribute,
            alignment: modifier[\.alignment]._attribute,
            inputs: inputs,
            body: body,
            flipOrder: false
        )
    }
}

@available(*, unavailable)
extension _OverlayModifier: Sendable {
    public typealias Body = Never
}

public struct _OverlayStyleModifier<Style>: MultiViewModifier, PrimitiveViewModifier where Style: ShapeStyle {
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
        let environmentAttr = inputs.base.cachedEnvironment.value.environment
        let dlAttr: Attribute<DisplayList> = graph.makeRule {
            let m = modifier._attribute.value
            let viewSize = sizeAttr.value.value
            let position = positionAttr.value
            let environment = environmentAttr.value.untrackedCopy()
            var list = DisplayList()
            if viewSize.width > 0 && viewSize.height > 0 {
                let frame = CGRect(origin: position, size: viewSize)
                let path = Rectangle().path(in: frame)
                list.appendShapeItem(
                    path: path,
                    role: .fill,
                    style: m.style,
                    bounds: frame,
                    fillStyle: FillStyle(),
                    environment: environment
                )
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

@available(*, unavailable)
extension _OverlayStyleModifier: Sendable {
    public typealias Body = Never
}

public struct _OverlayShapeModifier<Style, Bounds>: MultiViewModifier, PrimitiveViewModifier where Style: ShapeStyle, Bounds: Shape {
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
        let environmentAttr = inputs.base.cachedEnvironment.value.environment
        let dlAttr: Attribute<DisplayList> = graph.makeRule {
            let m = modifier._attribute.value
            let viewSize = sizeAttr.value.value
            let position = positionAttr.value
            let environment = environmentAttr.value.untrackedCopy()
            var list = DisplayList()
            if viewSize.width > 0 && viewSize.height > 0 {
                let frame = CGRect(origin: position, size: viewSize)
                let path = m.shape.path(in: frame)
                list.appendShapeItem(
                    path: path,
                    role: .fill,
                    style: m.style,
                    bounds: frame,
                    fillStyle: m.fillStyle,
                    environment: environment
                )
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

@available(*, unavailable)
extension _OverlayShapeModifier: Sendable {
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
