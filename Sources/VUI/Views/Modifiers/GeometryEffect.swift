//
//  File: GeometryEffect.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

public protocol GeometryEffect: Animatable, ViewModifier where Self.Body == Never {
    func effectValue(size: CGSize) -> ProjectionTransform
    static var _affectsLayout: Bool { get }
}

private protocol GeometryEffectProvider {
    associatedtype Effect: GeometryEffect

    static func resolve(
        effect: Effect,
        origin: inout CGPoint,
        size: CGSize,
        layoutDirection: LayoutDirection
    ) -> DisplayList.Effect
}

private struct DefaultGeometryEffectProvider<Effect: GeometryEffect>:
    GeometryEffectProvider {
    static func resolve(
        effect: Effect,
        origin: inout CGPoint,
        size: CGSize,
        layoutDirection: LayoutDirection
    ) -> DisplayList.Effect {
        var transform = effect.effectValue(size: size)
        if layoutDirection == .rightToLeft {
            transform.flipRTL(width: size.width)
        }

        guard transform.isInvertible else {
            Log.warning("ignoring singular matrix: \(transform)")
            return .identity
        }

        if transform.isAffine,
           transform.m11 == 1,
           transform.m12 == 0,
           transform.m21 == 0,
           transform.m22 == 1 {
            origin.x += transform.m31
            origin.y += transform.m32
            return .identity
        }
        return .transform(transform)
    }
}

private struct GeometryEffectTransform<Effect: GeometryEffect>:
    Rule, AsyncAttribute {
    var _effect: Attribute<Effect>
    var _size: Attribute<CGSize>
    var _position: Attribute<CGPoint>
    var _transform: Attribute<ViewTransform>
    var _layoutDirection: Attribute<LayoutDirection>

    var value: ViewTransform {
        var transform = _transform.value
        transform.appendPosition(_position.value)

        var projection = _effect.value.effectValue(size: _size.value)
        if _layoutDirection.value == .rightToLeft {
            projection.flipRTL(width: _size.value.width)
        }
        transform.appendProjectionTransform(projection, inverse: true)
        return transform
    }
}

private struct RoundedSize: Rule, AsyncAttribute {
    var _position: Attribute<CGPoint>
    var _size: Attribute<ViewSize>
    var _pixelLength: Attribute<CGFloat>

    var value: ViewSize {
        var frame = ViewFrame(
            origin: _position.value,
            size: _size.value
        )
        frame.round(toMultipleOf: _pixelLength.value)
        return frame.size
    }
}

private struct GeometryEffectDisplayList<Provider: GeometryEffectProvider>:
    Rule, AsyncAttribute {
    var identity: _DisplayList_Identity
    var _effect: Attribute<Provider.Effect>
    var _position: Attribute<CGPoint>
    var _size: Attribute<CGSize>
    var _layoutDirection: Attribute<LayoutDirection>
    var _containerPosition: Attribute<CGPoint>
    var _content: OptionalAttribute<DisplayList>
    var options: DisplayList.Options

    var value: DisplayList {
        guard let content = _content.value else {
            return DisplayList()
        }

        let position = _position.value
        let containerPosition = _containerPosition.value
        let size = _size.value
        var origin = CGPoint(
            x: position.x - containerPosition.x,
            y: position.y - containerPosition.y
        )
        let effect = Provider.resolve(
            effect: _effect.value,
            origin: &origin,
            size: size,
            layoutDirection: _layoutDirection.value
        )
        var item = DisplayList.Item(
            effect: effect,
            contents: content,
            frame: CGRect(origin: origin, size: size),
            identity: identity,
            version: DisplayList.Version(forUpdate: ())
        )
        item.canonicalize(options: options)

        var result = DisplayList()
        result.items.append(item)
        result.recordInterpolationBounds(item.frame)
        result.numericValue = content.numericValue
        return result
    }
}

enum _GeometryEffectSupport {
    static func makeView<Effect: GeometryEffect>(
        modifier: _GraphValue<Effect>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("\(Effect.self)._makeView called outside an active _AGGraph context.")
        }
        guard inputs.needsGeometry else {
            return body(_Graph(), inputs)
        }

        let cachedEnvironmentAttribute = inputs.base.cachedEnvironment
        var cachedEnvironment = cachedEnvironmentAttribute.value
        let layoutDirection = cachedEnvironment.attribute(
            id: .layoutDirection,
            \.layoutDirection
        )
        let sizeAttr = cachedEnvironment.animatedCGSize(for: inputs)
        let positionAttr = cachedEnvironment.animatedPosition(for: inputs)
        let pixelLength = cachedEnvironment.attribute(
            id: .pixelLength,
            \.animationPixelLength
        )
        cachedEnvironmentAttribute.value = cachedEnvironment
        let transformAttr = graph.makeRule(
            GeometryEffectTransform(
                _effect: modifier._attribute,
                _size: sizeAttr,
                _position: positionAttr,
                _transform: inputs.transform,
                _layoutDirection: layoutDirection
            )
        )

        var modifiedInputs = inputs
        modifiedInputs.base.options.formUnion(
            _GraphInputs.Options(rawValue: 0x1c)
        )
        modifiedInputs.transform = transformAttr
        guard let zeroPoint = ViewGraph.current.zeroPointAttr else {
            fatalError("GeometryEffect requires an instantiated ViewGraph zero point.")
        }
        modifiedInputs.position = zeroPoint
        modifiedInputs.containerPosition = zeroPoint
        modifiedInputs.size = graph.makeRule(
            RoundedSize(
                _position: inputs.position,
                _size: inputs.size,
                _pixelLength: pixelLength
            )
        )
        var outputs = body(_Graph(), modifiedInputs)
        if let content = outputs.preferences.reducedValue(
            for: DisplayList.Key.self,
            in: graph
        ) {
            var displayEnvironment = cachedEnvironmentAttribute.value
            let displayPosition = displayEnvironment.animatedPosition(
                for: inputs
            )
            let displaySize = displayEnvironment.animatedCGSize(for: inputs)
            cachedEnvironmentAttribute.value = displayEnvironment

            var identityInputs = inputs
            let displayList = graph.makeRule(
                GeometryEffectDisplayList<
                    DefaultGeometryEffectProvider<Effect>
                >(
                    identity: identityInputs.pushIdentity(),
                    _effect: modifier._attribute,
                    _position: displayPosition,
                    _size: displaySize,
                    _layoutDirection: layoutDirection,
                    _containerPosition: inputs.containerPosition,
                    _content: OptionalAttribute(content),
                    options: inputs[DisplayList.Options.self]
                )
            )
            outputs.preferences.setValue(
                displayList.identifier,
                for: DisplayList.Key.self
            )
        }
        return outputs
    }
}

private struct _ResolvedGeometryEffectModifier<Base: GeometryEffect>: ViewModifier {
    var base: Base

    typealias Body = Never

    static func _makeView(
        modifier: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        _GeometryEffectSupport.makeView(
            modifier: modifier[\.base],
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
            fatalError("\(Self.self)._makeViewList called outside an active _AGGraph context.")
        }
        var outputs = body(_Graph(), inputs)
        outputs.multiModifier(modifier, inputs: inputs)
        return outputs
    }
}

extension GeometryEffect {
    public static var _affectsLayout: Bool {
        true
    }

    public static func _makeView(
        modifier: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        guard inputs.needsGeometry else {
            return body(_Graph(), inputs)
        }
        var modifier = modifier
        Self._makeAnimatable(value: &modifier, inputs: inputs.base)
        return _GeometryEffectSupport.makeView(
            modifier: modifier,
            inputs: inputs,
            body: body
        )
    }

    public static func _makeViewList(
        modifier: _GraphValue<Self>,
        inputs: _ViewListInputs,
        body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs
    ) -> _ViewListOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("\(Self.self)._makeViewList called outside an active _AGGraph context.")
        }
        var modifier = modifier
        Self._makeAnimatable(value: &modifier, inputs: inputs.base)
        let resolvedModifier: Attribute<_ResolvedGeometryEffectModifier<Self>> = graph.makeRule {
            _ResolvedGeometryEffectModifier(base: modifier._attribute.value)
        }
        var outputs = body(_Graph(), inputs)
        outputs.multiModifier(
            _GraphValue(_attribute: resolvedModifier),
            inputs: inputs
        )
        return outputs
    }
}

public struct _IgnoredByLayoutEffect<Base>: GeometryEffect where Base: GeometryEffect {
    public var base: Base

    public static var _affectsLayout: Bool {
        false
    }

    @inlinable public init(_ base: Base) {
        self.base = base
    }

    public func effectValue(size: CGSize) -> ProjectionTransform {
        base.effectValue(size: size)
    }

    public var animatableData: Base.AnimatableData {
        get { base.animatableData }
        set { base.animatableData = newValue }
    }

    public typealias AnimatableData = Base.AnimatableData
    public typealias Body = Never
}

extension _IgnoredByLayoutEffect: Equatable where Base: Equatable {}

@available(*, unavailable)
extension _IgnoredByLayoutEffect: Sendable {
}

extension GeometryEffect {
    @inlinable public func ignoredByLayout() -> _IgnoredByLayoutEffect<Self> {
        _IgnoredByLayoutEffect(self)
    }
}

public struct _ProjectionEffect: GeometryEffect, Equatable {
    public var transform: ProjectionTransform

    @inlinable public init(transform: ProjectionTransform) {
        self.transform = transform
    }

    public func effectValue(size: CGSize) -> ProjectionTransform {
        transform
    }

    public typealias AnimatableData = EmptyAnimatableData
    public typealias Body = Never
}

public struct _TransformEffect: GeometryEffect, Equatable {
    public var transform: CGAffineTransform

    @inlinable public init(transform: CGAffineTransform) {
        self.transform = transform
    }

    public func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(transform)
    }

    public typealias AnimatableData = EmptyAnimatableData
    public typealias Body = Never
}

public struct _Rotation3DEffect: GeometryEffect, Equatable {
    public var angle: Angle
    public var axis: (x: CGFloat, y: CGFloat, z: CGFloat)
    public var anchor: UnitPoint
    public var anchorZ: CGFloat
    public var perspective: CGFloat

    @inlinable public init(
        angle: Angle,
        axis: (x: CGFloat, y: CGFloat, z: CGFloat),
        anchor: UnitPoint = .center,
        anchorZ: CGFloat = 0,
        perspective: CGFloat = 1
    ) {
        self.angle = angle
        self.axis = axis
        self.anchor = anchor
        self.anchorZ = anchorZ
        self.perspective = perspective
    }

    public func effectValue(size: CGSize) -> ProjectionTransform {
        let anchorPoint = (
            x: anchor.x * size.width,
            y: anchor.y * size.height,
            z: anchorZ
        )
        let maxDimension = size.width <= size.height ? size.height : size.width
        let projectionDistance = maxDimension / perspective

        var transform = Rotation3DMatrix4x4.translation(
            x: -anchorPoint.x,
            y: -anchorPoint.y,
            z: -anchorPoint.z
        )
        transform = transform.concatenating(
            Rotation3DMatrix4x4.rotation(angle: angle.radians, axis: axis)
        )
        if projectionDistance.isFinite {
            transform = transform.concatenating(.perspective(distance: projectionDistance))
        }
        transform = transform.concatenating(
            .translation(x: anchorPoint.x, y: anchorPoint.y, z: anchorPoint.z)
        )
        return transform.projectionTransform
    }

    public typealias AnimatableData = AnimatablePair<
        Angle.AnimatableData,
        AnimatablePair<
            CGFloat,
            AnimatablePair<
                CGFloat,
                AnimatablePair<
                    CGFloat,
                    AnimatablePair<UnitPoint.AnimatableData, AnimatablePair<CGFloat, CGFloat>>
                >
            >
        >
    >

    public var animatableData: AnimatableData {
        get {
            let scale: CGFloat = 128
            return AnimatableData(
                angle.radians * Double(scale),
                AnimatablePair(
                    axis.x * scale,
                    AnimatablePair(
                        axis.y * scale,
                        AnimatablePair(
                            axis.z * scale,
                            AnimatablePair(
                                UnitPoint.AnimatableData(anchor.x * scale, anchor.y * scale),
                                AnimatablePair(anchorZ, perspective * scale)
                            )
                        )
                    )
                )
            )
        }
        set {
            let scale: CGFloat = 128
            angle.radians = newValue.first / Double(scale)
            axis.x = newValue.second.first / scale
            axis.y = newValue.second.second.first / scale
            axis.z = newValue.second.second.second.first / scale
            let anchorData = newValue.second.second.second.second.first
            anchor = UnitPoint(x: anchorData.first / scale, y: anchorData.second / scale)
            let depthData = newValue.second.second.second.second.second
            anchorZ = depthData.first
            perspective = depthData.second / scale
        }
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.angle == rhs.angle &&
        lhs.axis.x == rhs.axis.x &&
        lhs.axis.y == rhs.axis.y &&
        lhs.axis.z == rhs.axis.z &&
        lhs.anchor == rhs.anchor &&
        lhs.anchorZ == rhs.anchorZ &&
        lhs.perspective == rhs.perspective
    }

    public typealias Body = Never
}

private struct Rotation3DMatrix4x4 {
    typealias Row = (x: CGFloat, y: CGFloat, z: CGFloat, w: CGFloat)

    var values: (Row, Row, Row, Row)

    static func identity() -> Self {
        Self(values: (
            (1, 0, 0, 0),
            (0, 1, 0, 0),
            (0, 0, 1, 0),
            (0, 0, 0, 1)
        ))
    }

    static func translation(x: CGFloat, y: CGFloat, z: CGFloat) -> Self {
        Self(values: (
            (1, 0, 0, 0),
            (0, 1, 0, 0),
            (0, 0, 1, 0),
            (x, y, z, 1)
        ))
    }

    static func perspective(distance: CGFloat) -> Self {
        Self(values: (
            (1, 0, 0, 0),
            (0, 1, 0, 0),
            (0, 0, 1, -1 / distance),
            (0, 0, 0, 1)
        ))
    }

    static func rotation(angle: Double, axis: (x: CGFloat, y: CGFloat, z: CGFloat)) -> Self {
        let length = sqrt(axis.x * axis.x + axis.y * axis.y + axis.z * axis.z)
        guard length != 0 else {
            return identity()
        }
        let x = axis.x / length
        let y = axis.y / length
        let z = axis.z / length
        let cosine = CGFloat(cos(angle))
        let sine = CGFloat(sin(angle))
        let inverseCosine = 1 - cosine
        return Self(values: (
            (
                inverseCosine * x * x + cosine,
                inverseCosine * x * y + sine * z,
                inverseCosine * x * z - sine * y,
                0
            ),
            (
                inverseCosine * x * y - sine * z,
                inverseCosine * y * y + cosine,
                inverseCosine * y * z + sine * x,
                0
            ),
            (
                inverseCosine * x * z + sine * y,
                inverseCosine * y * z - sine * x,
                inverseCosine * z * z + cosine,
                0
            ),
            (0, 0, 0, 1)
        ))
    }

    func concatenating(_ rhs: Self) -> Self {
        let lhsRows = [values.0, values.1, values.2, values.3]
        let rhsColumns = [
            (rhs.values.0.x, rhs.values.1.x, rhs.values.2.x, rhs.values.3.x),
            (rhs.values.0.y, rhs.values.1.y, rhs.values.2.y, rhs.values.3.y),
            (rhs.values.0.z, rhs.values.1.z, rhs.values.2.z, rhs.values.3.z),
            (rhs.values.0.w, rhs.values.1.w, rhs.values.2.w, rhs.values.3.w),
        ]
        func dot(_ row: Row, _ column: Row) -> CGFloat {
            row.x * column.x + row.y * column.y + row.z * column.z + row.w * column.w
        }
        return Self(values: (
            (
                dot(lhsRows[0], rhsColumns[0]),
                dot(lhsRows[0], rhsColumns[1]),
                dot(lhsRows[0], rhsColumns[2]),
                dot(lhsRows[0], rhsColumns[3])
            ),
            (
                dot(lhsRows[1], rhsColumns[0]),
                dot(lhsRows[1], rhsColumns[1]),
                dot(lhsRows[1], rhsColumns[2]),
                dot(lhsRows[1], rhsColumns[3])
            ),
            (
                dot(lhsRows[2], rhsColumns[0]),
                dot(lhsRows[2], rhsColumns[1]),
                dot(lhsRows[2], rhsColumns[2]),
                dot(lhsRows[2], rhsColumns[3])
            ),
            (
                dot(lhsRows[3], rhsColumns[0]),
                dot(lhsRows[3], rhsColumns[1]),
                dot(lhsRows[3], rhsColumns[2]),
                dot(lhsRows[3], rhsColumns[3])
            )
        ))
    }

    var projectionTransform: ProjectionTransform {
        var transform = ProjectionTransform()
        transform.m11 = values.0.x
        transform.m12 = values.0.y
        transform.m13 = values.0.w
        transform.m21 = values.1.x
        transform.m22 = values.1.y
        transform.m23 = values.1.w
        transform.m31 = values.3.x
        transform.m32 = values.3.y
        transform.m33 = values.3.w
        return transform
    }
}

public struct _OffsetEffect: GeometryEffect, Equatable {
    public var offset: CGSize

    @inlinable public init(offset: CGSize) {
        self.offset = offset
    }

    public func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: offset.width, y: offset.height))
    }

    public var animatableData: CGSize.AnimatableData {
        get { offset.animatableData }
        set { offset.animatableData = newValue }
    }

    public typealias Body = Never
}

public struct _RotationEffect: GeometryEffect, Equatable {
    public var angle: Angle
    public var anchor: UnitPoint

    @inlinable public init(angle: Angle, anchor: UnitPoint = .center) {
        self.angle = angle
        self.anchor = anchor
    }

    public func effectValue(size: CGSize) -> ProjectionTransform {
        let anchorPoint = CGPoint(
            x: anchor.x * size.width,
            y: anchor.y * size.height
        )
        let cosine = cos(angle.radians)
        let sine = sin(angle.radians)
        let transform = CGAffineTransform(
            a: cosine,
            b: sine,
            c: -sine,
            d: cosine,
            tx: anchorPoint.x - anchorPoint.x * cosine + anchorPoint.y * sine,
            ty: anchorPoint.y - anchorPoint.x * sine - anchorPoint.y * cosine
        )
        return ProjectionTransform(transform)
    }

    public typealias AnimatableData = AnimatablePair<Angle.AnimatableData, UnitPoint.AnimatableData>

    public var animatableData: AnimatableData {
        get { AnimatableData(angle.animatableData, anchor.animatableData) }
        set {
            angle.animatableData = newValue.first
            anchor.animatableData = newValue.second
        }
    }

    public typealias Body = Never
}

public struct _ScaleEffect: GeometryEffect, Equatable {
    public var scale: CGSize
    public var anchor: UnitPoint

    @inlinable public init(scale: CGSize, anchor: UnitPoint = .center) {
        self.scale = scale
        self.anchor = anchor
    }

    public func effectValue(size: CGSize) -> ProjectionTransform {
        let tx = anchor.x * size.width * (1 - scale.width)
        let ty = anchor.y * size.height * (1 - scale.height)
        let transform = CGAffineTransform(
            a: scale.width,
            b: 0,
            c: 0,
            d: scale.height,
            tx: tx,
            ty: ty
        )
        return ProjectionTransform(transform)
    }

    public typealias AnimatableData = AnimatablePair<CGSize.AnimatableData, UnitPoint.AnimatableData>

    public var animatableData: AnimatableData {
        get { AnimatableData(scale.animatableData, anchor.animatableData) }
        set {
            scale.animatableData = newValue.first
            anchor.animatableData = newValue.second
        }
    }

    public typealias Body = Never
}

extension _OffsetEffect: ProtobufEncodableMessage, ProtobufDecodableMessage {
    func encode(to encoder: inout ProtobufEncoder) throws {
        if offset != .zero {
            try encoder.encodeMessageField(1, offset)
        }
    }

    init(from decoder: inout ProtobufDecoder) throws {
        var offset = CGSize.zero
        while !decoder.isAtEnd {
            let tag = try decoder.decodeVarint()
            let fieldNumber = tag >> 3
            let wireType = tag & 0x7
            if fieldNumber == 1, wireType == 2 {
                offset = try decoder.decodeMessage(CGSize.self)
            } else if fieldNumber == 1 {
                throw ProtobufDecoder.DecodingError.failed
            } else {
                try decoder.skipField(wireType: wireType)
            }
        }
        self.init(offset: offset)
    }
}

extension _ScaleEffect: ProtobufEncodableMessage, ProtobufDecodableMessage {
    func encode(to encoder: inout ProtobufEncoder) throws {
        if scale != CGSize(width: 1, height: 1) {
            try encoder.encodeMessageField(1, scale)
        }
        if anchor != .center {
            try encoder.encodeMessageField(2, anchor)
        }
    }

    init(from decoder: inout ProtobufDecoder) throws {
        var scale = CGSize(width: 1, height: 1)
        var anchor = UnitPoint.center
        while !decoder.isAtEnd {
            let tag = try decoder.decodeVarint()
            let fieldNumber = tag >> 3
            let wireType = tag & 0x7
            switch fieldNumber {
            case 1 where wireType == 2:
                scale = try decoder.decodeMessage(CGSize.self)
            case 2 where wireType == 2:
                anchor = try decoder.decodeMessage(UnitPoint.self)
            case 1, 2:
                throw ProtobufDecoder.DecodingError.failed
            default:
                try decoder.skipField(wireType: wireType)
            }
        }
        self.init(scale: scale, anchor: anchor)
    }
}

extension _RotationEffect: ProtobufEncodableMessage, ProtobufDecodableMessage {
    func encode(to encoder: inout ProtobufEncoder) throws {
        if angle.radians != 0 {
            encoder.encodeDoubleFieldAlways(1, angle.radians)
        }
        if anchor != .center {
            try encoder.encodeMessageField(2, anchor)
        }
    }

    init(from decoder: inout ProtobufDecoder) throws {
        var angle = Angle.zero
        var anchor = UnitPoint.center
        while !decoder.isAtEnd {
            let tag = try decoder.decodeVarint()
            let fieldNumber = tag >> 3
            let wireType = tag & 0x7
            switch fieldNumber {
            case 1:
                angle = Angle(radians: try decoder.decodeDoubleField(wireType: wireType))
            case 2 where wireType == 2:
                anchor = try decoder.decodeMessage(UnitPoint.self)
            case 2:
                throw ProtobufDecoder.DecodingError.failed
            default:
                try decoder.skipField(wireType: wireType)
            }
        }
        self.init(angle: angle, anchor: anchor)
    }
}

extension View {
    @inlinable public func projectionEffect(_ transform: ProjectionTransform) -> some View {
        modifier(_ProjectionEffect(transform: transform))
    }

    @inlinable public func transformEffect(_ transform: CGAffineTransform) -> some View {
        modifier(_TransformEffect(transform: transform))
    }

    @inlinable public func rotation3DEffect(
        _ angle: Angle,
        axis: (x: CGFloat, y: CGFloat, z: CGFloat),
        anchor: UnitPoint = .center,
        anchorZ: CGFloat = 0,
        perspective: CGFloat = 1
    ) -> some View {
        modifier(
            _Rotation3DEffect(
                angle: angle,
                axis: axis,
                anchor: anchor,
                anchorZ: anchorZ,
                perspective: perspective
            )
        )
    }

    @inlinable public func offset(_ offset: CGSize) -> some View {
        modifier(_OffsetEffect(offset: offset))
    }

    @inlinable public func offset(x: CGFloat = 0, y: CGFloat = 0) -> some View {
        offset(CGSize(width: x, height: y))
    }

    @inlinable public func rotationEffect(_ angle: Angle, anchor: UnitPoint = .center) -> some View {
        modifier(_RotationEffect(angle: angle, anchor: anchor))
    }

    @inlinable public func scaleEffect(_ scale: CGSize, anchor: UnitPoint = .center) -> some View {
        modifier(_ScaleEffect(scale: scale, anchor: anchor))
    }

    @inlinable public func scaleEffect(_ s: CGFloat, anchor: UnitPoint = .center) -> some View {
        scaleEffect(CGSize(width: s, height: s), anchor: anchor)
    }

    @inlinable public func scaleEffect(
        x: CGFloat = 1,
        y: CGFloat = 1,
        anchor: UnitPoint = .center
    ) -> some View {
        scaleEffect(CGSize(width: x, height: y), anchor: anchor)
    }
}
