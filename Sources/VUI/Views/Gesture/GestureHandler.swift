//
//  File: GestureHandler.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

// GestureRecognizerState

/// State machine for gesture recognizers.
enum GestureRecognizerState {
    case ready        // waiting for first event
    case processing   // event(s) received, recognition in progress
    case cancelled    // interaction was cancelled
    case failed       // recognition failed (wrong gesture type, timeout, etc.)
    case done         // recognition succeeded, callbacks fired
}

// _GestureHandler (Phase 3 replacement target)

/// Legacy base class kept for Menu/ContextMenu gesture handlers.
/// Will be replaced when MenuDropdownModifier and ContextMenu are rewritten for AG.
class _GestureHandler {
    enum State { case ready, processing, done, failed, cancelled }

    var state: State = .ready
    var type: _PrimitiveGestureTypes { [] }
    var isValid: Bool { true }

    init<G: Gesture>(graph: _GraphValue<G>, target: Any?) {}

    func setTypeFilter(_ f: _PrimitiveGestureTypes) -> _PrimitiveGestureTypes { f }
    func locationInView(_ location: CGPoint) -> CGPoint { location }
    func began(deviceID: Int, buttonID: Int, location: CGPoint) {}
    func moved(deviceID: Int, buttonID: Int, location: CGPoint) {}
    func ended(deviceID: Int, buttonID: Int) {}
    func cancelled(deviceID: Int, buttonID: Int) {}
    func reset() { state = .ready }
}

// _GestureRecognizer

/// Base class for all concrete gesture recognizers.
/// Subclasses process raw events from `_GestureInputs.events` and update
/// the `phaseAttribute` source-of-truth node in the AG graph.
class _GestureRecognizer<Value> {
    var state: GestureRecognizerState = .ready

    /// The AG attribute that holds the current gesture phase.
    /// Set by the concrete `_makeGesture` implementation; updated here as state changes.
    var phaseAttribute: Attribute<GesturePhase<Value>>?

    var isPossible: Bool { state == .ready || state == .processing }

    /// Override to handle new events. Called from the AG rule that reads `inputs.events`.
    func processEvents(_ events: [EventID: any EventType]) {
    }

    /// Signals that the recognizer should reset to `.ready`.
    func reset() {
        state = .ready
    }

    func updatePhase(_ phase: GesturePhase<Value>) {
        phaseAttribute?.setValue(phase)
    }
}
