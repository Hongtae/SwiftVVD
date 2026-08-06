//
//  File: LayoutComputer.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

protocol Defaultable {
    associatedtype Value
    static var defaultValue: Value { get }
}

struct DefaultRule<A: Defaultable>: Rule, AsyncAttribute, CustomStringConvertible {
    fileprivate var overrideValue: WeakAttribute<A.Value>

    init() {
        overrideValue = WeakAttribute()
    }

    static var initialValue: A.Value? { A.defaultValue }

    var weakValue: A.Value? {
        guard let graph = _AGGraph.current,
              overrideValue.isValid(in: graph) else {
            return nil
        }
        return overrideValue.toStrong().value
    }

    var value: A.Value { weakValue ?? A.defaultValue }

    var description: String { "∨ \(A.Value.self)" }
}

extension Attribute {
    func overrideDefaultValue<A: Defaultable>(
        _ value: Attribute<Value>?,
        type: A.Type
    ) where Value == A.Value {
        guard let graph = _AGGraph.current else {
            fatalError("Attribute.overrideDefaultValue(_:type:) called outside an active graph context.")
        }
        graph.mutateRule(identifier, as: DefaultRule<A>.self, invalidating: true) { rule in
            rule.overrideValue = value?.asWeak() ?? WeakAttribute()
        }
    }
}

/// Encapsulates a view's layout logic via a boxed layout engine.
struct LayoutComputer: Defaultable {
    var box: AnyLayoutEngineBox
    var seed: Int

    // MARK: - Forwarding methods

    func sizeThatFits(_ proposal: _ProposedSize) -> CGSize {
        box.sizeThatFits(proposal)
    }

    func lengthThatFits(_ proposal: _ProposedSize, in axis: Axis) -> CGFloat {
        box.lengthThatFits(proposal, in: axis)
    }

    func spacing() -> Spacing { box.spacing() }
    func layoutPriority() -> Double { box.layoutPriority() }
    func ignoresAutomaticPadding() -> Bool { box.ignoresAutomaticPadding() }
    func requiresSpacingProjection() -> Bool { box.requiresSpacingProjection() }

    /// Returns layout dimensions for the given proposal.
    /// Creates ViewDimensions with self as guideComputer.
    /// The guideComputer is queried via ViewDimensions subscripts for explicit alignment guides.
    func dimensions(in proposal: _ProposedSize) -> ViewDimensions {
        let cgSize = sizeThatFits(proposal)
        return ViewDimensions(
            guideComputer: self,
            size: ViewSize(cgSize, proposal: proposal)
        )
    }

    func childGeometries(at size: ViewSize, origin: CGPoint) -> [ViewGeometry] {
        box.childGeometries(at: size, origin: origin)
    }

    func explicitAlignment(_ key: AlignmentKey, at size: ViewSize) -> CGFloat? {
        box.explicitAlignment(key, at: size)
    }

    func childPlacement(at size: ViewSize) -> _Placement {
        box.childPlacement(at: size)
    }

    func childPlacement(
        at size: ViewSize,
        placementContext: _PositionAwarePlacementContext
    ) -> _Placement {
        box.childPlacement(at: size, placementContext: placementContext)
    }

    // MARK: - Initializers

    init<Engine: LayoutEngine>(_ engine: Engine) {
        if LayoutTrace.recorder != nil {
            box = TracingLayoutEngineBox(engine)
        } else {
            box = LayoutEngineBox(engine)
        }
        seed = 0
    }

    /// Supplies proposal-derived fallback sizing when no concrete engine is connected.
    struct DefaultEngine: LayoutEngine {
        mutating func sizeThatFits(_ proposal: _ProposedSize) -> CGSize {
            proposal.fixingUnspecifiedDimensions()
        }

        mutating func lengthThatFits(
            _ proposal: _ProposedSize,
            in axis: Axis
        ) -> CGFloat {
            let size = proposal.fixingUnspecifiedDimensions()
            return axis == .horizontal ? size.width : size.height
        }

        mutating func childGeometries(
            at size: ViewSize,
            origin: CGPoint
        ) -> [ViewGeometry] {
            []
        }
    }

    nonisolated(unsafe) private static let _defaultValue =
        LayoutComputer(DefaultEngine())

    static var defaultValue: LayoutComputer { _defaultValue }
}

extension LayoutComputer: Equatable {
    static func == (lhs: LayoutComputer, rhs: LayoutComputer) -> Bool {
        lhs.box === rhs.box && lhs.seed == rhs.seed
    }
}

extension LayoutComputer {
    mutating func withMutableEngine<Engine: LayoutEngine, Result>(
        type: Engine.Type,
        do body: (inout Engine) -> Result
    ) -> Result {
        box.mutateEngine(as: type, do: body)
    }
}
