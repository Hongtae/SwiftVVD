//
//  File: DragGesture.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import VVD

// _EventDirections
//
// OptionSet controlling which drag directions are recognized.
// Stored as Int8. default rawValue=0x0F means all four directions.
public struct _EventDirections: OptionSet, Sendable {
    public let rawValue: Int8

    public init(rawValue: Int8) {
        self.rawValue = rawValue
    }

    public static let left       = _EventDirections(rawValue: 1 << 0)
    public static let right      = _EventDirections(rawValue: 1 << 1)
    public static let up         = _EventDirections(rawValue: 1 << 2)
    public static let down       = _EventDirections(rawValue: 1 << 3)
    public static let all        = _EventDirections(rawValue: 0x0F)
    public static let horizontal = _EventDirections(rawValue: 0x03)  // left | right
    public static let vertical   = _EventDirections(rawValue: 0x0C)  // up | down
}

// DragGesture
//
// _makeGesture copies fields into SpatialDragGesture, then wraps it with Gesture.category(.drag).

public struct DragGesture: Gesture, PubliclyPrimitiveGesture {
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
    // Hidden direction filter. Defaults to all four directions.
    var allowedDirections: _EventDirections

    public init(minimumDistance: CGFloat = 10, coordinateSpace: some CoordinateSpaceProtocol = .local) {
        self.minimumDistance = minimumDistance
        self.coordinateSpace = coordinateSpace.coordinateSpace
        self.allowedDirections = .all
    }

    public typealias Body = Never

    typealias InternalBody = ModifierGesture<CategoryGesture<Value>, SpatialDragGesture>

    var internalBody: InternalBody {
        SpatialDragGesture(
            minimumDistance: minimumDistance,
            coordinateSpace: coordinateSpace,
            allowedDirections: allowedDirections
        )
        .category(.drag, includeChildren: false)
    }

    public static func _makeGesture(
        gesture: _GraphValue<DragGesture>,
        inputs: _GestureInputs
    ) -> _GestureOutputs<DragGesture.Value> {
        makeGesture(gesture: gesture, inputs: inputs)
    }
}

extension DragGesture.Value: Sendable {}

// MARK: - SpatialDragGesture

/// Internal gesture type used by DragGesture.
/// Implements drag recognition via an AG modifier chain.
///
/// body chain (inner -> outer):
///   EventListener<MouseEvent>
///   -> EventFilter<MouseEvent>       (event.button == .primary)
///   -> CoordinateSpaceGesture<MouseEvent>
///   -> StateContainerGesture<InternalState, MouseEvent, DragGesture.Value>
///   -> DependentGesture<DragGesture.Value> (.pausedUntilFailed)
struct SpatialDragGesture: Gesture {
    var minimumDistance: CGFloat
    var coordinateSpace: CoordinateSpace
    var allowedDirections: _EventDirections

    typealias Value = DragGesture.Value

    /// Intermediate state for drag recognition.
    struct InternalState: GestureStateProtocol {
        var startLocation: CGPoint = .zero
        var currentLocation: CGPoint = .zero
        var startTime: Date = Date()
        var velocity: _Velocity<CGSize> = _Velocity(valuePerSecond: .zero)
        var isDragging: Bool = false

        init() {}
    }

    typealias RecognitionBody = ModifierGesture<
        StateContainerGesture<InternalState, MouseEvent, DragGesture.Value>,
        ModifierGesture<
            CoordinateSpaceGesture<MouseEvent>,
            ModifierGesture<
                EventFilter<MouseEvent>,
                EventListener<MouseEvent>
            >
        >
    >
    typealias Body = ModifierGesture<DependentGesture<DragGesture.Value>, RecognitionBody>

    var body: Body {
        let minDist = minimumDistance
        let cs = coordinateSpace
        let allowed = allowedDirections
        let transform: (inout InternalState, GesturePhase<MouseEvent>) -> GesturePhase<DragGesture.Value> = {
            SpatialDragGesture.applyPhase(minimumDistance: minDist, allowedDirections: allowed, state: &$0, phase: $1)
        }
        let recognitionBody = RecognitionBody(
            modifier: StateContainerGesture(body: transform),
            body: ModifierGesture(
                modifier: CoordinateSpaceGesture(coordinateSpace: cs),
                body: ModifierGesture(
                    modifier: EventFilter<MouseEvent> { event in
                        guard let mouseEvent = MouseEvent(event) else {
                            return true
                        }
                        return mouseEvent.button == .primary
                    },
                    body: EventListener<MouseEvent>()
                )
            )
        )
        return recognitionBody.dependency(.pausedUntilFailed)
    }

    /// StateContainerGesture.transform closure.
    /// Applies minimum distance and allowed-direction checks while building the drag phase.
    static func applyPhase(
        minimumDistance: CGFloat,
        allowedDirections: _EventDirections,
        state: inout InternalState,
        phase: GesturePhase<MouseEvent>
    ) -> GesturePhase<DragGesture.Value> {
        switch phase {
        case .possible:
            state.isDragging = false
            return .possible(nil)
        case .active(let event):
            let location = event.location
            if !state.isDragging && state.startLocation == .zero {
                state.startLocation = location
                state.startTime = Date()
            }
            let prev = state.currentLocation
            state.currentLocation = location
            if prev != .zero {
                let delta = CGSize(width: location.x - prev.x, height: location.y - prev.y)
                state.velocity = _Velocity(valuePerSecond: delta)
            }
            let dx = location.x - state.startLocation.x
            let dy = location.y - state.startLocation.y
            let dist = hypot(dx, dy)
            guard dist >= minimumDistance else { return .possible(nil) }
            // allowedDirections filter: check dominant drag direction
            if !allowedDirections.contains(.all) {
                let isHorizontal = abs(dx) >= abs(dy)
                if isHorizontal {
                    let dir: _EventDirections = dx >= 0 ? .right : .left
                    guard allowedDirections.contains(dir) else { return .possible(nil) }
                } else {
                    let dir: _EventDirections = dy >= 0 ? .down : .up
                    guard allowedDirections.contains(dir) else { return .possible(nil) }
                }
            }
            state.isDragging = true
            let value = DragGesture.Value(
                time: state.startTime,
                location: location,
                startLocation: state.startLocation,
                _velocity: state.velocity
            )
            return .active(value)
        case .ended(let event):
            guard state.isDragging else {
                state.startLocation = .zero
                state.currentLocation = .zero
                return .failed
            }
            let location = event.location
            let value = DragGesture.Value(
                time: state.startTime,
                location: location,
                startLocation: state.startLocation,
                _velocity: state.velocity
            )
            state.isDragging = false
            state.startLocation = .zero
            state.currentLocation = .zero
            return .ended(value)
        case .failed:
            state.isDragging = false
            state.startLocation = .zero
            state.currentLocation = .zero
            return .failed
        }
    }
}
