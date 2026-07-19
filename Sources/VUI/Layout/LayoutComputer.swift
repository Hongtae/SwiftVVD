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
/// `changeCount` participates in equality and graph dependency tracking.
struct LayoutComputer: Defaultable {
    /// The boxed layout engine. Holds a LayoutEngineBox<E> for some concrete E.
    /// Typed as a class-bound layout-engine dispatch existential.
    var box: any _AnyLayoutEngineBoxDispatch

    /// Monotonically increasing counter; incremented each time the engine value changes.
    /// Used for equality testing and AG dependency tracking.
    var changeCount: UInt

    // MARK: - Forwarding methods

    func sizeThatFits(_ proposal: _ProposedSize) -> CGSize {
        box.sizeThatFits_(proposal)
    }

    func lengthThatFits(_ proposal: _ProposedSize, in axis: Axis) -> CGFloat {
        box.lengthThatFits_(proposal, in: axis)
    }

    func spacing() -> Spacing { box.spacing_() }
    func layoutPriority() -> Double { box.layoutPriority_() }
    func ignoresAutomaticPadding() -> Bool { box.ignoresAutomaticPadding_() }
    func requiresSpacingProjection() -> Bool { box.requiresSpacingProjection_() }

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
        box.childGeometries_(at: size, origin: origin)
    }

    func explicitAlignment(_ key: AlignmentKey, at size: ViewSize) -> CGFloat? {
        box.explicitAlignment_(key, at: size)
    }

    func childPlacement(at size: ViewSize) -> _Placement {
        box.childPlacement_(at: size)
    }

    func childPlacement(
        at size: ViewSize,
        placementContext: _PositionAwarePlacementContext
    ) -> _Placement {
        box.childPlacement_(at: size, placementContext: placementContext)
    }

    /// Places this view at position relative to anchor.
    /// Writes resolved origin/size into the child's AG position/size attributes.
    func place(at position: CGPoint,
               anchor: UnitPoint = .topLeading,
               proposal: ProposedViewSize) {
        box.place_(position, anchor, proposal)
    }

    // MARK: - Initializers

    init(
        sizeThatFits: @escaping (_ProposedSize) -> CGSize,
        spacing: Spacing = Spacing(),
        place: @escaping (CGPoint, UnitPoint, ProposedViewSize) -> Void = { _, _, _ in },
        childGeometries: @escaping (ViewSize, CGPoint) -> [ViewGeometry] = { _, _ in [] },
        priority: Double = 0,
        explicitAlignment: ((AlignmentKey, ViewSize) -> CGFloat?)? = nil,
        changeCount: UInt = 0
    ) {
        let engine = ClosureLayoutEngine(
            sizeThatFits: sizeThatFits,
            spacing: spacing,
            place: place,
            childGeometries: childGeometries,
            priority: priority,
            explicitAlignment: explicitAlignment
        )
        self.box = LayoutEngineBox(engine: engine)
        self.changeCount = changeCount
    }

    init(box: some _AnyLayoutEngineBoxDispatch, changeCount: UInt = 0) {
        self.box = box
        self.changeCount = changeCount
    }

    // MARK: - Static helpers

    static func fixed(_ size: CGSize) -> LayoutComputer {
        LayoutComputer(sizeThatFits: { _ in size })
    }

    // Shared zero-size sentinel used by layout proxy and subview fallback paths.
    nonisolated(unsafe) private static let _defaultValue = LayoutComputer(sizeThatFits: { _ in .zero })

    static var defaultValue: LayoutComputer { _defaultValue }
}

extension LayoutComputer: Equatable {
    static func == (lhs: LayoutComputer, rhs: LayoutComputer) -> Bool {
        lhs.box === rhs.box && lhs.changeCount == rhs.changeCount
    }
}

extension LayoutComputer {
    mutating func withMutableEngine<Engine: LayoutEngine, Result>(
        type: Engine.Type,
        do body: (inout Engine) -> Result
    ) -> Result? {
        guard let box = box as? LayoutEngineBox<Engine> else {
            return nil
        }
        return body(&box.engine)
    }
}
