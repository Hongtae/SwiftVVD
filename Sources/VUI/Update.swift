//
//  File: Update.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import Synchronization

// Global update scheduler used to batch graph/event side effects and drain them
// after the outermost update pass.
enum Update {
    private struct Action {
        let reason: UInt32?
        let thunk: () -> Void
        let id: UInt32

        init(reason: UInt32?, thunk: @escaping () -> Void) {
            self.reason = reason
            self.thunk = thunk
            self.id = Self.nextID()
        }

        func callAsFunction() {
            thunk()
        }

        private static let nextActionID = Atomic<UInt32>(0)

        static func nextID() -> UInt32 {
            let rawID = nextActionID.wrappingAdd(2, ordering: .relaxed).oldValue
            return (rawID &>> 1) &+ 1
        }
    }

    private final class State: @unchecked Sendable {
        let lock = NSRecursiveLock()
        var lockDepth = 0
        var owner: Thread?
        var depth = 0
        var dispatchDepth = 0
        var actions: [Action] = []
    }

    private static let state = State()

    private static var isOwner: Bool {
        state.owner === Thread.current
    }

    private static func lock() {
        state.lock.lock()
        if state.lockDepth == 0 {
            state.owner = Thread.current
        }
        state.lockDepth += 1
    }

    private static func unlock() {
        precondition(state.lockDepth > 0, "Update.unlock() called without a matching Update.lock().")
        state.lockDepth -= 1
        if state.lockDepth == 0 {
            state.owner = nil
        }
        state.lock.unlock()
    }

    static func withLock<Result>(_ body: () throws -> Result) rethrows -> Result {
        lock()
        defer { unlock() }
        return try body()
    }

    static var threadIsUpdating: Bool {
        isOwner && state.dispatchDepth < state.depth
    }

    static var isActive: Bool {
        state.depth > 0
    }

    static var canDispatch: Bool {
        isOwner && state.depth == 1 && !state.actions.isEmpty
    }

    static var queuedActionReasons: [UInt32?] {
        lock()
        defer { unlock() }
        return state.actions.map(\.reason)
    }

    static func begin() {
        lock()
        state.depth += 1
    }

    static func end() {
        precondition(state.depth > 0, "Update.end() called without a matching Update.begin().")
        if state.depth == 1 {
            dispatchActions()
        }
        state.depth -= 1
        unlock()
    }

    static func ensure<Result>(_ body: () throws -> Result) rethrows -> Result {
        begin()
        defer { end() }
        return try body()
    }

    @discardableResult
    static func enqueueAction(reason: UInt32? = nil, _ action: @escaping () -> Void) -> UInt32 {
        begin()
        defer { end() }
        let queuedAction = Action(reason: reason, thunk: action)
        state.actions.append(queuedAction)
        return queuedAction.id
    }

    static func dispatchImmediately<Result>(
        reason: UInt32? = nil,
        _ body: () throws -> Result
    ) rethrows -> Result {
        begin()
        let previousDispatchDepth = state.dispatchDepth
        state.dispatchDepth = state.depth
        _ = Action.nextID()
        defer {
            state.dispatchDepth = previousDispatchDepth
            end()
        }
        return try body()
    }

    static func dispatchActions() {
        guard state.depth == 1 else { return }
        while canDispatch {
            let actions = state.actions
            state.actions.removeAll()

            begin()
            let previousDispatchDepth = state.dispatchDepth
            state.dispatchDepth = state.depth
            for action in actions {
                action()
            }
            state.dispatchDepth = previousDispatchDepth
            end()
        }
    }

}

/// Limits repeated action dispatches within the same graph update seed.
struct UpdateCycleDetector {
    private var seed: UInt32
    private var lastSeed: UInt32
    private var remainingPasses: UInt32
    private var didWarn: Bool

    init() {
        seed = Self.currentSeed()
        lastSeed = .max
        remainingPasses = 0
        didWarn = false
    }

    mutating func reset() {
        lastSeed = .max
        remainingPasses = 0
        didWarn = false
    }

    mutating func dispatch(label: @autoclosure () -> String, isDebug: Bool = false) -> Bool {
        let current = Self.currentSeed()
        seed = current

        if lastSeed == current {
            guard remainingPasses > 0 else {
                warnIfNeeded(label: label(), isDebug: isDebug)
                return false
            }

            remainingPasses -= 1
            guard remainingPasses > 0 else {
                warnIfNeeded(label: label(), isDebug: isDebug)
                return false
            }
            return true
        }

        lastSeed = current
        remainingPasses = 2
        return true
    }

    private mutating func warnIfNeeded(label: String, isDebug: Bool) {
        guard !didWarn else { return }
        didWarn = true
        if !isDebug {
            Log.warning("action tried to update multiple times per frame: \(label)")
        }
    }

    private static func currentSeed() -> UInt32 {
        guard let host = AttributeGraphRef.current?.context as? GraphHost else {
            return 0
        }
        return host.data.updateSeed
    }
}
