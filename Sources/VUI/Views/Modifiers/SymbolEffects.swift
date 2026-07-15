//
//  File: SymbolEffects.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

public protocol SymbolEffect: Hashable, Sendable {
    var configuration: SymbolEffectConfiguration { get }
}

public protocol TransitionSymbolEffect {}
public protocol ContentTransitionSymbolEffect {}
public protocol IndefiniteSymbolEffect {}
public protocol DiscreteSymbolEffect {}

public struct SymbolEffectConfiguration: Hashable, Sendable {
    enum Effect: Hashable, Sendable {
        case pulse(PulseSymbolEffect)
        case bounce(BounceSymbolEffect)
        case variableColor(VariableColorSymbolEffect)
        case scale(ScaleSymbolEffect)
        case appear(AppearSymbolEffect)
        case disappear(DisappearSymbolEffect)
        case replace(ReplaceSymbolEffect)
        case automatic(AutomaticSymbolEffect)
        case wiggle(WiggleSymbolEffect)
        case rotate(RotateSymbolEffect)
        case breathe(BreatheSymbolEffect)
        case magicReplace(MagicReplaceSymbolEffect)
        case drawOn(DrawOnSymbolEffect)
        case drawOff(DrawOffSymbolEffect)
    }

    var effect: Effect

    init(_ effect: Effect) {
        self.effect = effect
    }
}

struct RBSymbolAnimationReplaceFlags: OptionSet, Equatable, Hashable, Sendable {
    let rawValue: UInt32

    init(rawValue: UInt32) {
        self.rawValue = rawValue
    }
}

enum _SymbolEffect {
    struct ReplaceConfiguration: Equatable, Sendable {
        var flags: RBSymbolAnimationReplaceFlags
        var layered: Bool
        var speed: Float

        init() {
            self.flags = []
            self.layered = true
            self.speed = 1
        }

        init?(
            configuration: SymbolEffectConfiguration,
            options: SymbolEffectOptions
        ) {
            self.init()
            speed = Float(options.speed)

            switch configuration.effect {
            case .automatic:
                break
            case let .replace(effect):
                flags = RBSymbolAnimationReplaceFlags(
                    rawValue: Self.ordinaryFlags(for: effect.style)
                )
                layered = effect.isLayered ?? true
            case let .magicReplace(effect):
                flags = RBSymbolAnimationReplaceFlags(
                    rawValue: Self.magicFlags(for: effect.fallback.style)
                )
                layered = effect.fallback.isLayered ?? true
            default:
                return nil
            }
        }

        var transitionFlags: RBSymbolAnimationReplaceFlags {
            layered
                ? RBSymbolAnimationReplaceFlags(rawValue: flags.rawValue | 0x10)
                : flags
        }

        private static func ordinaryFlags(
            for style: ReplaceSymbolEffect.ReplaceStyle?
        ) -> UInt32 {
            switch style {
            case nil:
                0
            case .downUp:
                226
            case .upUp:
                227
            case .offUp:
                228
            }
        }

        private static func magicFlags(
            for style: ReplaceSymbolEffect.ReplaceStyle?
        ) -> UInt32 {
            switch style {
            case nil:
                0
            case .downUp:
                2
            case .upUp:
                3
            case .offUp:
                4
            }
        }
    }
}

public struct PulseSymbolEffect: SymbolEffect {
    var isLayered: Bool?

    init(isLayered: Bool? = nil) {
        self.isLayered = isLayered
    }

    public var byLayer: Self { Self(isLayered: true) }
    public var wholeSymbol: Self { Self(isLayered: false) }
    public var configuration: SymbolEffectConfiguration { .init(.pulse(self)) }
}

public extension SymbolEffect where Self == PulseSymbolEffect {
    static var pulse: PulseSymbolEffect { PulseSymbolEffect() }
}

public struct BounceSymbolEffect: SymbolEffect {
    var isUp: Bool?
    var isLayered: Bool?

    init(isUp: Bool? = nil, isLayered: Bool? = nil) {
        self.isUp = isUp
        self.isLayered = isLayered
    }

    public var up: Self { Self(isUp: true, isLayered: isLayered) }
    public var down: Self { Self(isUp: false, isLayered: isLayered) }
    public var byLayer: Self { Self(isUp: isUp, isLayered: true) }
    public var wholeSymbol: Self { Self(isUp: isUp, isLayered: false) }
    public var configuration: SymbolEffectConfiguration { .init(.bounce(self)) }
}

public extension SymbolEffect where Self == BounceSymbolEffect {
    static var bounce: BounceSymbolEffect { BounceSymbolEffect() }
}

public struct VariableColorSymbolEffect: SymbolEffect {
    var isReversing: Bool?
    var isIterative: Bool?
    var hasReveal: Bool?

    init(isReversing: Bool? = nil, isIterative: Bool? = nil, hasReveal: Bool? = nil) {
        self.isReversing = isReversing
        self.isIterative = isIterative
        self.hasReveal = hasReveal
    }

    public var reversing: Self {
        Self(isReversing: true, isIterative: isIterative, hasReveal: hasReveal)
    }
    public var nonReversing: Self {
        Self(isReversing: false, isIterative: isIterative, hasReveal: hasReveal)
    }
    public var cumulative: Self {
        Self(isReversing: isReversing, isIterative: false, hasReveal: hasReveal)
    }
    public var iterative: Self {
        Self(isReversing: isReversing, isIterative: true, hasReveal: hasReveal)
    }
    public var hideInactiveLayers: Self {
        Self(isReversing: isReversing, isIterative: isIterative, hasReveal: true)
    }
    public var dimInactiveLayers: Self {
        Self(isReversing: isReversing, isIterative: isIterative, hasReveal: false)
    }
    public var configuration: SymbolEffectConfiguration { .init(.variableColor(self)) }
}

public extension SymbolEffect where Self == VariableColorSymbolEffect {
    static var variableColor: VariableColorSymbolEffect { VariableColorSymbolEffect() }
}

public struct ScaleSymbolEffect: SymbolEffect {
    var isUp: Bool?
    var isLayered: Bool?

    init(isUp: Bool? = nil, isLayered: Bool? = nil) {
        self.isUp = isUp
        self.isLayered = isLayered
    }

    public var up: Self { Self(isUp: true, isLayered: isLayered) }
    public var down: Self { Self(isUp: false, isLayered: isLayered) }
    public var byLayer: Self { Self(isUp: isUp, isLayered: true) }
    public var wholeSymbol: Self { Self(isUp: isUp, isLayered: false) }
    public var configuration: SymbolEffectConfiguration { .init(.scale(self)) }
}

public extension SymbolEffect where Self == ScaleSymbolEffect {
    static var scale: ScaleSymbolEffect { ScaleSymbolEffect() }
}

public struct AppearSymbolEffect: SymbolEffect {
    var isUp: Bool?
    var isLayered: Bool?

    init(isUp: Bool? = nil, isLayered: Bool? = nil) {
        self.isUp = isUp
        self.isLayered = isLayered
    }

    public var up: Self { Self(isUp: true, isLayered: isLayered) }
    public var down: Self { Self(isUp: false, isLayered: isLayered) }
    public var byLayer: Self { Self(isUp: isUp, isLayered: true) }
    public var wholeSymbol: Self { Self(isUp: isUp, isLayered: false) }
    public var configuration: SymbolEffectConfiguration { .init(.appear(self)) }
}

public extension SymbolEffect where Self == AppearSymbolEffect {
    static var appear: AppearSymbolEffect { AppearSymbolEffect() }
}

public struct DisappearSymbolEffect: SymbolEffect {
    var isUp: Bool?
    var isLayered: Bool?

    init(isUp: Bool? = nil, isLayered: Bool? = nil) {
        self.isUp = isUp
        self.isLayered = isLayered
    }

    public var up: Self { Self(isUp: true, isLayered: isLayered) }
    public var down: Self { Self(isUp: false, isLayered: isLayered) }
    public var byLayer: Self { Self(isUp: isUp, isLayered: true) }
    public var wholeSymbol: Self { Self(isUp: isUp, isLayered: false) }
    public var configuration: SymbolEffectConfiguration { .init(.disappear(self)) }
}

public extension SymbolEffect where Self == DisappearSymbolEffect {
    static var disappear: DisappearSymbolEffect { DisappearSymbolEffect() }
}

public struct ReplaceSymbolEffect: SymbolEffect {
    enum ReplaceStyle: Hashable, Sendable {
        case downUp
        case upUp
        case offUp
    }

    var style: ReplaceStyle?
    var isLayered: Bool?

    init(style: ReplaceStyle? = nil, isLayered: Bool? = nil) {
        self.style = style
        self.isLayered = isLayered
    }

    public var downUp: Self { Self(style: .downUp, isLayered: isLayered) }
    public var upUp: Self { Self(style: .upUp, isLayered: isLayered) }
    public var offUp: Self { Self(style: .offUp, isLayered: isLayered) }
    public var byLayer: Self { Self(style: style, isLayered: true) }
    public var wholeSymbol: Self { Self(style: style, isLayered: false) }
    public var configuration: SymbolEffectConfiguration { .init(.replace(self)) }

    public struct MagicReplace: SymbolEffect {
        var _backing: MagicReplaceSymbolEffect

        public var configuration: SymbolEffectConfiguration {
            .init(.magicReplace(_backing))
        }
    }

    public func magic(fallback: ReplaceSymbolEffect) -> MagicReplace {
        MagicReplace(_backing: MagicReplaceSymbolEffect(fallback: fallback))
    }

    public static var downUp: Self { Self(style: .downUp) }
    public static var upUp: Self { Self(style: .upUp) }
    public static var offUp: Self { Self(style: .offUp) }
}

struct MagicReplaceSymbolEffect: Hashable, Sendable {
    var fallback: ReplaceSymbolEffect
}

public extension SymbolEffect where Self == ReplaceSymbolEffect {
    static var replace: ReplaceSymbolEffect { ReplaceSymbolEffect() }
}

public struct AutomaticSymbolEffect: SymbolEffect {
    init() {}

    public var configuration: SymbolEffectConfiguration { .init(.automatic(self)) }
}

public extension SymbolEffect where Self == AutomaticSymbolEffect {
    static var automatic: AutomaticSymbolEffect { AutomaticSymbolEffect() }
}

public struct WiggleSymbolEffect: SymbolEffect {
    enum WiggleStyle: Hashable, Sendable {
        case rotational(Bool)
        case linear(Double)
        case localized(Bool)
    }

    var style: WiggleStyle?
    var isLayered: Bool?

    init(style: WiggleStyle? = nil, isLayered: Bool? = nil) {
        self.style = style
        self.isLayered = isLayered
    }

    public var clockwise: Self { Self(style: .rotational(true), isLayered: isLayered) }
    public var counterClockwise: Self { Self(style: .rotational(false), isLayered: isLayered) }
    public var left: Self { Self(style: .linear(180), isLayered: isLayered) }
    public var right: Self { Self(style: .linear(0), isLayered: isLayered) }
    public var up: Self { Self(style: .linear(-90), isLayered: isLayered) }
    public var down: Self { Self(style: .linear(90), isLayered: isLayered) }
    public var forward: Self { Self(style: .localized(true), isLayered: isLayered) }
    public var backward: Self { Self(style: .localized(false), isLayered: isLayered) }
    public func custom(angle: Double) -> Self { Self(style: .linear(angle), isLayered: isLayered) }
    public func custom(angle: Angle) -> Self { custom(angle: angle.degrees) }
    public var byLayer: Self { Self(style: style, isLayered: true) }
    public var wholeSymbol: Self { Self(style: style, isLayered: false) }
    public var configuration: SymbolEffectConfiguration { .init(.wiggle(self)) }
}

public extension SymbolEffect where Self == WiggleSymbolEffect {
    static var wiggle: WiggleSymbolEffect { WiggleSymbolEffect() }
}

public struct RotateSymbolEffect: SymbolEffect {
    var isClockwise: Bool?
    var isLayered: Bool?

    init(isClockwise: Bool? = nil, isLayered: Bool? = nil) {
        self.isClockwise = isClockwise
        self.isLayered = isLayered
    }

    public var clockwise: Self { Self(isClockwise: true, isLayered: isLayered) }
    public var counterClockwise: Self { Self(isClockwise: false, isLayered: isLayered) }
    public var byLayer: Self { Self(isClockwise: isClockwise, isLayered: true) }
    public var wholeSymbol: Self { Self(isClockwise: isClockwise, isLayered: false) }
    public var configuration: SymbolEffectConfiguration { .init(.rotate(self)) }
}

public extension SymbolEffect where Self == RotateSymbolEffect {
    static var rotate: RotateSymbolEffect { RotateSymbolEffect() }
}

public struct BreatheSymbolEffect: SymbolEffect {
    enum BreatheStyle: Hashable, Sendable {
        case dim
        case scale
    }

    var style: BreatheStyle?
    var isLayered: Bool?

    init(style: BreatheStyle? = nil, isLayered: Bool? = nil) {
        self.style = style
        self.isLayered = isLayered
    }

    public var pulse: Self { Self(style: .dim, isLayered: isLayered) }
    public var plain: Self { Self(style: .scale, isLayered: isLayered) }
    public var byLayer: Self { Self(style: style, isLayered: true) }
    public var wholeSymbol: Self { Self(style: style, isLayered: false) }
    public var configuration: SymbolEffectConfiguration { .init(.breathe(self)) }
}

public extension SymbolEffect where Self == BreatheSymbolEffect {
    static var breathe: BreatheSymbolEffect { BreatheSymbolEffect() }
}

enum DrawLayerBehavior: Hashable, Sendable {
    case byLayer
    case wholeSymbol
    case individually
}

public struct DrawOnSymbolEffect: SymbolEffect {
    var layerBehavior: DrawLayerBehavior?

    init(layerBehavior: DrawLayerBehavior? = nil) {
        self.layerBehavior = layerBehavior
    }

    public var byLayer: Self { Self(layerBehavior: .byLayer) }
    public var wholeSymbol: Self { Self(layerBehavior: .wholeSymbol) }
    public var individually: Self { Self(layerBehavior: .individually) }
    public var configuration: SymbolEffectConfiguration { .init(.drawOn(self)) }
}

public extension SymbolEffect where Self == DrawOnSymbolEffect {
    static var drawOn: DrawOnSymbolEffect { DrawOnSymbolEffect() }
}

public struct DrawOffSymbolEffect: SymbolEffect {
    var layerBehavior: DrawLayerBehavior?
    var isReversed: Bool?

    init(layerBehavior: DrawLayerBehavior? = nil, isReversed: Bool? = nil) {
        self.layerBehavior = layerBehavior
        self.isReversed = isReversed
    }

    public var byLayer: Self { Self(layerBehavior: .byLayer, isReversed: isReversed) }
    public var wholeSymbol: Self { Self(layerBehavior: .wholeSymbol, isReversed: isReversed) }
    public var individually: Self { Self(layerBehavior: .individually, isReversed: isReversed) }
    public var reversed: Self { Self(layerBehavior: layerBehavior, isReversed: true) }
    public var nonReversed: Self { Self(layerBehavior: layerBehavior, isReversed: false) }
    public var configuration: SymbolEffectConfiguration { .init(.drawOff(self)) }
}

public extension SymbolEffect where Self == DrawOffSymbolEffect {
    static var drawOff: DrawOffSymbolEffect { DrawOffSymbolEffect() }
}

extension AppearSymbolEffect: TransitionSymbolEffect, IndefiniteSymbolEffect {}
extension DisappearSymbolEffect: TransitionSymbolEffect, IndefiniteSymbolEffect {}
extension AutomaticSymbolEffect: TransitionSymbolEffect, ContentTransitionSymbolEffect {}
extension DrawOnSymbolEffect: TransitionSymbolEffect, IndefiniteSymbolEffect {}
extension DrawOffSymbolEffect: TransitionSymbolEffect, IndefiniteSymbolEffect {}
extension ReplaceSymbolEffect: ContentTransitionSymbolEffect {}
extension ReplaceSymbolEffect.MagicReplace: ContentTransitionSymbolEffect {}
extension PulseSymbolEffect: IndefiniteSymbolEffect, DiscreteSymbolEffect {}
extension BounceSymbolEffect: IndefiniteSymbolEffect, DiscreteSymbolEffect {}
extension VariableColorSymbolEffect: IndefiniteSymbolEffect, DiscreteSymbolEffect {}
extension ScaleSymbolEffect: IndefiniteSymbolEffect {}
extension WiggleSymbolEffect: IndefiniteSymbolEffect, DiscreteSymbolEffect {}
extension RotateSymbolEffect: IndefiniteSymbolEffect, DiscreteSymbolEffect {}
extension BreatheSymbolEffect: IndefiniteSymbolEffect, DiscreteSymbolEffect {}

public struct SymbolEffectOptions: Hashable, Sendable {
    enum RepeatOption: Hashable, Sendable {
        case indefinite
        case count(Int)
    }

    var speed: Double
    var `repeat`: RepeatOption?
    var prefersContinuous: Bool
    var repeatDelay: Double?

    init(
        speed: Double = 1,
        repeat repeatOption: RepeatOption? = nil,
        prefersContinuous: Bool = false,
        repeatDelay: Double? = nil
    ) {
        self.speed = speed
        self.repeat = repeatOption
        self.prefersContinuous = prefersContinuous
        self.repeatDelay = repeatDelay
    }

    public static var `default`: Self { Self() }

    public static func speed(_ speed: Double) -> Self {
        Self(speed: speed)
    }

    public func speed(_ speed: Double) -> Self {
        var copy = self
        copy.speed = speed
        return copy
    }

    public struct RepeatBehavior: Sendable {
        struct RepeatStyle: Sendable {
            var prefersContinuous: Bool
            var delay: Double?
            var count: RepeatOption
        }

        var _backing: RepeatStyle

        public static var periodic: Self {
            periodic(nil, delay: nil)
        }

        public static func periodic(_ count: Int? = nil, delay: Double? = nil) -> Self {
            Self(
                _backing: RepeatStyle(
                    prefersContinuous: false,
                    delay: delay,
                    count: count.map(RepeatOption.count) ?? .indefinite
                )
            )
        }

        public static var continuous: Self {
            Self(
                _backing: RepeatStyle(
                    prefersContinuous: true,
                    delay: nil,
                    count: .indefinite
                )
            )
        }
    }

    public func `repeat`(_ behavior: RepeatBehavior) -> Self {
        var copy = self
        copy.repeat = behavior._backing.count
        copy.prefersContinuous = behavior._backing.prefersContinuous
        copy.repeatDelay = behavior._backing.delay
        return copy
    }

    public static func `repeat`(_ behavior: RepeatBehavior) -> Self {
        Self.default.repeat(behavior)
    }

    public static var nonRepeating: Self {
        .repeat(.periodic(1))
    }

    public var nonRepeating: Self {
        self.repeat(.periodic(1))
    }
}

struct AnySymbolEffectTrigger: @unchecked Sendable {
    let value: Any
    private let equals: (Any) -> Bool

    init<Value: Equatable>(_ value: Value) {
        self.value = value
        self.equals = { ($0 as? Value) == value }
    }

    func isEqual(to other: AnySymbolEffectTrigger) -> Bool {
        equals(other.value) && other.equals(value)
    }
}

struct ResolvedSymbolEffect: @unchecked Sendable {
    enum Trigger: @unchecked Sendable {
        case indefinite
        case value(AnySymbolEffectTrigger)
        case condition(Bool)
        case transition(TransitionPhase)
    }

    var configuration: SymbolEffectConfiguration
    var options: SymbolEffectOptions
    var trigger: Trigger
}

struct IdentifiedSymbolEffect: @unchecked Sendable {
    var id: Int
    var effect: ResolvedSymbolEffect
}

private struct SymbolEffectsEnvironmentKey: EnvironmentKey {
    static var defaultValue: [IdentifiedSymbolEffect] { [] }
}

extension EnvironmentValues {
    var symbolEffects: [IdentifiedSymbolEffect] {
        get { self[SymbolEffectsEnvironmentKey.self] }
        set { self[SymbolEffectsEnvironmentKey.self] = newValue }
    }

    mutating func appendSymbolEffect(_ effect: ResolvedSymbolEffect, for id: Int) {
        symbolEffects.append(IdentifiedSymbolEffect(id: id, effect: effect))
    }
}

public struct _SymbolEffectsRemovedModifier: ViewModifier, _GraphInputsModifier {
    var isEnabled: Bool

    init(isEnabled: Bool) {
        self.isEnabled = isEnabled
    }

    public static func _makeInputs(modifier: _GraphValue<Self>, inputs: inout _GraphInputs) {
        guard let graph = _AGGraph.current else {
            fatalError("\(Self.self)._makeInputs called outside an active _AGGraph context.")
        }
        let parentEnvironment = inputs.cachedEnvironment.value.environment
        let environment: Attribute<EnvironmentValues> = graph.makeRule {
            var values = parentEnvironment.value.trackingCopy()
            if modifier._attribute.value.isEnabled {
                values.symbolEffects = []
            }
            return values
        }
        inputs.cachedEnvironment = MutableBox(
            inputs.cachedEnvironment.value.replacingEnvironment(environment)
        )
    }

    public typealias Body = Never
}

public struct _IndefiniteSymbolEffectModifier: ViewModifier, _GraphInputsModifier {
    var config: SymbolEffectConfiguration
    var options: SymbolEffectOptions
    var isActive: Bool

    init<Effect>(effect: Effect, options: SymbolEffectOptions, isActive: Bool)
    where Effect: SymbolEffect & IndefiniteSymbolEffect {
        self.config = effect.configuration
        self.options = options
        self.isActive = isActive
    }

    public static func _makeInputs(modifier: _GraphValue<Self>, inputs: inout _GraphInputs) {
        guard let graph = _AGGraph.current else {
            fatalError("\(Self.self)._makeInputs called outside an active _AGGraph context.")
        }
        let id = AGMakeUniqueID()
        let parentEnvironment = inputs.cachedEnvironment.value.environment
        let environment: Attribute<EnvironmentValues> = graph.makeRule {
            let value = modifier._attribute.value
            var values = parentEnvironment.value.trackingCopy()
            if value.isActive {
                values.appendSymbolEffect(
                    ResolvedSymbolEffect(
                        configuration: value.config,
                        options: value.options,
                        trigger: .indefinite
                    ),
                    for: id
                )
            }
            return values
        }
        inputs.cachedEnvironment = MutableBox(
            inputs.cachedEnvironment.value.replacingEnvironment(environment)
        )
    }

    public typealias Body = Never
}

public struct _DiscreteSymbolEffectModifier<Value>: ViewModifier, _GraphInputsModifier
where Value: Equatable {
    var config: SymbolEffectConfiguration
    var options: SymbolEffectOptions
    var value: Value

    init<Effect>(effect: Effect, options: SymbolEffectOptions, value: Value)
    where Effect: SymbolEffect & DiscreteSymbolEffect {
        self.config = effect.configuration
        self.options = options
        self.value = value
    }

    public static func _makeInputs(modifier: _GraphValue<Self>, inputs: inout _GraphInputs) {
        guard let graph = _AGGraph.current else {
            fatalError("\(Self.self)._makeInputs called outside an active _AGGraph context.")
        }
        let id = AGMakeUniqueID()
        let parentEnvironment = inputs.cachedEnvironment.value.environment
        let environment: Attribute<EnvironmentValues> = graph.makeRule {
            let value = modifier._attribute.value
            var values = parentEnvironment.value.trackingCopy()
            values.appendSymbolEffect(
                ResolvedSymbolEffect(
                    configuration: value.config,
                    options: value.options,
                    trigger: .value(AnySymbolEffectTrigger(value.value))
                ),
                for: id
            )
            return values
        }
        inputs.cachedEnvironment = MutableBox(
            inputs.cachedEnvironment.value.replacingEnvironment(environment)
        )
    }

    public typealias Body = Never
}

public struct _ConditionalSymbolEffectModifier: ViewModifier, _GraphInputsModifier {
    var config: SymbolEffectConfiguration
    var options: SymbolEffectOptions
    var condition: Bool

    init<Effect>(effect: Effect, options: SymbolEffectOptions, condition: Bool)
    where Effect: SymbolEffect & DiscreteSymbolEffect {
        self.config = effect.configuration
        self.options = options
        self.condition = condition
    }

    public static func _makeInputs(modifier: _GraphValue<Self>, inputs: inout _GraphInputs) {
        guard let graph = _AGGraph.current else {
            fatalError("\(Self.self)._makeInputs called outside an active _AGGraph context.")
        }
        let id = AGMakeUniqueID()
        let parentEnvironment = inputs.cachedEnvironment.value.environment
        let environment: Attribute<EnvironmentValues> = graph.makeRule {
            let value = modifier._attribute.value
            var values = parentEnvironment.value.trackingCopy()
            values.appendSymbolEffect(
                ResolvedSymbolEffect(
                    configuration: value.config,
                    options: value.options,
                    trigger: .condition(value.condition)
                ),
                for: id
            )
            return values
        }
        inputs.cachedEnvironment = MutableBox(
            inputs.cachedEnvironment.value.replacingEnvironment(environment)
        )
    }

    public typealias Body = Never
}

private struct TransitionSymbolEffectModifier: ViewModifier, _GraphInputsModifier {
    var config: SymbolEffectConfiguration
    var options: SymbolEffectOptions
    var phase: TransitionPhase

    static func _makeInputs(modifier: _GraphValue<Self>, inputs: inout _GraphInputs) {
        guard let graph = _AGGraph.current else {
            fatalError("\(Self.self)._makeInputs called outside an active _AGGraph context.")
        }
        let id = AGMakeUniqueID()
        let parentEnvironment = inputs.cachedEnvironment.value.environment
        let environment: Attribute<EnvironmentValues> = graph.makeRule {
            let value = modifier._attribute.value
            var values = parentEnvironment.value.trackingCopy()
            values.appendSymbolEffect(
                ResolvedSymbolEffect(
                    configuration: value.config,
                    options: value.options,
                    trigger: .transition(value.phase)
                ),
                for: id
            )
            return values
        }
        inputs.cachedEnvironment = MutableBox(
            inputs.cachedEnvironment.value.replacingEnvironment(environment)
        )
    }

    typealias Body = Never
}

public extension View {
    func symbolEffectsRemoved(_ isEnabled: Bool = true) -> some View {
        modifier(_SymbolEffectsRemovedModifier(isEnabled: isEnabled))
    }

    func symbolEffect<Effect>(
        _ effect: Effect,
        options: SymbolEffectOptions = .default,
        isActive: Bool = true
    ) -> some View where Effect: SymbolEffect & IndefiniteSymbolEffect {
        modifier(
            _IndefiniteSymbolEffectModifier(
                effect: effect,
                options: options,
                isActive: isActive
            )
        )
    }

    func symbolEffect<Effect, Value>(
        _ effect: Effect,
        options: SymbolEffectOptions = .default,
        value: Value
    ) -> some View where Effect: SymbolEffect & DiscreteSymbolEffect, Value: Equatable {
        modifier(
            _DiscreteSymbolEffectModifier(
                effect: effect,
                options: options,
                value: value
            )
        )
    }
}

public struct SymbolEffectTransition: Transition {
    var config: SymbolEffectConfiguration
    var options: SymbolEffectOptions

    public init<Effect>(effect: Effect, options: SymbolEffectOptions)
    where Effect: SymbolEffect & TransitionSymbolEffect {
        self.config = effect.configuration
        self.options = options
    }

    public func body(content: Content, phase: TransitionPhase) -> some View {
        content.modifier(
            TransitionSymbolEffectModifier(
                config: config,
                options: options,
                phase: phase
            )
        )
    }

    public static let properties = TransitionProperties()

    public func _makeContentTransition(transition: inout _Transition_ContentTransition) {
        switch transition.operation {
        case .hasContentTransition:
            transition.result = .bool(true)
        case .effects:
            transition.result = .effects([])
        }
    }
}

public extension Transition where Self == SymbolEffectTransition {
    static func symbolEffect<Effect>(
        _ effect: Effect,
        options: SymbolEffectOptions = .default
    ) -> SymbolEffectTransition where Effect: SymbolEffect & TransitionSymbolEffect {
        SymbolEffectTransition(effect: effect, options: options)
    }

    static var symbolEffect: SymbolEffectTransition {
        .symbolEffect(.automatic)
    }
}
