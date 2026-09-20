import XCTest
@testable import VEditor
import VGame
import VVD

final class PhysicsSettingsDraftTests: XCTestCase {
    func testDraftRoundTripAndExplicitApplyChangeActualCCDPolicy() throws {
        var draft = PhysicsSettingsDraft()
        draft.configuration.fixedTimeStep = 0.5
        draft.configuration.ccd.mode = .motionClamping
        let data = try draft.encoded()
        var restored = PhysicsSettingsDraft()
        try restored.load(data)
        XCTAssertEqual(restored.configuration, draft.configuration)

        let physics = WorldPhysics()
        XCTAssertEqual(physics.configuration.ccd.mode, .hybrid)
        try restored.apply(to: physics)
        let body = RigidBody(primitive: Sphere(center: .zero, radius: 0.5))
        body.isContinuousCollisionDetectionEnabled = true
        body.linearVelocity = Vector3(10, 0, 0)
        let wall = RigidBody(primitive: Sphere(center: .zero, radius: 0.5),
            transform: Transform(position: Vector3(3, 0, 0)), motionType: .static)
        physics.simulator.rigidBodies.gravity = .zero
        physics.simulator.rigidBodies.add(body)
        physics.simulator.rigidBodies.add(wall)
        physics.step()
        XCTAssertEqual(body.transform.position.x, 2, accuracy: 1.0e-8)
        XCTAssertEqual(body.linearVelocity.x, 10, accuracy: 1.0e-8)
        XCTAssertEqual(physics.ccdStatistics?.clampedBodyCount, 1)
    }

    func testInvalidDraftCannotPartiallyChangeLiveSolver() throws {
        let physics = WorldPhysics()
        var draft = PhysicsSettingsDraft()
        draft.selectPreset(.accurateImpacts)
        draft.configuration.ccd.substepCount = 0
        XCTAssertTrue(draft.configuration.validationIssues.contains(.invalidSubstepCount))
        XCTAssertThrowsError(try draft.apply(to: physics))
        XCTAssertEqual(physics.configuration, .default)
        let solver = try XCTUnwrap(physics.simulator.rigidBodies.solver as? SequentialImpulseRigidBodySolver)
        XCTAssertEqual(solver.ccdConfiguration, .default)
        XCTAssertEqual(solver.velocityIterations, 8)
    }

    func testInvalidDocumentAndUnknownVersionLeaveDraftIntact() throws {
        var draft = PhysicsSettingsDraft()
        draft.selectPreset(.accurateImpacts)
        let original = draft.configuration
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: draft.encoded()) as? [String: Any])
        json["version"] = 2
        XCTAssertThrowsError(try draft.load(JSONSerialization.data(withJSONObject: json)))
        XCTAssertEqual(draft.configuration, original)
        json["version"] = 1
        var configuration = try XCTUnwrap(json["configuration"] as? [String: Any])
        configuration["fixedTimeStep"] = -1
        json["configuration"] = configuration
        XCTAssertThrowsError(try draft.load(JSONSerialization.data(withJSONObject: json)))
        XCTAssertEqual(draft.configuration, original)
    }

}
