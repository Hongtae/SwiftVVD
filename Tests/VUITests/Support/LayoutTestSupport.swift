import Foundation
@testable import VUI

/// Closure-backed layout fixture used only to express focused test behavior.
///
/// Production layout computers intentionally use concrete engine types. Keeping
/// this adapter in the test target prevents fixture convenience from expanding
/// the production dispatch surface.
struct TestClosureLayoutEngine: LayoutEngine {
    var sizeThatFitsBody: (_ProposedSize) -> CGSize
    var spacingValue: Spacing
    var placementBody: (CGPoint, UnitPoint, ProposedViewSize) -> Void
    var childGeometriesBody: (ViewSize, CGPoint) -> [ViewGeometry]
    var priority: Double
    var explicitAlignmentBody: ((AlignmentKey, ViewSize) -> CGFloat?)?

    func layoutPriority() -> Double {
        priority
    }

    mutating func spacing() -> Spacing {
        spacingValue
    }

    mutating func sizeThatFits(_ proposal: _ProposedSize) -> CGSize {
        sizeThatFitsBody(proposal)
    }

    mutating func childGeometries(
        at size: ViewSize,
        origin: CGPoint
    ) -> [ViewGeometry] {
        childGeometriesBody(size, origin)
    }

    mutating func explicitAlignment(
        _ key: AlignmentKey,
        at size: ViewSize
    ) -> CGFloat? {
        explicitAlignmentBody?(key, size)
    }
}

func testLayoutComputer(
    sizeThatFits: @escaping (_ProposedSize) -> CGSize,
    spacing: Spacing = Spacing(),
    place: @escaping (CGPoint, UnitPoint, ProposedViewSize) -> Void = { _, _, _ in },
    childGeometries: @escaping (ViewSize, CGPoint) -> [ViewGeometry] = { _, _ in [] },
    priority: Double = 0,
    explicitAlignment: ((AlignmentKey, ViewSize) -> CGFloat?)? = nil,
    seed: Int = 0
) -> LayoutComputer {
    var computer = LayoutComputer(
        TestClosureLayoutEngine(
            sizeThatFitsBody: sizeThatFits,
            spacingValue: spacing,
            placementBody: place,
            childGeometriesBody: childGeometries,
            priority: priority,
            explicitAlignmentBody: explicitAlignment
        )
    )
    computer.seed = seed
    return computer
}

extension LayoutComputer {
    /// Drives the current child-geometry pipeline from tests that previously
    /// invoked the removed renderer-placement callback directly.
    func place(
        at position: CGPoint,
        anchor: UnitPoint = .topLeading,
        proposal: ProposedViewSize
    ) {
        if let fixture = box as? LayoutEngineBox<TestClosureLayoutEngine> {
            fixture.engine.placementBody(position, anchor, proposal)
            return
        }

        let proposedSize = _ProposedSize(proposal)
        let measuredSize = sizeThatFits(proposedSize)
        let origin = CGPoint(
            x: position.x - measuredSize.width * anchor.x,
            y: position.y - measuredSize.height * anchor.y
        )
        _ = childGeometries(
            at: ViewSize(measuredSize, proposal: proposedSize),
            origin: origin
        )
    }
}
