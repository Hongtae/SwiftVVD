import XCTest
@testable import VUI

final class SemanticsFeatureTests: XCTestCase {
    override func tearDown() {
        Semantics.forced = Semantics.Forced()
        super.tearDown()
    }

    func testCurrentBaselineEnablesKnownSemanticMarkers() {
        Semantics.forced = Semantics.Forced()

        XCTAssertTrue(_SemanticFeature<Semantics_v4>.isEnabled)
        XCTAssertTrue(_SemanticFeature<Semantics_v5>.isEnabled)
        XCTAssertTrue(_SemanticFeature<Semantics_v6>.isEnabled)
        XCTAssertTrue(EnabledFeature.isEnabled)
        XCTAssertFalse(DisabledFeature.isEnabled)
    }

    func testForcedSDKLaneControlsDefaultSemanticFeatureRequirement() {
        Semantics.forced = Semantics.Forced(sdk: .v4, deploymentTarget: nil)

        XCTAssertTrue(_SemanticFeature<Semantics_v4>.isEnabled)
        XCTAssertFalse(_SemanticFeature<Semantics_v5>.isEnabled)
        XCTAssertFalse(_SemanticFeature<Semantics_v6>.isEnabled)
        XCTAssertTrue(DeploymentV6SemanticFeature.isEnabled)
    }

    func testForcedDeploymentLaneControlsDeploymentRequirementOnly() {
        Semantics.forced = Semantics.Forced(sdk: nil, deploymentTarget: .v4)

        XCTAssertTrue(_SemanticFeature<Semantics_v6>.isEnabled)
        XCTAssertFalse(DeploymentV6SemanticFeature.isEnabled)
    }

    func testSemanticsTestTemporarilyOverridesSelectedLaneAndRestores() {
        Semantics.forced = Semantics.Forced(sdk: .v4, deploymentTarget: nil)

        Semantics.test(as: \.sdk) {
            XCTAssertTrue(_SemanticFeature<Semantics_v6>.isEnabled)
            XCTAssertEqual(Semantics.forced.sdk, .v6)
        }

        XCTAssertEqual(Semantics.forced.sdk, .v4)
        XCTAssertFalse(_SemanticFeature<Semantics_v6>.isEnabled)
    }
}

private struct DeploymentV6SemanticFeature: SemanticFeature {
    static var introduced: Semantics { .v6 }
    static var requirement: SemanticRequirement { .deploymentTarget }
}
