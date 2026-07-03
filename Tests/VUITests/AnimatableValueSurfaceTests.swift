import XCTest
@testable import VUI

final class AnimatableValueSurfaceTests: XCTestCase {
    func testVectorArithmeticHelperDefaultsUseUnclampedInterpolation() {
        let base = ProbeVector(value: 2)
        let scaled = base.scaled(by: 4)
        XCTAssertEqual(scaled.value, 8)
        XCTAssertEqual(base.value, 2)

        var interpolating = ProbeVector(value: 2)
        interpolating.interpolate(towards: ProbeVector(value: 10), amount: 0.25)
        XCTAssertEqual(interpolating.value, 4)

        let interpolated = ProbeVector(value: 2)
            .interpolated(towards: ProbeVector(value: 10), amount: 0.25)
        XCTAssertEqual(interpolated.value, 4)

        var extrapolating = ProbeVector(value: 2)
        extrapolating.interpolate(towards: ProbeVector(value: 10), amount: -0.5)
        XCTAssertEqual(extrapolating.value, -2)

        let pair = AnimatablePair(2.0, 4.0)
            .interpolated(towards: AnimatablePair(10.0, 12.0), amount: 0.25)
        XCTAssertEqual(pair.first, 4)
        XCTAssertEqual(pair.second, 6)
    }

    func testAnimatablePairTypeInitializerUsesVectorZeros() {
        let scalarPair = AnimatablePair(Double.self, Float.self)
        XCTAssertEqual(scalarPair.first, 0)
        XCTAssertEqual(scalarPair.second, 0)

        let customPair = AnimatablePair(ProbeVector.self, Double.self)
        XCTAssertEqual(customPair.first, ProbeVector.zero)
        XCTAssertEqual(customPair.second, 0)

        let nestedPair = AnimatablePair(
            AnimatablePair<Double, Double>.self,
            ProbeVector.self
        )
        XCTAssertEqual(nestedPair.first, AnimatablePair.zero)
        XCTAssertEqual(nestedPair.second, ProbeVector.zero)
    }

    func testVectorArithmeticAnimatableDefaultReturnsAndAssignsSelf() {
        var vector = ProbeVector(value: 3.25)
        XCTAssertEqual(vector.animatableData, ProbeVector(value: 3.25))

        vector.animatableData = ProbeVector(value: -4.5)
        XCTAssertEqual(vector, ProbeVector(value: -4.5))

        var scalar = 2.0
        XCTAssertEqual(vuiAnimatableData(scalar), 2.0)

        setVUIAnimatableData(&scalar, -9.0)
        XCTAssertEqual(scalar, -9.0)

        var cgScalar = CGFloat(1.5)
        XCTAssertEqual(vuiAnimatableData(cgScalar), CGFloat(1.5))

        setVUIAnimatableData(&cgScalar, CGFloat(-3.5))
        XCTAssertEqual(cgScalar, CGFloat(-3.5))
    }

    func testAnimatableKeyPathHelpersMatchVectorNestedFallbackAndReferenceSurface() {
        let vectorType = ProbeAnimatableRoot[_animatableType: \.scalar]
        let nestedType = ProbeAnimatableRoot[_animatableType: \.nested]
        let fallbackType = ProbeAnimatableRoot[_animatableType: \.ignored]

        XCTAssertTrue(vectorType == Double.self)
        XCTAssertTrue(nestedType == Double.self)
        XCTAssertTrue(fallbackType == String.self)

        var root = ProbeAnimatableRoot(
            scalar: 1.25,
            nested: ProbeNestedAnimatable(amount: 2.5),
            ignored: "stable",
            reference: ProbeReference(4.0)
        )

        XCTAssertEqual(root[_animatableValue: \.scalar], 1.25)
        root[_animatableValue: \.scalar] = 7.0
        XCTAssertEqual(root.scalar, 7.0)

        XCTAssertEqual(root[_animatableValue: \.nested], 2.5)
        root[_animatableValue: \.nested] = 8.5
        XCTAssertEqual(root.nested.amount, 8.5)

        let ignored: EmptyAnimatableData = root[_animatableValue: \.ignored]
        XCTAssertEqual(ignored.magnitudeSquared, 0)
        root[_animatableValue: \.ignored] = EmptyAnimatableData()
        XCTAssertEqual(root.ignored, "stable")

        XCTAssertEqual(root[_animatableValue: \.reference.scalar], 4.0)
        root[_animatableValue: \.reference.scalar] = 11.0
        XCTAssertEqual(root.reference.scalar, 11.0)
    }

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
        let (directFirst, directSecond) = direct.value
        let (typedFirst, typedSecond) = typed.value

        XCTAssertEqual(MemoryLayout<AnimatableValues<Double, CGFloat>>.size, 16)
        XCTAssertEqual(MemoryLayout<AnimatableValues<>>.size, 0)
        XCTAssertEqual(MemoryLayout<AnimatableValues<>>.stride, 1)
        XCTAssertEqual(MemoryLayout<AnimatableValues<>>.alignment, 1)
        XCTAssertEqual(Mirror(reflecting: direct).children.count, 1)
        XCTAssertEqual(Mirror(reflecting: empty).children.count, 1)
        XCTAssertEqual(Mirror(reflecting: direct).children.first?.label, "value")
        XCTAssertEqual(Mirror(reflecting: empty).children.first?.label, "value")
        XCTAssertEqual(directFirst, 3)
        XCTAssertEqual(directSecond, CGFloat(4))
        XCTAssertEqual(typedFirst, 0)
        XCTAssertEqual(typedSecond, CGFloat(0))
        XCTAssertEqual(String(describing: empty.value), "()")

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
        assertAnyAnimatableDataSnapshot(
            doubleData,
            vtableContains: "ProbeLayout",
            valueContains: "3.0"
        )
        assertAnyAnimatableDataSnapshot(
            pairData,
            vtableContains: "PairLayout",
            valueContains: "AnimatablePair"
        )
        assertAnyAnimatableDataSnapshot(
            zero,
            vtableContains: "Zero",
            valueContains: "()"
        )

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
        assertAnyAnimatableDataSnapshot(
            targetLayout.animatableData,
            vtableContains: "ProbeLayout",
            valueContains: "-6.0"
        )

        var targetPairLayout = AnyLayout(PairLayout(first: 0, second: 0))
        targetPairLayout.animatableData = pairData
        let pair = targetPairLayout.layout as? PairLayout
        XCTAssertEqual(pair?.first, 1)
        XCTAssertEqual(pair?.second, 2)
        assertAnyAnimatableDataSnapshot(
            targetPairLayout.animatableData,
            vtableContains: "PairLayout",
            valueContains: "AnimatablePair"
        )
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

private func vuiAnimatableData<Value: VUI.Animatable>(_ value: Value) -> Value.AnimatableData {
    value.animatableData
}

private func setVUIAnimatableData<Value: VUI.Animatable>(
    _ value: inout Value,
    _ animatableData: Value.AnimatableData
) {
    value.animatableData = animatableData
}

private func assertAnyAnimatableDataSnapshot(
    _ data: _AnyAnimatableData,
    vtableContains expectedVTable: String,
    valueContains expectedValue: String,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let children = Array(Mirror(reflecting: data).children)
    XCTAssertEqual(children.count, 2, file: file, line: line)
    guard children.count == 2 else {
        return
    }
    XCTAssertEqual(children[0].label, "vtable", file: file, line: line)
    XCTAssertEqual(children[1].label, "value", file: file, line: line)
    XCTAssertTrue(
        String(describing: children[0].value).contains(expectedVTable),
        file: file,
        line: line
    )
    XCTAssertTrue(
        String(describing: children[1].value).contains(expectedValue),
        file: file,
        line: line
    )
}

private struct ProbeVector: VectorArithmetic, Animatable, Equatable {
    var value: Double

    static var zero: ProbeVector {
        ProbeVector(value: 0)
    }

    static func + (lhs: ProbeVector, rhs: ProbeVector) -> ProbeVector {
        ProbeVector(value: lhs.value + rhs.value)
    }

    static func - (lhs: ProbeVector, rhs: ProbeVector) -> ProbeVector {
        ProbeVector(value: lhs.value - rhs.value)
    }

    mutating func scale(by rhs: Double) {
        value *= rhs
    }

    var magnitudeSquared: Double {
        value * value
    }
}

private struct ProbeNestedAnimatable: Animatable, Equatable {
    var amount: Double

    var animatableData: Double {
        get { amount }
        set { amount = newValue }
    }
}

private struct ProbeAnimatableRoot: Animatable {
    var scalar: Double
    var nested: ProbeNestedAnimatable
    var ignored: String
    var reference: ProbeReference

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(scalar, nested.animatableData) }
        set {
            scalar = newValue.first
            nested.animatableData = newValue.second
        }
    }
}

private final class ProbeReference {
    var scalar: Double

    init(_ scalar: Double) {
        self.scalar = scalar
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
