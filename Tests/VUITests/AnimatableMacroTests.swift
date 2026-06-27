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

    func testAnimatablePairAccessorMacroSynthesizesLegacyPairAccessors() {
        var carrier = LegacyPairMacroCarrier(x: 2, y: 8)

        var data = carrier.animatableData
        data.scale(by: 0.25)
        carrier.animatableData = data

        XCTAssertEqual(carrier.x, 0.5)
        XCTAssertEqual(carrier.y, 2)
    }
}
