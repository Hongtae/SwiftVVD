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

extension AnimatedShape: ShapeStyledLeafView {
    typealias ShapeUpdateData = Void

    func shape(
        in size: CGSize
    ) -> (shape: _ShapeStyle_RenderedShape.Shape, frame: CGRect) {
        let frame = CGRect(origin: .zero, size: size)
        return (.path(shape.path(in: frame), fillStyle), frame)
    }

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

struct ShapeStyledResponderFilter<Content: ContentResponder>: StatefulRule {
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

struct ShapeStyleResolver<Style: ShapeStyle>:
    StatefulRule,
    ObservedAttribute,
    AsyncAttribute {
    typealias Value = _ShapeStyle_Pack

    var _style: OptionalAttribute<Style>
    var _mode: OptionalAttribute<_ShapeStyle_ResolverMode>
    var _environment: Attribute<EnvironmentValues>
    var role: ShapeRole
    var substrate: _ShapeStyle_Substrate?
    var animationsDisabled: Bool
    var helper: AnimatableAttributeHelper<_ShapeStyle_Pack>
    var tracker: _PropertyListTracker

    init(
        style: OptionalAttribute<Style>,
        mode: OptionalAttribute<_ShapeStyle_ResolverMode> = OptionalAttribute(),
        environment: Attribute<EnvironmentValues>,
        role: ShapeRole,
        substrate: _ShapeStyle_Substrate? = nil,
        animationsDisabled: Bool,
        helper: AnimatableAttributeHelper<_ShapeStyle_Pack>
    ) {
        self._style = style
        self._mode = mode
        self._environment = environment
        self.role = role
        self.substrate = substrate
        self.animationsDisabled = animationsDisabled
        self.helper = helper
        self.tracker = _PropertyListTracker()
    }

    mutating func updateValue() {
        let isInitialValue = !context.hasValue
        let styleValue = _style.changedValue(
            options: AGValueOptions(rawValue: 0)
        )
        let modeValue = _mode.changedValue(
            options: AGValueOptions(rawValue: 0)
        )
        let environmentValue = _environment.changedValue(
            options: AGValueOptions(rawValue: 0)
        )
        let environment = environmentValue.value
        let needsResolution = isInitialValue ||
            (styleValue?.changed ?? false) ||
            (modeValue?.changed ?? false) ||
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
        let style: any ShapeStyle = styleValue?.value ??
            AnyShapeStyle(ForegroundStyle())
        let mode = modeValue?.value
        let target = resolvedPack(
            style: style,
            mode: mode,
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
        style: any ShapeStyle,
        mode: _ShapeStyle_ResolverMode?,
        environment: EnvironmentValues
    ) -> _ShapeStyle_Pack {
        let foregroundLevels = max(
            Int(mode?.foregroundLevels ?? 1),
            1
        )
        var shape = _ShapeStyle_Shape(
            operation: .resolveStyle(
                name: .foreground,
                levels: 0..<foregroundLevels
            ),
            environment: environment,
            role: role,
            substrate: substrate
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

    func shape(
        in size: CGSize
    ) -> (shape: _ShapeStyle_RenderedShape.Shape, frame: CGRect) {
        let frame = CGRect(origin: .zero, size: size)
        return (.path(shape.path(in: frame), fillStyle), frame)
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
        var outputs: _ViewOutputs
        if MemoryLayout<Content.AnimatableData>.size == 0 {
            outputs = Self.makeLeafView(
                view: view,
                inputs: inputs,
                styles: animatedStylePack,
                interpolatorGroup: nil
            )
            makeLeafLayout(&outputs, view: view, inputs: inputs)
        } else {
            let layoutShape: Attribute<AnimatedShape<Content>> = graph.makeRule(
                AnimatedShape.Init(
                    shape: animatedShape._attribute,
                    fillStyle: view[\.fillStyle]._attribute
                )
            )
            outputs = AnimatedShape<Content>.makeLeafView(
                view: _GraphValue(_attribute: layoutShape),
                inputs: inputs,
                styles: animatedStylePack,
                interpolatorGroup: nil
            )
            AnimatedShape<Content>.makeLeafLayout(
                &outputs,
                view: _GraphValue(_attribute: layoutShape),
                inputs: inputs
            )
        }
        return outputs
    }

    private static func makeAnimatedStylePack(
        view: _GraphValue<Self>,
        inputs: _ViewInputs,
        graph: _AGGraph
    ) -> Attribute<_ShapeStyle_Pack> {
        let environment = inputs.base.cachedEnvironment.value.environment
        let resolver = ShapeStyleResolver(
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

extension _ShapeView: ShapeStyledLeafView {
    typealias ShapeUpdateData = Void
}
