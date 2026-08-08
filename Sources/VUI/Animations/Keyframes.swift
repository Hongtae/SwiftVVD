//
//  File: Keyframes.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

public protocol Keyframes<Value> {
    associatedtype Value = Self.Body.Value
    associatedtype Body: Keyframes

    @KeyframesBuilder<Self.Value> var body: Self.Body { get }

    func _resolve(
        into resolved: inout _ResolvedKeyframes<Self.Value>,
        initialValue: Self.Value,
        initialVelocity: Self.Value?
    )
}

extension Keyframes where Self.Value == Self.Body.Value {
    public func _resolve(
        into resolved: inout _ResolvedKeyframes<Self.Value>,
        initialValue: Self.Value,
        initialVelocity: Self.Value?
    ) {
        body._resolve(
            into: &resolved,
            initialValue: initialValue,
            initialVelocity: initialVelocity
        )
    }
}

protocol PrimitiveKeyframes: Keyframes where Body == Never {
}

extension PrimitiveKeyframes {
    public var body: Never {
        fatalError("body() should not be called on \(Self.self).")
    }
}

extension Never: Keyframes {
    public func _resolve(
        into resolved: inout _ResolvedKeyframes<Never>,
        initialValue: Never,
        initialVelocity: Never?
    ) {}
}

public struct _ResolvedKeyframes<Value> {
    struct Track {
        var duration: TimeInterval
        var update: (inout Value, Double) -> Void
        var updateVelocity: (inout Value, Double) -> Void
    }

    var tracks: [Track]

    init(tracks: [Track] = []) {
        self.tracks = tracks
    }

    var duration: TimeInterval {
        tracks.lazy.map(\.duration).max() ?? 0
    }

    fileprivate mutating func append<TrackValue>(
        keyPath: WritableKeyPath<Value, TrackValue>,
        path: AnimationPath<TrackValue>
    ) where TrackValue: Animatable {
        tracks.append(
            Track(
                duration: path.duration,
                update: { value, time in
                    path.update(value: &value[keyPath: keyPath], time: time)
                },
                updateVelocity: { value, time in
                    path.update(velocity: &value[keyPath: keyPath], time: time)
                }
            )
        )
    }

    func update(value: inout Value, time: Double) {
        for track in tracks {
            track.update(&value, time)
        }
    }

    func update(velocity: inout Value, time: Double) {
        for track in tracks {
            track.updateVelocity(&velocity, time)
        }
    }
}

@available(*, unavailable)
extension _ResolvedKeyframes: Sendable {
}

public protocol KeyframeTrackContent<Value> {
    associatedtype Value: Animatable = Self.Body.Value
    associatedtype Body: KeyframeTrackContent

    @KeyframeTrackContentBuilder<Self.Value> var body: Self.Body { get }

    func _resolve(into resolved: inout _ResolvedKeyframeTrackContent<Self.Value>)
}

extension KeyframeTrackContent where Self.Value == Self.Body.Value {
    public func _resolve(into resolved: inout _ResolvedKeyframeTrackContent<Self.Value>) {
        body._resolve(into: &resolved)
    }
}

protocol PrimitiveKeyframeTrackContent: KeyframeTrackContent where Body == Self {
}

extension PrimitiveKeyframeTrackContent {
    public var body: Self {
        fatalError("body() should not be called on \(Self.self).")
    }
}

public struct _ResolvedKeyframeTrackContent<Value> where Value: Animatable {
    enum Segment {
        case move(to: Value.AnimatableData)
        case cubic(
            to: Value.AnimatableData,
            startVelocity: Value.AnimatableData?,
            endVelocity: Value.AnimatableData?,
            duration: TimeInterval
        )
        case spring(
            to: Value.AnimatableData,
            spring: Spring,
            startVelocity: Value.AnimatableData?,
            duration: TimeInterval?
        )
        case linear(
            to: Value.AnimatableData,
            duration: TimeInterval,
            timingCurve: UnitCurve
        )
    }

    var segments: [Segment]

    init() {
        segments = []
    }

    mutating func append(_ segment: Segment) {
        segments.append(segment)
    }
}

@available(*, unavailable)
extension _ResolvedKeyframeTrackContent: Sendable {
}

public struct MoveKeyframe<Value>: KeyframeTrackContent where Value: Animatable {
    public var value: Value

    public init(_ to: Value) {
        value = to
    }

    public func _resolve(into resolved: inout _ResolvedKeyframeTrackContent<Value>) {
        resolved.append(.move(to: value.animatableData))
    }

    public typealias Body = MoveKeyframe<Value>
}

extension MoveKeyframe: PrimitiveKeyframeTrackContent {
}

@available(*, unavailable)
extension MoveKeyframe: Sendable {
}

public struct LinearKeyframe<Value>: KeyframeTrackContent where Value: Animatable {
    struct Segment {
        var to: Value.AnimatableData
        var duration: TimeInterval
        var timingCurve: UnitCurve
    }

    var segment: Segment

    public init(
        _ to: Value,
        duration: TimeInterval,
        timingCurve: UnitCurve = .linear
    ) {
        segment = Segment(
            to: to.animatableData,
            duration: duration,
            timingCurve: timingCurve
        )
    }

    public func _resolve(into resolved: inout _ResolvedKeyframeTrackContent<Value>) {
        resolved.append(
            .linear(
                to: segment.to,
                duration: segment.duration,
                timingCurve: segment.timingCurve
            )
        )
    }

    public typealias Body = LinearKeyframe<Value>
}

extension LinearKeyframe: PrimitiveKeyframeTrackContent {
}

@available(*, unavailable)
extension LinearKeyframe: Sendable {
}

public struct CubicKeyframe<Value>: KeyframeTrackContent where Value: Animatable {
    struct Segment {
        var to: Value.AnimatableData
        var startVelocity: Value.AnimatableData?
        var endVelocity: Value.AnimatableData?
        var duration: TimeInterval
    }

    var segment: Segment

    public init(
        _ to: Value,
        duration: TimeInterval,
        startVelocity: Value? = nil,
        endVelocity: Value? = nil
    ) {
        segment = Segment(
            to: to.animatableData,
            startVelocity: startVelocity?.animatableData,
            endVelocity: endVelocity?.animatableData,
            duration: duration
        )
    }

    public func _resolve(into resolved: inout _ResolvedKeyframeTrackContent<Value>) {
        resolved.append(
            .cubic(
                to: segment.to,
                startVelocity: segment.startVelocity,
                endVelocity: segment.endVelocity,
                duration: segment.duration
            )
        )
    }

    public typealias Body = CubicKeyframe<Value>
}

extension CubicKeyframe: PrimitiveKeyframeTrackContent {
}

@available(*, unavailable)
extension CubicKeyframe: Sendable {
}

public struct SpringKeyframe<Value>: KeyframeTrackContent where Value: Animatable {
    struct Segment {
        var to: Value.AnimatableData
        var spring: Spring
        var startVelocity: Value.AnimatableData?
        var duration: TimeInterval?
    }

    var segment: Segment

    public init(
        _ to: Value,
        duration: TimeInterval? = nil,
        spring: Spring = Spring(),
        startVelocity: Value? = nil
    ) {
        segment = Segment(
            to: to.animatableData,
            spring: spring,
            startVelocity: startVelocity?.animatableData,
            duration: duration
        )
    }

    public func _resolve(into resolved: inout _ResolvedKeyframeTrackContent<Value>) {
        resolved.append(
            .spring(
                to: segment.to,
                spring: segment.spring,
                startVelocity: segment.startVelocity,
                duration: segment.duration
            )
        )
    }

    public typealias Body = SpringKeyframe<Value>
}

extension SpringKeyframe: PrimitiveKeyframeTrackContent {
}

@available(*, unavailable)
extension SpringKeyframe: Sendable {
}

struct EmptyKeyframeTrackContent<Value>: PrimitiveKeyframeTrackContent where Value: Animatable {
    func _resolve(into resolved: inout _ResolvedKeyframeTrackContent<Value>) {
    }
}

struct MergedKeyframeTrackContent<Value, First, Second>: PrimitiveKeyframeTrackContent
where
    Value: Animatable,
    First: KeyframeTrackContent<Value>,
    Second: KeyframeTrackContent<Value>
{
    var first: First
    var second: Second

    func _resolve(into resolved: inout _ResolvedKeyframeTrackContent<Value>) {
        first._resolve(into: &resolved)
        second._resolve(into: &resolved)
    }
}

struct ArrayKeyframeTrackContent<Value, Content>: PrimitiveKeyframeTrackContent
where
    Value: Animatable,
    Content: KeyframeTrackContent<Value>
{
    var contents: [Content]

    func _resolve(into resolved: inout _ResolvedKeyframeTrackContent<Value>) {
        for content in contents {
            content._resolve(into: &resolved)
        }
    }
}

@resultBuilder
public struct KeyframeTrackContentBuilder<Value> where Value: Animatable {
    public static func buildExpression<K>(_ expression: K) -> K
    where K: KeyframeTrackContent<Value> {
        expression
    }

    public static func buildArray<K>(_ components: [K]) -> some KeyframeTrackContent<Value>
    where K: KeyframeTrackContent<Value> {
        ArrayKeyframeTrackContent<Value, K>(contents: components)
    }

    public static func buildEither<First, Second>(
        first component: First
    ) -> Conditional<Value, First, Second>
    where
        First: KeyframeTrackContent<Value>,
        Second: KeyframeTrackContent<Value>
    {
        Conditional(storage: .first(component))
    }

    public static func buildEither<First, Second>(
        second component: Second
    ) -> Conditional<Value, First, Second>
    where
        First: KeyframeTrackContent<Value>,
        Second: KeyframeTrackContent<Value>
    {
        Conditional(storage: .second(component))
    }

    public static func buildPartialBlock<K>(first: K) -> K
    where K: KeyframeTrackContent<Value> {
        first
    }

    public static func buildPartialBlock<Accumulated, Next>(
        accumulated: Accumulated,
        next: Next
    ) -> some KeyframeTrackContent<Value>
    where
        Accumulated: KeyframeTrackContent<Value>,
        Next: KeyframeTrackContent<Value>
    {
        MergedKeyframeTrackContent<Value, Accumulated, Next>(
            first: accumulated,
            second: next
        )
    }

    public static func buildBlock() -> some KeyframeTrackContent<Value> {
        EmptyKeyframeTrackContent<Value>()
    }

    public struct Conditional<ConditionalValue, First, Second>: PrimitiveKeyframeTrackContent
    where
        ConditionalValue == First.Value,
        First: KeyframeTrackContent,
        Second: KeyframeTrackContent,
        First.Value == Second.Value
    {
        enum Storage {
            case first(First)
            case second(Second)
        }

        var storage: Storage

        public func _resolve(
            into resolved: inout _ResolvedKeyframeTrackContent<ConditionalValue>
        ) {
            switch storage {
            case let .first(content):
                content._resolve(into: &resolved)
            case let .second(content):
                content._resolve(into: &resolved)
            }
        }

        public typealias Body = Conditional<ConditionalValue, First, Second>
        public typealias Value = ConditionalValue
    }
}

@available(*, unavailable)
extension KeyframeTrackContentBuilder: Sendable {
}

@available(*, unavailable)
extension KeyframeTrackContentBuilder.Conditional: Sendable {
}

public struct KeyframeTrack<Root, Value, Content>: PrimitiveKeyframes
where
    Value == Content.Value,
    Content: KeyframeTrackContent
{
    var keyPath: WritableKeyPath<Root, Value>
    var content: Content

    public init(
        @KeyframeTrackContentBuilder<Root> content: () -> Content
    ) where Root == Value {
        self.keyPath = \.self
        self.content = content()
    }

    public init(
        _ keyPath: WritableKeyPath<Root, Value>,
        @KeyframeTrackContentBuilder<Value> content: () -> Content
    ) {
        self.keyPath = keyPath
        self.content = content()
    }

    public func _resolve(
        into resolved: inout _ResolvedKeyframes<Root>,
        initialValue: Root,
        initialVelocity: Root?
    ) {
        let path = resolve(
            initialValue: initialValue[keyPath: keyPath],
            initialVelocity: initialVelocity?[keyPath: keyPath]
        )
        resolved.append(keyPath: keyPath, path: path)
    }

    private func resolve(
        initialValue: Value,
        initialVelocity: Value?
    ) -> AnimationPath<Value> {
        var content = _ResolvedKeyframeTrackContent<Value>()
        self.content._resolve(into: &content)
        return AnimationPath(
            initialValue: initialValue,
            initialVelocity: initialVelocity,
            content: content
        )
    }

    public typealias Body = Never
}

@available(*, unavailable)
extension KeyframeTrack: Sendable {
}

struct EmptyKeyframes<Value>: PrimitiveKeyframes {
    func _resolve(
        into resolved: inout _ResolvedKeyframes<Value>,
        initialValue: Value,
        initialVelocity: Value?
    ) {
    }
}

struct CombinedKeyframes<Value, First, Second>: PrimitiveKeyframes
where
    First: Keyframes<Value>,
    Second: Keyframes<Value>
{
    var first: First
    var second: Second

    func _resolve(
        into resolved: inout _ResolvedKeyframes<Value>,
        initialValue: Value,
        initialVelocity: Value?
    ) {
        first._resolve(
            into: &resolved,
            initialValue: initialValue,
            initialVelocity: initialVelocity
        )
        second._resolve(
            into: &resolved,
            initialValue: initialValue,
            initialVelocity: initialVelocity
        )
    }
}

@resultBuilder
public struct KeyframesBuilder<Value> {
    public static func buildExpression<K>(_ expression: K) -> K
    where K: KeyframeTrackContent<Value> {
        expression
    }

    public static func buildArray<K>(_ components: [K]) -> some KeyframeTrackContent<Value>
    where K: KeyframeTrackContent<Value> {
        ArrayKeyframeTrackContent<Value, K>(contents: components)
    }

    public static func buildEither<First, Second>(
        first component: First
    ) -> KeyframeTrackContentBuilder<Value>.Conditional<Value, First, Second>
    where
        First: KeyframeTrackContent<Value>,
        Second: KeyframeTrackContent<Value>
    {
        KeyframeTrackContentBuilder<Value>.buildEither(first: component)
    }

    public static func buildEither<First, Second>(
        second component: Second
    ) -> KeyframeTrackContentBuilder<Value>.Conditional<Value, First, Second>
    where
        First: KeyframeTrackContent<Value>,
        Second: KeyframeTrackContent<Value>
    {
        KeyframeTrackContentBuilder<Value>.buildEither(second: component)
    }

    public static func buildPartialBlock<K>(first: K) -> K
    where K: KeyframeTrackContent<Value> {
        first
    }

    public static func buildPartialBlock<Accumulated, Next>(
        accumulated: Accumulated,
        next: Next
    ) -> some KeyframeTrackContent<Value>
    where
        Accumulated: KeyframeTrackContent<Value>,
        Next: KeyframeTrackContent<Value>
    {
        MergedKeyframeTrackContent<Value, Accumulated, Next>(
            first: accumulated,
            second: next
        )
    }

    public static func buildBlock() -> some KeyframeTrackContent<Value>
    where Value: Animatable {
        EmptyKeyframeTrackContent<Value>()
    }

    public static func buildFinalResult<Content>(
        _ component: Content
    ) -> KeyframeTrack<Value, Value, Content>
    where Content: KeyframeTrackContent<Value> {
        KeyframeTrack(\.self) {
            component
        }
    }

    public static func buildExpression<Content>(_ expression: Content) -> Content
    where Content: Keyframes<Value> {
        expression
    }

    public static func buildPartialBlock<Content>(first: Content) -> Content
    where Content: Keyframes<Value> {
        first
    }

    public static func buildPartialBlock<Accumulated, Next>(
        accumulated: Accumulated,
        next: Next
    ) -> some Keyframes<Value>
    where
        Accumulated: Keyframes<Value>,
        Next: Keyframes<Value>
    {
        CombinedKeyframes<Value, Accumulated, Next>(
            first: accumulated,
            second: next
        )
    }

    public static func buildBlock() -> some Keyframes<Value> {
        EmptyKeyframes<Value>()
    }

    public static func buildFinalResult<Content>(_ component: Content) -> Content
    where Content: Keyframes<Value> {
        component
    }
}

@available(*, unavailable)
extension KeyframesBuilder: Sendable {
}

fileprivate struct AnimationPath<Value> where Value: Animatable {
    private enum Element {
        case move(to: Value.AnimatableData)
        case linear(
            from: Value.AnimatableData,
            to: Value.AnimatableData,
            duration: TimeInterval,
            timingCurve: UnitCurve
        )
        case cubic(
            from: Value.AnimatableData,
            to: Value.AnimatableData,
            startVelocity: Value.AnimatableData,
            endVelocity: Value.AnimatableData,
            duration: TimeInterval
        )
        case spring(
            from: Value.AnimatableData,
            to: Value.AnimatableData,
            spring: Spring,
            initialVelocity: Value.AnimatableData,
            duration: TimeInterval
        )

        var duration: TimeInterval {
            switch self {
            case .move:
                return 0
            case let .linear(_, _, duration, _),
                 let .cubic(_, _, _, _, duration),
                 let .spring(_, _, _, _, duration):
                return duration
            }
        }

        var end: Value.AnimatableData {
            switch self {
            case let .move(to),
                 let .linear(_, to, _, _),
                 let .cubic(_, to, _, _, _),
                 let .spring(_, to, _, _, _):
                return to
            }
        }

        var endVelocity: Value.AnimatableData {
            switch self {
            case .move:
                return .zero
            case let .linear(from, to, duration, timingCurve):
                guard duration > 0 else { return .zero }
                var velocity = to
                velocity -= from
                velocity.scale(by: timingCurve.velocity(at: 1) / duration)
                return velocity
            case let .cubic(_, _, _, endVelocity, _):
                return endVelocity
            case let .spring(from, to, spring, initialVelocity, duration):
                var target = to
                target -= from
                return spring._keyframeVelocity(
                    target: target,
                    initialVelocity: initialVelocity,
                    time: duration
                )
            }
        }

        func value(at time: Double) -> Value.AnimatableData {
            switch self {
            case let .move(to):
                return to
            case let .linear(from, to, duration, timingCurve):
                guard time > 0 else { return from }
                guard duration > 0, time < duration else { return to }
                return Self.interpolate(
                    from: from,
                    to: to,
                    progress: timingCurve.value(at: time / duration)
                )
            case let .cubic(from, to, startVelocity, endVelocity, duration):
                guard time > 0 else { return from }
                guard duration > 0, time < duration else { return to }
                return Self.hermite(
                    from: from,
                    to: to,
                    startVelocity: startVelocity,
                    endVelocity: endVelocity,
                    duration: duration,
                    progress: time / duration
                )
            case let .spring(from, to, spring, initialVelocity, duration):
                if time >= duration {
                    var target = to
                    target -= from
                    var result = from
                    result += spring._keyframeValue(
                        target: target,
                        initialVelocity: initialVelocity,
                        time: duration
                    )
                    return result
                }
                var target = to
                target -= from
                var result = from
                result += spring._keyframeValue(
                    target: target,
                    initialVelocity: initialVelocity,
                    time: time
                )
                return result
            }
        }

        func velocity(at time: Double) -> Value.AnimatableData {
            switch self {
            case .move:
                return .zero
            case let .linear(from, to, duration, timingCurve):
                guard duration > 0 else { return .zero }
                let boundedTime = min(max(time, 0), duration)
                var result = to
                result -= from
                result.scale(
                    by: timingCurve.velocity(at: boundedTime / duration) / duration
                )
                return result
            case let .cubic(from, to, startVelocity, endVelocity, duration):
                guard duration > 0 else { return endVelocity }
                return Self.hermiteVelocity(
                    from: from,
                    to: to,
                    startVelocity: startVelocity,
                    endVelocity: endVelocity,
                    duration: duration,
                    progress: min(max(time / duration, 0), 1)
                )
            case let .spring(from, to, spring, initialVelocity, duration):
                var target = to
                target -= from
                return spring._keyframeVelocity(
                    target: target,
                    initialVelocity: initialVelocity,
                    time: min(time, duration)
                )
            }
        }

        private static func interpolate(
            from: Value.AnimatableData,
            to: Value.AnimatableData,
            progress: Double
        ) -> Value.AnimatableData {
            var delta = to
            delta -= from
            delta.scale(by: progress)
            var result = from
            result += delta
            return result
        }

        private static func hermite(
            from: Value.AnimatableData,
            to: Value.AnimatableData,
            startVelocity: Value.AnimatableData,
            endVelocity: Value.AnimatableData,
            duration: Double,
            progress t: Double
        ) -> Value.AnimatableData {
            let t2 = t * t
            let t3 = t2 * t
            var result = from
            result.scale(by: 2 * t3 - 3 * t2 + 1)
            var term = startVelocity
            term.scale(by: (t3 - 2 * t2 + t) * duration)
            result += term
            term = to
            term.scale(by: -2 * t3 + 3 * t2)
            result += term
            term = endVelocity
            term.scale(by: (t3 - t2) * duration)
            result += term
            return result
        }

        private static func hermiteVelocity(
            from: Value.AnimatableData,
            to: Value.AnimatableData,
            startVelocity: Value.AnimatableData,
            endVelocity: Value.AnimatableData,
            duration: Double,
            progress t: Double
        ) -> Value.AnimatableData {
            let t2 = t * t
            var result = from
            result.scale(by: (6 * t2 - 6 * t) / duration)
            var term = startVelocity
            term.scale(by: 3 * t2 - 4 * t + 1)
            result += term
            term = to
            term.scale(by: (-6 * t2 + 6 * t) / duration)
            result += term
            term = endVelocity
            term.scale(by: 3 * t2 - 2 * t)
            result += term
            return result
        }
    }

    private var elements: [Element]
    private var initialValue: Value.AnimatableData

    init(
        initialValue: Value,
        initialVelocity: Value?,
        content: _ResolvedKeyframeTrackContent<Value>
    ) {
        self.initialValue = initialValue.animatableData

        var elements: [Element] = []
        var current = initialValue.animatableData
        var currentVelocity = initialVelocity?.animatableData ?? .zero

        for segment in content.segments {
            let element: Element
            switch segment {
            case let .move(to):
                element = .move(to: to)
            case let .linear(to, duration, timingCurve):
                element = .linear(
                    from: current,
                    to: to,
                    duration: duration,
                    timingCurve: timingCurve
                )
            case let .cubic(to, startVelocity, endVelocity, duration):
                element = .cubic(
                    from: current,
                    to: to,
                    startVelocity: startVelocity ?? currentVelocity,
                    endVelocity: endVelocity ?? .zero,
                    duration: duration
                )
            case let .spring(to, spring, startVelocity, requestedDuration):
                let velocity = startVelocity ?? currentVelocity
                var target = to
                target -= current
                let duration = requestedDuration ?? spring.settlingDuration(
                    target: target,
                    initialVelocity: velocity,
                    epsilon: 0.001
                )
                element = .spring(
                    from: current,
                    to: to,
                    spring: spring,
                    initialVelocity: velocity,
                    duration: duration
                )
            }
            elements.append(element)
            current = element.end
            currentVelocity = element.endVelocity
        }

        self.elements = elements
    }

    var duration: TimeInterval {
        elements.reduce(0) { $0 + $1.duration }
    }

    func update(value: inout Value, time: Double) {
        value.animatableData = animatableData(at: time)
    }

    func update(velocity: inout Value, time: Double) {
        velocity.animatableData = self.velocity(at: time)
    }

    private func animatableData(at time: Double) -> Value.AnimatableData {
        guard let first = elements.first else {
            return initialValue
        }

        var localTime = time
        for element in elements {
            if localTime <= element.duration {
                return element.value(at: localTime)
            }
            localTime -= element.duration
        }
        return elements.last?.value(at: elements.last?.duration ?? 0) ?? first.end
    }

    private func velocity(at time: Double) -> Value.AnimatableData {
        guard !elements.isEmpty else {
            return .zero
        }

        var localTime = time
        for element in elements {
            if localTime <= element.duration {
                return element.velocity(at: localTime)
            }
            localTime -= element.duration
        }
        guard let last = elements.last else { return .zero }
        return last.velocity(at: last.duration)
    }
}

public struct KeyframeTimeline<Value> {
    var initialValue: Value
    var content: _ResolvedKeyframes<Value>

    public init(
        initialValue: Value,
        @KeyframesBuilder<Value> content: () -> some Keyframes<Value>
    ) {
        self.initialValue = initialValue
        var resolved = _ResolvedKeyframes<Value>()
        content()._resolve(
            into: &resolved,
            initialValue: initialValue,
            initialVelocity: nil
        )
        self.content = resolved
    }

    init(
        initialValue: Value,
        initialVelocity: Value,
        @KeyframesBuilder<Value> content: () -> some Keyframes<Value>
    ) {
        self.initialValue = initialValue
        var resolved = _ResolvedKeyframes<Value>()
        content()._resolve(
            into: &resolved,
            initialValue: initialValue,
            initialVelocity: initialVelocity
        )
        self.content = resolved
    }

    public var duration: TimeInterval {
        content.duration
    }

    public func value(time: Double) -> Value {
        var value = initialValue
        content.update(value: &value, time: time)
        return value
    }

    public func value(progress: Double) -> Value {
        value(time: progress * duration)
    }

    func velocity(time: Double) -> Value {
        var velocity = initialValue
        content.update(velocity: &velocity, time: time)
        return velocity
    }

    mutating func update(value: inout Value, time: Double) {
        content.update(value: &value, time: time)
    }
}

@available(*, unavailable)
extension KeyframeTimeline: Sendable {
}

private enum AnimationTime {
    case pending(Time)
    case started(Time)

    func elapsed(at time: Time) -> Double {
        switch self {
        case .pending:
            return 0
        case let .started(start):
            return time.seconds - start.seconds
        }
    }

    mutating func update(at time: Time) {
        guard case let .pending(pending) = self, pending < time else {
            return
        }
        self = .started(time)
    }
}

private enum PlaybackMode {
    case onChange(trigger: AnyEquatable)
    case repeating(paused: Bool)
}

private enum KeyframeTrackState<Value, Path>
where Value == Path.Value, Path: Keyframes {
    struct RepeatingState {
        enum Mode {
            case paused(elapsed: Double)
            case playing(start: AnimationTime, elapsedOffset: Double)
        }

        var timeline: KeyframeTimeline<Value>
        var mode: Mode

        func value(at time: Time) -> Value {
            let elapsed: Double
            switch mode {
            case let .paused(pausedElapsed):
                elapsed = pausedElapsed
            case let .playing(start, elapsedOffset):
                elapsed = elapsedOffset + start.elapsed(at: time)
            }
            guard timeline.duration > 0 else {
                return timeline.value(time: 0)
            }
            return timeline.value(
                time: elapsed.truncatingRemainder(dividingBy: timeline.duration)
            )
        }

        mutating func update(at time: Time, paused: Bool) {
            switch (mode, paused) {
            case let (.paused(elapsed), false):
                mode = .playing(
                    start: .pending(time),
                    elapsedOffset: elapsed
                )
            case let (.playing(start, elapsedOffset), true):
                mode = .paused(
                    elapsed: elapsedOffset + start.elapsed(at: time)
                )
            default:
                break
            }
        }
    }

    struct EventDrivenState {
        enum Phase {
            case idle(Value)
            case playing(timeline: KeyframeTimeline<Value>, start: AnimationTime)
        }

        var trigger: AnyEquatable
        var phase: Phase

        func value(at time: Time) -> Value {
            switch phase {
            case let .idle(value):
                return value
            case let .playing(timeline, start):
                return timeline.value(time: start.elapsed(at: time))
            }
        }

        mutating func update(
            at time: Time,
            trigger newTrigger: AnyEquatable,
            initialValue: Value,
            path: (Value) -> Path
        ) {
            guard trigger != newTrigger else {
                return
            }

            trigger = newTrigger
            switch phase {
            case .idle:
                let timeline = KeyframeTimeline(initialValue: initialValue) {
                    path(initialValue)
                }
                phase = .playing(
                    timeline: timeline,
                    start: .pending(time)
                )
            case let .playing(timeline, start):
                let elapsed = min(start.elapsed(at: time), timeline.duration)
                let value = timeline.value(time: elapsed)
                let velocity = timeline.velocity(time: elapsed)
                let newTimeline = KeyframeTimeline(
                    initialValue: value,
                    initialVelocity: velocity
                ) {
                    path(value)
                }
                phase = .playing(
                    timeline: newTimeline,
                    start: .pending(time)
                )
            }
        }
    }

    case eventDriven(EventDrivenState)
    case repeating(RepeatingState)
    case initial

    var isInitial: Bool {
        if case .initial = self {
            return true
        }
        return false
    }

    var isAnimating: Bool {
        switch self {
        case let .eventDriven(state):
            if case .playing = state.phase {
                return true
            }
            return false
        case let .repeating(state):
            if case .playing = state.mode {
                return true
            }
            return false
        case .initial:
            return false
        }
    }

    mutating func updatePlayback(
        _ playback: PlaybackMode,
        time: Time,
        initialValue: Value,
        plan: (Value) -> Path
    ) {
        switch (self, playback) {
        case let (.eventDriven(state), .onChange(trigger)):
            var state = state
            state.update(
                at: time,
                trigger: trigger,
                initialValue: initialValue,
                path: plan
            )
            self = .eventDriven(state)

        case let (.repeating(state), .repeating(paused)):
            var state = state
            state.update(at: time, paused: paused)
            self = .repeating(state)

        case let (.repeating(state), .onChange(trigger)):
            self = .eventDriven(
                EventDrivenState(
                    trigger: trigger,
                    phase: .idle(state.value(at: time))
                )
            )

        case let (.eventDriven(state), .repeating(paused)):
            let value = state.value(at: time)
            let timeline = KeyframeTimeline(initialValue: value) {
                plan(value)
            }
            self = .repeating(
                RepeatingState(
                    timeline: timeline,
                    mode: paused
                        ? .paused(elapsed: 0)
                        : .playing(start: .pending(time), elapsedOffset: 0)
                )
            )

        case let (.initial, .onChange(trigger)):
            self = .eventDriven(
                EventDrivenState(
                    trigger: trigger,
                    phase: .idle(initialValue)
                )
            )

        case let (.initial, .repeating(paused)):
            let timeline = KeyframeTimeline(initialValue: initialValue) {
                plan(initialValue)
            }
            self = .repeating(
                RepeatingState(
                    timeline: timeline,
                    mode: paused
                        ? .paused(elapsed: 0)
                        : .playing(start: .pending(time), elapsedOffset: 0)
                )
            )
        }
    }

    mutating func updateAnimation(time: Time) {
        switch self {
        case let .repeating(state):
            var state = state
            guard case let .playing(currentStart, elapsedOffset) = state.mode else {
                return
            }
            var start = currentStart
            start.update(at: time)
            state.mode = .playing(start: start, elapsedOffset: elapsedOffset)
            self = .repeating(state)

        case let .eventDriven(state):
            var state = state
            guard case let .playing(timeline, currentStart) = state.phase else {
                return
            }
            var start = currentStart
            switch start {
            case .pending:
                start.update(at: time)
                state.phase = .playing(timeline: timeline, start: start)
            case .started:
                if start.elapsed(at: time) > timeline.duration {
                    state.phase = .idle(timeline.value(progress: 1))
                }
            }
            self = .eventDriven(state)

        case .initial:
            break
        }
    }

    func value(at time: Time, initialValue: Value) -> Value {
        switch self {
        case let .eventDriven(state):
            return state.value(at: time)
        case let .repeating(state):
            return state.value(at: time)
        case .initial:
            return initialValue
        }
    }
}

private struct AnimatorAttribute<AnimatorValue, Path, Content>: StatefulRule
where
    AnimatorValue == Path.Value,
    Path: Keyframes,
    Content: View
{
    typealias Value = Content
    typealias Animator = KeyframeAnimator<AnimatorValue, Path, Content>

    var _view: Attribute<Animator>
    var _playback: Attribute<PlaybackMode>
    var _phase: Attribute<_GraphInputs.Phase>
    var _time: Attribute<Time>
    var resetSeed: UInt32
    var currentState: KeyframeTrackState<AnimatorValue, Path>

    mutating func updateValue() {
        let phase = _phase.value
        if resetSeed != phase.resetSeed {
            resetSeed = phase.resetSeed
            currentState = .initial
        }

        let time = _time.value
        let playbackChanged = _AGGraph.currentStatefulInputChanged(_playback.identifier)
        let playback = _playback.value
        let animator = _view.value

        if playbackChanged || currentState.isInitial {
            currentState.updatePlayback(
                playback,
                time: time,
                initialValue: animator.initialValue,
                plan: animator.path
            )
        }

        if currentState.isAnimating {
            currentState.updateAnimation(time: time)
            guard let viewGraph = GraphHost.currentHost as? ViewGraph else {
                fatalError("KeyframeAnimator requires an active ViewGraph host.")
            }
            viewGraph.nextUpdate.views.at(time + 1.0 / 120.0)
        }

        let value = currentState.value(
            at: time,
            initialValue: animator.initialValue
        )
        _AGGraph.setStatefulOutput(animator.content(value))
    }
}

public struct KeyframeAnimator<Value, KeyframePath, Content>: View
where
    Value == KeyframePath.Value,
    KeyframePath: Keyframes,
    Content: View
{
    var initialValue: Value
    var path: (Value) -> KeyframePath
    private var playback: PlaybackMode
    var content: (Value) -> Content

    public init(
        initialValue: Value,
        trigger: some Equatable,
        @ViewBuilder content: @escaping (Value) -> Content,
        @KeyframesBuilder<Value> keyframes: @escaping (Value) -> KeyframePath
    ) {
        self.initialValue = initialValue
        self.path = keyframes
        self.playback = .onChange(trigger: AnyEquatable(trigger))
        self.content = content
    }

    public init(
        initialValue: Value,
        repeating: Bool = true,
        @ViewBuilder content: @escaping (Value) -> Content,
        @KeyframesBuilder<Value> keyframes: @escaping (Value) -> KeyframePath
    ) {
        self.initialValue = initialValue
        self.path = keyframes
        self.playback = .repeating(paused: !repeating)
        self.content = content
    }

    public static func _makeView(
        view: _GraphValue<Self>,
        inputs: _ViewInputs
    ) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("\(Self.self)._makeView called outside an active _AGGraph context.")
        }
        let content: Attribute<Content> = graph.makeStatefulRule(
            AnimatorAttribute(
                _view: view._attribute,
                _playback: view[\.playback]._attribute,
                _phase: inputs.base.phase,
                _time: inputs.base.time,
                resetSeed: 0,
                currentState: .initial
            )
        )
        return Content._makeView(
            view: _GraphValue(_attribute: content),
            inputs: inputs
        )
    }

    public typealias Body = Never
}

extension KeyframeAnimator: PrimitiveView, UnaryView {
}

@available(*, unavailable)
extension KeyframeAnimator: Sendable {
}

extension View {
    public func keyframeAnimator<Value>(
        initialValue: Value,
        trigger: some Equatable,
        @ViewBuilder content: @escaping @Sendable (
            PlaceholderContentView<Self>,
            Value
        ) -> some View,
        @KeyframesBuilder<Value> keyframes: @escaping (Value) -> some Keyframes<Value>
    ) -> some View {
        let result = KeyframeAnimator(
            initialValue: initialValue,
            trigger: trigger,
            content: { value in
                content(PlaceholderContentView<Self>(), value)
            },
            keyframes: keyframes
        )
        return modifier(keyframeAnimatorModifier(result))
    }

    public func keyframeAnimator<Value>(
        initialValue: Value,
        repeating: Bool = true,
        @ViewBuilder content: @escaping @Sendable (
            PlaceholderContentView<Self>,
            Value
        ) -> some View,
        @KeyframesBuilder<Value> keyframes: @escaping (Value) -> some Keyframes<Value>
    ) -> some View {
        let result = KeyframeAnimator(
            initialValue: initialValue,
            repeating: repeating,
            content: { value in
                content(PlaceholderContentView<Self>(), value)
            },
            keyframes: keyframes
        )
        return modifier(keyframeAnimatorModifier(result))
    }

    private func keyframeAnimatorModifier<Result>(
        _ result: Result
    ) -> CustomModifier<Self, Result> where Result: View {
        CustomModifier(result: result)
    }
}
