import XCTest
@testable import VUI

final class SemanticsFeatureTests: XCTestCase {
    override func tearDown() {
        Semantics.overrides = Semantics.Overrides()
        super.tearDown()
    }

    func testCurrentBaselineEnablesKnownSemanticMarkers() {
        Semantics.overrides = Semantics.Overrides()

        XCTAssertTrue(_SemanticFeature<Semantics_v4>.isEnabled)
        XCTAssertTrue(_SemanticFeature<Semantics_v5>.isEnabled)
        XCTAssertTrue(_SemanticFeature<Semantics_v6>.isEnabled)
        XCTAssertTrue(_SemanticFeature<Semantics_v7>.isEnabled)
        XCTAssertTrue(EnabledFeature.isEnabled)
        XCTAssertFalse(DisabledFeature.isEnabled)
    }

    func testSemanticMarkerTokensUseProjectLocalOrdering() {
        XCTAssertEqual(Semantics_v4.semantic.rawValue, 400)
        XCTAssertEqual(Semantics_v5.semantic.rawValue, 500)
        XCTAssertEqual(Semantics_v6.semantic.rawValue, 600)
        XCTAssertEqual(Semantics_v7.semantic.rawValue, 700)
        XCTAssertLessThan(Semantics_v4.semantic, Semantics_v5.semantic)
        XCTAssertLessThan(Semantics_v5.semantic, Semantics_v6.semantic)
        XCTAssertLessThan(Semantics_v6.semantic, Semantics_v7.semantic)
    }

    func testBuildOverrideControlsDefaultSemanticFeatureRequirement() {
        Semantics.overrides = Semantics.Overrides(build: .v4, runtime: nil)

        XCTAssertTrue(_SemanticFeature<Semantics_v4>.isEnabled)
        XCTAssertFalse(_SemanticFeature<Semantics_v5>.isEnabled)
        XCTAssertFalse(_SemanticFeature<Semantics_v6>.isEnabled)
        XCTAssertFalse(_SemanticFeature<Semantics_v7>.isEnabled)
        XCTAssertTrue(RuntimeV6SemanticFeature.isEnabled)
    }

    func testRuntimeOverrideControlsRuntimeRequirementOnly() {
        Semantics.overrides = Semantics.Overrides(build: nil, runtime: .v4)

        XCTAssertTrue(_SemanticFeature<Semantics_v6>.isEnabled)
        XCTAssertTrue(_SemanticFeature<Semantics_v7>.isEnabled)
        XCTAssertFalse(RuntimeV6SemanticFeature.isEnabled)
        XCTAssertFalse(RuntimeV7SemanticFeature.isEnabled)
    }

    func testSemanticsTestTemporarilyOverridesSelectedLaneAndRestores() {
        Semantics.overrides = Semantics.Overrides(build: .v4, runtime: nil)

        Semantics.test(as: \.build) {
            XCTAssertTrue(_SemanticFeature<Semantics_v6>.isEnabled)
            XCTAssertTrue(_SemanticFeature<Semantics_v7>.isEnabled)
            XCTAssertEqual(Semantics.overrides.build, .v7)
        }

        XCTAssertEqual(Semantics.overrides.build, .v4)
        XCTAssertFalse(_SemanticFeature<Semantics_v6>.isEnabled)
    }

    func testSemanticsTestOnlyOverridesSelectedLane() {
        Semantics.overrides = Semantics.Overrides(build: .v4, runtime: .v4)

        Semantics.test(as: \.runtime) {
            XCTAssertFalse(_SemanticFeature<Semantics_v6>.isEnabled)
            XCTAssertTrue(RuntimeV6SemanticFeature.isEnabled)
            XCTAssertTrue(RuntimeV7SemanticFeature.isEnabled)
            XCTAssertEqual(Semantics.overrides.build, .v4)
            XCTAssertEqual(Semantics.overrides.runtime, .v7)
        }

        XCTAssertEqual(Semantics.overrides.build, .v4)
        XCTAssertEqual(Semantics.overrides.runtime, .v4)
    }

    func testSemanticsTestRestoresSelectedLaneAfterThrow() {
        Semantics.overrides = Semantics.Overrides(build: .v4, runtime: .v5)

        do {
            try Semantics.test(as: \.runtime) {
                XCTAssertEqual(Semantics.overrides.build, .v4)
                XCTAssertEqual(Semantics.overrides.runtime, .v7)
                throw SemanticsFeatureProbeError.expected
            }
            XCTFail("Semantics.test returned normally")
        } catch SemanticsFeatureProbeError.expected {
            XCTAssertEqual(Semantics.overrides.build, .v4)
            XCTAssertEqual(Semantics.overrides.runtime, .v5)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }
}

private struct RuntimeV6SemanticFeature: SemanticFeature {
    static var introduced: Semantics { .v6 }
    static var requirement: SemanticRequirement { .runtime }
}

private struct RuntimeV7SemanticFeature: SemanticFeature {
    static var introduced: Semantics { .v7 }
    static var requirement: SemanticRequirement { .runtime }
}

private enum SemanticsFeatureProbeError: Error {
    case expected
}
