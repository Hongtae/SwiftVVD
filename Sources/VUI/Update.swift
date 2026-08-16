//
//  File: Update.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import Synchronization
import VVD

// Update scheduler used to batch graph and event side effects and drain them
// after the outermost update pass on the current host lane.
enum Update {
    fileprivate struct Action {
        let reason: CustomEventTrace.ActionEventType.Reason?
        let thunk: () -> Void
        let id: UInt32

        init(reason: CustomEventTrace.ActionEventType.Reason?, thunk: @escaping () -> Void) {
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

    fileprivate final class State: @unchecked Sendable {
        var lockDepth = 0
        var depth = 0
        var dispatchDepth = 0
        var actions: [Action] = []
    }

    /// A root window and every window in its presentation tree must share one
    /// scheduling context.
    ///
    /// A platform presentation window owns an independent frame task, but its
    /// graph work is not independent: popup and modal graphs can read from or
    /// tear down state in the presenting graph. Sharing only an action mailbox
    /// is therefore insufficient. The recursive lock serializes the complete
    /// frame, including drawing, while `State` keeps nested updates and queued
    /// actions on the same logical host lane.
    ///
    /// Every independent root must own a distinct context. Sharing one across
    /// unrelated roots would unnecessarily serialize otherwise independent UI.
    /// A presentation child must retain its inherited context through teardown;
    /// its final frame can overlap the operation that detaches it from its parent.
    final class HostContext: @unchecked Sendable {
        fileprivate let lock = NSRecursiveLock()
        fileprivate let state = State()
    }

    private final class ThreadStateKey: @unchecked Sendable {}
    private final class HostContextKey: @unchecked Sendable {}

    private static let threadStateKey = ThreadStateKey()
    private static let hostContextKey = HostContextKey()

    private static var threadStateKeyPointer: UnsafeRawPointer {
        UnsafeRawPointer(Unmanaged.passUnretained(threadStateKey).toOpaque())
    }

    private static var hostContextKeyPointer: UnsafeRawPointer {
        UnsafeRawPointer(Unmanaged.passUnretained(hostContextKey).toOpaque())
    }

    private static var currentHostContext: HostContext? {
        guard let pointer = ThreadLocalStorage.get(hostContextKeyPointer) else {
            return nil
        }
        return Unmanaged<HostContext>.fromOpaque(pointer).takeUnretainedValue()
    }

    private static var currentThreadState: State? {
        guard let pointer = ThreadLocalStorage.get(threadStateKeyPointer) else {
            return nil
        }
        return Unmanaged<State>.fromOpaque(pointer).takeUnretainedValue()
    }

    private static var currentState: State? {
        currentHostContext?.state ?? currentThreadState
    }

    private static func makeState() -> State {
        precondition(currentHostContext == nil)
        precondition(currentThreadState == nil)
        let state = State()
        ThreadLocalStorage.set(
            threadStateKeyPointer,
            Unmanaged.passRetained(state).toOpaque()
        )
        return state
    }

    static func withHostContext<Result>(
        _ context: HostContext,
        _ body: () throws -> Result
    ) rethrows -> Result {
        if let currentHostContext {
            precondition(
                currentHostContext === context,
                "Nested window updates must use the same Update.HostContext."
            )
            return try body()
        }
        precondition(
            currentThreadState == nil,
            "A host update context cannot replace an active thread-local Update state."
        )

        ThreadLocalStorage.set(
            hostContextKeyPointer,
            Unmanaged.passUnretained(context).toOpaque()
        )
        defer { ThreadLocalStorage.set(hostContextKeyPointer, nil) }
        return try withExtendedLifetime(context, body)
    }

    private static var isOwner: Bool {
        currentState?.lockDepth ?? 0 > 0
    }

    private static func lock() {
        if let context = currentHostContext {
            context.lock.lock()
            context.state.lockDepth += 1
            return
        }
        let state = currentThreadState ?? makeState()
        state.lockDepth += 1
    }

    private static func unlock() {
        if let context = currentHostContext {
            let state = context.state
            precondition(state.lockDepth > 0, "Update.unlock() called without a matching Update.lock().")
            state.lockDepth -= 1
            if state.lockDepth == 0 {
                precondition(state.depth == 0, "Update state released while an update is active.")
                precondition(state.actions.isEmpty, "Update state released with queued actions.")
            }
            context.lock.unlock()
            return
        }

        guard let state = currentThreadState else {
            preconditionFailure("Update.unlock() called without a matching Update.lock().")
        }
        precondition(state.lockDepth > 0, "Update.unlock() called without a matching Update.lock().")
        state.lockDepth -= 1
        if state.lockDepth == 0 {
            precondition(state.depth == 0, "Update state released while an update is active.")
            precondition(state.actions.isEmpty, "Update state released with queued actions.")
            guard let pointer = ThreadLocalStorage.get(threadStateKeyPointer) else {
                preconditionFailure("Update thread state disappeared before final unlock.")
            }
            ThreadLocalStorage.set(threadStateKeyPointer, nil)
            Unmanaged<State>.fromOpaque(pointer).release()
        }
    }

    static func locked<Result>(_ body: () throws -> Result) rethrows -> Result {
        lock()
        defer { unlock() }
        return try body()
    }

    static var threadIsUpdating: Bool {
        guard let state = currentState else { return false }
        return isOwner && state.dispatchDepth < state.depth
    }

    static var isActive: Bool {
        currentState?.depth ?? 0 > 0
    }

    static var canDispatch: Bool {
        guard let state = currentState else { return false }
        return isOwner && state.depth == 1 && !state.actions.isEmpty
    }

    static var queuedActionReasons: [CustomEventTrace.ActionEventType.Reason?] {
        lock()
        defer { unlock() }
        return currentState!.actions.map(\.reason)
    }

    static func begin() {
        lock()
        currentState!.depth += 1
    }

    static func end() {
        guard let state = currentState else {
            preconditionFailure("Update.end() called without a matching Update.begin().")
        }
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
    static func enqueueAction(
        reason: CustomEventTrace.ActionEventType.Reason? = nil,
        _ action: @escaping () -> Void
    ) -> UInt32 {
        begin()
        defer { end() }
        let queuedAction = Action(reason: reason, thunk: action)
        currentState!.actions.append(queuedAction)
        return queuedAction.id
    }

    static func dispatchImmediately<Result>(
        reason: CustomEventTrace.ActionEventType.Reason? = nil,
        _ body: () throws -> Result
    ) rethrows -> Result {
        begin()
        let state = currentState!
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
        guard let state = currentState else { return }
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
        guard let host = _AGGraphContext.current?.context as? GraphHost else {
            return 0
        }
        return host.data.updateSeed
    }
}
