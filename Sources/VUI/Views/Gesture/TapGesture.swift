//
//  File: TapGesture.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

// TapGesture

public struct TapGesture: Gesture {
    public var count: Int
    public init(count: Int = 1) {
        self.count = count
    }

    public static func _makeGesture(gesture: _GraphValue<TapGesture>, inputs: _GestureInputs) -> _GestureOutputs<Value> {
        guard let graph = AttributeGraph.current else {
            fatalError("TapGesture._makeGesture requires AG context")
        }

        let tapCount = gesture._attribute.value.count
        let recognizer = TapGestureRecognizer(
            requiredCount: tapCount,
            position: inputs.position,
            size: inputs.size)

        // Create the phase source-of-truth attribute
        let phase: Attribute<GesturePhase<Void>> = graph.makeInput(value: .possible(nil))
        recognizer.phaseAttribute = phase

        // Create an AG rule that reads the events attribute and feeds them to the recognizer.
        // Whenever the events attribute changes, AG re-evaluates this rule automatically.
        let eventsAttr = inputs.events
        let resetSeedAttr = inputs.resetSeed
        var lastResetSeed: UInt32 = 0

        graph.makeSideEffectRule { () -> Void in
            let events = eventsAttr.value          // establishes AG dependency on events
            let currentSeed = resetSeedAttr.value  // establishes dependency on reset seed

            if currentSeed != lastResetSeed {
                lastResetSeed = currentSeed
                recognizer.reset()
            }

            recognizer.processEvents(events)
        }

        return _GestureOutputs(phase: phase)
    }

    public typealias Body = Never
    public typealias Value = Void
}

extension View {
    public func onTapGesture(count: Int = 1, perform action: @escaping () -> Void) -> some View {
        self.gesture(TapGesture(count: count).onEnded(action), including: .all)
    }
}

// TapGestureRecognizer

final class TapGestureRecognizer: _GestureRecognizer<Void> {
    let requiredCount: Int

    // Per-interaction tracking
    private var activeDeviceID: Int? = nil
    private var completedTaps: Int = 0
    private var lastTapTime: ContinuousClock.Instant = .now
    private let clock = ContinuousClock()

    private let maximumInterval: ContinuousClock.Duration = .seconds(0.5)
    private let maximumPressDuration: ContinuousClock.Duration = .seconds(1.0)
    private var pressStart: ContinuousClock.Instant = .now

    // Track which event IDs we have already processed to avoid re-processing
    private var processedBeganIDs: Set<Int> = []
    private var processedEndedIDs: Set<Int> = []

    // View frame for hit testing (eventsAttr is broadcast to all recognizers)
    let position: Attribute<CGPoint>
    let size: Attribute<ViewSize>

    init(requiredCount: Int = 1, position: Attribute<CGPoint>, size: Attribute<ViewSize>) {
        self.requiredCount = requiredCount
        self.position = position
        self.size = size
    }

    private func viewFrame() -> CGRect {
        CGRect(origin: position.value, size: size.value.value)
    }

    override func processEvents(_ events: [EventID: any EventType]) {
        for (id, event) in events {
            guard let tap = event as? TappableEvent else { continue }

            switch tap.phase {
            case .began:
                guard !processedBeganIDs.contains(id.serial) else { continue }
                processedBeganIDs.insert(id.serial)

                if state == .ready {
                    // Only start if tap is within this view's frame.
                    // eventsAttr is shared among all gesture recognizers so each
                    // recognizer must do its own hit test to avoid firing globally.
                    guard viewFrame().contains(tap.location) else { continue }

                    // Check tap interval
                    let now = clock.now
                    let interval = lastTapTime.duration(to: now)
                    if completedTaps > 0 && interval > maximumInterval {
                        completedTaps = 0
                    }
                    activeDeviceID = id.serial
                    pressStart = now
                    state = .processing
                    updatePhase(.active(()))
                }

            case .moved:
                if state == .processing, activeDeviceID == id.serial {
                    let pressDuration = pressStart.duration(to: clock.now)
                    if pressDuration > maximumPressDuration {
                        state = .failed
                        processedBeganIDs.remove(id.serial)
                        processedEndedIDs.remove(id.serial)
                        activeDeviceID = nil
                        updatePhase(.failed)
                    }
                }

            case .ended:
                guard !processedEndedIDs.contains(id.serial) else { continue }
                processedEndedIDs.insert(id.serial)

                if state == .processing, activeDeviceID == id.serial {
                    let now = clock.now
                    let pressDuration = pressStart.duration(to: now)
                    if pressDuration > maximumPressDuration {
                        state = .failed
                        activeDeviceID = nil
                        updatePhase(.failed)
                    } else {
                        completedTaps += 1
                        lastTapTime = now
                        activeDeviceID = nil

                        if completedTaps >= requiredCount {
                            state = .done
                            completedTaps = 0
                            updatePhase(.ended(()))
                            // _EndedGesture callback has already fired synchronously above.
                            // Reset now so the recognizer accepts the next tap sequence.
                            reset()
                        } else {
                            state = .ready
                            updatePhase(.possible(nil))
                        }
                    }
                }

            case .cancelled:
                if activeDeviceID == id.serial {
                    activeDeviceID = nil
                    state = .failed
                    processedBeganIDs.remove(id.serial)
                    processedEndedIDs.remove(id.serial)
                    updatePhase(.failed)
                    reset()
                }
            }
        }
    }

    override func reset() {
        super.reset()
        activeDeviceID = nil
        completedTaps = 0
        processedBeganIDs.removeAll()
        processedEndedIDs.removeAll()
        updatePhase(.possible(nil))
    }
}
