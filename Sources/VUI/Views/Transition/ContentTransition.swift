//
//  File: ContentTransition.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

// Public content replacement transition value carried through the environment and lowered into
// display-list renderer effects when interpolatable content changes.
public struct ContentTransition: Equatable, Sendable {
    // Style hint that lets transition effects vary by environment-provided transition context.
    struct Style: Equatable, Hashable, Sendable {
        enum Storage: UInt8, Equatable, Hashable, Sendable {
            case `default` = 0
            case sessionWidget = 1
            case animatedWidget = 2
        }

        var storage: Storage

        init(_ storage: Storage = .default) {
            self.storage = storage
        }

        static let `default` = Style(.default)
        static let sessionWidget = Style(.sessionWidget)
        static let animatedWidget = Style(.animatedWidget)
    }

    // Flags carried by an active content-transition state for drawing-group and grouping behavior.
    struct Options: OptionSet, Equatable, Hashable, Sendable {
        let rawValue: UInt32

        static let addsDrawingGroup = Options(rawValue: 1)
        static let animatesDifferentContent = Options(rawValue: 1 << 1)
        static let formsGroup = Options(rawValue: 1 << 2)
        static let implicitGroup = Options(rawValue: 1 << 3)
        static let inherited = Options(rawValue: 1)
    }

    // Encoded matching strategy used when a content transition is lowered to the render path.
    struct Method: Equatable, Sendable {
        var method: Int32

        init(method: Int32) {
            self.method = method
        }

        static let diff = Method(method: 1)
        static let forwards = Method(method: 2)
        static let backwards = Method(method: 3)
        static let prefix = Method(method: 4)
        static let suffix = Method(method: 5)
        static let prefixAndSuffix = Method(method: 8)
        static let binary = Method(method: 6)
        static let none = Method(method: 7)
    }

    enum SequenceDirection: Hashable, Sendable {
        case leading
        case trailing
        case up
        case down
        case forwards
        case backwards

        var effectType: Int32 {
            switch self {
            case .leading:
                11
            case .trailing:
                12
            case .up:
                13
            case .down:
                14
            case .forwards:
                19
            case .backwards:
                20
            }
        }
    }

    // Encoded renderer effect kind plus the small argument payload used by that effect.
    struct EffectType: Equatable, Sendable {
        enum Arg: Equatable, Sendable {
            case float(Float)
            case int(UInt32)
            case none
        }

        var type: Int32
        var arg0: Arg
        var arg1: Arg

        init(type: Int32, arg0: Arg = .none, arg1: Arg = .none) {
            self.type = type
            self.arg0 = arg0
            self.arg1 = arg1
        }

        static let opacity = EffectType(type: 1)
        static let matchMove = EffectType(type: 5)

        static func opacity(_ value: Double) -> EffectType {
            opacity
        }

        static func scale(_ value: CGFloat) -> EffectType {
            EffectType(type: 2, arg0: .float(Float(value)))
        }

        static func translation(_ size: CGSize) -> EffectType {
            EffectType(
                type: 3,
                arg0: .float(Float(size.width)),
                arg1: .float(Float(size.height))
            )
        }

        static func blur(radius: CGFloat) -> EffectType {
            EffectType(type: 4, arg0: .float(Float(radius)))
        }

        static func translation(scale: CGSize) -> EffectType {
            EffectType(
                type: 15,
                arg0: .float(Float(scale.width)),
                arg1: .float(Float(scale.height))
            )
        }

        static func relativeBlur(scale: CGSize) -> EffectType {
            EffectType(
                type: 16,
                arg0: .float(Float(scale.width)),
                arg1: .float(Float(scale.height))
            )
        }
    }

    // Timed renderer effect instance emitted by transitions such as opacity, move, scale, and blur.
    struct Effect: Equatable, Sendable {
        var type: EffectType
        var begin: Float
        var duration: Float
        var events: UInt32
        var flags: UInt32

        init(
            type: EffectType,
            begin: Float = 0,
            duration: Float = 1,
            events: UInt32 = 0,
            flags: UInt32 = 0
        ) {
            self.type = type
            self.begin = begin
            self.duration = duration
            self.events = events
            self.flags = flags
        }

        init(
            _ type: EffectType,
            timeline: ClosedRange<Float>,
            appliesOnInsertion: Bool,
            appliesOnRemoval: Bool
        ) {
            var events: UInt32 = 0
            if appliesOnInsertion {
                events = appliesOnRemoval ? 3 : 1
            } else if appliesOnRemoval {
                events = 2
            }

            self.init(
                type: type,
                begin: timeline.lowerBound,
                duration: timeline.upperBound - timeline.lowerBound,
                events: events,
                flags: 0
            )
        }

        static func sequence(
            direction: SequenceDirection,
            delay: Double,
            maxAllowedDurationMultiple: Double,
            appliesOnInsertion: Bool,
            appliesOnRemoval: Bool
        ) -> Effect {
            Effect(
                type: EffectType(type: direction.effectType),
                begin: Float(delay),
                duration: Float(1 / maxAllowedDurationMultiple),
                events: 3,
                flags: 0
            )
        }

        func removeInverts(_ shouldRemove: Bool) -> Effect {
            var copy = self
            if shouldRemove {
                copy.flags |= 1
            } else {
                copy.flags &= ~1
            }
            return copy
        }
    }

    // Internal storage for explicitly constructed transitions backed by effect lists.
    struct CustomTransition: Equatable, @unchecked Sendable {
        var effects: [Effect]
        var method: Method
        var layoutDirection: LayoutDirection?

        init(
            effects: [Effect],
            method: Method,
            layoutDirection: LayoutDirection?
        ) {
            self.effects = effects
            self.method = method
            self.layoutDirection = layoutDirection
        }
    }

    // Environment carrier for the currently active content-transition configuration.
    struct State: Equatable, EnvironmentKey {
        var transition: ContentTransition
        var style: Style
        var animation: Animation?
        var options: Options

        static var defaultValue: State {
            State()
        }

        init(
            transition: ContentTransition = ContentTransition.defaultTransition,
            style: Style = .default,
            animation: Animation? = nil,
            options: Options = []
        ) {
            self.transition = transition
            self.style = style
            self.animation = animation
            self.options = options
        }

        mutating func applyDynamicTextAnimation(in transaction: Transaction) {
            guard animation == nil,
                  !transaction.disablesAnimations,
                  style == .sessionWidget || style == .animatedWidget else {
                return
            }
            animation = .default
        }

        var rasterizationOptions: RasterizationOptions {
            var options = RasterizationOptions()
            options.requiresLayer = false
            options.isAccelerated = self.options.contains(.addsDrawingGroup)
            return options
        }
    }

    // Keeps either a named transition or an explicit effect-list transition.
    private enum Storage: Equatable, Sendable {
        case named(NamedTransition)
        case custom(CustomTransition)
        case symbolReplace(_SymbolEffect.ReplaceConfiguration)
    }

    // Named transition storage used by public factories and lowered into RBTransition on demand.
    private struct NamedTransition: Equatable, @unchecked Sendable {
        enum Name: Equatable, Sendable {
            case `default`
            case identity
            case opacity
            case diff
            case text(Bool)
            case fadeIfDifferent
            case numericText(NumericTextConfiguration)
        }

        var name: Name
        var layoutDirection: LayoutDirection?
        var style: Style?

        func makeRBTransition() -> RBTransition {
            let transition = RBTransition()

            switch name {
            case .default:
                transition.method = Method.binary.method
                transition.addEffect(Self.opacityEffect())
            case .identity:
                transition.method = Method.none.method
            case .opacity:
                transition.method = Method.none.method
                transition.addEffect(Self.opacityEffect())
            case .diff:
                transition.method = Method.diff.method
                transition.addEffect(Self.opacityEffect())
            case .text:
                transition.method = Method.none.method
                transition.addEffect(Self.opacityEffect())
            case .fadeIfDifferent:
                transition.addEffect(Self.opacityEffect())
            case let .numericText(configuration):
                transition.method = Method.prefixAndSuffix.method
                transition.animation = Self.numericAnimation()

                let sequence = RBTransitionEffect()
                sequence.type = SequenceDirection.leading.effectType
                sequence.beginTime = Float(38) / 255
                sequence.duration = Float(204) / 255
                sequence.events = 3
                transition.addEffect(sequence)

                let opacity = Self.opacityEffect()
                opacity.duration = 1
                transition.addEffect(opacity)

                let blur = RBTransitionEffect()
                blur.type = EffectType.relativeBlur(scale: .zero).type
                blur.setArgumentValue(0.25, atIndex: 1)
                blur.duration = 1
                blur.events = 3
                transition.addEffect(blur)

                let translation = RBTransitionEffect()
                translation.type = EffectType.translation(scale: .zero).type
                let offset: Float
                switch configuration.direction {
                case let .fixed(downwards):
                    offset = downwards ? -0.59375 : 0.59375
                    translation.flags = 1
                case .automatic:
                    offset = 0.59375
                    translation.flags = 3
                }
                translation.setArgumentValue(offset, atIndex: 1)
                translation.events = 3
                translation.animationIndex = 1
                transition.addEffect(translation)

                let scale = RBTransitionEffect()
                scale.type = EffectType.scale(0.3984375).type
                scale.setArgumentValue(0.3984375, atIndex: 0)
                scale.duration = 1
                scale.events = 3
                transition.addEffect(scale)
            }
            return transition
        }

        private static func opacityEffect() -> RBTransitionEffect {
            let effect = RBTransitionEffect()
            effect.type = EffectType.opacity.type
            effect.beginTime = 0
            effect.duration = 0
            effect.events = 3
            return effect
        }

        private static func numericAnimation() -> RBAnimation {
            let animation = RBAnimation()
            animation.addSpringDuration(
                0.5,
                mass: 1,
                stiffness: 344,
                damping: 37,
                initialVelocity: 0
            )
            animation.addSpringDuration(
                0.8,
                mass: 2,
                stiffness: 470,
                damping: 34,
                initialVelocity: 0
            )
            return animation
        }
    }

    // Payload for numeric text transitions, including direction and sampled effect tuning bytes.
    private struct NumericTextConfiguration: Equatable, @unchecked Sendable {
        enum Direction: Equatable, Sendable {
            case fixed(downwards: Bool)
            case automatic(value: Float)
        }

        struct Options: OptionSet, Equatable, Sendable {
            let rawValue: UInt8

            static let numericTextDefault = Self(rawValue: 2)
        }

        var direction: Direction
        var axis: Axis?
        var options: Options
        var _delay: UInt8
        var _scale: UInt8
        var _blur: UInt8
        var _offset: UInt8
    }

    private var storage: Storage
    private var isReplaceable: Bool

    private init(storage: Storage, isReplaceable: Bool = false) {
        self.storage = storage
        self.isReplaceable = isReplaceable
    }

    static let defaultTransition = ContentTransition(named: .default)

    public static let identity = ContentTransition(named: .identity)
    public static let opacity = ContentTransition(named: .opacity)
    public static let interpolate = ContentTransition(named: .diff)
    static let text = ContentTransition(named: .text(false))

    public static func numericText(countsDown: Bool = false) -> ContentTransition {
        ContentTransition(
            numericTextDirection: .fixed(downwards: countsDown)
        )
    }

    public static func numericText(value: Double) -> ContentTransition {
        ContentTransition(
            numericTextDirection: .automatic(value: Float(value))
        )
    }

    public static func symbolEffect<Effect>(
        _ effect: Effect,
        options: SymbolEffectOptions = .default
    ) -> ContentTransition where Effect: SymbolEffect & ContentTransitionSymbolEffect {
        guard let configuration = _SymbolEffect.ReplaceConfiguration(
            configuration: effect.configuration,
            options: options
        ) else {
            return defaultTransition
        }
        return ContentTransition(storage: .symbolReplace(configuration))
    }

    public static var symbolEffect: ContentTransition {
        .symbolEffect(.automatic)
    }

    private init(named name: NamedTransition.Name) {
        self.init(
            storage: .named(
                NamedTransition(
                    name: name,
                    layoutDirection: nil,
                    style: nil
                )
            )
        )
    }

    init(method: Method, effects: [Effect]) {
        self.init(
            storage: .custom(
                CustomTransition(
                    effects: effects,
                    method: method,
                    layoutDirection: nil
                )
            )
        )
    }

    mutating func applyEnvironmentValues(style: Style, layoutDirection: LayoutDirection) {
        switch storage {
        case var .named(named):
            named.style = style
            named.layoutDirection = layoutDirection
            storage = .named(named)
        case var .custom(custom):
            custom.layoutDirection = layoutDirection
            storage = .custom(custom)
        case .symbolReplace:
            break
        }
    }

    var style: Style? {
        get {
            switch storage {
            case let .named(named):
                named.style
            case .custom, .symbolReplace:
                nil
            }
        }
        set {
            switch storage {
            case var .named(named):
                named.style = newValue
                storage = .named(named)
            case .custom, .symbolReplace:
                break
            }
        }
    }

    var isIdentity: Bool {
        switch storage {
        case let .named(named):
            named.name == .identity
        case .custom, .symbolReplace:
            false
        }
    }

    var symbolReplaceConfiguration: _SymbolEffect.ReplaceConfiguration? {
        guard case let .symbolReplace(configuration) = storage else {
            return nil
        }
        return configuration
    }

    var numericValue: Float? {
        guard case let .named(named) = storage,
              case let .numericText(configuration) = named.name,
              case let .automatic(value) = configuration.direction else {
            return nil
        }
        return value
    }

    var isNumericText: Bool {
        guard case let .named(named) = storage,
              case .numericText = named.name else {
            return false
        }
        return true
    }

    var rbTransition: RBTransition {
        let transition: RBTransition
        switch storage {
        case let .named(named):
            transition = named.makeRBTransition()
        case let .custom(custom):
            transition = RBTransition()
            transition.method = custom.method.method
            for effect in custom.effects {
                transition.addEffect(RBTransitionEffect(effect))
            }
        case let .symbolReplace(configuration):
            transition = RBTransition()
            transition.method = Method.binary.method
            let effect = RBTransitionEffect()
            effect.type = 18
            effect.setIntegerArgumentValue(
                configuration.transitionFlags.rawValue,
                atIndex: 0
            )
            effect.setArgumentValue(1, atIndex: 1)
            transition.addEffect(effect)
        }
        transition.isReplaceable = isReplaceable
        return transition
    }

    private init(numericTextDirection direction: NumericTextConfiguration.Direction) {
        self.init(
            named: .numericText(
                NumericTextConfiguration(
                    direction: direction,
                    axis: nil,
                    options: NumericTextConfiguration.Options.numericTextDefault,
                    _delay: 18,
                    _scale: 51,
                    _blur: 32,
                    _offset: 19
                )
            )
        )
    }
}

extension ContentTransition.Style: ProtobufEncodableMessage, ProtobufDecodableMessage {
    func encode(to encoder: inout ProtobufEncoder) throws {
        let fieldNumber: UInt
        switch storage {
        case .default:
            return
        case .sessionWidget:
            fieldNumber = 1
        case .animatedWidget:
            fieldNumber = 2
        }

        encoder.encodeVarint((fieldNumber << 3) | 2)
        encoder.startLengthDelimited()
        encoder.endLengthDelimited()
    }

    init(from decoder: inout ProtobufDecoder) throws {
        self = .default

        while !decoder.isAtEnd {
            let tag = try decoder.decodeVarint()
            let fieldNumber = tag >> 3
            let wireType = tag & 0x7

            switch fieldNumber {
            case 1, 2:
                guard wireType == 2 else {
                    throw ProtobufDecoder.DecodingError.failed
                }
                try decoder.decodeLengthDelimited { nested in
                    while !nested.isAtEnd {
                        let nestedTag = try nested.decodeVarint()
                        try nested.skipField(wireType: nestedTag & 0x7)
                    }
                }
                self = fieldNumber == 1 ? .sessionWidget : .animatedWidget
            default:
                try decoder.skipField(wireType: wireType)
            }
        }
    }
}

private struct ContentTransitionKey: EnvironmentKey {
    static let defaultValue = ContentTransition.defaultTransition
}

private struct ContentTransitionAddsDrawingGroupKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    public var contentTransition: ContentTransition {
        get { self[ContentTransitionKey.self] }
        set { self[ContentTransitionKey.self] = newValue }
    }

    public var contentTransitionAddsDrawingGroup: Bool {
        get { self[ContentTransitionAddsDrawingGroupKey.self] }
        set { self[ContentTransitionAddsDrawingGroupKey.self] = newValue }
    }

    var contentTransitionState: ContentTransition.State {
        // State is the environment key so every layout and interpolation
        // consumer observes the same hidden transition state.
        get { self[ContentTransition.State.self] }
        set { self[ContentTransition.State.self] = newValue }
    }
}

extension View {
    @inlinable public func contentTransition(_ transition: ContentTransition) -> some View {
        environment(\.contentTransition, transition)
    }
}
