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

enum _GeometryEffectSupport {
    static func makeView<Modifier: ViewModifier>(
        modifier: _GraphValue<Modifier>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs,
        effectValue: @escaping (Modifier, CGSize) -> ProjectionTransform
    ) -> _ViewOutputs {
        guard let graph = AttributeGraph.current else {
            fatalError("\(Modifier.self)._makeView called outside an active AttributeGraph context.")
        }

        let sizeAttr = inputs.size
        let positionAttr = inputs.position
        let parentTransformAttr = inputs.transform
        // The view input transform drives child layout/render traversal. The
        // display-list rewrite below keeps already-produced drawing commands in
        // the same projected coordinate space.
        let effectAttr: Attribute<ProjectionTransform> = graph.makeRule {
            effectValue(modifier._attribute.value, sizeAttr.value.value)
        }
        let transformAttr: Attribute<ViewTransform> = graph.makeRule {
            var transform = parentTransformAttr.value
            transform.appendProjectionTransform(effectAttr.value, inverse: false)
            return transform
        }

        var modifiedInputs = inputs
        modifiedInputs.transform = transformAttr
        var outputs = body(_Graph(), modifiedInputs)
        applyProjectionEffect(
            to: &outputs.preferences,
            effect: effectAttr,
            position: positionAttr,
            graph: graph
        )
        return outputs
    }

    static func applyProjectionEffect(
        to preferences: inout PreferencesOutputs,
        effect: Attribute<ProjectionTransform>,
        position: Attribute<CGPoint>,
        graph: AttributeGraph
    ) {
        let displayNodes = preferences.values(for: DisplayList.Key.self)
        guard !displayNodes.isEmpty else { return }

        // Capture weak display-list handles so removed retained subgraphs do not
        // keep drawing commands alive after their AG nodes are invalidated.
        let weakNodes = displayNodes.compactMap { graph.weakAttributeIfValid(for: $0) }
        let transformedAttr: Attribute<DisplayList> = graph.makeRule {
            var combined = DisplayList.Key.defaultValue
            for weakNode in weakNodes where weakNode.isValid(in: graph) {
                let list = Attribute<DisplayList>(weakNode.toStrong()).value
                DisplayList.Key.reduce(value: &combined) { list }
            }
            return displayList(
                combined,
                applying: effect.value,
                at: position.value
            )
        }

        let displayKeyID = ObjectIdentifier(DisplayList.Key.self)
        preferences.preferences.removeAll {
            ObjectIdentifier($0.key) == displayKeyID
        }
        preferences.append(DisplayList.Key.self, node: transformedAttr.identifier)
    }

    private static func displayList(
        _ source: DisplayList,
        applying transform: ProjectionTransform,
        at position: CGPoint
    ) -> DisplayList {
        guard let affine = affineTransform(from: transform, at: position),
              !affine.isIdentity else {
            return source
        }

        let items = source.items
        let debugItems = source.debugItems
        var result = DisplayList()
        if !items.isEmpty {
            result.items.append { context in
                var context = context
                context.concatenate(affine)
                for item in items {
                    item(context)
                }
            }
        }
        if !debugItems.isEmpty {
            result.debugItems.append { context in
                var context = context
                context.concatenate(affine)
                for item in debugItems {
                    item(context)
                }
            }
        }
        return result
    }

    private static func affineTransform(
        from transform: ProjectionTransform,
        at position: CGPoint
    ) -> CGAffineTransform? {
        // The current renderer path accepts affine projection effects. Non-affine
        // perspective transforms need a later renderer-side implementation.
        guard transform.m13 == 0,
              transform.m23 == 0,
              transform.m33 == 1 else {
            return nil
        }
        let a = transform.m11
        let b = transform.m12
        let c = transform.m21
        let d = transform.m22
        let tx = transform.m31 + position.x - position.x * a - position.y * c
        let ty = transform.m32 + position.y - position.x * b - position.y * d
        return CGAffineTransform(a: a, b: b, c: c, d: d, tx: tx, ty: ty)
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
        var modifier = modifier
        Self._makeAnimatable(value: &modifier, inputs: inputs.base)
        return _GeometryEffectSupport.makeView(
            modifier: modifier,
            inputs: inputs,
            body: body
        ) { modifier, size in
            modifier.effectValue(size: size)
        }
    }

    public static func _makeViewList(
        modifier: _GraphValue<Self>,
        inputs: _ViewListInputs,
        body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs
    ) -> _ViewListOutputs {
        guard AttributeGraph.current != nil else {
            fatalError("\(Self.self)._makeViewList called outside an active AttributeGraph context.")
        }
        var outputs = body(_Graph(), inputs)
        outputs.multiModifier(modifier, inputs: inputs)
        return outputs
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

extension View {
    @inlinable public func offset(_ offset: CGSize) -> some View {
        modifier(_OffsetEffect(offset: offset))
    }

    @inlinable public func offset(x: CGFloat = 0, y: CGFloat = 0) -> some View {
        offset(CGSize(width: x, height: y))
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
