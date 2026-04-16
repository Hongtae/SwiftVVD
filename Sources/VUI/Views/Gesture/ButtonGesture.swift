//
//  File: ButtonGesture.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

// Environment key for button hit-test outset.
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

// pressing(2): isPressing=true in ButtonPressingAction closure.
enum ButtonPressPhase: UInt8, Equatable {
    case idle      = 0  // inactive
    case outside   = 1  // active but pointer/touch outside bounds
    case pressing  = 2  // within bounds (or inset bounds)
    case triggered = 3  // released in bounds, action will fire
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

// HoverCallback wraps the main action and ignores the optional location argument.
// ButtonPressingAction wraps the optional pressing-state callback.
// ButtonPressPhase.rawValue == 2 (.pressing) maps to isPressing=true, others map to false.
typealias HoverCallback        = (CGPoint?) -> ()
typealias ButtonPressingAction = (ButtonPressPhase) -> ()

// MARK: - PrimitiveButtonGestureCore

// Primitive button gesture core.
// Body chain, from inner to outer:
//   EventListener<SpatialEvent>
//   -> DelayedGesture<SpatialEvent>   (duration=0 for buttons, immediate)
//   -> MapGesture<SpatialEvent, Value> (event to locationInBounds hit test)
//   -> SizeGesture<...>               (provides CGSize for bounds check)
struct PrimitiveButtonGestureCore: Gesture {
    var outset: CGFloat       // effectiveOutset for hit-test expansion
    var alwaysActive: Bool    // if true, gesture stays active even outside view

    struct Value: Equatable {
        var location: CGPoint          // pointer/touch location
        var timestamp: Double          // event timestamp
        var locationInBounds: LocationInBounds
    }

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
        // Outset is captured; SizeGesture provides current CGSize reactively.
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

// MARK: - PrimitiveButtonGestureCallbacks

// Dispatches button phase transitions to hover and pressing callbacks.
struct PrimitiveButtonGestureCallbacks: GestureCallbacks {
    typealias Value = PrimitiveButtonGestureCore.Value
    typealias StateType = ButtonPressPhase

    var hoverCallback: HoverCallback?
    var buttonPressingAction: ButtonPressingAction?

    static var initialState: ButtonPressPhase { .idle }

    // Converts a gesture phase into a button press phase.
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

    // Tap order: pressing=true -> pressing=false -> action().
    // Cancel never calls action().
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
            // Fire ButtonPressingAction on state change.
            state = newPhase
            guard hasHover else { return nil }
            let bpa = buttonPressingAction
            let newPh = newPhase
            return { bpa?(newPh) }

        case .ended(let v) where newPhase == .triggered && (old == .pressing || old == .outside):
            // Triggered release: pressing callback fires first, then the action callback.
            state = .idle
            let bpa = buttonPressingAction
            let hc  = hoverCallback
            return {
                bpa?(.idle)   // pressingAction(false) first
                hc?(nil)      // action() second
            }

        case .ended:
            // Ended outside bounds: notify press ended without firing the action.
            state = .idle
            let bpa = buttonPressingAction
            return bpa.map { bpa in { bpa(.idle) } }

        case .failed:
            // Cancellation resets pressing state but never fires the action.
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

    // Mirrors the cancellation branch used by dispatch.
    func cancel(state: ButtonPressPhase) -> (() -> ())? {
        if hoverCallback != nil && (state == .pressing || state == .outside) {
            let bpa = buttonPressingAction
            return { bpa?(.idle) }
        }
        return nil
    }
}

// MARK: - PrimitiveButtonGesture

// Builds PrimitiveButtonGestureCore and PrimitiveButtonGestureCallbacks reactively.
struct PrimitiveButtonGesture: Gesture {
    var hoverCallback: HoverCallback?
    var buttonPressingAction: ButtonPressingAction?
    var outset: CGFloat = 0.0     // passed to PrimitiveButtonGestureCore
    var alwaysActive: Bool = false

    typealias Value = ()
    typealias Body = Never

    public var body: Never { fatalError("PrimitiveButtonGesture.body must not be called") }

    // Builds the callback/core chain and maps its phase to Void.
    static func _makeGesture(
        gesture: _GraphValue<Self>,
        inputs: _GestureInputs
    ) -> _GestureOutputs<()> {
        guard let graph = AttributeGraph.current else {
            fatalError("PrimitiveButtonGesture._makeGesture requires AG context")
        }

        let gestureAttr = gesture._attribute

        // GestureGraph has a separate AG from ViewGraph, so inputs.environment cannot be read
        // directly inside a GestureGraph rule. Use cachedValue on the ViewGraph's AG instead.
        let envAttr = inputs.environment
        let viewGraphAG: AttributeGraph? = (AttributeGraphRef.current?.context as? GestureGraph)?
            .rendererHost?.viewGraph.data.graph
        let outsetAttr: Attribute<CGFloat> = graph.makeRule {
            if let vg = viewGraphAG,
               let env = vg.cachedValue(for: envAttr.identifier) as? EnvironmentValues,
               let outset = env.buttonOutset {
                return outset
            }
            return gestureAttr.value.outset
        }

        // Build the callback modifier and core gesture reactively.
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

        // Call _makeGesture on the full chain.
        typealias ChainType = ModifierGesture<
            CallbacksGesture<PrimitiveButtonGestureCallbacks>,
            PrimitiveButtonGestureCore
        >
        let chainGV = _GraphValue<ChainType>(_attribute: coreGestureAttr)
        let outputs = ChainType._makeGesture(gesture: chainGV, inputs: inputs)

        // Map the core value phase to a Void phase.
        let phaseAttr: Attribute<GesturePhase<()>> = graph.makeRule {
            outputs.phase.value.withValue(())
        }
        return outputs.withPhase(phaseAttr)
    }
}

// MARK: - _ButtonGesture

// Public button gesture wrapper.
// Conversion in _makeGesture:
//   pressingAction: Optional<(Bool)->()>
//     -> ButtonPressingAction = (ButtonPressPhase)->() (rawValue==2 maps to isPressing=true)
//   action: ()->()
//     -> HoverCallback = (CGPoint?)->() (ignores argument, always calls action())
public struct _ButtonGesture: Gesture, PubliclyPrimitiveGesture {
    public var action: () -> Void
    public var pressingAction: ((Bool) -> Void)?

    public init(action: @escaping () -> Void, pressing: ((Bool) -> Void)? = nil) {
        self.action = action
        self.pressingAction = pressing
    }

    public typealias Body = Never
    public typealias Value = Void

    public var body: Never { fatalError("_ButtonGesture.body must not be called") }

    // Builds HoverCallback(action) + ButtonPressingAction(pressingAction),
    // then delegates to PrimitiveButtonGesture._makeGesture.
    public static func _makeGesture(
        gesture: _GraphValue<Self>,
        inputs: _GestureInputs
    ) -> _GestureOutputs<Void> {
        guard let graph = AttributeGraph.current else {
            fatalError("_ButtonGesture._makeGesture requires AG context")
        }
        // Reactive: rebuild PBG when _ButtonGesture fields change
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

extension View {
    public func _onButtonGesture(pressing: ((Bool) -> Void)? = nil, perform action: @escaping () -> Void) -> some View {
        self.gesture(_ButtonGesture(action: action, pressing: pressing))
    }
}
