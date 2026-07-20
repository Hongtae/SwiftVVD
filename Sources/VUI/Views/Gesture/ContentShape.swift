//
//  File: ContentShape.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
// ContentShapeKinds

/// Specifies which interaction contexts a content shape applies to.
///
/// Raw values:
///   .interaction         = 1
///   .dragPreview         = 2
///   .contextMenuPreview  = 4
///   .hoverEffect         = 8
///   .focusEffect         = 16
///   .accessibility       = 64
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
    /// Shape used for focus effects.
    public static let focusEffect        = ContentShapeKinds(rawValue: 1 << 4)
    /// Shape used for accessibility focus.
    public static let accessibility      = ContentShapeKinds(rawValue: 1 << 6)
}

// Content responder core

protocol ContentResponder {
    func contains(points: UnsafeBufferPointer<CGPoint>, size: CGSize) -> BitVector64
    func contentPath(size: CGSize) -> Path
    func contentPath(size: CGSize, kind: ContentShapeKinds) -> Path
}

extension ContentResponder {
    func contentPath(size: CGSize) -> Path {
        Path(CGRect(origin: .zero, size: size))
    }

    func contains(points: UnsafeBufferPointer<CGPoint>, size: CGSize) -> BitVector64 {
        let path = contentPath(size: size)
        var result = BitVector64()
        for (index, point) in points.prefix(64).enumerated() {
            result[index] = path.contains(point)
        }
        return result
    }

    func contentPath(size: CGSize, kind: ContentShapeKinds) -> Path {
        contentPath(size: size)
    }
}

struct ContentResponderHelper<Data: ContentResponder> {
    var size: CGSize
    var data: Data?
    var transform: ViewTransform
    var observers: ContentPathObservers
    var cache: ViewResponder.ContainsPointsCache

    init() {
        size = .zero
        data = nil
        transform = ViewTransform()
        observers = ContentPathObservers()
        cache = ViewResponder.ContainsPointsCache()
    }

    mutating func update(
        data: (value: Data, changed: Bool),
        size: (value: ViewSize, changed: Bool),
        position: (value: CGPoint, changed: Bool),
        transform: (value: ViewTransform, changed: Bool),
        parent: ViewResponder
    ) {
        let changed = data.changed || size.changed || position.changed || transform.changed
        if data.changed || self.data == nil {
            self.data = data.value
        }
        if size.changed || self.size == .zero {
            self.size = size.value.value
        }
        if position.changed || transform.changed || self.transform.isEmpty {
            var resolvedTransform = transform.value
            resolvedTransform.appendPosition(position.value)
            self.transform = resolvedTransform
        }
        if changed {
            cache = ViewResponder.ContainsPointsCache()
            var finished = false
            let currentObservers = observers.takeObservers()
            for observer in currentObservers {
                observer.contentPathDidChange(
                    for: parent,
                    changes: [.data, .size, .transform],
                    transform: (old: self.transform, new: self.transform),
                    finished: &finished
                )
            }
        }
    }

    mutating func containsGlobalPoints(
        _ points: [CGPoint],
        cacheKey: UInt32?,
        options: ViewResponder.ContainsPointsOptions,
        children: [ViewResponder]
    ) -> ViewResponder.ContainsPointsResult {
        cache.fetch(key: cacheKey) {
            guard let data else {
                return .stop
            }
            var localPoints = Array(points.prefix(64))
            transform.convertGlobal(to: .local, points: &localPoints)
            let mask = localPoints.withUnsafeBufferPointer {
                data.contains(points: $0, size: size)
            }
            return ViewResponder.ContainsPointsResult(
                mask: mask,
                priority: 0,
                children: children
            )
        }
    }

    mutating func addContentPath(
        to path: inout Path,
        kind: ContentShapeKinds,
        in coordinateSpace: CoordinateSpace,
        observer: (any ContentPathObserver)?
    ) {
        guard let data else { return }
        if let observer {
            observers.add(observer: observer)
        }
        path.addPath(data.contentPath(size: size, kind: kind))
    }

    var globalPosition: CGPoint {
        var points = [CGPoint.zero]
        transform.convertGlobal(from: .local, points: &points)
        return points[0]
    }
}

class LeafViewResponder<Data: ContentResponder>: ViewResponder {
    var helper = ContentResponderHelper<Data>()

    override func containsGlobalPoints(
        _ points: [CGPoint],
        cacheKey: UInt32?,
        options: ViewResponder.ContainsPointsOptions
    ) -> ViewResponder.ContainsPointsResult {
        guard hitTestPolicy(options: options) != .exclude else {
            return .stop
        }
        return helper.containsGlobalPoints(
            points,
            cacheKey: cacheKey,
            options: options,
            children: []
        )
    }

    override func addContentPath(
        to path: inout Path,
        kind: ContentShapeKinds,
        in coordinateSpace: CoordinateSpace,
        observer: (any ContentPathObserver)?
    ) {
        helper.addContentPath(
            to: &path,
            kind: kind,
            in: coordinateSpace,
            observer: observer
        )
    }

    override func addObserver(_ observer: any ContentPathObserver) {
        helper.observers.add(observer: observer)
    }
}

// ContentShapeResponder

final class ContentShapeResponder<S: Shape>: DefaultLayoutViewResponder {
    var helper = ContentResponderHelper<_ContentShapeModifier<S>>()

    override func hitTestPolicy(
        options: ViewResponder.ContainsPointsOptions
    ) -> ViewResponder.HitTestPolicy {
        .include
    }

    override func containsGlobalPoints(
        _ points: [CGPoint],
        cacheKey: UInt32?,
        options: ViewResponder.ContainsPointsOptions
    ) -> ViewResponder.ContainsPointsResult {
        let inherited = super.containsGlobalPoints(
            points,
            cacheKey: cacheKey,
            options: options
        )
        var result = helper.containsGlobalPoints(
            points,
            cacheKey: cacheKey,
            options: options,
            children: children
        )
        result.priority = max(result.priority, inherited.priority)
        return result
    }

    override func addContentPath(
        to path: inout Path,
        kind: ContentShapeKinds,
        in coordinateSpace: CoordinateSpace,
        observer: (any ContentPathObserver)?
    ) {
        helper.addContentPath(
            to: &path,
            kind: kind,
            in: coordinateSpace,
            observer: observer
        )
    }
}

struct ContentShapeResponderFilter<S: Shape>: StatefulRule {
    typealias Value = [ViewResponder]

    var _modifier: Attribute<_ContentShapeModifier<S>>
    var _position: Attribute<CGPoint>
    var _size: Attribute<ViewSize>
    var _transform: Attribute<ViewTransform>
    var _children: Attribute<[ViewResponder]>
    var inputs: _ViewInputs
    var viewSubgraph: AGSubgraph
    var _responder: ContentShapeResponder<S>?

    mutating func updateValue() {
        if _responder == nil {
            _responder = AGSubgraph.withCurrent(viewSubgraph) {
                ContentShapeResponder<S>(inputs: inputs, viewSubgraph: viewSubgraph)
            }
        }
        guard let responder = _responder else {
            fatalError("ContentShapeResponderFilter failed to create its responder")
        }
        responder.helper.update(
            data: (
                value: _modifier.value,
                changed: _AGGraph.currentStatefulInputChanged(_modifier.identifier)
            ),
            size: (
                value: _size.value,
                changed: _AGGraph.currentStatefulInputChanged(_size.identifier)
            ),
            position: (
                value: _position.value,
                changed: _AGGraph.currentStatefulInputChanged(_position.identifier)
            ),
            transform: (
                value: _transform.value,
                changed: _AGGraph.currentStatefulInputChanged(_transform.identifier)
            ),
            parent: responder
        )
        if _AGGraph.currentStatefulInputChanged(_children.identifier) || !context.hasValue {
            responder.children = _children.value
        }
        if !context.hasValue {
            _AGGraph.setStatefulOutput([responder])
        }
    }
}

final class ContentShapeKindResponder<S: Shape>: DefaultLayoutViewResponder {
    var kind: ContentShapeKinds = []
    var helper = ContentResponderHelper<_ContentShapeKindModifier<S>>()

    override func hitTestPolicy(
        options: ViewResponder.ContainsPointsOptions
    ) -> ViewResponder.HitTestPolicy {
        .include
    }

    override func containsGlobalPoints(
        _ points: [CGPoint],
        cacheKey: UInt32?,
        options: ViewResponder.ContainsPointsOptions
    ) -> ViewResponder.ContainsPointsResult {
        guard kind.contains(.interaction) else {
            return super.containsGlobalPoints(points, cacheKey: cacheKey, options: options)
        }
        let inherited = super.containsGlobalPoints(points, cacheKey: cacheKey, options: options)
        var result = helper.containsGlobalPoints(
            points,
            cacheKey: cacheKey,
            options: options,
            children: children
        )
        result.priority = max(result.priority, inherited.priority)
        return result
    }

    override func addContentPath(
        to path: inout Path,
        kind: ContentShapeKinds,
        in coordinateSpace: CoordinateSpace,
        observer: (any ContentPathObserver)?
    ) {
        helper.addContentPath(
            to: &path,
            kind: kind,
            in: coordinateSpace,
            observer: observer
        )
    }
}

struct ContentShapeKindResponderFilter<S: Shape>: StatefulRule {
    typealias Value = [ViewResponder]

    var _modifier: Attribute<_ContentShapeKindModifier<S>>
    var _position: Attribute<CGPoint>
    var _size: Attribute<ViewSize>
    var _transform: Attribute<ViewTransform>
    var _children: Attribute<[ViewResponder]>
    var responder: ContentShapeKindResponder<S>

    mutating func updateValue() {
        let modifier = _modifier.value
        responder.helper.update(
            data: (
                value: modifier,
                changed: _AGGraph.currentStatefulInputChanged(_modifier.identifier)
            ),
            size: (
                value: _size.value,
                changed: _AGGraph.currentStatefulInputChanged(_size.identifier)
            ),
            position: (
                value: _position.value,
                changed: _AGGraph.currentStatefulInputChanged(_position.identifier)
            ),
            transform: (
                value: _transform.value,
                changed: _AGGraph.currentStatefulInputChanged(_transform.identifier)
            ),
            parent: responder
        )
        responder.kind = modifier.kind
        if _AGGraph.currentStatefulInputChanged(_children.identifier) || !context.hasValue {
            responder.children = _children.value
        }
        if !context.hasValue {
            _AGGraph.setStatefulOutput([responder])
        }
    }
}

// _ContentShapeModifier

/// View modifier that overrides the hit-test region for gesture interactions.
/// Implicitly uses `.interaction` kind.
///
/// Created by `View.contentShape(_:eoFill:)`.
public struct _ContentShapeModifier<S: Shape>: MultiViewModifier, PrimitiveViewModifier, ContentResponder {
    public var shape: S
    public var eoFill: Bool

    public init(shape: S, eoFill: Bool) {
        self.shape = shape
        self.eoFill = eoFill
    }

    public typealias Body = Never

    func contains(points: UnsafeBufferPointer<CGPoint>, size: CGSize) -> BitVector64 {
        let path = contentPath(size: size)
        var result = BitVector64()
        for (index, point) in points.prefix(64).enumerated() {
            result[index] = path.contains(point, eoFill: eoFill)
        }
        return result
    }

    func contentPath(size: CGSize) -> Path {
        shape.path(in: CGRect(origin: .zero, size: size))
    }

    func contentPath(size: CGSize, kind: ContentShapeKinds) -> Path {
        contentPath(size: size)
    }

    public static func _makeView(
        modifier: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("_ContentShapeModifier._makeView requires AG context")
        }

        var outputs = body(_Graph(), inputs)

        guard inputs.preferences.keys.contains(ViewRespondersKey.self) else { return outputs }

        let innerNodes = outputs.preferences.values(for: ViewRespondersKey.self)
        let innerAttr: Attribute<[ViewResponder]>
        if innerNodes.isEmpty {
            innerAttr = graph.makeInput(value: [])
        } else {
            innerAttr = graph.makeRule {
                var combined: [ViewResponder] = []
                for nodeID in innerNodes {
                    combined.append(contentsOf: Attribute<[ViewResponder]>(nodeID).value)
                }
                return combined
            }
        }

        let keyID = ObjectIdentifier(ViewRespondersKey.self)
        outputs.preferences.preferences.removeAll(where: { ObjectIdentifier($0.key) == keyID })
        guard let viewSubgraph = AGSubgraph.current else {
            fatalError("_ContentShapeModifier._makeView requires a current AGSubgraph")
        }
        let respondersAttr = graph.makeStatefulRule(
            ContentShapeResponderFilter(
                _modifier: modifier._attribute,
                _position: inputs.position,
                _size: inputs.size,
                _transform: inputs.transform,
                _children: innerAttr,
                inputs: inputs,
                viewSubgraph: viewSubgraph,
                _responder: nil
            )
        )
        outputs.preferences.append(ViewRespondersKey.self, node: respondersAttr.identifier)

        return outputs
    }
}

// _ContentShapeKindModifier

/// View modifier that overrides the hit-test region for specified interaction kinds.
///
/// Created by `View.contentShape(_:_:eoFill:)`.
public struct _ContentShapeKindModifier<S: Shape>: MultiViewModifier, PrimitiveViewModifier, ContentResponder {
    public var shape: S
    public var eoFill: Bool
    public var kind: ContentShapeKinds

    public init(shape: S, eoFill: Bool, kind: ContentShapeKinds) {
        self.shape = shape
        self.eoFill = eoFill
        self.kind = kind
    }

    public typealias Body = Never

    func contains(points: UnsafeBufferPointer<CGPoint>, size: CGSize) -> BitVector64 {
        guard kind.contains(.interaction) else { return [] }
        let path = contentPath(size: size)
        var result = BitVector64()
        for (index, point) in points.prefix(64).enumerated() {
            result[index] = path.contains(point, eoFill: eoFill)
        }
        return result
    }

    func contentPath(size: CGSize) -> Path {
        guard kind.contains(.interaction) else { return Path() }
        return shape.path(in: CGRect(origin: .zero, size: size))
    }

    func contentPath(size: CGSize, kind requestedKind: ContentShapeKinds) -> Path {
        guard !kind.intersection(requestedKind).isEmpty else { return Path() }
        return shape.path(in: CGRect(origin: .zero, size: size))
    }

    public static func _makeView(
        modifier: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("_ContentShapeKindModifier._makeView requires AG context")
        }

        var outputs = body(_Graph(), inputs)

        guard inputs.preferences.keys.contains(ViewRespondersKey.self) else { return outputs }

        let innerNodes = outputs.preferences.values(for: ViewRespondersKey.self)
        let innerAttr: Attribute<[ViewResponder]>
        if innerNodes.isEmpty {
            innerAttr = graph.makeInput(value: [])
        } else {
            innerAttr = graph.makeRule {
                var combined: [ViewResponder] = []
                for nodeID in innerNodes {
                    combined.append(contentsOf: Attribute<[ViewResponder]>(nodeID).value)
                }
                return combined
            }
        }

        let keyID = ObjectIdentifier(ViewRespondersKey.self)
        outputs.preferences.preferences.removeAll(where: { ObjectIdentifier($0.key) == keyID })
        guard let viewSubgraph = AGSubgraph.current else {
            fatalError("_ContentShapeKindModifier._makeView requires a current AGSubgraph")
        }
        let responder = ContentShapeKindResponder<S>(
            inputs: inputs,
            viewSubgraph: viewSubgraph
        )
        let respondersAttr = graph.makeStatefulRule(
            ContentShapeKindResponderFilter(
                _modifier: modifier._attribute,
                _position: inputs.position,
                _size: inputs.size,
                _transform: inputs.transform,
                _children: innerAttr,
                responder: responder
            )
        )
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
