//
//  File: VisualEffect.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

public protocol VisualEffect: Sendable, Animatable {
    static func _makeVisualEffect(
        effect: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs

    static func _makeTransform(
        effect: _GraphValue<Self>,
        inputs: _ViewInputs
    ) -> _VisualEffectTransformOutputs
}

public struct _VisualEffectTransformOutputs {
    var transform: OptionalAttribute<ProjectionTransform>

    init(transform: OptionalAttribute<ProjectionTransform>) {
        self.transform = transform
    }
}

@available(*, unavailable)
extension _VisualEffectTransformOutputs: Sendable {
}

extension VisualEffect {
    public static func _makeTransform(
        effect: _GraphValue<Self>,
        inputs: _ViewInputs
    ) -> _VisualEffectTransformOutputs {
        _VisualEffectTransformOutputs(transform: OptionalAttribute())
    }

    func combining<Effect: VisualEffect>(
        _ effect: Effect
    ) -> CombinedVisualEffect<Self, Effect> {
        CombinedVisualEffect(first: self, second: effect)
    }
}

public struct EmptyVisualEffect: VisualEffect {
    public init() {
    }

    public static func _makeVisualEffect(
        effect: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        body(_Graph(), inputs)
    }

    public typealias AnimatableData = EmptyAnimatableData
}

private struct GeometryVisualEffect<Base: GeometryEffect>: VisualEffect, @unchecked Sendable {
    var base: Base

    static func _makeVisualEffect(
        effect: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        Base._makeView(modifier: effect[\.base], inputs: inputs, body: body)
    }

    static func _makeTransform(
        effect: _GraphValue<Self>,
        inputs: _ViewInputs
    ) -> _VisualEffectTransformOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("GeometryVisualEffect._makeTransform called outside an active _AGGraph context.")
        }
        let transform = graph.makeRule(
            GeometryEffectProjectionTransform(
                _base: effect[\.base]._attribute,
                _size: graph.makeRule { inputs.size.value.value }
            )
        )
        return _VisualEffectTransformOutputs(transform: OptionalAttribute(transform))
    }

    var animatableData: Base.AnimatableData {
        get { base.animatableData }
        set { base.animatableData = newValue }
    }
}

private struct GeometryEffectProjectionTransform<Base: GeometryEffect>: Rule {
    var _base: Attribute<Base>
    var _size: Attribute<CGSize>

    var value: ProjectionTransform {
        _base.value.effectValue(size: _size.value)
    }
}

private struct RendererVisualEffect<Base>: VisualEffect, @unchecked Sendable
where Base: Animatable & ViewModifier {
    var base: Base

    static func _makeVisualEffect(
        effect: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        Base._makeView(modifier: effect[\.base], inputs: inputs, body: body)
    }

    var animatableData: Base.AnimatableData {
        get { base.animatableData }
        set { base.animatableData = newValue }
    }
}

struct CombinedVisualEffect<First: VisualEffect, Second: VisualEffect>:
    VisualEffect,
    @unchecked Sendable
{
    var first: First
    var second: Second

    static func _makeVisualEffect(
        effect: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        Second._makeVisualEffect(effect: effect[\.second], inputs: inputs) { _, inputs in
            First._makeVisualEffect(effect: effect[\.first], inputs: inputs, body: body)
        }
    }

    static func _makeTransform(
        effect: _GraphValue<Self>,
        inputs: _ViewInputs
    ) -> _VisualEffectTransformOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("CombinedVisualEffect._makeTransform called outside an active _AGGraph context.")
        }
        let first = First._makeTransform(effect: effect[\.first], inputs: inputs).transform
        let second = Second._makeTransform(effect: effect[\.second], inputs: inputs).transform
        guard first.attribute != nil || second.attribute != nil else {
            return _VisualEffectTransformOutputs(transform: OptionalAttribute())
        }
        let transform = graph.makeRule(TransformCombiner(_first: first, _second: second))
        return _VisualEffectTransformOutputs(transform: OptionalAttribute(transform))
    }

    var animatableData: AnimatablePair<First.AnimatableData, Second.AnimatableData> {
        get { AnimatablePair(first.animatableData, second.animatableData) }
        set {
            first.animatableData = newValue.first
            second.animatableData = newValue.second
        }
    }

    private struct TransformCombiner: Rule {
        var _first: OptionalAttribute<ProjectionTransform>
        var _second: OptionalAttribute<ProjectionTransform>

        var value: ProjectionTransform {
            switch (_first.attribute?.value, _second.attribute?.value) {
            case let (first?, second?):
                return first.concatenating(second)
            case let (first?, nil):
                return first
            case let (nil, second?):
                return second
            case (nil, nil):
                return ProjectionTransform()
            }
        }
    }
}

extension ModifiedContent: @unchecked Sendable
where Content: VisualEffect, Modifier: VisualEffect {
}

extension ModifiedContent: Animatable
where Content: VisualEffect, Modifier: VisualEffect {
    public var animatableData: AnimatablePair<Content.AnimatableData, Modifier.AnimatableData> {
        get { AnimatablePair(content.animatableData, modifier.animatableData) }
        set {
            content.animatableData = newValue.first
            modifier.animatableData = newValue.second
        }
    }
}

extension ModifiedContent: VisualEffect
where Content: VisualEffect, Modifier: VisualEffect {
    public static func _makeVisualEffect(
        effect: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        Modifier._makeVisualEffect(effect: effect[\.modifier], inputs: inputs) { _, inputs in
            Content._makeVisualEffect(effect: effect[\.content], inputs: inputs, body: body)
        }
    }

}

public struct GeometryProxy {
    var owner: AGWeakAttribute
    var _size: WeakAttribute<ViewSize>
    var _environment: WeakAttribute<EnvironmentValues>
    var _transform: WeakAttribute<ViewTransform>
    var _position: WeakAttribute<CGPoint>
    var _safeAreaInsets: WeakAttribute<SafeAreaInsets>
    var _seed: UInt32

    init(
        owner: AGAttribute,
        size: Attribute<ViewSize>,
        environment: Attribute<EnvironmentValues>,
        transform: Attribute<ViewTransform>,
        position: Attribute<CGPoint>,
        safeAreaInsets: Attribute<SafeAreaInsets>?,
        seed: UInt32
    ) {
        guard let graph = _AGGraph.current,
              let owner = graph.weakAttributeIfValid(for: owner) else {
            fatalError("GeometryProxy.init called outside a valid AttributeGraph owner.")
        }
        self.owner = owner
        self._size = size.asWeak()
        self._environment = environment.asWeak()
        self._transform = transform.asWeak()
        self._position = position.asWeak()
        self._safeAreaInsets = safeAreaInsets?.asWeak() ?? WeakAttribute()
        self._seed = seed
    }

    public var size: CGSize {
        read(_size).value
    }

    public subscript<T>(anchor: Anchor<T>) -> T {
        guard let graph = _AGGraph.current else {
            fatalError("GeometryProxy anchor resolution requires an active AttributeGraph context.")
        }
        guard owner.isValid(in: graph), _position.isValid(in: graph),
              _transform.isValid(in: graph) else {
            return anchor.box.defaultValue
        }
        var transform = _transform.toStrong().value
        transform.appendPosition(_position.toStrong().value)
        return anchor.box.convert(to: transform)
    }

    public var safeAreaInsets: EdgeInsets {
        readOptional(_safeAreaInsets)?.value ?? EdgeInsets()
    }

    public func bounds(of coordinateSpace: NamedCoordinateSpace) -> CGRect? {
        let transform = read(_transform)
        guard let namedSize = transform.size(ofNamedCoordinateSpace: coordinateSpace.name) else {
            return nil
        }
        let localOriginInNamed = point(.zero, in: coordinateSpace)
        let localXInNamed = point(CGPoint(x: 1, y: 0), in: coordinateSpace)
        let localYInNamed = point(CGPoint(x: 0, y: 1), in: coordinateSpace)
        let localToNamed = CGAffineTransform(
            a: localXInNamed.x - localOriginInNamed.x,
            b: localXInNamed.y - localOriginInNamed.y,
            c: localYInNamed.x - localOriginInNamed.x,
            d: localYInNamed.y - localOriginInNamed.y,
            tx: localOriginInNamed.x,
            ty: localOriginInNamed.y
        )
        let determinant = localToNamed.a * localToNamed.d - localToNamed.b * localToNamed.c
        guard abs(determinant) > CGFloat.ulpOfOne else {
            return nil
        }
        let namedToLocal = localToNamed.inverted()
        return CGRect(origin: .zero, size: namedSize).applying(namedToLocal).standardized
    }

    public func frame<Space: CoordinateSpaceProtocol>(in coordinateSpace: Space) -> CGRect {
        let rect = CGRect(origin: .zero, size: size)
        let points = [
            rect.origin,
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.maxY),
        ].map { point($0, in: coordinateSpace) }
        return CGRect(cornerPoints: points)
    }

    /// Resolves this view's frame and clips it to each enclosing scroll
    /// viewport before returning it in the requested coordinate space.
    func frameClippedToScrollViews(
        in coordinateSpace: CoordinateSpace
    ) -> (frame: CGRect, exact: Bool) {
        var transform = read(_transform)
        transform.appendPosition(read(_position))
        var frame = CGRect(origin: .zero, size: size)
        let exact = frame.convertAndClipToScrollView(
            to: coordinateSpace,
            transform: transform
        )
        return (frame, exact)
    }

    public var containerCornerInsets: RectangleCornerInsets {
        RectangleCornerInsets()
    }

    private func point<Space: CoordinateSpaceProtocol>(
        _ point: CGPoint,
        in coordinateSpace: Space
    ) -> CGPoint {
        if coordinateSpace.coordinateSpace == .local {
            return point
        }

        let transform = read(_transform)
        var points = [CGPoint.zero, point]
        transform.convertGlobal(from: .local, points: &points)
        let position = read(_position)
        let adjustment = CGSize(
            width: position.x - points[0].x,
            height: position.y - points[0].y
        )
        points[1].x += adjustment.width
        points[1].y += adjustment.height
        points.removeFirst()
        transform.convertGlobal(to: coordinateSpace.coordinateSpace, points: &points)
        return points[0]
    }

    private func read<Value>(_ attribute: WeakAttribute<Value>) -> Value {
        guard let graph = _AGGraph.current,
              owner.isValid(in: graph),
              attribute.isValid(in: graph) else {
            fatalError("GeometryProxy was accessed outside its valid graph lifetime.")
        }
        return attribute.toStrong().value
    }

    private func readOptional<Value>(_ attribute: WeakAttribute<Value>) -> Value? {
        guard let graph = _AGGraph.current,
              owner.isValid(in: graph),
              attribute.isValid(in: graph) else {
            return nil
        }
        return attribute.toStrong().value
    }
}

enum ThreadGeometryProxyData {
    private static let storage = _AGThreadLocal<GeometryProxy?>(nil)

    static var current: GeometryProxy? {
        storage.value
    }

    static func withValue<Result>(
        _ proxy: GeometryProxy,
        _ body: () throws -> Result
    ) rethrows -> Result {
        try storage.withValue(proxy, operation: body)
    }
}

@available(*, unavailable)
extension GeometryProxy: Sendable {
}

private struct VisualEffectModifier<Effect: VisualEffect>: ViewModifier {
    var effect: @Sendable (EmptyVisualEffect, GeometryProxy) -> Effect

    typealias Body = Never

    static func _makeView(
        modifier: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("VisualEffectModifier._makeView called outside an active _AGGraph context.")
        }
        let child = graph.makeStatefulRule(
            Child(
                _modifier: modifier._attribute,
                _position: inputs.position,
                _size: inputs.size,
                _transform: inputs.transform,
                _environment: inputs.base.cachedEnvironment.value.environment,
                _safeAreaInsets: inputs.safeAreaInsets,
                seed: 0
            )
        )
        return Effect._makeVisualEffect(
            effect: _GraphValue(_attribute: child),
            inputs: inputs,
            body: body
        )
    }

    static func _makeViewList(
        modifier: _GraphValue<Self>,
        inputs: _ViewListInputs,
        body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs
    ) -> _ViewListOutputs {
        guard _AGGraph.current != nil else {
            fatalError("VisualEffectModifier._makeViewList called outside an active _AGGraph context.")
        }
        var outputs = body(_Graph(), inputs)
        outputs.multiModifier(modifier, inputs: inputs)
        return outputs
    }

    private struct Child: StatefulRule, AsyncAttribute {
        typealias Value = Effect

        var _modifier: Attribute<VisualEffectModifier>
        var _position: Attribute<CGPoint>
        var _size: Attribute<ViewSize>
        var _transform: Attribute<ViewTransform>
        var _environment: Attribute<EnvironmentValues>
        var _safeAreaInsets: OptionalAttribute<SafeAreaInsets>
        var seed: UInt32

        mutating func updateValue() {
            seed &+= 1
            let proxy = GeometryProxy(
                owner: context.attribute.identifier,
                size: _size,
                environment: _environment,
                transform: _transform,
                position: _position,
                safeAreaInsets: _safeAreaInsets.attribute,
                seed: seed
            )
            let value = _modifier.value.effect(EmptyVisualEffect(), proxy)
            _AGGraph.setStatefulOutput(value)
        }
    }
}

extension View {
    nonisolated public func visualEffect<Effect: VisualEffect>(
        _ effect: @escaping @Sendable (EmptyVisualEffect, GeometryProxy) -> Effect
    ) -> some View {
        modifier(VisualEffectModifier(effect: effect))
    }
}

extension VisualEffect {
    public func offset(_ offset: CGSize) -> some VisualEffect {
        combining(GeometryVisualEffect(base: _OffsetEffect(offset: offset)))
    }

    public func offset(x: CGFloat = 0, y: CGFloat = 0) -> some VisualEffect {
        offset(CGSize(width: x, height: y))
    }

    public func rotationEffect(
        _ angle: Angle,
        anchor: UnitPoint = .center
    ) -> some VisualEffect {
        combining(GeometryVisualEffect(base: _RotationEffect(angle: angle, anchor: anchor)))
    }

    public func blendMode(_ blendMode: BlendMode) -> some VisualEffect {
        combining(RendererVisualEffect(base: _BlendModeEffect(blendMode: blendMode)))
    }

    public func contrast(_ amount: Double) -> some VisualEffect {
        combining(RendererVisualEffect(base: _ContrastEffect(amount: amount)))
    }

    public func blur(radius: CGFloat, opaque: Bool = false) -> some VisualEffect {
        combining(RendererVisualEffect(base: _BlurEffect(radius: radius, opaque: opaque)))
    }

    public func grayscale(_ amount: Double) -> some VisualEffect {
        combining(RendererVisualEffect(base: _GrayscaleEffect(amount: amount)))
    }

    public func rotation3DEffect(
        _ angle: Angle,
        axis: (x: CGFloat, y: CGFloat, z: CGFloat),
        anchor: UnitPoint = .center,
        anchorZ: CGFloat = 0,
        perspective: CGFloat = 1
    ) -> some VisualEffect {
        combining(
            GeometryVisualEffect(
                base: _Rotation3DEffect(
                    angle: angle,
                    axis: axis,
                    anchor: anchor,
                    anchorZ: anchorZ,
                    perspective: perspective
                )
            )
        )
    }

    public func opacity(_ opacity: Double) -> some VisualEffect {
        combining(RendererVisualEffect(base: _OpacityEffect(opacity: opacity)))
    }

    public func brightness(_ amount: Double) -> some VisualEffect {
        combining(RendererVisualEffect(base: _BrightnessEffect(amount: amount)))
    }

    public func transformEffect(_ transform: ProjectionTransform) -> some VisualEffect {
        let affine: CGAffineTransform
        if transform.isAffine {
            affine = CGAffineTransform(
                a: transform.m11,
                b: transform.m12,
                c: transform.m21,
                d: transform.m22,
                tx: transform.m31,
                ty: transform.m32
            )
        } else {
            affine = .identity
        }
        return combining(GeometryVisualEffect(base: _TransformEffect(transform: affine)))
    }

    public func transformEffect(_ transform: CGAffineTransform) -> some VisualEffect {
        combining(GeometryVisualEffect(base: _TransformEffect(transform: transform)))
    }

    public func saturation(_ amount: Double) -> some VisualEffect {
        combining(RendererVisualEffect(base: _SaturationEffect(amount: amount)))
    }

    public func scaleEffect(
        _ scale: CGSize,
        anchor: UnitPoint = .center
    ) -> some VisualEffect {
        combining(GeometryVisualEffect(base: _ScaleEffect(scale: scale, anchor: anchor)))
    }

    public func scaleEffect(
        _ scale: CGFloat,
        anchor: UnitPoint = .center
    ) -> some VisualEffect {
        scaleEffect(CGSize(width: scale, height: scale), anchor: anchor)
    }

    public func scaleEffect(
        x: CGFloat = 1,
        y: CGFloat = 1,
        anchor: UnitPoint = .center
    ) -> some VisualEffect {
        scaleEffect(CGSize(width: x, height: y), anchor: anchor)
    }

    public func hueRotation(_ angle: Angle) -> some VisualEffect {
        combining(RendererVisualEffect(base: _HueRotationEffect(angle: angle)))
    }
}
