import XCTest
@testable import VUI

final class SemanticsFeatureTests: XCTestCase {
    func testCurrentBaselineEnablesKnownSemanticMarkers() {
        XCTAssertTrue(_SemanticFeature<Semantics_v4>.isEnabled)
        XCTAssertTrue(_SemanticFeature<Semantics_v5>.isEnabled)
        XCTAssertTrue(_SemanticFeature<Semantics_v6>.isEnabled)
        XCTAssertTrue(_SemanticFeature<Semantics_v7>.isEnabled)
        XCTAssertTrue(_SemanticFeature<Semantics_v8>.isEnabled)
        XCTAssertTrue(EnabledFeature.isEnabled)
        XCTAssertFalse(DisabledFeature.isEnabled)
    }

    func testSemanticMarkerTokensUseProjectLocalOrdering() {
        XCTAssertEqual(Semantics_v4.semantic.rawValue, 400)
        XCTAssertEqual(Semantics_v5.semantic.rawValue, 500)
        XCTAssertEqual(Semantics_v6.semantic.rawValue, 600)
        XCTAssertEqual(Semantics.v6_4.rawValue, 640)
        XCTAssertEqual(Semantics_v7.semantic.rawValue, 700)
        XCTAssertEqual(Semantics_v8.semantic.rawValue, 800)
        XCTAssertLessThan(Semantics_v4.semantic, Semantics_v5.semantic)
        XCTAssertLessThan(Semantics_v5.semantic, Semantics_v6.semantic)
        XCTAssertLessThan(Semantics_v6.semantic, Semantics_v7.semantic)
        XCTAssertLessThan(Semantics_v7.semantic, Semantics_v8.semantic)
    }

    func testBothRequirementKindsUseLatestBaseline() {
        XCTAssertTrue(RuntimeV6SemanticFeature.isEnabled)
        XCTAssertTrue(RuntimeV7SemanticFeature.isEnabled)
        XCTAssertTrue(RuntimeV8SemanticFeature.isEnabled)
        XCTAssertTrue(isLinkedOnOrAfter(.v8))
        XCTAssertTrue(isDeployedOnOrAfter(.v8))
        XCTAssertFalse(isLinkedOnOrAfter(Semantics(rawValue: 801)))
        XCTAssertFalse(isDeployedOnOrAfter(Semantics(rawValue: 801)))
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

private struct RuntimeV8SemanticFeature: SemanticFeature {
    static var introduced: Semantics { .v8 }
    static var requirement: SemanticRequirement { .runtime }
}
