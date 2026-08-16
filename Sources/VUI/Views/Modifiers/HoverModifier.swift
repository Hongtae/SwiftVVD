//
//  File: HoverModifier.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

public enum HoverPhase: Equatable {
    case active(CGPoint)
    case ended
}

enum HoverCallback {
    case spatial((HoverPhase) -> Void)
    case nonSpatial((Bool) -> Void)
}

final class HoverResponder: DefaultLayoutViewResponder {
    var callback: HoverCallback
    var transform: ViewTransform
    var size: CGSize
    var coordinateSpace: CoordinateSpace
    var helper: ContentResponderHelper<TrivialContentResponder>
    private(set) var currentPhase: HoverPhase
    var isEnabled: Bool

    override init(inputs: _ViewInputs) {
        callback = .nonSpatial { _ in }
        transform = ViewTransform()
        size = .zero
        coordinateSpace = .local
        helper = ContentResponderHelper()
        currentPhase = .ended
        isEnabled = true
        super.init(inputs: inputs)
    }

    override func hitTestPolicy(options: ViewResponder.ContainsPointsOptions) -> ViewResponder.HitTestPolicy {
        let inherited = super.hitTestPolicy(options: options)
        guard inherited != .exclude else { return inherited }
        guard isEnabled,
              options.contains(.includeHoverResponders) else {
            return .passthrough
        }
        return .include
    }

    override func containsGlobalPoints(_ points: [CGPoint],
                                       cacheKey: UInt32?,
                                       options: ViewResponder.ContainsPointsOptions) -> ViewResponder.ContainsPointsResult {
        guard hitTestPolicy(options: options) != .exclude else {
            return .passthrough(to: children)
        }
        var result = helper.containsGlobalPoints(
            points,
            cacheKey: cacheKey,
            options: options,
            children: children
        )
        let inherited = super.containsGlobalPoints(
            points,
            cacheKey: cacheKey,
            options: options
        )
        result.mask.formUnion(inherited.mask)
        result.priority = max(result.priority, inherited.priority)
        return result
    }

    func updatePhase(_ nextPhase: HoverPhase) {
        switch callback {
        case .spatial(let action):
            guard currentPhase != nextPhase else { return }
            currentPhase = nextPhase
            Update.enqueueAction {
                action(nextPhase)
            }

        case .nonSpatial(let action):
            let wasActive = currentPhase.isActive
            let isActive = nextPhase.isActive
            currentPhase = nextPhase
            guard wasActive != isActive else { return }
            Update.enqueueAction {
                action(isActive)
            }
        }
    }
}

struct HoverResponderChild: StatefulRule, RemovableAttribute {
    typealias Value = [ViewResponder]

    enum CoordinateSpaceStorage {
        case eager(CoordinateSpace)
        case lazy(Attribute<CoordinateSpace>)

        var value: CoordinateSpace {
            switch self {
            case .eager(let value): value
            case .lazy(let value): value.value
            }
        }
    }

    var responder: HoverResponder
    var coordinateSpace: CoordinateSpaceStorage
    var _callback: Attribute<HoverCallback>
    var _children: Attribute<[ViewResponder]>
    var _position: Attribute<CGPoint>
    var _transform: Attribute<ViewTransform>
    var _size: Attribute<ViewSize>
    var _isEnabled: Attribute<Bool>
    var _updateBindingManager: Attribute<Void>

    mutating func updateValue() {
        let isInitialValue = !context.hasValue
        let positionChanged = _AGGraph.currentStatefulInputChanged(
            _position.identifier
        )
        let transformChanged = _AGGraph.currentStatefulInputChanged(
            _transform.identifier
        )
        let sizeChanged = _AGGraph.currentStatefulInputChanged(_size.identifier)

        let position = _position.value
        let transform = _transform.value
        let size = _size.value
        if isInitialValue || positionChanged || transformChanged || sizeChanged {
            var resolvedTransform = transform
            resolvedTransform.appendPosition(position)
            responder.transform = resolvedTransform
            responder.size = size.value
        }

        let callbackChanged = _AGGraph.currentStatefulInputChanged(
            _callback.identifier
        )
        let callback = _callback.value
        if isInitialValue || callbackChanged {
            responder.callback = callback
        }
        responder.coordinateSpace = coordinateSpace.value
        responder.isEnabled = _isEnabled.value

        responder.helper.update(
            data: (value: TrivialContentResponder(), changed: false),
            size: (value: size, changed: sizeChanged),
            position: (value: position, changed: positionChanged),
            transform: (value: transform, changed: transformChanged),
            parent: responder
        )
        responder.updateChildren((
            value: _children.value,
            changed: _AGGraph.currentStatefulInputChanged(_children.identifier)
        ))
        if isInitialValue {
            _AGGraph.setStatefulOutput([responder])
        }
    }

    static func willRemove(attribute: AGAttribute) {
        guard let graph = _AGGraph.current else {
            fatalError("HoverResponderChild.willRemove called outside AG context")
        }
        var responder: HoverResponder?
        graph.mutateStatefulRule(attribute, as: Self.self) { rule in
            responder = rule.responder
        }
        guard let responder else { return }
        Update.enqueueAction {
            responder.updatePhase(.ended)
        }
    }

    struct UpdateBindingManagerChild: StatefulRule {
        typealias Value = Void

        var eventBindingManager: EventBindingManager
        var _position: Attribute<CGPoint>
        var _transform: Attribute<ViewTransform>
        var _size: Attribute<ViewSize>

        mutating func updateValue() {
            _ = _position.value
            _ = _transform.value
            _ = _size.value
            eventBindingManager.enqueueHoverUpdateIfNeeded()
        }
    }
}

private extension HoverPhase {
    var isActive: Bool {
        if case .active = self {
            return true
        }
        return false
    }
}

struct HoverEventDispatcher: ForwardedEventDispatcher {
    static var eventType: any EventType.Type { HoverEvent.self }

    private var bindings: [EventID: EventBinding] = [:]

    @discardableResult
    mutating func receiveEvents(
        _ events: [EventID: any EventType],
        manager: EventBindingManager
    ) -> Set<EventID> {
        guard let rootResponder = manager.host?.responderNode else { return [] }

        var consumed: Set<EventID> = []
        for (eventID, event) in events {
            guard let hoverEvent = event as? HoverEvent else { continue }

            let oldBinding = bindings[eventID]
            if hoverEvent.phase.isTerminal {
                if let oldBinding {
                    dispatchHoverCallbacks(
                        oldResponder: oldBinding.responder,
                        newResponder: nil,
                        point: hoverEvent.globalLocation
                    )
                    bindings.removeValue(forKey: eventID)
                    consumed.insert(eventID)
                }
                continue
            }

            let newResponder = rootResponder
                .bindEvent(hoverEvent)?
                .firstAncestor(ofType: HoverResponder.self)

            dispatchHoverCallbacks(
                oldResponder: oldBinding?.responder,
                newResponder: newResponder,
                point: hoverEvent.globalLocation
            )

            if let newResponder {
                bindings[eventID] = EventBinding(responder: newResponder)
            } else {
                bindings.removeValue(forKey: eventID)
            }
            if oldBinding != nil || newResponder != nil {
                consumed.insert(eventID)
            }
        }
        return consumed
    }

    mutating func reset() {
        bindings.removeAll()
    }

    private func hoverAncestors(
        from responder: ResponderNode?
    ) -> [HoverResponder] {
        guard let responder else { return [] }
        return responder.sequence.compactMap { $0 as? HoverResponder }
    }

    private func contains(
        _ point: CGPoint,
        responder: HoverResponder
    ) -> Bool {
        guard responder.isEnabled else { return false }
        var points = [point]
        responder.transform.convertGlobal(to: .local, points: &points)
        return CGRect(
            origin: .zero,
            size: responder.size
        ).contains(points[0])
    }

    private func phase(
        at point: CGPoint,
        responder: HoverResponder
    ) -> HoverPhase {
        var points = [point]
        responder.transform.convertGlobal(
            to: responder.coordinateSpace,
            points: &points
        )
        return .active(points[0])
    }

    private func dispatchHoverCallbacks(
        oldResponder: ResponderNode?,
        newResponder: ResponderNode?,
        point: CGPoint
    ) {
        let oldAncestors = hoverAncestors(from: oldResponder)
        let newAncestors = hoverAncestors(from: newResponder).filter {
            contains(point, responder: $0)
        }

        var commonSuffixCount = 0
        while commonSuffixCount < oldAncestors.count,
              commonSuffixCount < newAncestors.count {
            let old = oldAncestors[oldAncestors.count - commonSuffixCount - 1]
            let new = newAncestors[newAncestors.count - commonSuffixCount - 1]
            guard old === new else { break }
            commonSuffixCount += 1
        }

        let oldOnlyCount = oldAncestors.count - commonSuffixCount
        if oldOnlyCount > 0 {
            for responder in oldAncestors[..<oldOnlyCount] {
                responder.updatePhase(.ended)
            }
        }

        for responder in newAncestors {
            responder.updatePhase(phase(at: point, responder: responder))
        }
    }
}

public struct _HoverRegionModifier: ViewModifier, MultiViewModifier, PrimitiveViewModifier {
    public let callback: (Bool) -> Void

    @inlinable public init(_ callback: @escaping (Bool) -> Void) {
        self.callback = callback
    }

    struct Callback: Rule {
        var _modifier: Attribute<_HoverRegionModifier>

        var value: HoverCallback {
            .nonSpatial(_modifier.value.callback)
        }
    }

    struct HoverBehavior: Rule {
        var _modifier: Attribute<_HoverRegionModifier>

        var value: (inout PlatformItemList) -> Void {
            let callback = _modifier.value.callback
            return { list in
                var item = list.mergedContentItem
                item.onHover = callback
                list = PlatformItemList(items: [item])
            }
        }
    }

    public static func _makeView(
        modifier: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("_HoverRegionModifier._makeView called outside AG context")
        }

        var outputs = body(_Graph(), inputs)
        if let eventBindingManager = EventBindingManager.current,
           inputs.preferences.keys.contains(ViewRespondersKey.self) {
            let innerResponderNodes = outputs.preferences.values(
                for: ViewRespondersKey.self
            )
            let innerRespondersAttr: Attribute<[ViewResponder]>
            if innerResponderNodes.isEmpty {
                innerRespondersAttr = graph.makeInput(value: [])
            } else if innerResponderNodes.count == 1 {
                innerRespondersAttr = Attribute<[ViewResponder]>(
                    innerResponderNodes[0]
                )
            } else {
                innerRespondersAttr = graph.makeRule {
                    var combined = ViewRespondersKey.defaultValue
                    for nodeID in innerResponderNodes {
                        let val = Attribute<[ViewResponder]>(nodeID).value
                        ViewRespondersKey.reduce(value: &combined) { val }
                    }
                    return combined
                }
            }

            let responder = HoverResponder(inputs: inputs)
            let callback: Attribute<HoverCallback> = graph.makeRule(
                Callback(_modifier: modifier._attribute)
            )
            let position = inputs.animatedPosition()
            let transform = inputs.transform
            let size = inputs.animatedSize()
            let isEnabled = inputs.isEnabled
            let updateBindingManager: Attribute<Void> = graph.makeStatefulRule(
                HoverResponderChild.UpdateBindingManagerChild(
                    eventBindingManager: eventBindingManager,
                    _position: position,
                    _transform: transform,
                    _size: size
                )
            )
            updateBindingManager.flags = .transactional

            let respondersAttr: Attribute<[ViewResponder]> =
                graph.makeStatefulRule(
                    HoverResponderChild(
                        responder: responder,
                        coordinateSpace: .eager(.local),
                        _callback: callback,
                        _children: innerRespondersAttr,
                        _position: position,
                        _transform: transform,
                        _size: size,
                        _isEnabled: isEnabled,
                        _updateBindingManager: updateBindingManager
                    )
                )
            respondersAttr.setFlags(.removable, mask: .removable)
            outputs.preferences.setValue(
                respondersAttr.identifier,
                for: ViewRespondersKey.self
            )
        }

        if inputs[PlatformItemListFlagsInput.self]
            .contains(SelectionPlatformItemListFlags.flags) {
            outputs.preferences.makePreferenceTransformer(
                inputs: inputs.preferences,
                key: PlatformItemList.Key.self,
                transform: graph.makeRule(
                    HoverBehavior(_modifier: modifier._attribute)
                )
            )
        }
        return outputs
    }
}

extension _HoverRegionModifier {
    public typealias Body = Never
}

struct SpatialHoverRegionModifier: ViewModifier, MultiViewModifier {
    let coordinateSpace: CoordinateSpace
    let callback: HoverCallback

    static func _makeView(
        modifier: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("SpatialHoverRegionModifier._makeView called outside AG context")
        }

        var outputs = body(_Graph(), inputs)
        guard let eventBindingManager = EventBindingManager.current,
              inputs.preferences.keys.contains(ViewRespondersKey.self) else {
            return outputs
        }

        let innerResponderNodes = outputs.preferences.values(
            for: ViewRespondersKey.self
        )
        let innerRespondersAttr: Attribute<[ViewResponder]>
        if innerResponderNodes.isEmpty {
            innerRespondersAttr = graph.makeInput(value: [])
        } else if innerResponderNodes.count == 1 {
            innerRespondersAttr = Attribute<[ViewResponder]>(innerResponderNodes[0])
        } else {
            innerRespondersAttr = graph.makeRule {
                var combined = ViewRespondersKey.defaultValue
                for nodeID in innerResponderNodes {
                    let val = Attribute<[ViewResponder]>(nodeID).value
                    ViewRespondersKey.reduce(value: &combined) { val }
                }
                return combined
            }
        }

        let responder = HoverResponder(inputs: inputs)
        let callback = modifier[\.callback]._attribute
        let coordinateSpace = HoverResponderChild.CoordinateSpaceStorage.lazy(
            modifier[\.coordinateSpace]._attribute
        )
        let position = inputs.animatedPosition()
        let transform = inputs.transform
        let size = inputs.animatedSize()
        let isEnabled = inputs.isEnabled
        let updateBindingManager: Attribute<Void> = graph.makeStatefulRule(
            HoverResponderChild.UpdateBindingManagerChild(
                eventBindingManager: eventBindingManager,
                _position: position,
                _transform: transform,
                _size: size
            )
        )
        updateBindingManager.flags = .transactional

        let respondersAttr: Attribute<[ViewResponder]> = graph.makeStatefulRule(
            HoverResponderChild(
                responder: responder,
                coordinateSpace: coordinateSpace,
                _callback: callback,
                _children: innerRespondersAttr,
                _position: position,
                _transform: transform,
                _size: size,
                _isEnabled: isEnabled,
                _updateBindingManager: updateBindingManager
            )
        )
        outputs.preferences.setValue(
            respondersAttr.identifier,
            for: ViewRespondersKey.self
        )
        return outputs
    }
}

extension SpatialHoverRegionModifier {
    typealias Body = Never
}

extension View {
    @inlinable
    public func onHover(perform action: @escaping (Bool) -> Void) -> some View {
        modifier(_HoverRegionModifier(action))
    }

    public func onContinuousHover(
        coordinateSpace: some CoordinateSpaceProtocol = .local,
        perform action: @escaping (HoverPhase) -> Void
    ) -> some View {
        modifier(SpatialHoverRegionModifier(
            coordinateSpace: coordinateSpace.coordinateSpace,
            callback: .spatial(action)
        ))
    }
}
