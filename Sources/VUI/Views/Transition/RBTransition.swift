//
//  File: RBTransition.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

struct RBTransitionAnimationContext {
    var animationTable: RBAnimationTable
    var operation: RBAnimationSequencer.OperationAnimationRecord
    var time: Float
    var isFlipped: Bool = false

    func progress(sequence: UInt32, event: UInt32) -> Float {
        let sampled = animationTable.evaluate(
            animationIndex: operation.animationIndex,
            sequence: sequence,
            time: Double(time) - Double(operation.delay)
        )
        return event & 1 == 0 ? 1 - sampled : sampled
    }
}

// Accumulated render-state mutations produced by applying transition effects to one item.
struct RBTransitionEffectResults: Equatable {
    var alpha: Float = 1
    var transform: CGAffineTransform = .identity
    var blurRadius: CGFloat = 0
    var hasBlur: Bool = false
    var bounds: CGRect?
}

struct RBSymbolReplacementConfiguration: Equatable {
    enum Style: Equatable {
        case downUp
        case upUp
        case offUp
    }

    var style: Style
    var isLayered: Bool
    var isAutomaticStyle: Bool
    var duration: Double
}

// Single render effect entry used by RBTransition to describe opacity, transform, blur, and
// other content-transition operations.
final class RBTransitionEffect: NSObject, NSCopying {
    private static let geometryChangingEffectTypeMask: UInt32 = 0x1e1ff
    private static let flippedDirections: [UInt32] = [1, 0, 3, 2, 5, 4]
    private static let sequenceDirections: [UInt32?] = [0, 1, 2, 3, nil, nil, nil, nil, 4, 5]

    var type: Int32
    var beginTime: Float {
        get { usesAnimationIndexMode ? 0 : Self.timingFloat(beginTimeByte) }
        set {
            if usesAnimationIndexMode {
                durationByte = UInt8.max
            }
            usesAnimationIndexMode = false
            beginTimeByte = Self.timingByte(newValue)
        }
    }
    var duration: Float {
        get { usesAnimationIndexMode ? 1 : Self.timingFloat(durationByte) }
        set {
            if usesAnimationIndexMode {
                beginTimeByte = 0
            }
            usesAnimationIndexMode = false
            durationByte = Self.timingByte(newValue)
        }
    }
    var events: UInt32
    var flags: UInt32
    var semanticType: Int32 {
        type & 0x3f
    }
    var animationIndex: UInt {
        get {
            guard usesAnimationIndexMode, beginTimeByte == durationByte else {
                return 0
            }
            return UInt(beginTimeByte)
        }
        set {
            let byte = Self.animationIndexByte(newValue)
            usesAnimationIndexMode = true
            beginTimeByte = byte
            durationByte = byte
        }
    }
    var insertAnimationIndex: UInt {
        get { usesAnimationIndexMode ? UInt(beginTimeByte) : 0 }
        set {
            if !usesAnimationIndexMode {
                durationByte = 0
            }
            usesAnimationIndexMode = true
            beginTimeByte = Self.animationIndexByte(newValue)
        }
    }
    var removeAnimationIndex: UInt {
        get { usesAnimationIndexMode ? UInt(durationByte) : 0 }
        set {
            if !usesAnimationIndexMode {
                beginTimeByte = 0
            }
            usesAnimationIndexMode = true
            durationByte = Self.animationIndexByte(newValue)
        }
    }
    var changesGeometry: Bool {
        let index = semanticType - 2
        guard index >= 0, index <= 16 else { return false }
        return (Self.geometryChangingEffectTypeMask & (1 << UInt32(index))) != 0
    }

    private var beginTimeByte: UInt8
    private var durationByte: UInt8
    private var usesAnimationIndexMode: Bool
    private var argumentWords: [UInt32]

    private var argumentCount: Int {
        let counts = Self.effectArgumentCounts
        let index = Int(semanticType)
        guard index >= 0, index < counts.count else { return 0 }
        return min(Int(counts[index]), argumentWords.count)
    }

    private static let effectArgumentCounts: [UInt8] = [
        0, 0, 1, 2, 1, 0, 1, 0,
        0, 0, 0, 0, 0, 0, 0, 2,
        2, 2, 2, 0, 0, 2, 2, 2,
        2, 0, 0, 0, 1, 0, 0, 0,
    ]

    override init() {
        self.type = 0
        self.beginTimeByte = 0
        self.durationByte = 0
        self.events = 0
        self.flags = 0
        self.usesAnimationIndexMode = false
        self.argumentWords = Self.emptyArgumentWords()
        super.init()
    }

    init(_ effect: ContentTransition.Effect) {
        self.type = effect.type.type
        self.beginTimeByte = Self.timingByte(effect.begin)
        self.durationByte = Self.timingByte(effect.duration)
        self.events = effect.events
        self.flags = effect.flags
        self.usesAnimationIndexMode = false
        self.argumentWords = Self.emptyArgumentWords()
        super.init()

        set(effect.type.arg0, atIndex: 0)
        set(effect.type.arg1, atIndex: 1)
    }

    private init(
        type: Int32,
        beginTimeByte: UInt8,
        durationByte: UInt8,
        usesAnimationIndexMode: Bool,
        events: UInt32,
        flags: UInt32,
        argumentWords: [UInt32]
    ) {
        self.type = type
        self.beginTimeByte = beginTimeByte
        self.durationByte = durationByte
        self.usesAnimationIndexMode = usesAnimationIndexMode
        self.events = events
        self.flags = flags
        self.argumentWords = Self.normalizedArgumentWords(argumentWords)
        super.init()
    }

    private static func emptyArgumentWords() -> [UInt32] {
        [0, 0]
    }

    private static func normalizedArgumentWords(_ words: [UInt32]) -> [UInt32] {
        var normalized = emptyArgumentWords()
        for index in normalized.indices where index < words.count {
            normalized[index] = words[index]
        }
        return normalized
    }

    private static func argumentSlotIndex(_ index: UInt) -> Int? {
        guard index < 2 else { return nil }
        return Int(index)
    }

    private static func timingByte(_ value: Float) -> UInt8 {
        let clamped = min(max(value, 0), 1)
        return UInt8((clamped * 255 + 0.5).rounded(.towardZero))
    }

    private static func timingFloat(_ byte: UInt8) -> Float {
        Float(byte) / 255
    }

    private static func animationIndexByte(_ value: UInt) -> UInt8 {
        UInt8(truncatingIfNeeded: value)
    }

    func setArgumentValue(_ value: Float, atIndex index: UInt) {
        guard let index = Self.argumentSlotIndex(index) else { return }
        argumentWords[index] = value.bitPattern
    }

    func argumentValue(atIndex index: UInt) -> Float {
        guard let index = Self.argumentSlotIndex(index) else { return 0 }
        return Float(bitPattern: argumentWords[index])
    }

    func setIntegerArgumentValue(_ value: UInt32, atIndex index: UInt) {
        guard let index = Self.argumentSlotIndex(index) else { return }
        argumentWords[index] = value
    }

    func integerArgumentValue(atIndex index: UInt) -> UInt32 {
        guard let index = Self.argumentSlotIndex(index) else { return 0 }
        return argumentWords[index]
    }

    func customDuration(for event: UInt32) -> Float? {
        switch semanticType {
        case 17:
            let base: Float = event & 1 == 0 ? 1 / 6 : 0.25
            return base / argumentValue(atIndex: 1)
        case 18:
            let base: Float = integerArgumentValue(atIndex: 0) & 0xf == 4 ? 0.25 : 0.5
            return base / argumentValue(atIndex: 1)
        default:
            return nil
        }
    }

    func anchorDirection(event: UInt32, isFlipped: Bool) -> UInt32? {
        let direction = semanticType - 7
        guard direction >= 0, direction <= 3 else { return nil }
        return resolvedDirection(UInt32(direction), event: event, isFlipped: isFlipped)
    }

    func sequenceDirection(event: UInt32, isFlipped: Bool) -> UInt32? {
        let index = semanticType - 11
        guard index >= 0, index < Self.sequenceDirections.count,
              let direction = Self.sequenceDirections[Int(index)] else {
            return nil
        }
        return resolvedDirection(direction, event: event, isFlipped: isFlipped)
    }

    func effectTime(
        at progress: Float,
        event: UInt32,
        transition: RBTransition,
        usesAddRemoveDurationFallback: Bool = false,
        animationContext: RBTransitionAnimationContext? = nil
    ) -> Float? {
        let directedProgress = event & 1 == 0 ? 1 - progress : progress

        if usesAnimationIndexMode {
            let index = event & 1 == 0 ? removeAnimationIndex : insertAnimationIndex
            if let animationContext {
                return animationContext.progress(sequence: UInt32(index), event: event)
            }
            return index == 0 ? directedProgress : nil
        }

        let duration = Self.timingFloat(durationByte)
        guard duration > 0 else {
            guard usesAddRemoveDurationFallback,
                  transition.addRemoveDuration > 0 else {
                return directedProgress
            }
            return 1 + (directedProgress - 1) / transition.addRemoveDuration
        }

        let begin = Self.timingFloat(beginTimeByte)
        let localProgress = (directedProgress - begin) / duration
        return min(max(localProgress, 0), 1)
    }

    @discardableResult
    func apply(
        to results: inout RBTransitionEffectResults,
        bounds: CGRect,
        progress: Float,
        event: UInt32,
        transition: RBTransition,
        isFlipped: Bool = false,
        usesAddRemoveDurationFallback: Bool = false,
        animationContext: RBTransitionAnimationContext? = nil
    ) -> Bool {
        let requestedEvents = event & 0x3f
        guard requestedEvents != 0, (events & requestedEvents) != 0 else {
            return true
        }

        guard let effectProgress = effectTime(
            at: progress,
            event: event,
            transition: transition,
            usesAddRemoveDurationFallback: usesAddRemoveDurationFallback,
            animationContext: animationContext
        ) else {
            return false
        }

        switch semanticType {
        case ContentTransition.EffectType.opacity.type:
            results.alpha *= min(max(effectProgress, 0), 1)
        case ContentTransition.EffectType.scale(1).type:
            applyScale(
                to: &results,
                bounds: bounds,
                progress: effectProgress,
                event: event,
                isFlipped: isFlipped
            )
        case ContentTransition.EffectType.translation(.zero).type:
            let vector = CGSize(
                width: CGFloat(argumentValue(atIndex: 0)),
                height: CGFloat(argumentValue(atIndex: 1))
            )
            applyTranslation(
                vector,
                to: &results,
                progress: effectProgress,
                event: event,
                isFlipped: isFlipped
            )
        case ContentTransition.EffectType.blur(radius: 0).type:
            applyBlur(
                CGFloat(argumentValue(atIndex: 0)),
                to: &results,
                progress: effectProgress
            )
        case ContentTransition.EffectType.translation(scale: .zero).type:
            let vector = CGSize(
                width: bounds.width * CGFloat(argumentValue(atIndex: 0)),
                height: bounds.height * CGFloat(argumentValue(atIndex: 1))
            )
            applyTranslation(
                vector,
                to: &results,
                progress: effectProgress,
                event: event,
                isFlipped: isFlipped
            )
        case ContentTransition.EffectType.relativeBlur(scale: .zero).type:
            let radius = bounds.width * CGFloat(argumentValue(atIndex: 0)) +
                bounds.height * CGFloat(argumentValue(atIndex: 1))
            applyBlur(radius, to: &results, progress: effectProgress)
        default:
            break
        }

        return true
    }

    private func set(_ argument: ContentTransition.EffectType.Arg, atIndex index: UInt) {
        switch argument {
        case let .float(value):
            setArgumentValue(value, atIndex: index)
        case let .int(value):
            setIntegerArgumentValue(value, atIndex: index)
        case .none:
            break
        }
    }

    private func applyScale(
        to results: inout RBTransitionEffectResults,
        bounds: CGRect,
        progress: Float,
        event: UInt32,
        isFlipped: Bool
    ) {
        var baseScale = CGFloat(argumentValue(atIndex: 0))
        if shouldInvertDirection(for: event, isFlipped: isFlipped),
           baseScale.magnitude > .ulpOfOne {
            baseScale = 1 / baseScale
        }

        let minimum = 1 - baseScale
        let scale = max(baseScale + minimum * CGFloat(progress), minimum)
        let anchor = CGPoint(x: bounds.maxX, y: bounds.maxY)
        let transform = CGAffineTransform(
            a: scale,
            b: 0,
            c: 0,
            d: scale,
            tx: anchor.x * (1 - scale),
            ty: anchor.y * (1 - scale)
        )
        compose(transform, into: &results)
        if results.hasBlur {
            results.blurRadius *= scale.magnitude
        }
    }

    private func applyTranslation(
        _ vector: CGSize,
        to results: inout RBTransitionEffectResults,
        progress: Float,
        event: UInt32,
        isFlipped: Bool
    ) {
        let sign: CGFloat = shouldInvertDirection(
            for: event,
            isFlipped: isFlipped
        ) ? -1 : 1
        let scale = CGFloat(1 - progress)
        let transform = CGAffineTransform(
            translationX: vector.width * sign * scale,
            y: vector.height * sign * scale
        )
        compose(transform, into: &results)
    }

    private func applyBlur(
        _ radius: CGFloat,
        to results: inout RBTransitionEffectResults,
        progress: Float
    ) {
        guard radius > 0 else { return }
        let radius = max(radius * CGFloat(1 - progress), 0)
        if results.hasBlur {
            results.blurRadius = sqrt(results.blurRadius * results.blurRadius + radius * radius)
        } else {
            results.blurRadius = radius
            results.hasBlur = true
        }
    }

    private func compose(
        _ transform: CGAffineTransform,
        into results: inout RBTransitionEffectResults
    ) {
        results.transform = transform.concatenating(results.transform)
        if let bounds = results.bounds {
            results.bounds = bounds.applying(transform).standardized
        }
    }

    private func shouldInvertDirection(for event: UInt32, isFlipped: Bool) -> Bool {
        let automaticFlip = isFlipped && flags & 2 != 0
        let removalFlip = event & 2 != 0 && flags & 1 != 0
        return automaticFlip != removalFlip
    }

    private func resolvedDirection(
        _ direction: UInt32,
        event: UInt32,
        isFlipped: Bool
    ) -> UInt32 {
        guard shouldFlipDirection(event: event, isFlipped: isFlipped),
              direction < Self.flippedDirections.count else {
            return direction
        }
        return Self.flippedDirections[Int(direction)]
    }

    private func shouldFlipDirection(event: UInt32, isFlipped: Bool) -> Bool {
        let layoutFlip = isFlipped && (flags & 2) != 0
        let removalFlip = event & 2 != 0 && (flags & 1) != 0
        return layoutFlip != removalFlip
    }

    func copy(with zone: NSZone? = nil) -> Any {
        RBTransitionEffect(
            type: type,
            beginTimeByte: beginTimeByte,
            durationByte: durationByte,
            usesAnimationIndexMode: usesAnimationIndexMode,
            events: events,
            flags: flags,
            argumentWords: argumentWords
        )
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? RBTransitionEffect else {
            return false
        }
        return type == other.type &&
            beginTimeByte == other.beginTimeByte &&
            durationByte == other.durationByte &&
            usesAnimationIndexMode == other.usesAnimationIndexMode &&
            events == other.events &&
            flags == other.flags &&
            argumentWords.prefix(argumentCount) == other.argumentWords.prefix(other.argumentCount)
    }

    override var hash: Int {
        var hasher = Hasher()
        hasher.combine(type)
        hasher.combine(beginTimeByte)
        hasher.combine(durationByte)
        hasher.combine(usesAnimationIndexMode)
        hasher.combine(events)
        hasher.combine(flags)
        for word in argumentWords.prefix(argumentCount) {
            hasher.combine(word)
        }
        return hasher.finalize()
    }
}

// RenderBox-style transition carrier built from ContentTransition and consumed by
// RBDisplayListInterpolator.
final class RBTransition: NSObject, NSCopying {
    private static let blurBoundsExpansionScale: CGFloat = 2.8

    var method: Int32
    var maxChanges: UInt32
    var isReplaceable: Bool
    var addRemoveDuration: Float {
        get { Float(addRemoveDurationByte) / 255 }
        set { addRemoveDurationByte = Self.timingByte(newValue) }
    }
    var animation: RBAnimation?
    private(set) var effects: [RBTransitionEffect]
    private var addRemoveDurationByte: UInt8

    override init() {
        self.method = ContentTransition.Method.diff.method
        self.maxChanges = UInt32.max
        self.isReplaceable = false
        self.addRemoveDurationByte = 32
        self.animation = nil
        self.effects = []
        super.init()
    }

    private init(
        method: Int32,
        maxChanges: UInt32,
        isReplaceable: Bool,
        addRemoveDurationByte: UInt8,
        animation: RBAnimation?,
        effects: [RBTransitionEffect]
    ) {
        self.method = method
        self.maxChanges = maxChanges
        self.isReplaceable = isReplaceable
        self.addRemoveDurationByte = addRemoveDurationByte
        self.animation = animation
        self.effects = effects
        super.init()
    }

    private static func timingByte(_ value: Float) -> UInt8 {
        let clamped = min(max(value, 0), 1)
        return UInt8((clamped * 255 + 0.5).rounded(.towardZero))
    }

    func addEffect(_ effect: RBTransitionEffect) {
        effects.append(effect)
    }

    func isEmpty(for event: UInt32) -> Bool {
        let requestedEvents = event & 0x3f
        guard requestedEvents != 0 else { return true }
        return !effects.contains { ($0.events & requestedEvents) != 0 }
    }

    var symbolReplacementConfiguration: RBSymbolReplacementConfiguration? {
        guard let effect = effects.first(where: { $0.semanticType == 18 }) else {
            return nil
        }
        let flags = effect.integerArgumentValue(atIndex: 0)
        let style: RBSymbolReplacementConfiguration.Style
        switch flags & 0xf {
        case 0, 2:
            style = .downUp
        case 3:
            style = .upUp
        case 4:
            style = .offUp
        default:
            return nil
        }
        guard let duration = effect.customDuration(for: 1),
              duration.isFinite,
              duration > 0 else {
            return nil
        }
        return RBSymbolReplacementConfiguration(
            style: style,
            isLayered: flags & 0x10 != 0,
            isAutomaticStyle: flags & 0xf == 0,
            duration: Double(duration)
        )
    }

    func effectResults(
        at progress: Float,
        event: UInt32,
        bounds: CGRect,
        isFlipped: Bool = false,
        usesAddRemoveDurationFallback: Bool = false,
        animationContext: RBTransitionAnimationContext? = nil
    ) -> RBTransitionEffectResults? {
        var results = RBTransitionEffectResults()
        results.bounds = bounds.standardized
        for effect in effects {
            guard effect.apply(
                to: &results,
                bounds: bounds,
                progress: progress,
                event: event,
                transition: self,
                isFlipped: isFlipped || animationContext?.isFlipped == true,
                usesAddRemoveDurationFallback: usesAddRemoveDurationFallback,
                animationContext: animationContext
            ) else {
                return nil
            }
        }
        if results.alpha <= 0 {
            results.bounds = .zero
        } else if results.hasBlur, let bounds = results.bounds {
            results.bounds = Self.expandedBlurBounds(
                bounds,
                radius: results.blurRadius,
                alpha: results.alpha
            )
        }
        return results
    }

    private static func expandedBlurBounds(
        _ bounds: CGRect,
        radius: CGFloat,
        alpha: Float
    ) -> CGRect {
        let alphaFactor = CGFloat(sqrt(Double(max(alpha, 0))))
        let expansion = radius * blurBoundsExpansionScale * alphaFactor
        guard expansion.isFinite, expansion > 0 else {
            return bounds
        }
        return bounds.insetBy(dx: -expansion, dy: -expansion).standardized
    }

    func copy(with zone: NSZone? = nil) -> Any {
        RBTransition(
            method: method,
            maxChanges: maxChanges,
            isReplaceable: isReplaceable,
            addRemoveDurationByte: addRemoveDurationByte,
            animation: animation?.copy() as? RBAnimation,
            effects: effects.map { $0.copy() as! RBTransitionEffect }
        )
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? RBTransition else {
            return false
        }
        return method == other.method &&
            maxChanges == other.maxChanges &&
            isReplaceable == other.isReplaceable &&
            addRemoveDurationByte == other.addRemoveDurationByte &&
            effects == other.effects &&
            animation == other.animation
    }

    override var hash: Int {
        var hasher = Hasher()
        hasher.combine(method)
        hasher.combine(maxChanges)
        hasher.combine(isReplaceable)
        hasher.combine(addRemoveDurationByte)
        hasher.combine(animation)
        for effect in effects {
            hasher.combine(effect)
        }
        return hasher.finalize()
    }
}
