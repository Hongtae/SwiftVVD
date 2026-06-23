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
        XCTAssertTrue(EnabledFeature.isEnabled)
        XCTAssertFalse(DisabledFeature.isEnabled)
    }

    func testSemanticMarkerTokensUseProjectLocalOrdering() {
        XCTAssertEqual(Semantics_v4.semantic.rawValue, 400)
        XCTAssertEqual(Semantics_v5.semantic.rawValue, 500)
        XCTAssertEqual(Semantics_v6.semantic.rawValue, 600)
        XCTAssertLessThan(Semantics_v4.semantic, Semantics_v5.semantic)
        XCTAssertLessThan(Semantics_v5.semantic, Semantics_v6.semantic)
    }

    func testBuildOverrideControlsDefaultSemanticFeatureRequirement() {
        Semantics.overrides = Semantics.Overrides(build: .v4, runtime: nil)

        XCTAssertTrue(_SemanticFeature<Semantics_v4>.isEnabled)
        XCTAssertFalse(_SemanticFeature<Semantics_v5>.isEnabled)
        XCTAssertFalse(_SemanticFeature<Semantics_v6>.isEnabled)
        XCTAssertTrue(RuntimeV6SemanticFeature.isEnabled)
    }

    func testRuntimeOverrideControlsRuntimeRequirementOnly() {
        Semantics.overrides = Semantics.Overrides(build: nil, runtime: .v4)

        XCTAssertTrue(_SemanticFeature<Semantics_v6>.isEnabled)
        XCTAssertFalse(RuntimeV6SemanticFeature.isEnabled)
    }

    func testSemanticsTestTemporarilyOverridesSelectedLaneAndRestores() {
        Semantics.overrides = Semantics.Overrides(build: .v4, runtime: nil)

        Semantics.test(as: \.build) {
            XCTAssertTrue(_SemanticFeature<Semantics_v6>.isEnabled)
            XCTAssertEqual(Semantics.overrides.build, .v6)
        }

        XCTAssertEqual(Semantics.overrides.build, .v4)
        XCTAssertFalse(_SemanticFeature<Semantics_v6>.isEnabled)
    }
}

private struct RuntimeV6SemanticFeature: SemanticFeature {
    static var introduced: Semantics { .v6 }
    static var requirement: SemanticRequirement { .runtime }
}
