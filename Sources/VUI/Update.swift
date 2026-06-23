//
//  File: Update.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

enum Update {
    private struct Action {
        let reason: UInt32?
        let thunk: () -> Void
        let id: UInt32

        func callAsFunction() {
            thunk()
        }
    }

    private final class State: @unchecked Sendable {
        let lock = NSRecursiveLock()
        var lockDepth = 0
        var owner: Thread?
        var depth = 0
        var dispatchDepth = 0
        var actions: [Action] = []
        var nextActionID: UInt32 = 0
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
        let queuedAction = Action(reason: reason, thunk: action, id: nextActionID())
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

    private static func nextActionID() -> UInt32 {
        let currentID = state.nextActionID &>> 1
        state.nextActionID &+= 2
        return currentID &+ 1
    }
}
