import XCTest
@testable import VUI

final class AnimatableValueSurfaceTests: XCTestCase {
    func testViewSizeAnimatableDataPreservesProposalMetadata() {
        let proposal = ProposedViewSize(width: 160, height: 34)
        var size = ViewSize(width: 80, height: 20, proposal: proposal)

        size.animatableData = CGSize(width: 120, height: 30).animatableData

        XCTAssertEqual(size.width, 120)
        XCTAssertEqual(size.height, 30)
        XCTAssertEqual(size.proposal, proposal)
    }

    func testAnimatableValuesPackOperationsMatchElementWiseSurface() {
        let direct = AnimatableValues(3.0, CGFloat(4.0))
        let typed = AnimatableValues(Double.self, CGFloat.self)
        let zero = AnimatableValues<Double, CGFloat>.zero
        let empty: AnimatableValues<> = _animatableMacroKind()

        XCTAssertEqual(MemoryLayout<AnimatableValues<Double, CGFloat>>.size, 16)
        XCTAssertEqual(MemoryLayout<AnimatableValues<>>.size, 0)
        XCTAssertEqual(MemoryLayout<AnimatableValues<>>.stride, 1)
        XCTAssertEqual(MemoryLayout<AnimatableValues<>>.alignment, 1)

        XCTAssertEqual(direct.magnitudeSquared, 25)
        XCTAssertEqual(typed, zero)
        XCTAssertEqual(direct, AnimatableValues(3.0, CGFloat(4.0)))
        XCTAssertNotEqual(direct, AnimatableValues(3.0, CGFloat(5.0)))

        var scaled = direct
        scaled.scale(by: 2)
        XCTAssertEqual(scaled, AnimatableValues(6.0, CGFloat(8.0)))
        XCTAssertEqual(scaled.magnitudeSquared, 100)

        XCTAssertEqual(direct + AnimatableValues(1.5, CGFloat(-1.0)),
                       AnimatableValues(4.5, CGFloat(3.0)))
        XCTAssertEqual(direct - AnimatableValues(1.5, CGFloat(-1.0)),
                       AnimatableValues(1.5, CGFloat(5.0)))
        XCTAssertEqual(empty.magnitudeSquared, 0)
    }

    func testAnyAnimatableDataUsesOwnerVTableForArithmeticAndUpdate() {
        var doubleData = AnyLayout(ProbeLayout(value: 3)).animatableData
        let otherDouble = AnyLayout(ProbeLayout(value: 2)).animatableData
        let pairData = AnyLayout(PairLayout(first: 1, second: 2)).animatableData
        let zero = _AnyAnimatableData.zero

        XCTAssertEqual(MemoryLayout<_AnyAnimatableData>.size, 40)
        XCTAssertEqual(MemoryLayout<_AnyAnimatableData>.stride, 40)
        XCTAssertEqual(MemoryLayout<_AnyAnimatableData>.alignment, 8)

        XCTAssertEqual(doubleData.magnitudeSquared, 9)
        XCTAssertEqual(otherDouble.magnitudeSquared, 4)
        XCTAssertEqual(pairData.magnitudeSquared, 5)
        XCTAssertEqual(zero.magnitudeSquared, 0)

        XCTAssertEqual((doubleData + otherDouble).magnitudeSquared, 25)
        XCTAssertEqual((doubleData - otherDouble).magnitudeSquared, 1)
        XCTAssertEqual((zero + doubleData).magnitudeSquared, 9)
        XCTAssertEqual((doubleData + zero).magnitudeSquared, 9)
        XCTAssertEqual((zero - doubleData).magnitudeSquared, 9)
        XCTAssertEqual((doubleData - zero).magnitudeSquared, 9)
        XCTAssertEqual((doubleData + pairData).magnitudeSquared, 9)
        XCTAssertEqual((doubleData - pairData).magnitudeSquared, 9)

        doubleData += otherDouble
        XCTAssertEqual(doubleData.magnitudeSquared, 25)
        doubleData -= otherDouble
        XCTAssertEqual(doubleData.magnitudeSquared, 9)
        doubleData.scale(by: -2)
        XCTAssertEqual(doubleData.magnitudeSquared, 36)

        XCTAssertEqual(zero, _AnyAnimatableData.zero)
        XCTAssertNotEqual(zero, AnyLayout(ProbeLayout(value: 0)).animatableData)
        XCTAssertNotEqual(doubleData, pairData)

        var targetLayout = AnyLayout(ProbeLayout(value: 0))
        targetLayout.animatableData = doubleData
        XCTAssertEqual((targetLayout.layout as? ProbeLayout)?.value, -6)

        var targetPairLayout = AnyLayout(PairLayout(first: 0, second: 0))
        targetPairLayout.animatableData = pairData
        let pair = targetPairLayout.layout as? PairLayout
        XCTAssertEqual(pair?.first, 1)
        XCTAssertEqual(pair?.second, 2)
    }

    func testAnyAnimatableDataZeroAndMismatchedSetAreNoOps() {
        let zero = _AnyAnimatableData.zero
        let pairData = AnyLayout(PairLayout(first: 1, second: 2)).animatableData

        var zeroTarget = AnyLayout(ProbeLayout(value: 7))
        zeroTarget.animatableData = zero
        XCTAssertEqual((zeroTarget.layout as? ProbeLayout)?.value, 7)

        var mismatchTarget = AnyLayout(ProbeLayout(value: 7))
        mismatchTarget.animatableData = pairData
        XCTAssertEqual((mismatchTarget.layout as? ProbeLayout)?.value, 7)
    }
}

private struct ProbeLayout: Layout {
    var value: Double

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        CGSize(width: value, height: value)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
    }
}

private struct PairLayout: Layout {
    var first: Double
    var second: Double

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(first, second) }
        set {
            first = newValue.first
            second = newValue.second
        }
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        CGSize(width: first, height: second)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
    }
}
