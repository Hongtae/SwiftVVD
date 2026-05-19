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
    private var isActive = false

    init(callback: @escaping (Bool) -> Void,
         transform: ViewTransform,
         size: ViewSize,
         isEnabled: Bool,
         innerResponders: [any ViewResponder]) {
        self.hitTestKey = _hoverResponderNextKey.withLock { key in
            defer { key &+= 1 }
            return key
        }
        self.callback = callback
        self.snapshotTransform = transform
        self.snapshotSize = size
        self.snapshotIsEnabled = isEnabled
        self.innerResponders = innerResponders
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
        let responder = HoverResponder(
            callback: modifier._attribute.value.callback,
            transform: inputs.transform.value,
            size: inputs.size.value,
            isEnabled: environmentAttr.value.isEnabled,
            innerResponders: innerRespondersAttr.value
        )
        graph.makeSideEffectRule { [weak responder] in
            guard let responder else { return }
            responder.callback = modifier._attribute.value.callback
            responder.snapshotTransform = inputs.transform.value
            responder.snapshotSize = inputs.size.value
            responder.snapshotIsEnabled = environmentAttr.value.isEnabled
            responder.innerResponders = innerRespondersAttr.value
        }

        // Install the responder preference surface and dispatch enter/exit from
        // WindowController.
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
