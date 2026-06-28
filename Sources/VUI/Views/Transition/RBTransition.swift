//
//  File: RBTransition.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

// Single render effect entry used by RBTransition to describe opacity, transform, blur, and
// other content-transition operations.
final class RBTransitionEffect: NSObject, NSCopying {
    // Effect arguments can be stored as either float or integer payloads depending on type.
    enum Argument: Equatable {
        case float(Float)
        case integer(UInt32)
    }

    var type: Int32
    var beginTime: Float
    var duration: Float
    var events: UInt32
    var flags: UInt32
    var animationIndex: UInt
    var insertAnimationIndex: UInt
    var removeAnimationIndex: UInt

    private var arguments: [UInt: Argument]

    override init() {
        self.type = 0
        self.beginTime = 0
        self.duration = 0
        self.events = 0
        self.flags = 0
        self.animationIndex = 0
        self.insertAnimationIndex = 0
        self.removeAnimationIndex = 0
        self.arguments = [:]
        super.init()
    }

    init(_ effect: ContentTransition.Effect) {
        self.type = effect.type.type
        self.beginTime = effect.begin
        self.duration = effect.duration
        self.events = effect.events
        self.flags = effect.flags
        self.animationIndex = 0
        self.insertAnimationIndex = 0
        self.removeAnimationIndex = 0
        self.arguments = [:]
        super.init()

        set(effect.type.arg0, atIndex: 0)
        set(effect.type.arg1, atIndex: 1)
    }

    private init(
        type: Int32,
        beginTime: Float,
        duration: Float,
        events: UInt32,
        flags: UInt32,
        animationIndex: UInt,
        insertAnimationIndex: UInt,
        removeAnimationIndex: UInt,
        arguments: [UInt: Argument]
    ) {
        self.type = type
        self.beginTime = beginTime
        self.duration = duration
        self.events = events
        self.flags = flags
        self.animationIndex = animationIndex
        self.insertAnimationIndex = insertAnimationIndex
        self.removeAnimationIndex = removeAnimationIndex
        self.arguments = arguments
        super.init()
    }

    func setArgumentValue(_ value: Float, atIndex index: UInt) {
        arguments[index] = .float(value)
    }

    func argumentValue(atIndex index: UInt) -> Float {
        switch arguments[index] {
        case let .float(value):
            return value
        case let .integer(value):
            return Float(value)
        case .none:
            return 0
        }
    }

    func setIntegerArgumentValue(_ value: UInt32, atIndex index: UInt) {
        arguments[index] = .integer(value)
    }

    func integerArgumentValue(atIndex index: UInt) -> UInt32 {
        switch arguments[index] {
        case let .integer(value):
            return value
        case let .float(value):
            return UInt32(value)
        case .none:
            return 0
        }
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

    func copy(with zone: NSZone? = nil) -> Any {
        RBTransitionEffect(
            type: type,
            beginTime: beginTime,
            duration: duration,
            events: events,
            flags: flags,
            animationIndex: animationIndex,
            insertAnimationIndex: insertAnimationIndex,
            removeAnimationIndex: removeAnimationIndex,
            arguments: arguments
        )
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? RBTransitionEffect else {
            return false
        }
        return type == other.type &&
            beginTime == other.beginTime &&
            duration == other.duration &&
            events == other.events &&
            flags == other.flags &&
            animationIndex == other.animationIndex &&
            insertAnimationIndex == other.insertAnimationIndex &&
            removeAnimationIndex == other.removeAnimationIndex &&
            arguments == other.arguments
    }

    override var hash: Int {
        var hasher = Hasher()
        hasher.combine(type)
        hasher.combine(beginTime)
        hasher.combine(duration)
        hasher.combine(events)
        hasher.combine(flags)
        hasher.combine(animationIndex)
        hasher.combine(insertAnimationIndex)
        hasher.combine(removeAnimationIndex)
        for key in arguments.keys.sorted() {
            hasher.combine(key)
            switch arguments[key] {
            case let .float(value):
                hasher.combine(0 as UInt8)
                hasher.combine(value)
            case let .integer(value):
                hasher.combine(1 as UInt8)
                hasher.combine(value)
            case .none:
                break
            }
        }
        return hasher.finalize()
    }
}

// RenderBox-style transition carrier built from ContentTransition and consumed by
// RBDisplayListInterpolator.
final class RBTransition: NSObject, NSCopying {
    var method: Int32
    var maxChanges: UInt32
    var isReplaceable: Bool
    var addRemoveDuration: Float
    var animation: Animation?
    private(set) var effects: [RBTransitionEffect]

    override init() {
        self.method = ContentTransition.Method.diff.method
        self.maxChanges = UInt32.max
        self.isReplaceable = false
        self.addRemoveDuration = 0.1254902
        self.animation = nil
        self.effects = []
        super.init()
    }

    private init(
        method: Int32,
        maxChanges: UInt32,
        isReplaceable: Bool,
        addRemoveDuration: Float,
        animation: Animation?,
        effects: [RBTransitionEffect]
    ) {
        self.method = method
        self.maxChanges = maxChanges
        self.isReplaceable = isReplaceable
        self.addRemoveDuration = addRemoveDuration
        self.animation = animation
        self.effects = effects
        super.init()
    }

    func addEffect(_ effect: RBTransitionEffect) {
        effects.append(effect)
    }

    func copy(with zone: NSZone? = nil) -> Any {
        RBTransition(
            method: method,
            maxChanges: maxChanges,
            isReplaceable: isReplaceable,
            addRemoveDuration: addRemoveDuration,
            animation: animation,
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
            addRemoveDuration == other.addRemoveDuration &&
            effects == other.effects &&
            ((animation == nil && other.animation == nil) || (animation != nil && other.animation != nil))
    }

    override var hash: Int {
        var hasher = Hasher()
        hasher.combine(method)
        hasher.combine(maxChanges)
        hasher.combine(isReplaceable)
        hasher.combine(addRemoveDuration)
        hasher.combine(animation != nil)
        for effect in effects {
            hasher.combine(effect)
        }
        return hasher.finalize()
    }
}
