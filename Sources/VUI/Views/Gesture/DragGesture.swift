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
// Stored as UInt8. default rawValue=0x0F means all four directions.
public struct _EventDirections: OptionSet, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let up         = _EventDirections(rawValue: 1 << 0)
    public static let down       = _EventDirections(rawValue: 1 << 1)
    public static let left       = _EventDirections(rawValue: 1 << 2)
    public static let right      = _EventDirections(rawValue: 1 << 3)
    public static let all        = _EventDirections(rawValue: 0x0F)
    public static let vertical   = _EventDirections(rawValue: 0x03)  // up | down
    public static let horizontal = _EventDirections(rawValue: 0x0C)  // left | right
}

// DragGesture
//
// _makeGesture copies fields into SpatialDragGesture, then wraps it with Gesture.category(.drag).

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
    // Hidden direction filter. Defaults to all four directions.
    var allowedDirections: _EventDirections

    public init(minimumDistance: CGFloat = 10, coordinateSpace: some CoordinateSpaceProtocol = .local) {
        self.minimumDistance = minimumDistance
        self.coordinateSpace = coordinateSpace.coordinateSpace
        self.allowedDirections = .all
    }

    public typealias Body = Never

    public static func _makeGesture(
        gesture: _GraphValue<DragGesture>,
        inputs: _GestureInputs
    ) -> _GestureOutputs<DragGesture.Value> {
        guard let graph = AttributeGraph.current else {
            fatalError("DragGesture._makeGesture requires AG context")
        }
        // Copies minimumDistance/coordinateSpace/allowedDirections into SpatialDragGesture,
        // then wraps result with Gesture.category(.drag, includeChildren: false).
        let self_ = gesture._attribute.value
        let spatial = SpatialDragGesture(
            minimumDistance: self_.minimumDistance,
            coordinateSpace: self_.coordinateSpace,
            allowedDirections: self_.allowedDirections
        )
        // CategoryGesture is pass-through until GestureCategory.Key preference
        // injection is implemented. Keep the wrapper so category injection can be
        // added without refactoring.
        let categorized = spatial.category(.drag, includeChildren: false)
        typealias Chain = ModifierGesture<CategoryGesture<DragGesture.Value>, SpatialDragGesture>
        let attr: Attribute<Chain> = graph.makeInput(value: categorized)
        return Chain._makeGesture(gesture: _GraphValue(_attribute: attr), inputs: inputs)
    }
}

extension DragGesture.Value: Sendable {}

extension DragGesture: GestureEventTypeAccepting {
    static func acceptsEventType(_ eventType: Any.Type) -> Bool {
        eventType == TappableEvent.self
    }
}

// MARK: - SpatialDragGesture

/// Internal gesture type used by DragGesture.
/// Implements drag recognition via an AG modifier chain.
///
/// GestureGraph currently converts platform mouse input into TappableEvent,
/// so this local chain uses EventListener<TappableEvent>.
///
/// body chain (inner -> outer):
///   EventListener<TappableEvent>
///   -> EventFilter<TappableEvent>       (event.button == .primary)
///   -> CoordinateSpaceGesture<TappableEvent>
///   -> StateContainerGesture<InternalState, TappableEvent, DragGesture.Value>
struct SpatialDragGesture: Gesture, PubliclyPrimitiveGesture {
    var minimumDistance: CGFloat
    var coordinateSpace: CoordinateSpace
    var allowedDirections: _EventDirections

    typealias Value = DragGesture.Value

    /// Intermediate state for drag recognition.
    struct InternalState {
        var startLocation: CGPoint = .zero
        var currentLocation: CGPoint = .zero
        var startTime: Date = Date()
        var velocity: _Velocity<CGSize> = _Velocity(valuePerSecond: .zero)
        var isDragging: Bool = false
    }

    typealias Body = ModifierGesture<
        StateContainerGesture<InternalState, TappableEvent, DragGesture.Value>,
        ModifierGesture<
            CoordinateSpaceGesture<TappableEvent>,
            ModifierGesture<
                EventFilter<TappableEvent>,
                EventListener<TappableEvent>
            >
        >
    >

    var body: Body {
        let minDist = minimumDistance
        let cs = coordinateSpace
        let allowed = allowedDirections
        let transform: (inout InternalState, GesturePhase<TappableEvent>) -> GesturePhase<DragGesture.Value> = {
            SpatialDragGesture.applyPhase(minimumDistance: minDist, allowedDirections: allowed, state: &$0, phase: $1)
        }
        return ModifierGesture(
            modifier: StateContainerGesture(
                initialState: InternalState(),
                transform: transform
            ),
            body: ModifierGesture(
                modifier: CoordinateSpaceGesture(coordinateSpace: cs),
                body: ModifierGesture(
                    modifier: EventFilter(),
                    body: EventListener<TappableEvent>()
                )
            )
        )
    }

    /// StateContainerGesture.transform closure.
    /// Applies minimum distance and allowed-direction checks while building the drag phase.
    static func applyPhase(
        minimumDistance: CGFloat,
        allowedDirections: _EventDirections,
        state: inout InternalState,
        phase: GesturePhase<TappableEvent>
    ) -> GesturePhase<DragGesture.Value> {
        switch phase {
        case .possible:
            state.isDragging = false
            return .possible(nil)
        case .active(let event):
            guard let location = event.location else { return .possible(nil) }
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
            guard let location = event.location else { return .failed }
            let value = DragGesture.Value(
                time: state.startTime,
                location: location,
                startLocation: state.startLocation,
                _velocity: state.velocity
            )
            state.isDragging = false
            return .ended(value)
        case .failed:
            state.isDragging = false
            return .failed
        }
    }
}

extension SpatialDragGesture: GestureEventTypeAccepting {
    static func acceptsEventType(_ eventType: Any.Type) -> Bool {
        eventType == TappableEvent.self
    }
}
