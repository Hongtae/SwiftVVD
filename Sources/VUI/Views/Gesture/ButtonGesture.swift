//
//  File: ButtonGesture.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

// Effective hit-test expansion read by primitive button gestures.
struct ButtonOutsetKey: EnvironmentKey {
    static let defaultValue: CGFloat? = nil
}

extension EnvironmentValues {
    var buttonOutset: CGFloat? {
        get { self[ButtonOutsetKey.self] }
        set { self[ButtonOutsetKey.self] = newValue }
    }
}

// MARK: - ButtonPressPhase

// Press phase passed to ButtonPressingAction. `.pressing` maps to true.
enum ButtonPressPhase: UInt8, Equatable {
    case idle      = 0  // inactive
    case outside   = 1  // active but pointer/touch outside bounds
    case pressing  = 2  // within bounds (or inset bounds)
    case triggered = 3  // released in bounds. action will fire
}

// MARK: - LocationInBounds

// Encodes the result of the outset-based hit test on PrimitiveButtonGestureCore.Value.
// 3 cases: inBounds(0)/inset(1)/outOfBounds(2)
enum LocationInBounds: UInt8, Equatable, Hashable {
    case inBounds    = 0  // strictly within CGRect(origin:.zero, size:viewSize)
    case inset       = 1  // within outset-expanded rect (outset > 0)
    case outOfBounds = 2  // outside all bounds
}

// MARK: - HoverCallback / ButtonPressingAction

// HoverCallback wraps the main action. It ignores the optional point.
// ButtonPressingAction wraps pressingAction and maps `.pressing` to true.
typealias HoverCallback        = (CGPoint?) -> ()
typealias ButtonPressingAction = (ButtonPressPhase) -> ()

// MARK: - PrimitiveButtonGestureCore

// PrimitiveButtonGestureCore performs button hit testing.
// Body chain (inner to outer):
//   EventListener<SpatialEvent>
//   -> DelayedGesture<SpatialEvent>   (duration=0 for buttons, so immediate)
//   -> MapGesture<SpatialEvent, Value> (event to locationInBounds hit test)
//   -> SizeGesture<...>               (provides CGSize for bounds check)
struct PrimitiveButtonGestureCore: Gesture {
    // reserved1 is omitted until its role is confirmed.
    var outset: CGFloat       // effectiveOutset for hit-test expansion
    var alwaysActive: Bool    // if true, gesture stays active even outside view

    // Hit-test value produced from the current event and view size.
    struct Value: Equatable {
        var location: CGPoint          // pointer/touch location
        var timestamp: Double          // event timestamp
        var locationInBounds: LocationInBounds
    }

    // Body chain type for event listening, immediate delay, hit-test mapping, and size input.
    typealias Body = SizeGesture<
        ModifierGesture<
            MapGesture<SpatialEvent, Value>,
            ModifierGesture<
                DelayedGesture<SpatialEvent>,
                EventListener<SpatialEvent>
            >
        >
    >

    var body: Body {
        // Map SpatialEvent to Value using the current size and captured outset.
        let capturedOutset = outset
        return SizeGesture { size in
            let transform: (SpatialEvent) -> Value = { event in
                let loc = event.location ?? .zero
                let rect = CGRect(origin: .zero, size: size)
                let insetRect = rect.insetBy(dx: -capturedOutset, dy: -capturedOutset)
                let locationInBounds: LocationInBounds =
                    rect.contains(loc)      ? .inBounds :
                    insetRect.contains(loc) ? .inset    :
                                              .outOfBounds
                return Value(
                    location: loc,
                    timestamp: event.timestamp,
                    locationInBounds: locationInBounds
                )
            }
            return ModifierGesture(
                modifier: MapGesture(transform: transform),
                body: ModifierGesture(
                    modifier: DelayedGesture<SpatialEvent>(),  // duration=0
                    body: EventListener<SpatialEvent>()
                )
            )
        }
    }
}

extension PrimitiveButtonGestureCore: GestureEventTypeAccepting {
    static func acceptsEventType(_ eventType: Any.Type) -> Bool {
        eventType == SpatialEvent.self
    }
}

// MARK: - PrimitiveButtonGestureCallbacks

// GestureCallbacks conformer for PrimitiveButtonGesture.
// hoverCallback wraps the action.
// buttonPressingAction wraps pressing changes.
struct PrimitiveButtonGestureCallbacks: GestureCallbacks {
    typealias Value = PrimitiveButtonGestureCore.Value
    typealias StateType = ButtonPressPhase

    var hoverCallback: HoverCallback?
    var buttonPressingAction: ButtonPressingAction?

    static var initialState: ButtonPressPhase { .idle }

    // Converts the core gesture phase to a button press phase.
    func pressPhase(_ phase: GesturePhase<Value>) -> ButtonPressPhase {
        switch phase {
        case .possible, .failed: return .idle
        case .active(let v):
            switch v.locationInBounds {
            case .inBounds, .inset: return .pressing
            case .outOfBounds:      return .outside
            }
        case .ended(let v):
            switch v.locationInBounds {
            case .inBounds, .inset: return .triggered
            case .outOfBounds:      return .idle
            }
        }
    }

    // Triggered tap order: pressing(true), pressing(false), then action().
    // Cancel cleanup must not call action().
    func dispatch(
        phase: GesturePhase<Value>,
        state: inout ButtonPressPhase
    ) -> (() -> ())? {
        let newPhase = pressPhase(phase)
        guard newPhase != state else { return nil }

        let hasHover = hoverCallback != nil
        let old = state

        switch phase {
        case .active:
            // State changes notify the pressing callback.
            state = newPhase
            guard hasHover else { return nil }
            let bpa = buttonPressingAction
            let newPh = newPhase
            return { bpa?(newPh) }

        case .ended(_) where newPhase == .triggered && (old == .pressing || old == .outside):
            // Triggered: pressing cleanup first, then action.
            state = .idle
            let bpa = buttonPressingAction
            let hc  = hoverCallback
            return {
                bpa?(.idle)   // pressingAction(false) first
                hc?(nil)      // action() second
            }

        case .ended:
            // Ended outside bounds: notify press ended, no action.
            state = .idle
            let bpa = buttonPressingAction
            return bpa.map { bpa in { bpa(.idle) } }

        case .failed:
            // Cancel cleanup: pressing(false) only. action must not fire.
            if hasHover && (old == .pressing || old == .outside) {
                state = .idle
                let bpa = buttonPressingAction
                return { bpa?(.idle) }
            }
            state = .idle
            return nil

        default:
            return nil
        }
    }

    // Same cleanup branch used by cancellation.
    func cancel(state: ButtonPressPhase) -> (() -> ())? {
        if hoverCallback != nil && (state == .pressing || state == .outside) {
            let bpa = buttonPressingAction
            return { bpa?(.idle) }
        }
        return nil
    }
}

// MARK: - PrimitiveButtonGesture

// Internal primitive used by the public button gesture.
// It reads the effective button outset, builds the core hit-test gesture,
// attaches the button callbacks, and maps the resulting phase value to Void.
struct PrimitiveButtonGesture: Gesture {
    // Closure wrappers produced by the public button gesture.
    var hoverCallback: HoverCallback?
    var buttonPressingAction: ButtonPressingAction?
    var outset: CGFloat = 0.0     // fallback hit-test expansion
    var alwaysActive: Bool = false

    typealias Value = ()
    typealias Body = Never

    public var body: Never { fatalError("PrimitiveButtonGesture.body must not be called") }

    // Builds a reactive callback/core gesture chain and converts the core value phase to Void.
    static func _makeGesture(
        gesture: _GraphValue<Self>,
        inputs: _GestureInputs
    ) -> _GestureOutputs<()> {
        guard let graph = _AGGraph.current else {
            fatalError("PrimitiveButtonGesture._makeGesture requires AG context")
        }

        let gestureAttr = gesture._attribute

        // GestureGraph has a separate AG from ViewGraph, so use the view graph's cached
        // environment value instead of reading inputs.environment inside a gesture rule.
        let envAttr = inputs.environment
        let viewGraphAG: _AGGraph? = (_AGGraphContext.current?.context as? GestureGraph)?
            .rendererHost?.viewGraph.data.graph
        let outsetAttr: Attribute<CGFloat> = graph.makeRule {
            if let vg = viewGraphAG,
               let env = vg.cachedValue(for: envAttr.identifier) as? EnvironmentValues,
               let outset = env.buttonOutset {
                return outset
            }
            return gestureAttr.value.outset
        }

        // Build the reactive callback/core gesture chain from the current primitive fields.
        let coreGestureAttr: Attribute<
            ModifierGesture<
                CallbacksGesture<PrimitiveButtonGestureCallbacks>,
                PrimitiveButtonGestureCore
            >
        > = graph.makeRule {
            let pbg = gestureAttr.value
            let outset = outsetAttr.value
            return ModifierGesture(
                modifier: CallbacksGesture(callbacks: PrimitiveButtonGestureCallbacks(
                    hoverCallback: pbg.hoverCallback,
                    buttonPressingAction: pbg.buttonPressingAction
                )),
                body: PrimitiveButtonGestureCore(
                    outset: outset,
                    alwaysActive: pbg.alwaysActive
                )
            )
        }

        // Delegate evaluation to the composed callback/core gesture chain.
        typealias ChainType = ModifierGesture<
            CallbacksGesture<PrimitiveButtonGestureCallbacks>,
            PrimitiveButtonGestureCore
        >
        let chainGV = _GraphValue<ChainType>(_attribute: coreGestureAttr)
        let outputs = ChainType._makeGesture(gesture: chainGV, inputs: inputs)

        // Drop the core hit-test value while preserving the phase shape.
        let phaseAttr: Attribute<GesturePhase<()>> = graph.makeRule {
            outputs.phase.value.withValue(())
        }
        return outputs.withPhase(phaseAttr)
    }
}

extension PrimitiveButtonGesture: GestureEventTypeAccepting {
    static func acceptsEventType(_ eventType: Any.Type) -> Bool {
        eventType == SpatialEvent.self
    }
}

// MARK: - _ButtonGesture

// Public button gesture entry point.
// Gesture construction is routed directly through PrimitiveButtonGesture for now.
// _makeGesture converts the public closures to primitive callback wrappers:
// pressingAction receives true only for the pressing phase, and action ignores the point.
public struct _ButtonGesture: Gesture, PubliclyPrimitiveGesture {
    public var action: () -> Void
    public var pressingAction: ((Bool) -> Void)?

    public init(action: @escaping () -> Void, pressing: ((Bool) -> Void)? = nil) {
        self.action = action
        self.pressingAction = pressing
    }

    // Body is intentionally unavailable. Gesture construction goes through _makeGesture.
    public typealias Body = Never
    public typealias Value = Void

    public var body: Never { fatalError("_ButtonGesture.body must not be called") }

    // Converts stored closures to primitive callback wrappers, then delegates to the primitive.
    public static func _makeGesture(
        gesture: _GraphValue<Self>,
        inputs: _GestureInputs
    ) -> _GestureOutputs<Void> {
        guard let graph = _AGGraph.current else {
            fatalError("_ButtonGesture._makeGesture requires AG context")
        }
        // Rebuild the primitive when the public gesture fields change.
        let pbgAttr: Attribute<PrimitiveButtonGesture> = graph.makeRule {
            let s = gesture._attribute.value
            let bpa2: ButtonPressingAction? = s.pressingAction.map { pc in
                { phase in pc(phase.rawValue == 2) }
            }
            let act = s.action
            return PrimitiveButtonGesture(
                hoverCallback: { _ in act() },
                buttonPressingAction: bpa2,
                outset: 0.0,
                alwaysActive: false
            )
        }
        return PrimitiveButtonGesture._makeGesture(
            gesture: _GraphValue(_attribute: pbgAttr),
            inputs: inputs
        )
    }
}

extension _ButtonGesture: GestureEventTypeAccepting {
    static func acceptsEventType(_ eventType: Any.Type) -> Bool {
        eventType == SpatialEvent.self
    }
}

extension View {
    public func _onButtonGesture(pressing: ((Bool) -> Void)? = nil, perform action: @escaping () -> Void) -> some View {
        self.gesture(_ButtonGesture(action: action, pressing: pressing))
    }
}
