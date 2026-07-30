//
//  File: ShapeView.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

public protocol ShapeView<Content>: View {
    associatedtype Content: Shape
    var shape: Content { get }
}

struct AnimatedShape<Content: Shape>: LeafViewLayout {
    var shape: Content
    var fillStyle: FillStyle

    struct Init: Rule, AsyncAttribute {
        typealias Value = AnimatedShape<Content>

        var shape: Attribute<Content>
        var fillStyle: Attribute<FillStyle>

        var value: Value {
            AnimatedShape(shape: shape.value, fillStyle: fillStyle.value)
        }
    }

    func sizeThatFits(in proposal: _ProposedSize) -> CGSize {
        shape.sizeThatFits(ProposedViewSize(proposal))
    }
}

extension AnimatedShape: ContentResponder {
    func contentPath(size: CGSize) -> Path {
        shape.path(in: CGRect(origin: .zero, size: size))
    }
}

struct ShapeStyledResponderData<Content: ContentResponder>: ContentResponder {
    var view: Content
    var styles: _ShapeStyle_Pack

    func contains(
        points: UnsafeBufferPointer<CGPoint>,
        size: CGSize
    ) -> BitVector64 {
        guard !isClear else { return [] }
        return view.contains(points: points, size: size)
    }

    func contentPath(size: CGSize) -> Path {
        guard !isClear else { return Path() }
        return view.contentPath(size: size)
    }

    private var isClear: Bool {
        styles.isClear(name: .foreground) &&
            styles.isClear(name: .background)
    }
}

private struct ShapeStyledResponderFilter<Content: ContentResponder>: StatefulRule {
    typealias Value = [ViewResponder]

    var _view: Attribute<Content>
    var _styles: Attribute<_ShapeStyle_Pack>
    var _size: Attribute<ViewSize>
    var _position: Attribute<CGPoint>
    var _transform: Attribute<ViewTransform>
    var responder: LeafViewResponder<ShapeStyledResponderData<Content>>

    mutating func updateValue() {
        let isInitialValue = !context.hasValue
        let viewChanged = isInitialValue || _AGGraph.currentStatefulInputChanged(_view.identifier)
        let stylesChanged = isInitialValue || _AGGraph.currentStatefulInputChanged(_styles.identifier)
        let sizeChanged = isInitialValue || _AGGraph.currentStatefulInputChanged(_size.identifier)
        let positionChanged = isInitialValue || _AGGraph.currentStatefulInputChanged(_position.identifier)
        let transformChanged = isInitialValue || _AGGraph.currentStatefulInputChanged(_transform.identifier)

        responder.helper.update(
            data: (
                value: ShapeStyledResponderData(
                    view: _view.value,
                    styles: _styles.value
                ),
                changed: viewChanged || stylesChanged
            ),
            size: (value: _size.value, changed: sizeChanged),
            position: (value: _position.value, changed: positionChanged),
            transform: (value: _transform.value, changed: transformChanged),
            parent: responder
        )
        if isInitialValue {
            _AGGraph.setStatefulOutput([responder])
        }
    }
}

struct DirectShapeStyleResolver<Style: ShapeStyle>: StatefulRule, ObservedAttribute, AsyncAttribute {
    typealias Value = _ShapeStyle_Pack

    var _style: OptionalAttribute<Style>
    var _environment: Attribute<EnvironmentValues>
    var role: ShapeRole
    var animationsDisabled: Bool
    var helper: AnimatableAttributeHelper<_ShapeStyle_Pack>
    var tracker: _PropertyListTracker

    init(
        style: OptionalAttribute<Style>,
        environment: Attribute<EnvironmentValues>,
        role: ShapeRole,
        animationsDisabled: Bool,
        helper: AnimatableAttributeHelper<_ShapeStyle_Pack>,
        tracker: _PropertyListTracker = _PropertyListTracker()
    ) {
        self._style = style
        self._environment = environment
        self.role = role
        self.animationsDisabled = animationsDisabled
        self.helper = helper
        self.tracker = tracker
    }

    mutating func updateValue() {
        let isInitialValue = !context.hasValue
        let styleValue = _style.changedValue(
            options: AGValueOptions(rawValue: 0)
        )
        let environmentValue = _environment.changedValue(
            options: AGValueOptions(rawValue: 0)
        )
        let environment = environmentValue.value
        let needsResolution = isInitialValue ||
            (styleValue?.changed ?? false) ||
            helper.needsModelResolutionForReset ||
            (
                environmentValue.changed &&
                    tracker.hasDifferentUsedValues(environment._plist)
            )

        if !needsResolution && !helper.isAnimating {
            return
        }

        if needsResolution {
            tracker.reset()
        }
        let trackedEnvironment = EnvironmentValues(
            environment._plist,
            tracker: tracker
        )
        guard let style = styleValue?.value else {
            finishValue(_ShapeStyle_Pack())
            return
        }
        let target = resolvedPack(
            style: style,
            environment: trackedEnvironment
        )
        if animationsDisabled {
            finishValue(target)
            return
        }

        var value = (value: target, changed: needsResolution)
        helper.update(
            value: &value,
            defaultAnimation: nil,
            environment: _environment
        )
        if value.changed {
            _AGGraph.setStatefulOutput(value.value)
        }
    }

    mutating func destroy() {
        helper.finishAndClearAnimatorState()
    }

    private func resolvedPack(
        style: Style,
        environment: EnvironmentValues
    ) -> _ShapeStyle_Pack {
        var shape = _ShapeStyle_Shape(
            operation: .resolveStyle(
                name: .foreground,
                levels: 0..<1
            ),
            environment: environment,
            role: role
        )
        style._apply(to: &shape)
        if case let .pack(pack) = shape.result {
            return pack
        }
        guard let property = shape.resolvedShading?.properties.first else {
            return _ShapeStyle_Pack()
        }
        switch property {
        case let .color(color):
            return .fill(.color(color.resolveHDR(in: environment)))
        case let .meshGradient(mesh):
            return .fill(.paint(_AnyResolvedPaint(
                mesh.resolvePaint(in: environment)
            )))
        default:
            return _ShapeStyle_Pack()
        }
    }

    private mutating func finishValue(_ value: _ShapeStyle_Pack) {
        helper.finishAndClearAnimatorState()
        helper.commitTarget(value)
        _AGGraph.setStatefulOutput(value)
    }
}

public struct _ShapeView<Content, Style>: View, ShapeView, ContentResponder
    where Content: Shape, Style: ShapeStyle {
    public var shape: Content
    public var style: Style
    public var fillStyle: FillStyle

    public init(shape: Content, style: Style, fillStyle: FillStyle = FillStyle()) {
        self.shape = shape
        self.style = style
        self.fillStyle = fillStyle
    }

    func contentPath(size: CGSize) -> Path {
        shape.path(in: CGRect(origin: .zero, size: size))
    }

    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("\(self)._makeView called outside an active _AGGraph context.")
        }
        let sourceShape = view[\.shape]
        var animatedShape = sourceShape
        Content._makeAnimatable(value: &animatedShape, inputs: inputs.base)
        let animatedStylePack = Self.makeAnimatedStylePack(
            view: view,
            inputs: inputs,
            graph: graph
        )
        let cachedEnvironmentAttribute = inputs.base.cachedEnvironment
        var cachedEnvironment = cachedEnvironmentAttribute.value
        let sizeAttr = cachedEnvironment.animatedSize(for: inputs)
        let positionAttr = cachedEnvironment.animatedPosition(for: inputs)
        cachedEnvironmentAttribute.value = cachedEnvironment
        let environmentAttr = inputs.base.cachedEnvironment.value.environment
        let responderStyles: Attribute<_ShapeStyle_Pack>
        if let animatedStylePack {
            responderStyles = animatedStylePack
        } else {
            responderStyles = graph.makeRule {
                _ = view._attribute.value.style
                return _ShapeStyle_Pack.fill(
                    .color(Color.black.resolveHDR(in: environmentAttr.value))
                )
            }
        }
        let fillStyleAttr = view[\.fillStyle]._attribute
        let dlAttr: Attribute<DisplayList> = graph.makeRule {
            let shape = animatedShape._attribute.value
            let fillStyle = fillStyleAttr.value
            let viewSize = sizeAttr.value.value
            let position = positionAttr.value
            let environment = environmentAttr.value.untrackedCopy()
            var list = DisplayList()
            //Log.debug("ShapeView: size=\(viewSize), position=\(position)")
            if viewSize.width > 0 && viewSize.height > 0 {
                let frame = CGRect(origin: position, size: viewSize)
                let strokeStyle = (shape as? ShapeStrokeStyleProviding)?.strokeStyle
                if let animatedStylePack,
                   let style = animatedStylePack.value.shapeStyle() {
                    if let drawer = shape as? ShapeDrawer {
                        list.appendShapeItem(
                            role: Content.role,
                            style: style,
                            bounds: frame,
                            fillStyle: fillStyle,
                            strokeStyle: strokeStyle,
                            environment: environment
                        ) { context in
                            drawer._draw(
                                in: frame,
                                style: style,
                                fillStyle: fillStyle,
                                context: context
                            )
                        }
                    } else {
                        list.appendShapeItem(
                            path: shape.path(in: frame),
                            role: Content.role,
                            style: style,
                            bounds: frame,
                            fillStyle: fillStyle,
                            strokeStyle: strokeStyle,
                            environment: environment
                        )
                    }
                } else {
                    let style = view._attribute.value.style
                    if let drawer = shape as? ShapeDrawer {
                        list.appendShapeItem(
                            role: Content.role,
                            style: style,
                            bounds: frame,
                            fillStyle: fillStyle,
                            strokeStyle: strokeStyle,
                            environment: environment
                        ) { context in
                            drawer._draw(
                                in: frame,
                                style: style,
                                fillStyle: fillStyle,
                                context: context
                            )
                        }
                    } else {
                        list.appendShapeItem(
                            path: shape.path(in: frame),
                            role: Content.role,
                            style: style,
                            bounds: frame,
                            fillStyle: fillStyle,
                            strokeStyle: strokeStyle,
                            environment: environment
                        )
                    }
                }
            }
            return list
        }
        var outputs = _ViewOutputs()
        outputs.preferences.append(DisplayList.Key.self, node: dlAttr.identifier)

        let responderSizeAttr = cachedEnvironment.animatedSize(for: inputs)
        let responderPositionAttr = cachedEnvironment.animatedPosition(for: inputs)
        cachedEnvironmentAttribute.value = cachedEnvironment
        if MemoryLayout<Content.AnimatableData>.size == 0 {
            makeLeafLayout(&outputs, view: view, inputs: inputs)
            makeShapeResponder(
                &outputs,
                view: view._attribute,
                styles: responderStyles,
                size: responderSizeAttr,
                position: responderPositionAttr,
                transform: inputs.transform,
                requested: inputs.preferences.keys.contains(ViewRespondersKey.self),
                graph: graph
            )
        } else {
            let layoutShape: Attribute<AnimatedShape<Content>> = graph.makeRule(
                AnimatedShape.Init(
                    shape: animatedShape._attribute,
                    fillStyle: view[\.fillStyle]._attribute
                )
            )
            AnimatedShape<Content>.makeLeafLayout(
                &outputs,
                view: _GraphValue(_attribute: layoutShape),
                inputs: inputs
            )
            makeShapeResponder(
                &outputs,
                view: layoutShape,
                styles: responderStyles,
                size: responderSizeAttr,
                position: responderPositionAttr,
                transform: inputs.transform,
                requested: inputs.preferences.keys.contains(ViewRespondersKey.self),
                graph: graph
            )
        }
        return outputs
    }

    private static func makeShapeResponder<ResponderContent: ContentResponder>(
        _ outputs: inout _ViewOutputs,
        view: Attribute<ResponderContent>,
        styles: Attribute<_ShapeStyle_Pack>,
        size: Attribute<ViewSize>,
        position: Attribute<CGPoint>,
        transform: Attribute<ViewTransform>,
        requested: Bool,
        graph: _AGGraph
    ) {
        guard requested else { return }
        let responder = LeafViewResponder<ShapeStyledResponderData<ResponderContent>>()
        let filter = ShapeStyledResponderFilter(
            _view: view,
            _styles: styles,
            _size: size,
            _position: position,
            _transform: transform,
            responder: responder
        )
        let responders = graph.makeStatefulRule(filter)
        outputs.preferences.append(
            ViewRespondersKey.self,
            node: responders.identifier
        )
    }

    private static func makeAnimatedStylePack(
        view: _GraphValue<Self>,
        inputs: _ViewInputs,
        graph: _AGGraph
    ) -> Attribute<_ShapeStyle_Pack>? {
        guard Style.self == Color.self ||
                Style.self == MeshGradient.self ||
                Style.self == SeparatorShapeStyle.self ||
                Style.self == HierarchicalShapeStyle.self else {
            return nil
        }

        let environment = inputs.base.cachedEnvironment.value.environment
        let resolver = DirectShapeStyleResolver(
            style: OptionalAttribute(view[\.style]._attribute),
            environment: environment,
            role: Content.role,
            animationsDisabled: inputs.base.options.contains(.animationsDisabled),
            helper: AnimatableAttributeHelper(
                _phase: inputs.base.phase,
                _time: inputs.base.time,
                _transaction: inputs.base.transaction
            )
        )
        let resolvedStyle = graph.makeStatefulRule(resolver)
        resolvedStyle.flags = .transactional
        return resolvedStyle
    }

    public typealias Body = Never
}

extension _ShapeView: LeafViewLayout {
    func sizeThatFits(in proposal: _ProposedSize) -> CGSize {
        shape.sizeThatFits(ProposedViewSize(proposal))
    }
}

@available(*, unavailable)
extension _ShapeView: Sendable {
}

extension _ShapeView: PrimitiveView, UnaryView {
}
