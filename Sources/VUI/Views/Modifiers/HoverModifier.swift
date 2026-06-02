//
//  File: HoverModifier.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import Synchronization

public enum HoverPhase: Equatable {
    case active(CGPoint)
    case ended
}

protocol AnyHoverResponder: ViewResponder {
    func updateHover(isActive: Bool, point: CGPoint?) -> (() -> Void)?
}

private let _hoverResponderNextKey = Mutex<UInt32>(0xA0000000)

final class HoverResponder: MultiViewResponder, AnyHoverResponder {
    let hitTestKey: UInt32
    weak var nextResponder: ResponderNode?
    var gestureContainer: AnyObject? { nil }

    var callback: ((Bool) -> Void)?
    var continuousCallback: ((HoverPhase) -> Void)?
    var coordinateSpace: CoordinateSpace
    var snapshotTransform: ViewTransform
    var snapshotSize: ViewSize
    var snapshotIsEnabled: Bool
    var innerResponders: [any ViewResponder]
    weak var eventBindingManager: EventBindingManager?
    private var isActive = false
    private var phase: HoverPhase = .ended

    init(callback: ((Bool) -> Void)?,
         continuousCallback: ((HoverPhase) -> Void)?,
         coordinateSpace: CoordinateSpace,
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
        self.continuousCallback = continuousCallback
        self.coordinateSpace = coordinateSpace
        self.snapshotTransform = transform
        self.snapshotSize = size
        self.snapshotIsEnabled = isEnabled
        self.innerResponders = innerResponders
        self.eventBindingManager = eventBindingManager
        super.init()
        updateInnerResponders(innerResponders)
    }

    func updateInnerResponders(_ responders: [any ViewResponder]) {
        innerResponders = responders
        for responder in responders where responder.nextResponder == nil {
            responder.nextResponder = self
        }
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

    private func hoverPhase(isActive active: Bool, point: CGPoint?) -> HoverPhase {
        guard active, var point else { return .ended }
        switch coordinateSpace {
        case .local:
            var points = [point]
            snapshotTransform.convertGlobal(to: .local, points: &points)
            point = points[0]
        case .global, .named:
            break
        }
        return .active(point)
    }

    func updateHover(isActive newValue: Bool, point: CGPoint?) -> (() -> Void)? {
        let active = snapshotIsEnabled && newValue && point != nil
        let nextPhase = hoverPhase(isActive: active, point: point)
        let shouldSendBool = isActive != active
        let shouldSendContinuous = phase != nextPhase
        guard shouldSendBool || shouldSendContinuous else { return nil }

        isActive = active
        phase = nextPhase
        let callback = callback
        let continuousCallback = continuousCallback
        return {
            if shouldSendBool {
                callback?(active)
            }
            if shouldSendContinuous {
                continuousCallback?(nextPhase)
            }
        }
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
        let newIDs = Set(newResponders.map(responderID))

        var actions: [() -> Void] = []
        for responder in oldResponders where !newIDs.contains(responderID(responder)) {
            if let action = responder.updateHover(isActive: false, point: nil) {
                actions.append(action)
            }
        }
        for responder in newResponders.reversed() {
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
            continuousCallback: nil,
            coordinateSpace: .local,
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
            responder.updateInnerResponders(innerRespondersAttr.value)
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

public struct _ContinuousHoverModifier: ViewModifier, MultiViewModifier {
    public let coordinateSpace: CoordinateSpace
    public let callback: (HoverPhase) -> Void

    @inlinable public init(
        coordinateSpace: CoordinateSpace = .local,
        _ callback: @escaping (HoverPhase) -> Void
    ) {
        self.coordinateSpace = coordinateSpace
        self.callback = callback
    }

    public static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        guard let graph = AttributeGraph.current else {
            fatalError("_ContinuousHoverModifier._makeView called outside AG context")
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
            callback: nil,
            continuousCallback: modifier._attribute.value.callback,
            coordinateSpace: modifier._attribute.value.coordinateSpace,
            transform: inputs.transform.value,
            size: inputs.size.value,
            isEnabled: environmentAttr.value.isEnabled,
            innerResponders: innerRespondersAttr.value,
            eventBindingManager: eventBindingManager
        )
        graph.makeSideEffectRule { [weak responder] in
            guard let responder else { return }
            responder.continuousCallback = modifier._attribute.value.callback
            responder.coordinateSpace = modifier._attribute.value.coordinateSpace
            responder.snapshotTransform = inputs.transform.value
            responder.snapshotSize = inputs.size.value
            responder.snapshotIsEnabled = environmentAttr.value.isEnabled
            responder.updateInnerResponders(innerRespondersAttr.value)
            responder.eventBindingManager?.enqueueHoverUpdateIfNeeded()
        }

        outputs.preferences.preferences.removeAll { $0.key == ViewRespondersKey.self }
        let respondersAttr: Attribute<[any ViewResponder]> = graph.makeInput(value: [responder])
        outputs.preferences.append(ViewRespondersKey.self, node: respondersAttr.identifier)
        return outputs
    }
}

extension _ContinuousHoverModifier {
    public typealias Body = Never
}

extension View {
    @inlinable
    public func onHover(perform action: @escaping (Bool) -> Void) -> some View {
        modifier(_HoverRegionModifier(action))
    }

    @inlinable
    public func onContinuousHover(
        coordinateSpace: some CoordinateSpaceProtocol = .local,
        perform action: @escaping (HoverPhase) -> Void
    ) -> some View {
        modifier(_ContinuousHoverModifier(
            coordinateSpace: coordinateSpace.coordinateSpace,
            action
        ))
    }
}
