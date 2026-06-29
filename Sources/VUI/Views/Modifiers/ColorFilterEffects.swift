//
//  File: ColorFilterEffects.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

private struct _ColorFilterConfiguration {
    var record: DisplayList.ItemRecord.ColorFilterRecord
    var filter: GraphicsContext.Filter
    var isIdentity: Bool
}

private enum _ColorFilterEffectSupport {
    static func makeView<Modifier>(
        modifier: _GraphValue<Modifier>,
        configuration: @escaping (Modifier) -> _ColorFilterConfiguration,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs where Modifier: ViewModifier {
        guard let graph = AttributeGraph.current else {
            fatalError("\(Modifier.self)._makeView called outside an active AttributeGraph context.")
        }
        var outputs = body(_Graph(), inputs)
        applyColorFilter(
            to: &outputs.preferences,
            modifier: modifier,
            configuration: configuration,
            graph: graph
        )
        return outputs
    }

    static func makeViewList<Modifier>(
        modifier: _GraphValue<Modifier>,
        inputs: _ViewListInputs,
        body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs
    ) -> _ViewListOutputs where Modifier: ViewModifier {
        guard AttributeGraph.current != nil else {
            fatalError("\(Modifier.self)._makeViewList called outside an active AttributeGraph context.")
        }
        var outputs = body(_Graph(), inputs)
        outputs.multiModifier(modifier, inputs: inputs)
        return outputs
    }

    private static func applyColorFilter<Modifier>(
        to preferences: inout PreferencesOutputs,
        modifier: _GraphValue<Modifier>,
        configuration: @escaping (Modifier) -> _ColorFilterConfiguration,
        graph: AttributeGraph
    ) where Modifier: ViewModifier {
        let displayNodes = preferences.values(for: DisplayList.Key.self)
        guard !displayNodes.isEmpty else { return }

        let weakNodes = displayNodes.compactMap { graph.weakAttributeIfValid(for: $0) }
        let modifierAttr: Attribute<Modifier> = modifier._attribute
        let transformedAttr: Attribute<DisplayList> = graph.makeRule {
            var combined = DisplayList.Key.defaultValue
            for weakNode in weakNodes where weakNode.isValid(in: graph) {
                let list = Attribute<DisplayList>(weakNode.toStrong()).value
                DisplayList.Key.reduce(value: &combined) { list }
            }
            return displayList(
                combined,
                applying: configuration(modifierAttr.value)
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
        applying configuration: _ColorFilterConfiguration
    ) -> DisplayList {
        var result = DisplayList()
        result.debugItems.append(contentsOf: source.debugItems)
        result.recordInterpolationBounds(source.interpolationBounds)
        for effect in source.effects {
            result.appendEffect(
                effect.effect,
                contents: displayList(effect.contents, applying: configuration)
            )
        }

        guard !source.items.isEmpty else { return result }
        guard !configuration.isIdentity else {
            result.items.append(contentsOf: source.items)
            return result
        }

        let items = source.items
        result.appendColorFilterItem(
            bounds: source.interpolationBounds,
            filter: configuration.record
        ) { context in
            context.drawLayer { layerContext in
                layerContext.addFilter(configuration.filter)
                for item in items {
                    item(layerContext)
                }
            }
        }
        return result
    }
}

public struct _ContrastEffect: Equatable, Animatable, ViewModifier, Sendable {
    public var amount: Double

    @inlinable public init(amount: Double) {
        self.amount = amount
    }

    public var animatableData: Double {
        get { amount }
        set { amount = newValue }
    }

    public typealias Body = Never

    public static func _makeView(
        modifier: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        var modifier = modifier
        Self._makeAnimatable(value: &modifier, inputs: inputs.base)
        return _ColorFilterEffectSupport.makeView(
            modifier: modifier,
            configuration: { effect in
                _ColorFilterConfiguration(
                    record: DisplayList.ItemRecord.ColorFilterRecord(
                        kind: .contrast,
                        amount: effect.amount
                    ),
                    filter: .contrast(effect.amount),
                    isIdentity: effect.amount == 1
                )
            },
            inputs: inputs,
            body: body
        )
    }

    public static func _makeViewList(
        modifier: _GraphValue<Self>,
        inputs: _ViewListInputs,
        body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs
    ) -> _ViewListOutputs {
        _ColorFilterEffectSupport.makeViewList(
            modifier: modifier,
            inputs: inputs,
            body: body
        )
    }
}

public struct _GrayscaleEffect: Equatable, Animatable, ViewModifier, Sendable {
    public var amount: Double

    @inlinable public init(amount: Double) {
        self.amount = amount
    }

    public var animatableData: Double {
        get { amount }
        set { amount = newValue }
    }

    public typealias Body = Never

    public static func _makeView(
        modifier: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        var modifier = modifier
        Self._makeAnimatable(value: &modifier, inputs: inputs.base)
        return _ColorFilterEffectSupport.makeView(
            modifier: modifier,
            configuration: { effect in
                _ColorFilterConfiguration(
                    record: DisplayList.ItemRecord.ColorFilterRecord(
                        kind: .grayscale,
                        amount: effect.amount
                    ),
                    filter: .grayscale(effect.amount),
                    isIdentity: effect.amount == 0
                )
            },
            inputs: inputs,
            body: body
        )
    }

    public static func _makeViewList(
        modifier: _GraphValue<Self>,
        inputs: _ViewListInputs,
        body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs
    ) -> _ViewListOutputs {
        _ColorFilterEffectSupport.makeViewList(
            modifier: modifier,
            inputs: inputs,
            body: body
        )
    }
}

public struct _BrightnessEffect: Equatable, Animatable, ViewModifier, Sendable {
    public var amount: Double

    @inlinable public init(amount: Double) {
        self.amount = amount
    }

    public var animatableData: Double {
        get { amount }
        set { amount = newValue }
    }

    public typealias Body = Never

    public static func _makeView(
        modifier: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        var modifier = modifier
        Self._makeAnimatable(value: &modifier, inputs: inputs.base)
        return _ColorFilterEffectSupport.makeView(
            modifier: modifier,
            configuration: { effect in
                _ColorFilterConfiguration(
                    record: DisplayList.ItemRecord.ColorFilterRecord(
                        kind: .brightness,
                        amount: effect.amount
                    ),
                    filter: .brightness(effect.amount),
                    isIdentity: effect.amount == 0
                )
            },
            inputs: inputs,
            body: body
        )
    }

    public static func _makeViewList(
        modifier: _GraphValue<Self>,
        inputs: _ViewListInputs,
        body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs
    ) -> _ViewListOutputs {
        _ColorFilterEffectSupport.makeViewList(
            modifier: modifier,
            inputs: inputs,
            body: body
        )
    }
}

public struct _SaturationEffect: Equatable, Animatable, ViewModifier, Sendable {
    public var amount: Double

    @inlinable public init(amount: Double) {
        self.amount = amount
    }

    public var animatableData: Double {
        get { amount }
        set { amount = newValue }
    }

    public typealias Body = Never

    public static func _makeView(
        modifier: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        var modifier = modifier
        Self._makeAnimatable(value: &modifier, inputs: inputs.base)
        return _ColorFilterEffectSupport.makeView(
            modifier: modifier,
            configuration: { effect in
                _ColorFilterConfiguration(
                    record: DisplayList.ItemRecord.ColorFilterRecord(
                        kind: .saturation,
                        amount: effect.amount
                    ),
                    filter: .saturation(effect.amount),
                    isIdentity: effect.amount == 1
                )
            },
            inputs: inputs,
            body: body
        )
    }

    public static func _makeViewList(
        modifier: _GraphValue<Self>,
        inputs: _ViewListInputs,
        body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs
    ) -> _ViewListOutputs {
        _ColorFilterEffectSupport.makeViewList(
            modifier: modifier,
            inputs: inputs,
            body: body
        )
    }
}

public struct _HueRotationEffect: Equatable, Animatable, ViewModifier, Sendable {
    public var angle: Angle

    @inlinable public init(angle: Angle) {
        self.angle = angle
    }

    public var animatableData: Angle.AnimatableData {
        get { angle.animatableData }
        set { angle.animatableData = newValue }
    }

    public typealias Body = Never

    public static func _makeView(
        modifier: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        var modifier = modifier
        Self._makeAnimatable(value: &modifier, inputs: inputs.base)
        return _ColorFilterEffectSupport.makeView(
            modifier: modifier,
            configuration: { effect in
                _ColorFilterConfiguration(
                    record: DisplayList.ItemRecord.ColorFilterRecord(
                        kind: .hueRotation,
                        amount: effect.angle.radians
                    ),
                    filter: .hueRotation(effect.angle),
                    isIdentity: effect.angle.radians == 0
                )
            },
            inputs: inputs,
            body: body
        )
    }

    public static func _makeViewList(
        modifier: _GraphValue<Self>,
        inputs: _ViewListInputs,
        body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs
    ) -> _ViewListOutputs {
        _ColorFilterEffectSupport.makeViewList(
            modifier: modifier,
            inputs: inputs,
            body: body
        )
    }
}

public struct _ColorInvertEffect: Equatable, Animatable, ViewModifier, Sendable {
    @inlinable public init() {}

    public typealias AnimatableData = EmptyAnimatableData
    public typealias Body = Never

    public static func _makeView(
        modifier: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        _ColorFilterEffectSupport.makeView(
            modifier: modifier,
            configuration: { _ in
                _ColorFilterConfiguration(
                    record: DisplayList.ItemRecord.ColorFilterRecord(
                        kind: .colorInvert,
                        amount: 1
                    ),
                    filter: .colorInvert(),
                    isIdentity: false
                )
            },
            inputs: inputs,
            body: body
        )
    }

    public static func _makeViewList(
        modifier: _GraphValue<Self>,
        inputs: _ViewListInputs,
        body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs
    ) -> _ViewListOutputs {
        _ColorFilterEffectSupport.makeViewList(
            modifier: modifier,
            inputs: inputs,
            body: body
        )
    }
}

public struct _LuminanceToAlphaEffect: Equatable, Animatable, ViewModifier, Sendable {
    @inlinable public init() {}

    public typealias AnimatableData = EmptyAnimatableData
    public typealias Body = Never

    public static func _makeView(
        modifier: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        _ColorFilterEffectSupport.makeView(
            modifier: modifier,
            configuration: { _ in
                _ColorFilterConfiguration(
                    record: DisplayList.ItemRecord.ColorFilterRecord(
                        kind: .luminanceToAlpha,
                        amount: 1
                    ),
                    filter: .luminanceToAlpha,
                    isIdentity: false
                )
            },
            inputs: inputs,
            body: body
        )
    }

    public static func _makeViewList(
        modifier: _GraphValue<Self>,
        inputs: _ViewListInputs,
        body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs
    ) -> _ViewListOutputs {
        _ColorFilterEffectSupport.makeViewList(
            modifier: modifier,
            inputs: inputs,
            body: body
        )
    }
}

public struct _ColorMatrixEffect: Animatable, ViewModifier, Sendable {
    public var matrix: _ColorMatrix

    @inlinable public init(matrix: _ColorMatrix) {
        self.matrix = matrix
    }

    public typealias AnimatableData = EmptyAnimatableData
    public typealias Body = Never

    public static func _makeView(
        modifier: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        _ColorFilterEffectSupport.makeView(
            modifier: modifier,
            configuration: { effect in
                let colorMatrix = effect.matrix.colorMatrix
                return _ColorFilterConfiguration(
                    record: DisplayList.ItemRecord.ColorFilterRecord(
                        kind: .colorMatrix,
                        amount: 1,
                        matrix: colorMatrix
                    ),
                    filter: .colorMatrix(colorMatrix),
                    isIdentity: effect.matrix == _ColorMatrix()
                )
            },
            inputs: inputs,
            body: body
        )
    }

    public static func _makeViewList(
        modifier: _GraphValue<Self>,
        inputs: _ViewListInputs,
        body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs
    ) -> _ViewListOutputs {
        _ColorFilterEffectSupport.makeViewList(
            modifier: modifier,
            inputs: inputs,
            body: body
        )
    }
}

public struct _ColorMultiplyEffect: EnvironmentalModifier, Equatable {
    public var color: Color

    @inlinable public init(color: Color) {
        self.color = color
    }

    public func resolve(in environment: EnvironmentValues) -> _Resolved {
        _Resolved(color: color.resolve(in: environment))
    }

    public struct _Resolved: ViewModifier, Animatable {
        public var color: Color.Resolved

        init(color: Color.Resolved) {
            self.color = color
        }

        public typealias AnimatableData = Color.Resolved.AnimatableData

        public var animatableData: AnimatableData {
            get { color.animatableData }
            set { color.animatableData = newValue }
        }

        public typealias Body = Never

        public static func _makeView(
            modifier: _GraphValue<Self>,
            inputs: _ViewInputs,
            body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
        ) -> _ViewOutputs {
            var modifier = modifier
            Self._makeAnimatable(value: &modifier, inputs: inputs.base)
            return _ColorFilterEffectSupport.makeView(
                modifier: modifier,
                configuration: { effect in
                    _ColorFilterConfiguration(
                        record: DisplayList.ItemRecord.ColorFilterRecord(
                            kind: .colorMultiply,
                            amount: 1,
                            color: effect.color
                        ),
                        filter: .colorMultiply(Color(effect.color)),
                        isIdentity: effect.color.linearRed == 1 &&
                            effect.color.linearGreen == 1 &&
                            effect.color.linearBlue == 1 &&
                            effect.color.opacity == 1
                    )
                },
                inputs: inputs,
                body: body
            )
        }

        public static func _makeViewList(
            modifier: _GraphValue<Self>,
            inputs: _ViewListInputs,
            body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs
        ) -> _ViewListOutputs {
            _ColorFilterEffectSupport.makeViewList(
                modifier: modifier,
                inputs: inputs,
                body: body
            )
        }
    }
}

extension View {
    @inlinable public func contrast(_ amount: Double) -> some View {
        modifier(_ContrastEffect(amount: amount))
    }

    @inlinable public func grayscale(_ amount: Double) -> some View {
        modifier(_GrayscaleEffect(amount: amount))
    }

    @inlinable public func brightness(_ amount: Double) -> some View {
        modifier(_BrightnessEffect(amount: amount))
    }

    @inlinable public func saturation(_ amount: Double) -> some View {
        modifier(_SaturationEffect(amount: amount))
    }

    @inlinable public func hueRotation(_ angle: Angle) -> some View {
        modifier(_HueRotationEffect(angle: angle))
    }

    @inlinable public func colorInvert() -> some View {
        modifier(_ColorInvertEffect())
    }

    @inlinable public func luminanceToAlpha() -> some View {
        modifier(_LuminanceToAlphaEffect())
    }

    @inlinable public func colorMultiply(_ color: Color) -> some View {
        modifier(_ColorMultiplyEffect(color: color))
    }

    public func _colorMatrix(_ matrix: _ColorMatrix) -> some View {
        modifier(_ColorMatrixEffect(matrix: matrix))
    }
}
