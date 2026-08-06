//
//  File: ScrollPhase.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

/// User-visible phase of a scroll interaction.
public enum ScrollPhase: Hashable, CustomDebugStringConvertible, Sendable {
    case idle
    case tracking
    case interacting
    case decelerating
    case animating

    public var isScrolling: Bool {
        self != .idle
    }

    public var debugDescription: String {
        switch self {
        case .idle:
            return "idle"
        case .tracking:
            return "tracking"
        case .interacting:
            return "interacting"
        case .decelerating:
            return "decelerating"
        case .animating:
            return "animating"
        }
    }
}

/// Internal scroll phase value plus the velocity sampled for phase callbacks.
struct ScrollPhaseState: Equatable, CustomStringConvertible {
    var phase: ScrollPhase
    var velocity: CGVector

    init(phase: ScrollPhase = .idle, velocity: CGVector = .zero) {
        self.phase = phase
        self.velocity = velocity
    }

    var isScrolling: Bool {
        phase.isScrolling
    }

    var isTracking: Bool {
        phase == .tracking
    }

    var isInteracting: Bool {
        phase == .interacting
    }

    var isDecelerating: Bool {
        phase == .decelerating
    }

    var isAnimating: Bool {
        phase == .animating
    }

    var shouldUpdateValue: Bool {
        switch phase {
        case .tracking, .interacting, .decelerating:
            return true
        case .idle, .animating:
            return false
        }
    }

    var description: String {
        "ScrollPhaseState(phase: \(phase.debugDescription), velocity: \(velocity))"
    }
}

extension _GraphInputs {
    var scrollPhaseState: OptionalAttribute<ScrollPhaseState> {
        top(ScrollPhaseStateKey.self) ?? OptionalAttribute()
    }

    var scrollPhaseStates: Stack<OptionalAttribute<ScrollPhaseState>> {
        get { self[ScrollPhaseStateKey.self] }
        set { self[ScrollPhaseStateKey.self] = newValue }
    }

    mutating func appendScrollPhaseState(_ state: OptionalAttribute<ScrollPhaseState>) {
        append(state, to: ScrollPhaseStateKey.self)
    }
}

/// Graph input stack that carries active scroll phase states through descendants.
private struct ScrollPhaseStateKey: GraphInput {
    static var defaultValue: Stack<OptionalAttribute<ScrollPhaseState>> {
        .empty
    }

    static func valuesEqual(
        _ a: Stack<OptionalAttribute<ScrollPhaseState>>,
        _ b: Stack<OptionalAttribute<ScrollPhaseState>>
    ) -> Bool {
        var lhs = a
        var rhs = b
        while true {
            switch (lhs.pop(), rhs.pop()) {
            case (nil, nil):
                return true
            case let (left?, right?):
                guard left.base.identifier == right.base.identifier else {
                    return false
                }
            default:
                return false
            }
        }
    }
}
