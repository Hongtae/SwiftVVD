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
            if animation == nil {
                animation = transaction.effectiveAnimation
            }
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
            let effect = RBTransitionEffect()
            effect.type = ContentTransition.EffectType.opacity.type
            effect.beginTime = 0
            effect.duration = 0
            effect.events = 3
            transition.addEffect(effect)
            return transition
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
        }
    }

    var style: Style? {
        get {
            switch storage {
            case let .named(named):
                named.style
            case .custom:
                nil
            }
        }
        set {
            switch storage {
            case var .named(named):
                named.style = newValue
                storage = .named(named)
            case .custom:
                break
            }
        }
    }

    var isIdentity: Bool {
        switch storage {
        case let .named(named):
            named.name == .identity
        case .custom:
            false
        }
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

private struct ContentTransitionKey: EnvironmentKey {
    static let defaultValue = ContentTransition.defaultTransition
}

private struct ContentTransitionAddsDrawingGroupKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

private struct ContentTransitionStateKey: EnvironmentKey {
    static var defaultValue: ContentTransition.State { .defaultValue }
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
        get { self[ContentTransitionStateKey.self] }
        set { self[ContentTransitionStateKey.self] = newValue }
    }
}

extension View {
    @inlinable public func contentTransition(_ transition: ContentTransition) -> some View {
        environment(\.contentTransition, transition)
    }
}
