//
//  File: LongPressGesture.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import VVD

public struct LongPressGesture: Gesture {
    public var minimumDuration: Double
    public var maximumDistance: CGFloat {
        get { _maximumDistance }
        set { _maximumDistance = newValue }
    }

    var _maximumDistance: CGFloat

    public init(minimumDuration: Double = 0.5, maximumDistance: CGFloat = 10) {
        self.minimumDuration = minimumDuration
        self._maximumDistance = maximumDistance
    }

    public static func _makeGesture(gesture: _GraphValue<Self>, inputs: _GestureInputs) -> _GestureOutputs<Value> {
        guard let graph = AttributeGraph.current else {
            fatalError("LongPressGesture._makeGesture requires AG context")
        }

        let minimumDuration = gesture._attribute.value.minimumDuration
        let maximumDistance = gesture._attribute.value._maximumDistance
        let recognizer = LongPressGestureRecognizer(
            minimumDuration: minimumDuration, maximumDistance: maximumDistance)

        let phase: Attribute<GesturePhase<Bool>> = graph.makeInput(value: .possible(nil))
        recognizer.phaseAttribute = phase

        let eventsAttr = inputs.events
        let resetSeedAttr = inputs.resetSeed
        var lastResetSeed: UInt32 = 0

        graph.makeSideEffectRule { () -> Void in
            let events = eventsAttr.value
            let currentSeed = resetSeedAttr.value
            if currentSeed != lastResetSeed {
                lastResetSeed = currentSeed
                recognizer.reset()
            }
            recognizer.processEvents(events)
        }

        return _GestureOutputs(phase: phase)
    }

    public typealias Value = Bool
    public typealias Body = Never
}

extension View {
    public func onLongPressGesture(
        minimumDuration: Double = 0.5,
        maximumDistance: CGFloat = 10,
        perform action: @escaping () -> Void,
        onPressingChanged: ((Bool) -> Void)? = nil
    ) -> some View {
        self.gesture(
            ModifierGesture(
                modifier: CallbacksGesture(
                    callbacks: PressableGestureCallbacks(pressing: onPressingChanged,
                                                         pressed: action)
                ),
                body: LongPressGesture(minimumDuration: minimumDuration,
                                       maximumDistance: maximumDistance)
            )
        )
    }
}

// LongPressGestureRecognizer

final class LongPressGestureRecognizer: _GestureRecognizer<Bool>, @unchecked Sendable {
    let minimumDuration: Double
    let maximumDistance: CGFloat

    private var activeSerial: Int? = nil
    private var startLocation: CGPoint = .zero
    private var pressTask: Task<Void, Never>? = nil
    private var processedBeganSerials: Set<Int> = []

    init(minimumDuration: Double, maximumDistance: CGFloat) {
        self.minimumDuration = minimumDuration
        self.maximumDistance = maximumDistance
    }

    override func processEvents(_ events: [EventID: any EventType]) {
        guard let graph = AttributeGraph.current else {
            fatalError("LongPressGestureRecognizer.processEvents requires AG context")
        }
        let inbox = graph.inbox
        for (id, event) in events {
            guard let tap = event as? TappableEvent else { continue }

            switch tap.phase {
            case .began:
                guard !processedBeganSerials.contains(id.serial) else { continue }
                processedBeganSerials.insert(id.serial)
                if activeSerial == nil {
                    activeSerial = id.serial
                    startLocation = tap.location
                    state = .processing
                    updatePhase(.active(false))

                    let duration = minimumDuration
                    pressTask = Task { @MainActor [weak self] in
                        try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
                        guard !Task.isCancelled else { return }

                        inbox.enqueue { [weak self] in
                            guard let self else { return }
                            self.state = .done
                            self.activeSerial = nil
                            self.updatePhase(.ended(true))
                        }
                    }
                }

            case .moved:
                if activeSerial == id.serial {
                    let dist = (tap.location - startLocation).magnitude
                    if dist > maximumDistance {
                        pressTask?.cancel()
                        pressTask = nil
                        activeSerial = nil
                        state = .failed
                        updatePhase(.failed)
                    }
                }

            case .ended:
                if activeSerial == id.serial {
                    pressTask?.cancel()
                    pressTask = nil
                    activeSerial = nil
                    state = .failed
                    updatePhase(.failed)
                }

            case .cancelled:
                if activeSerial == id.serial {
                    pressTask?.cancel()
                    pressTask = nil
                    activeSerial = nil
                    state = .failed
                    updatePhase(.failed)
                }
            }
        }
    }

    override func reset() {
        pressTask?.cancel()
        pressTask = nil
        activeSerial = nil
        processedBeganSerials.removeAll()
        super.reset()
        updatePhase(.possible(nil))
    }
}
