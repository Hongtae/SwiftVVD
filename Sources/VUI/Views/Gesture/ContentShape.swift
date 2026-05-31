//
//  File: ContentShape.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import Synchronization

// ContentShapeKinds

/// Specifies which interaction contexts a content shape applies to.
///
/// Raw values:
///   .interaction         = 1
///   .dragPreview         = 2
///   .contextMenuPreview  = 4
///   .hoverEffect         = 8
///   .accessibility       = 16 (renamed from focusEffect in later SDKs)
public struct ContentShapeKinds: OptionSet, Sendable {
    public var rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    /// Hit-testing for gesture recognizers (tap, drag, etc.).
    public static let interaction        = ContentShapeKinds(rawValue: 1 << 0)
    /// Shape used for drag-and-drop previews.
    public static let dragPreview        = ContentShapeKinds(rawValue: 1 << 1)
    /// Shape used for context menu previews.
    public static let contextMenuPreview = ContentShapeKinds(rawValue: 1 << 2)
    /// Shape used for hover effects.
    public static let hoverEffect        = ContentShapeKinds(rawValue: 1 << 3)
    /// Shape used for accessibility focus.
    public static let accessibility      = ContentShapeKinds(rawValue: 1 << 4)
}

// ContentShapeResponder

private let _contentShapeResponderNextKey = Mutex<UInt32>(0x80000000)

/// Path-based `ViewResponder` created by `_ContentShapeModifier._makeView`.
///
/// When hit, returns the inner responders (collected from the subtree below
/// the contentShape modifier) via `ContainsPointsResult.children`. The caller
/// (`MultiViewResponder.respondersContaining`) follows `children` recursively
/// to arrive at the concrete `GestureResponder` instances.
final class ContentShapeResponder<S: Shape>: ViewResponder {

    let hitTestKey: UInt32
    weak var nextResponder: ResponderNode?
    var gestureContainer: AnyObject? { nil }

    let shape: Attribute<S>
    let position: Attribute<CGPoint>
    let size: Attribute<ViewSize>
    let transform: Attribute<ViewTransform>
    let innerResponders: Attribute<[any ViewResponder]>
    let eoFill: Bool
    let kinds: ContentShapeKinds

    init(
        shape: Attribute<S>,
        position: Attribute<CGPoint>,
        size: Attribute<ViewSize>,
        transform: Attribute<ViewTransform>,
        innerResponders: Attribute<[any ViewResponder]>,
        eoFill: Bool,
        kinds: ContentShapeKinds
    ) {
        self.hitTestKey = _contentShapeResponderNextKey.withLock { key in
            defer { key &+= 1 }
            return key
        }
        self.shape = shape
        self.position = position
        self.size = size
        self.transform = transform
        self.innerResponders = innerResponders
        self.eoFill = eoFill
        self.kinds = kinds
    }

    func hitTestPolicy(options: ContainsPointsOptions) -> HitTestPolicy {
        .include
    }

    func containsGlobalPoints(
        _ points: [CGPoint],
        cacheKey: UInt32?,
        options: ContainsPointsOptions
    ) -> ContainsPointsResult {
        let sz = size.value.value
        let t = transform.value
        var localPts = Array(points.prefix(64))
        t.convertGlobal(to: .local, points: &localPts)
        let localBounds = CGRect(origin: .zero, size: sz)
        let shapePath = shape.value.path(in: localBounds)

        var mask: UInt64 = 0
        for (i, localPt) in localPts.enumerated() {
            if shapePath.contains(localPt, eoFill: eoFill) {
                mask |= (1 << i)
            }
        }

        guard mask != 0 else { return .stop }
        return ContainsPointsResult(mask: mask, priority: 0, children: innerResponders.value)
    }
}

// _ContentShapeModifier

/// View modifier that overrides the hit-test region for gesture interactions.
/// Implicitly uses `.interaction` kind.
///
/// Created by `View.contentShape(_:eoFill:)`.
public struct _ContentShapeModifier<S: Shape>: ViewModifier, PrimitiveViewModifier {
    public var shape: S
    public var eoFill: Bool

    public init(shape: S, eoFill: Bool) {
        self.shape = shape
        self.eoFill = eoFill
    }

    public typealias Body = Never

    public static func _makeView(
        modifier: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        guard let graph = AttributeGraph.current else {
            fatalError("_ContentShapeModifier._makeView requires AG context")
        }

        var outputs = body(_Graph(), inputs)

        // Only active when ViewRespondersKey is in the preference keys (gesture-enabled pass).
        guard inputs.preferences.keys.contains(ViewRespondersKey.self) else { return outputs }

        // Collect inner ViewRespondersKey nodes from body outputs.
        let innerNodes = outputs.preferences.values(for: ViewRespondersKey.self)
        guard !innerNodes.isEmpty else { return outputs }

        // Build a combined attribute for all inner responders.
        let innerAttr: Attribute<[any ViewResponder]> = graph.makeRule {
            var combined: [any ViewResponder] = []
            for nodeID in innerNodes {
                let responders = Attribute<[any ViewResponder]>(nodeID).value
                combined.append(contentsOf: responders)
            }
            return combined
        }

        // Remove existing ViewRespondersKey entries; ContentShapeResponder replaces them.
        let keyID = ObjectIdentifier(ViewRespondersKey.self)
        outputs.preferences.preferences.removeAll(where: { ObjectIdentifier($0.key) == keyID })

        let responder = ContentShapeResponder(
            shape: modifier[\.shape]._attribute,
            position: inputs.position,
            size: inputs.size,
            transform: inputs.transform,
            innerResponders: innerAttr,
            eoFill: modifier._attribute.value.eoFill,
            kinds: .interaction
        )

        let respondersAttr: Attribute<[any ViewResponder]> = graph.makeInput(value: [responder])
        outputs.preferences.append(ViewRespondersKey.self, node: respondersAttr.identifier)

        return outputs
    }
}

// _ContentShapeKindModifier

/// View modifier that overrides the hit-test region for specified interaction kinds.
///
/// Created by `View.contentShape(_:_:eoFill:)`.
public struct _ContentShapeKindModifier<S: Shape>: ViewModifier, PrimitiveViewModifier {
    public var shape: S
    public var eoFill: Bool
    public var kind: ContentShapeKinds

    public init(shape: S, eoFill: Bool, kind: ContentShapeKinds) {
        self.shape = shape
        self.eoFill = eoFill
        self.kind = kind
    }

    public typealias Body = Never

    public static func _makeView(
        modifier: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        guard let graph = AttributeGraph.current else {
            fatalError("_ContentShapeKindModifier._makeView requires AG context")
        }

        var outputs = body(_Graph(), inputs)

        guard inputs.preferences.keys.contains(ViewRespondersKey.self) else { return outputs }

        let kinds = modifier._attribute.value.kind

        // Only wire a ContentShapeResponder when the kind includes .interaction.
        // Other kinds (dragPreview, contextMenuPreview, etc.) would go through
        // ContentShapePathData preference; not yet implemented.
        guard kinds.contains(.interaction) else { return outputs }

        let innerNodes = outputs.preferences.values(for: ViewRespondersKey.self)
        guard !innerNodes.isEmpty else { return outputs }

        let innerAttr: Attribute<[any ViewResponder]> = graph.makeRule {
            var combined: [any ViewResponder] = []
            for nodeID in innerNodes {
                let responders = Attribute<[any ViewResponder]>(nodeID).value
                combined.append(contentsOf: responders)
            }
            return combined
        }

        let keyID = ObjectIdentifier(ViewRespondersKey.self)
        outputs.preferences.preferences.removeAll(where: { ObjectIdentifier($0.key) == keyID })

        let responder = ContentShapeResponder(
            shape: modifier[\.shape]._attribute,
            position: inputs.position,
            size: inputs.size,
            transform: inputs.transform,
            innerResponders: innerAttr,
            eoFill: modifier._attribute.value.eoFill,
            kinds: kinds
        )

        let respondersAttr: Attribute<[any ViewResponder]> = graph.makeInput(value: [responder])
        outputs.preferences.append(ViewRespondersKey.self, node: respondersAttr.identifier)

        return outputs
    }
}

// View Extensions

extension View {
    /// Defines a custom shape to use for hit-testing gesture interactions.
    ///
    /// - Parameters:
    ///   - shape: The shape to use for hit testing.
    ///   - eoFill: When `true`, uses even-odd fill rule for path containment.
    public func contentShape<S: Shape>(_ shape: S, eoFill: Bool = false) -> some View {
        modifier(_ContentShapeModifier(shape: shape, eoFill: eoFill))
    }

    /// Defines a custom shape to use for the specified interaction kinds.
    ///
    /// - Parameters:
    ///   - kind: The interaction kinds to which the shape applies.
    ///   - shape: The shape to use for the specified kinds.
    ///   - eoFill: When `true`, uses even-odd fill rule for path containment.
    public func contentShape<S: Shape>(
        _ kind: ContentShapeKinds,
        _ shape: S,
        eoFill: Bool = false
    ) -> some View {
        modifier(_ContentShapeKindModifier(shape: shape, eoFill: eoFill, kind: kind))
    }
}
