//
//  File: HoverModifier.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import Synchronization

protocol AnyHoverResponder: ViewResponder {
    func updateHover(isActive: Bool, point: CGPoint?) -> (() -> Void)?
}

private let _hoverResponderNextKey = Mutex<UInt32>(0xA0000000)

final class HoverResponder: AnyHoverResponder {
    let hitTestKey: UInt32
    weak var nextResponder: ResponderNode?
    var gestureContainer: AnyObject? { nil }

    var callback: (Bool) -> Void
    var snapshotTransform: ViewTransform
    var snapshotSize: ViewSize
    var snapshotIsEnabled: Bool
    var innerResponders: [any ViewResponder]
    weak var eventBindingManager: EventBindingManager?
    private var isActive = false

    init(callback: @escaping (Bool) -> Void,
         transform: ViewTransform,
         size: ViewSize,
         isEnabled: Bool,
         innerResponders: [any ViewResponder],
         eventBindingManager: EventBindingManager?) {
        self.hitTestKey = _hoverResponderNextKey.withLock { key in
            defer { key &+= 1 }
            return key
        }
        self.callback = callback
        self.snapshotTransform = transform
        self.snapshotSize = size
        self.snapshotIsEnabled = isEnabled
        self.innerResponders = innerResponders
        self.eventBindingManager = eventBindingManager
    }

    func hitTestPolicy(options: ContainsPointsOptions) -> HitTestPolicy {
        .include
    }

    func containsGlobalPoints(_ points: [CGPoint],
                              cacheKey: UInt32?,
                              options: ContainsPointsOptions) -> ContainsPointsResult {
        guard snapshotIsEnabled else { return .stop }

        var localPts = Array(points.prefix(64))
        snapshotTransform.convertGlobal(to: .local, points: &localPts)
        let bounds = CGRect(origin: .zero, size: snapshotSize.value)

        var mask: UInt64 = 0
        for (i, point) in localPts.enumerated() {
            if bounds.contains(point) { mask |= (1 << i) }
        }

        guard mask != 0 else { return .stop }
        return ContainsPointsResult(mask: mask, priority: 16.0, children: innerResponders)
    }

    func updateHover(isActive newValue: Bool, point: CGPoint?) -> (() -> Void)? {
        let active = snapshotIsEnabled && newValue
        guard isActive != active else { return nil }
        isActive = active
        let callback = callback
        return { callback(active) }
    }
}

extension MultiViewResponder {
    func hoverResponders(containing point: CGPoint) -> [any AnyHoverResponder] {
        respondersContaining(point: point).compactMap { $0 as? any AnyHoverResponder }
    }
}

final class HoverEventDispatcher {
    private var activeResponders: [Int: [any AnyHoverResponder]] = [:]

    func hasActiveResponders(deviceID: Int) -> Bool {
        !(activeResponders[deviceID] ?? []).isEmpty
    }

    @discardableResult
    func receiveEvents(
        _ events: [EventID: any EventType],
        rootResponder: MultiViewResponder?,
        enqueueAction: (@escaping () -> Void) -> Void
    ) -> Set<EventID> {
        var consumed: Set<EventID> = []
        for (eventID, event) in events {
            guard let hoverEvent = event as? HoverEvent,
                  let location = hoverEvent.location else { continue }
            let wasActive = hasActiveResponders(deviceID: hoverEvent.deviceID)
            let allowHit = hoverEvent.eventPhase != .ended && hoverEvent.eventPhase != .cancelled
            let isActive = updateResponders(
                at: location,
                deviceID: hoverEvent.deviceID,
                allowHit: allowHit,
                rootResponder: rootResponder,
                enqueueAction: enqueueAction
            )
            if wasActive || isActive {
                consumed.insert(eventID)
            }
        }
        return consumed
    }

    func reset(enqueueAction: (@escaping () -> Void) -> Void) {
        var actions: [() -> Void] = []
        for responders in activeResponders.values {
            for responder in responders {
                if let action = responder.updateHover(isActive: false, point: nil) {
                    actions.append(action)
                }
            }
        }
        activeResponders.removeAll()
        actions.forEach(enqueueAction)
    }

    private func responderID(_ responder: any AnyHoverResponder) -> ObjectIdentifier {
        ObjectIdentifier(responder as AnyObject)
    }

    @discardableResult
    private func updateResponders(
        at location: CGPoint,
        deviceID: Int,
        allowHit: Bool,
        rootResponder: MultiViewResponder?,
        enqueueAction: (@escaping () -> Void) -> Void
    ) -> Bool {
        let newResponders = allowHit
            ? (rootResponder?.hoverResponders(containing: location) ?? [])
            : []
        let oldResponders = activeResponders[deviceID] ?? []
        let oldIDs = Set(oldResponders.map(responderID))
        let newIDs = Set(newResponders.map(responderID))

        var actions: [() -> Void] = []
        for responder in oldResponders where !newIDs.contains(responderID(responder)) {
            if let action = responder.updateHover(isActive: false, point: nil) {
                actions.append(action)
            }
        }
        for responder in newResponders where !oldIDs.contains(responderID(responder)) {
            if let action = responder.updateHover(isActive: true, point: location) {
                actions.append(action)
            }
        }

        if newResponders.isEmpty {
            activeResponders.removeValue(forKey: deviceID)
        } else {
            activeResponders[deviceID] = newResponders
        }

        actions.forEach(enqueueAction)
        return !newResponders.isEmpty
    }
}

public struct _HoverRegionModifier: ViewModifier, MultiViewModifier {
    public let callback: (Bool) -> Void

    @inlinable public init(_ callback: @escaping (Bool) -> Void) {
        self.callback = callback
    }

    public static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        guard let graph = AttributeGraph.current else {
            fatalError("_HoverRegionModifier._makeView called outside AG context")
        }

        var outputs = body(_Graph(), inputs)

        guard inputs.preferences.keys.contains(ViewRespondersKey.self) else {
            return outputs
        }

        let innerResponderNodes = outputs.preferences.preferences
            .filter { $0.key == ViewRespondersKey.self }
            .map { $0.value }

        let innerRespondersAttr: Attribute<[any ViewResponder]>
        if innerResponderNodes.isEmpty {
            innerRespondersAttr = graph.makeInput(value: [])
        } else if innerResponderNodes.count == 1 {
            innerRespondersAttr = Attribute<[any ViewResponder]>(innerResponderNodes[0])
        } else {
            innerRespondersAttr = graph.makeRule {
                var combined = ViewRespondersKey.defaultValue
                for nodeID in innerResponderNodes {
                    let val = Attribute<[any ViewResponder]>(nodeID).value
                    ViewRespondersKey.reduce(value: &combined) { val }
                }
                return combined
            }
        }

        let environmentAttr = inputs.base.cachedEnvironment.value.environment
        let eventBindingManager =
            (AttributeGraphRef.current?.context as? ViewGraph)?
                .rendererHost?.gestureGraph?.eventBindingManager
        let responder = HoverResponder(
            callback: modifier._attribute.value.callback,
            transform: inputs.transform.value,
            size: inputs.size.value,
            isEnabled: environmentAttr.value.isEnabled,
            innerResponders: innerRespondersAttr.value,
            eventBindingManager: eventBindingManager
        )
        graph.makeSideEffectRule { [weak responder] in
            guard let responder else { return }
            responder.callback = modifier._attribute.value.callback
            responder.snapshotTransform = inputs.transform.value
            responder.snapshotSize = inputs.size.value
            responder.snapshotIsEnabled = environmentAttr.value.isEnabled
            responder.innerResponders = innerRespondersAttr.value
            responder.eventBindingManager?.enqueueHoverUpdateIfNeeded()
        }

        // Install the responder preference surface and ask the event manager
        // for a hover refresh when geometry changes.
        outputs.preferences.preferences.removeAll { $0.key == ViewRespondersKey.self }
        let respondersAttr: Attribute<[any ViewResponder]> = graph.makeInput(value: [responder])
        outputs.preferences.append(ViewRespondersKey.self, node: respondersAttr.identifier)
        return outputs
    }
}

extension _HoverRegionModifier {
    public typealias Body = Never
}

extension View {
    @inlinable
    public func onHover(perform action: @escaping (Bool) -> Void) -> some View {
        modifier(_HoverRegionModifier(action))
    }
}
