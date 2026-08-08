//
//  File: CachedEnvironment.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

/// Shared environment cache passed down the view tree via `_GraphInputs`.
/// Copying `_GraphInputs` preserves the same `CachedEnvironment` reference
/// (via `MutableBox`) so all descendants share a single environment Attribute.
struct CachedEnvironment {

    struct ID: Equatable {
        var base: UniqueID
    }

    struct MapItem {
        var key: ID
        var value: AGAttribute
    }

    struct AnimatedFrame {
        var position:          Attribute<CGPoint>
        var size:              Attribute<ViewSize>
        var pixelLength:       Attribute<CGFloat>
        var time:              Attribute<Time>
        var transaction:       Attribute<Transaction>
        var viewPhase:         Attribute<_GraphInputs.Phase>
        var animatedFrame:     Attribute<ViewFrame>
        var _animatedPosition: Attribute<CGPoint>?
        var _animatedSize:     Attribute<ViewSize>?
        var _animatedCGSize:   Attribute<CGSize>?
    }

    /// The live `EnvironmentValues` AG node.
    /// Reading `.value` inside a rule registers a dependency so the rule
    /// re-evaluates automatically when the environment changes.
    var environment: Attribute<EnvironmentValues>

    /// Style-map items threaded through the environment cache.
    var mapItems: [MapItem]

    /// Per-frame animation layout snapshot.
    /// Nil until layout AG nodes are wired. Animation modifiers read from here.
    var animatedFrame: AnimatedFrame?

    /// Resolved shape-style attributes shared by leaves with the same graph
    /// inputs and rendering role.
    var resolvedShapeStyles: [ResolvedShapeStyles: Attribute<_ShapeStyle_Pack>]

    /// Platform-specific renderer cache (e.g. Metal layer reference).
    var platformCache: Any?

    init(environment: Attribute<EnvironmentValues>) {
        self.environment = environment
        self.mapItems = []
        self.animatedFrame = nil
        self.resolvedShapeStyles = [:]
        self.platformCache = nil
    }

    func replacingEnvironment(_ environment: Attribute<EnvironmentValues>) -> CachedEnvironment {
        var copy = CachedEnvironment(environment: environment)
        copy.animatedFrame = animatedFrame
        return copy
    }

    mutating func attribute<Value>(
        id: ID,
        _ value: @escaping (EnvironmentValues) -> Value
    ) -> Attribute<Value> {
        if let item = mapItems.first(where: { $0.key == id }) {
            return Attribute<Value>(item.value)
        }
        guard let graph = _AGGraph.current else {
            fatalError("CachedEnvironment.attribute(id:_:) called outside an active _AGGraph context.")
        }
        let environment = environment
        let attribute = graph.makeRule {
            value(environment.value)
        }
        mapItems.append(MapItem(key: id, value: attribute.identifier))
        return attribute
    }

    mutating func resolvedShapeStyles(
        for inputs: _ViewInputs,
        role: ShapeRole,
        mode: Attribute<_ShapeStyle_ResolverMode>? = nil
    ) -> Attribute<_ShapeStyle_Pack> {
        guard inputs.preferences.keys.contains(DisplayList.Key.self) else {
            return GraphHost.currentHost.intern(
                _ShapeStyle_Pack(),
                for: _ShapeStyle_Pack.self,
                id: .defaultValue
            )
        }

        let key = ResolvedShapeStyles(
            environment: environment,
            time: inputs.base.time,
            transaction: inputs.base.transaction,
            viewPhase: inputs.base.phase,
            mode: OptionalAttribute(mode),
            role: role,
            substrate: nil,
            animationsDisabled: inputs.base.options.contains(
                .animationsDisabled
            )
        )
        if let cached = resolvedShapeStyles[key] {
            return cached
        }
        let styles = key.makeStyles()
        resolvedShapeStyles[key] = styles
        return styles
    }
}

extension CachedEnvironment.ID {
    static let pixelLength = CachedEnvironment.ID(base: UniqueID())
}

struct ResolvedShapeStyles: Hashable {
    var environment: Attribute<EnvironmentValues>
    var time: Attribute<Time>
    var transaction: Attribute<Transaction>
    var viewPhase: Attribute<_GraphInputs.Phase>
    var mode: OptionalAttribute<_ShapeStyle_ResolverMode>
    var role: ShapeRole
    var substrate: _ShapeStyle_Substrate?
    var animationsDisabled: Bool

    func makeStyles() -> Attribute<_ShapeStyle_Pack> {
        guard let graph = _AGGraph.current else {
            fatalError(
                "ResolvedShapeStyles.makeStyles called outside an active " +
                    "_AGGraph context."
            )
        }
        let resolver = ShapeStyleResolver<AnyShapeStyle>(
            style: OptionalAttribute(),
            mode: mode,
            environment: environment,
            role: role,
            substrate: substrate,
            animationsDisabled: animationsDisabled,
            helper: AnimatableAttributeHelper(
                _phase: viewPhase,
                _time: time,
                _transaction: transaction
            )
        )
        let styles = graph.makeStatefulRule(resolver)
        styles.flags = .transactional
        return styles
    }
}
