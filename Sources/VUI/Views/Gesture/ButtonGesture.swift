//
//  File: ButtonGesture.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

public struct _ButtonGesture: Gesture {
    public var action: () -> Void
    public var pressingAction: ((Bool) -> Void)?

    public init(action: @escaping () -> Void, pressing: ((Bool) -> Void)? = nil) {
        self.action = action
        self.pressingAction = pressing
    }

    public static func _makeGesture(gesture: _GraphValue<Self>, inputs: _GestureInputs) -> _GestureOutputs<Value> {
        guard let graph = AttributeGraph.current else {
            fatalError("_ButtonGesture._makeGesture requires AG context")
        }

        let action = gesture._attribute.value.action
        let pressingAction = gesture._attribute.value.pressingAction
        let recognizer = ButtonGestureRecognizer(
            action: action, pressingAction: pressingAction,
            transform: inputs.transform, size: inputs.size)

        let phase: Attribute<GesturePhase<Void>> = graph.makeInput(value: .possible(nil))
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
    public typealias Value = Void
}

extension View {
    public func _onButtonGesture(pressing: ((Bool) -> Void)? = nil, perform action: @escaping () -> Void) -> some View {
        self.gesture(_ButtonGesture(action: action, pressing: pressing))
    }
}

// ButtonGestureRecognizer

final class ButtonGestureRecognizer: _GestureRecognizer<Void> {
    let action: () -> Void
    let pressingAction: ((Bool) -> Void)?
    let transform: Attribute<ViewTransform>
    let size: Attribute<ViewSize>

    private var activeSerial: Int? = nil
    private var isHovering: Bool = false
    private var processedBeganSerials: Set<Int> = []

    init(action: @escaping () -> Void, pressingAction: ((Bool) -> Void)?,
         transform: Attribute<ViewTransform>, size: Attribute<ViewSize>) {
        self.action = action
        self.pressingAction = pressingAction
        self.transform = transform
        self.size = size
    }

    private func containsGlobalPoint(_ globalPoint: CGPoint) -> Bool {
        var pts = [globalPoint]
        transform.value.convertGlobal(to: .local, points: &pts)
        return CGRect(origin: .zero, size: size.value.value).contains(pts[0])
    }

    override func processEvents(_ events: [EventID: any EventType]) {
        for (id, event) in events {
            guard let tap = event as? TappableEvent else { continue }

            switch tap.eventPhase {
            case .began:
                guard !processedBeganSerials.contains(id.serial) else { continue }
                processedBeganSerials.insert(id.serial)
                if activeSerial == nil {
                    // Only accept the event if the initial tap is within this view's frame.
                    guard let loc = tap.location, containsGlobalPoint(loc) else { continue }
                    activeSerial = id.serial
                    isHovering = true
                    state = .processing
                    AttributeGraph.withoutTracking { pressingAction?(true) }
                    updatePhase(.active(()))
                }

            case .moved:
                if activeSerial == id.serial {
                    let newHover = tap.location.map { containsGlobalPoint($0) } ?? isHovering
                    if newHover != isHovering {
                        isHovering = newHover
                        AttributeGraph.withoutTracking { pressingAction?(isHovering) }
                    }
                }

            case .ended:
                if activeSerial == id.serial {
                    let wasHovering = isHovering
                    activeSerial = nil
                    isHovering = false
                    state = .done
                    AttributeGraph.withoutTracking { pressingAction?(false) }
                    if wasHovering {
                        // enqueue via GestureGraph so the action fires in the
                        // pendingActions drain phase, outside AG evaluation context.
                        let act = action
                        if let gg = AttributeGraphRef.current?.context as? GestureGraph {
                            gg.enqueueAction { act() }
                        } else {
                            AttributeGraph.withoutTracking { act() }
                        }
                        updatePhase(.ended(()))
                    } else {
                        updatePhase(.possible(nil))
                    }
                }

            case .cancelled:
                if activeSerial == id.serial {
                    activeSerial = nil
                    if isHovering {
                        isHovering = false
                        AttributeGraph.withoutTracking { pressingAction?(false) }
                    }
                    state = .failed
                    updatePhase(.failed)
                }
            }
        }
    }

    override func reset() {
        if isHovering { pressingAction?(false) }
        activeSerial = nil
        isHovering = false
        processedBeganSerials.removeAll()
        super.reset()
        updatePhase(.possible(nil))
    }
}
