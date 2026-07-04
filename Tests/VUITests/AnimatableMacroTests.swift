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

@Animatable
private struct MacroMixedTuplePatternPoint {
    var tracked: Double
    var (ignoredY, ignoredZ): (Double, Double)

    init(tracked: Double, ignoredY: Double, ignoredZ: Double) {
        self.tracked = tracked
        self.ignoredY = ignoredY
        self.ignoredZ = ignoredZ
    }
}

@propertyWrapper
private struct MacroWrapper<Value> {
    var wrappedValue: Value
}

@Animatable
private struct MacroSourceShapePoint {
    var tracked: Double
    let constant: Double = 11
    var computed: Double { tracked + constant }
    lazy var lazyValue: Double = 13
    var observed: Double = 17 { didSet {} }
    @MacroWrapper var wrapped: Double = 19
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

    func testAnimatableMacroIgnoresTuplePatternStoredProperties() {
        var point = MacroMixedTuplePatternPoint(tracked: 8, ignoredY: 3, ignoredZ: 5)

        var data = point.animatableData
        data.scale(by: 0.25)
        point.animatableData = data

        XCTAssertEqual(point.tracked, 2)
        XCTAssertEqual(point.ignoredY, 3)
        XCTAssertEqual(point.ignoredZ, 5)
    }

    func testAnimatableMacroMatchesStoredSourceShapeSelection() {
        var point = MacroSourceShapePoint(tracked: 8)

        var data = point.animatableData
        data.scale(by: 0.25)
        point.animatableData = data

        XCTAssertEqual(point.tracked, 2)
        XCTAssertEqual(point.constant, 11)
        XCTAssertEqual(point.computed, 13)
        XCTAssertEqual(point.lazyValue, 13)
        XCTAssertEqual(point.observed, 4.25)
        XCTAssertEqual(point.wrapped, 4.75)
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

    func testAnimatableMacroNoEffectDiagnosticIncludesRemoveNote() throws {
        #if os(macOS)
        let cases = [
            (
                name: "empty",
                source: """
                import VUI

                @Animatable
                struct EmptyMacroProbe {}
                """,
                extensionNeedle: "extension EmptyMacroProbe: nonisolated VUI.Animatable"
            ),
            (
                name: "tuple",
                source: """
                import VUI

                @Animatable
                struct TupleOnlyPatternMacroProbe {
                    var (x, y): (Double, Double)
                }
                """,
                extensionNeedle: "extension TupleOnlyPatternMacroProbe: nonisolated VUI.Animatable"
            ),
        ]

        for testCase in cases {
            let output = try runMacroDiagnosticProbe(named: testCase.name, source: testCase.source)
            XCTAssertTrue(
                output.contains("'@Animatable' macro has no effect; it can only attach to types with animatable properties."),
                output
            )
            XCTAssertTrue(output.contains("note: Remove '@Animatable'"), output)
            XCTAssertTrue(output.contains(testCase.extensionNeedle), output)
        }
        #endif
    }

    func testAnimatableMacroInvalidPropertyDiagnosticIncludesGuidanceNotes() throws {
        #if os(macOS)
        let output = try runMacroDiagnosticProbe(
            named: "invalid-property",
            source: """
            import VUI

            @Animatable
            struct InvalidPropertyProbe {
                var x: Bool
            }
            """
        )
        XCTAssertTrue(output.contains("error: Cannot automatically synthesize 'animatableData'."), output)
        XCTAssertFalse(
            output.contains("error: Cannot automatically synthesize 'animatableData'. Mark this property"),
            output
        )
        XCTAssertTrue(output.contains("note: Mark this property with '@AnimatableIgnored'."), output)
        XCTAssertTrue(
            output.contains("note: Conform the type of this property to 'Animatable' or 'VectorArithmetic'."),
            output
        )
        XCTAssertTrue(output.contains("extension InvalidPropertyProbe: nonisolated VUI.Animatable"), output)
        #endif
    }

    func testAnimatableDataAccessorMacroEmptyDiagnosticsMatchSwiftUI() throws {
        #if os(macOS)
        let cases = [
            (
                name: "empty-animatable-data",
                attribute: "@_AnimatableData",
                typeName: "EmptyAnimatableDataMacroProbe",
                secondaryDiagnostic: "expansion of macro '_AnimatableData()' did not produce a non-observing accessor"
            ),
            (
                name: "empty-pair-data",
                attribute: "@_AnimatablePairData",
                typeName: "EmptyPairDataMacroProbe",
                secondaryDiagnostic: "expansion of macro '_AnimatablePairData()' did not produce a non-observing accessor"
            ),
        ]

        for testCase in cases {
            let output = try runMacroDiagnosticProbe(
                named: testCase.name,
                source: """
                import VUI

                struct \(testCase.typeName): Animatable {
                    var animatableData: EmptyAnimatableData {
                        get { data }
                        set { data = newValue }
                    }

                    \(testCase.attribute) private var data = {
                        return EmptyAnimatableData()
                    }()
                }
                """
            )
            XCTAssertTrue(
                output.contains("'@_AnimatableData' macro did not discover any key paths to animated properties."),
                output
            )
            XCTAssertTrue(output.contains(testCase.secondaryDiagnostic), output)
        }
        #endif
    }

    func testAnimatableMacroStaticStoredPropertyMatchesSwiftUIEmission() throws {
        #if os(macOS)
        let output = try runMacroDiagnosticProbe(
            named: "static-stored-property",
            source: """
            import VUI

            @Animatable
            struct StaticOnlyProbe {
                static var x: Double = 1
            }
            """
        )
        XCTAssertTrue(output.contains("Self[_animatableType: \\.x]"), output)
        XCTAssertTrue(output.contains("static member 'x' cannot be used on instance of type 'StaticOnlyProbe'"), output)
        XCTAssertFalse(output.contains("'@Animatable' macro has no effect"), output)
        XCTAssertTrue(output.contains("extension StaticOnlyProbe: nonisolated VUI.Animatable"), output)
        #endif
    }
}
