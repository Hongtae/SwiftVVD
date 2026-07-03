import XCTest
@testable import VUI

@Animatable
private struct MacroPoint {
    var x: Double
    var y: Double
    @AnimatableIgnored var flag: Bool
}

@Animatable
private final class MacroBox {
    var x: Double = 1
}

@Animatable
private struct MacroMultiBindingPoint {
    var x: Double = 2, y: Double = 4
}

private struct LegacyPairMacroCarrier: Animatable {
    var x: Double
    var y: Double

    var animatableData: AnimatablePair<Double, Double> {
        get { legacyData }
        set { legacyData = newValue }
    }

    @_AnimatablePairData private var legacyData = {
        let x = #_SwiftUIAnimatableProperty(Self[_animatableType: \.x])
        let y = #_SwiftUIAnimatableProperty(Self[_animatableType: \.y])
        return AnimatablePair(x, y)
    }()
}

private struct LegacyTriplePairMacroCarrier: Animatable {
    var x: Double
    var y: Double
    var z: Double

    var animatableData: AnimatablePair<Double, AnimatablePair<Double, Double>> {
        get { legacyData }
        set { legacyData = newValue }
    }

    @_AnimatablePairData private var legacyData = {
        let x = #_SwiftUIAnimatableProperty(Self[_animatableType: \.x])
        let y = #_SwiftUIAnimatableProperty(Self[_animatableType: \.y])
        let z = #_SwiftUIAnimatableProperty(Self[_animatableType: \.z])
        return AnimatablePair(x, AnimatablePair<Double, Double>.self)
    }()
}

final class AnimatableMacroTests: XCTestCase {
    func testAnimatableMacroSynthesizesAnimatableDataForStoredVectorProperties() {
        var point = MacroPoint(x: 2, y: 4, flag: true)

        var data = point.animatableData
        data.scale(by: 0.5)
        point.animatableData = data

        XCTAssertEqual(point.x, 1)
        XCTAssertEqual(point.y, 2)
        XCTAssertTrue(point.flag)
    }

    func testAnimatableMacroSynthesizesClassAnimatableData() {
        let box = MacroBox()

        var data = box.animatableData
        data.scale(by: 3)
        box.animatableData = data

        XCTAssertEqual(box.x, 3)
    }

    func testAnimatableMacroSynthesizesMultiBindingStoredProperties() {
        var point = MacroMultiBindingPoint()

        var data = point.animatableData
        data.scale(by: 0.25)
        point.animatableData = data

        XCTAssertEqual(point.x, 0.5)
        XCTAssertEqual(point.y, 1)
    }

    func testAnimatablePairAccessorMacroSynthesizesLegacyPairAccessors() {
        var carrier = LegacyPairMacroCarrier(x: 2, y: 8)

        var data = carrier.animatableData
        data.scale(by: 0.25)
        carrier.animatableData = data

        XCTAssertEqual(carrier.x, 0.5)
        XCTAssertEqual(carrier.y, 2)
    }

    func testAnimatablePairAccessorMacroSynthesizesRightNestedLegacyPairAccessors() {
        var carrier = LegacyTriplePairMacroCarrier(x: 2, y: 8, z: -4)

        var data = carrier.animatableData
        data.first += 1
        data.second.first *= 0.25
        data.second.second -= 6
        carrier.animatableData = data

        XCTAssertEqual(carrier.x, 3)
        XCTAssertEqual(carrier.y, 2)
        XCTAssertEqual(carrier.z, -10)
    }
}
