//
//  File: LayoutComputer.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

/// Protocol satisfied by types that provide a static default value.
protocol Defaultable {
    static var defaultValue: Self { get }
}

/// Encapsulates a view's layout logic via a reference to a LayoutEngineBox.
/// Dispatch goes through the LayoutEngineBox vtable (class dispatch).
struct LayoutComputer {
    /// The boxed layout engine. Holds a LayoutEngineBox<E> for some concrete E.
    /// Typed as any _AnyLayoutEngineBoxDispatch (class-bound existential = 8 bytes).
    var box: any _AnyLayoutEngineBoxDispatch

    /// Monotonically increasing counter; incremented each time the engine value changes.
    /// Used for equality testing and AG dependency tracking.
    var changeCount: UInt

    // MARK: - Forwarding methods

    func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        box.sizeThatFits_(proposal)
    }

    var spacing: ViewSpacing { box.spacing_() }
    var priority: Double { box.layoutPriority_() }

    /// Returns layout dimensions for the given proposal.
    /// Creates ViewDimensions with self as guideComputer.
    /// The guideComputer is queried via ViewDimensions subscripts for explicit alignment guides.
    func dimensions(in proposal: ProposedViewSize) -> ViewDimensions {
        let cgSize = sizeThatFits(proposal)
        return ViewDimensions(
            guideComputer: self,
            size: ViewSize(cgSize, proposal: proposal)
        )
    }

    func explicitAlignment(_ key: AlignmentKey, at size: ViewSize) -> CGFloat? {
        box.explicitAlignment_(key, at: size)
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
        sizeThatFits: @escaping (ProposedViewSize) -> CGSize,
        spacing: ViewSpacing = ViewSpacing(),
        place: @escaping (CGPoint, UnitPoint, ProposedViewSize) -> Void = { _, _, _ in },
        priority: Double = 0,
        explicitAlignment: ((AlignmentKey, ViewSize) -> CGFloat?)? = nil
    ) {
        let engine = ClosureLayoutEngine(
            sizeThatFits: sizeThatFits,
            spacing: spacing,
            place: place,
            priority: priority,
            explicitAlignment: explicitAlignment
        )
        self.box = LayoutEngineBox(engine: engine)
        self.changeCount = 0
    }

    init(box: some _AnyLayoutEngineBoxDispatch, changeCount: UInt = 0) {
        self.box = box
        self.changeCount = changeCount
    }

    // MARK: - Static helpers

    static func fixed(_ size: CGSize) -> LayoutComputer {
        LayoutComputer(sizeThatFits: { _ in size })
    }

    // Stored once because LayoutComputer.defaultValue contains a reference type.
    nonisolated(unsafe) private static let _defaultValue = LayoutComputer(sizeThatFits: { _ in .zero })

    static var defaultValue: LayoutComputer { _defaultValue }
}

extension LayoutComputer: Equatable {
    static func == (lhs: LayoutComputer, rhs: LayoutComputer) -> Bool {
        lhs.box === rhs.box && lhs.changeCount == rhs.changeCount
    }
}
