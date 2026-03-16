//
//  File: DragGesture.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import VVD

public struct DragGesture: Gesture {
    public struct Value: Equatable {
        public var time: Date
        public var location: CGPoint
        public var startLocation: CGPoint

        var _velocity: _Velocity<CGSize>

        public var translation: CGSize {
            CGSize(width: location.x - startLocation.x,
                   height: location.y - startLocation.y)
        }

        public var velocity: CGSize {
            let predicted = predictedEndLocation
            return CGSize(
                width: 4.0 * (predicted.x - location.x),
                height: 4.0 * (predicted.y - location.y))
        }

        public var predictedEndLocation: CGPoint {
            let x = location.x + _velocity.valuePerSecond.width * 0.25
            let y = location.y + _velocity.valuePerSecond.height * 0.25
            return CGPoint(x: x, y: y)
        }

        public var predictedEndTranslation: CGSize {
            let loc = predictedEndLocation
            return CGSize(width: loc.x - startLocation.x,
                          height: loc.y - startLocation.y)
        }
    }

    public var minimumDistance: CGFloat
    public var coordinateSpace: CoordinateSpace

    public init(minimumDistance: CGFloat = 10, coordinateSpace: some CoordinateSpaceProtocol = .local) {
        self.minimumDistance = minimumDistance
        self.coordinateSpace = coordinateSpace.coordinateSpace
    }

    public static func _makeGesture(gesture: _GraphValue<DragGesture>, inputs: _GestureInputs) -> _GestureOutputs<DragGesture.Value> {
        guard let graph = AttributeGraph.current else {
            fatalError("DragGesture._makeGesture requires AG context")
        }

        let minimumDistance = gesture._attribute.value.minimumDistance
        let recognizer = DragGestureRecognizer(minimumDistance: minimumDistance)

        let phase: Attribute<GesturePhase<DragGesture.Value>> = graph.makeInput(value: .possible(nil))
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

    public typealias Body = Never
}

extension DragGesture.Value: Sendable {}

final class DragGestureRecognizer: _GestureRecognizer<DragGesture.Value> {
    let minimumDistance: CGFloat

    private var activeSerial: Int? = nil
    private var currentValue: DragGesture.Value = .init(
        time: .now, location: .zero, startLocation: .zero,
        _velocity: _Velocity(valuePerSecond: .zero))
    private var isDragging = false

    private var processedBeganSerials: Set<Int> = []

    init(minimumDistance: CGFloat = 10) {
        self.minimumDistance = minimumDistance
    }

    override func processEvents(_ events: [EventID: any EventType]) {
        for (id, event) in events {
            guard let tap = event as? TappableEvent,
                  id.type == TappableEvent.self else { continue }

            switch tap.phase {
            case .began:
                guard !processedBeganSerials.contains(id.serial) else { continue }
                processedBeganSerials.insert(id.serial)
                if activeSerial == nil {
                    activeSerial = id.serial
                    let now = Date.now
                    currentValue = DragGesture.Value(
                        time: now,
                        location: tap.location,
                        startLocation: tap.location,
                        _velocity: _Velocity(valuePerSecond: .zero))
                    isDragging = false
                    state = .processing
                }

            case .moved:
                guard activeSerial == id.serial else { continue }
                let now = Date.now
                let interval = currentValue.time.distance(to: now)
                if interval > 0 {
                    let delta = tap.location - currentValue.location
                    currentValue._velocity.valuePerSecond = CGSize(
                        width: delta.x / interval, height: delta.y / interval)
                }
                currentValue.time = now
                currentValue.location = tap.location

                if !isDragging {
                    let dist = (tap.location - currentValue.startLocation).magnitude
                    if dist >= minimumDistance { isDragging = true }
                }

                if isDragging {
                    state = .processing
                    updatePhase(.active(currentValue))
                }

            case .ended:
                guard activeSerial == id.serial else { continue }
                activeSerial = nil
                state = .done
                if isDragging {
                    updatePhase(.ended(currentValue))
                } else {
                    updatePhase(.possible(nil))
                }
                isDragging = false

            case .cancelled:
                if activeSerial == id.serial {
                    activeSerial = nil
                    isDragging = false
                    state = .failed
                    updatePhase(.failed)
                }
            }
        }
    }

    override func reset() {
        super.reset()
        activeSerial = nil
        isDragging = false
        processedBeganSerials.removeAll()
        updatePhase(.possible(nil))
    }
}
