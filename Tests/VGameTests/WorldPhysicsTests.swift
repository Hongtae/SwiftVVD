import XCTest
import VGame
import VVD

final class WorldPhysicsTests: XCTestCase {
    func testWorldsOwnIndependentPhysicsSettingsAndTicks() throws {
        let first = World {}
        let second = World {}
        var settings = ScenePhysicsConfiguration.Preset.accurateImpacts.configuration
        settings.fixedTimeStep = 0.25
        try first.physics.apply(settings)
        let body = RigidBody(primitive: Sphere(center: .zero, radius: 0.5))
        body.linearVelocity = Vector3(4, 0, 0)
        first.physics.simulator.rigidBodies.gravity = .zero
        first.physics.simulator.rigidBodies.add(body)
        first.physics.step()
        XCTAssertEqual(body.transform.position.x, 1, accuracy: 1.0e-9)
        XCTAssertEqual(first.physics.tickCount, 1)
        XCTAssertEqual(second.physics.tickCount, 0)
        XCTAssertEqual(second.physics.configuration, .default)
    }

    func testSettingsChangeWakesSleepingBodies() throws {
        let physics = WorldPhysics()
        let body = RigidBody(primitive: Sphere(center: .zero, radius: 0.5))
        physics.simulator.rigidBodies.add(body)
        body.putToSleep()
        try physics.apply(ScenePhysicsConfiguration.Preset.accurateImpacts.configuration)
        XCTAssertFalse(body.isSleeping)
    }

    func testCustomSolverCannotSilentlyIgnoreSceneSettings() {
        final class CustomSolver: RigidBodySolver {
            func solve(_ context: RigidBodySolverContext) {}
        }
        let physics = WorldPhysics()
        let custom = CustomSolver()
        physics.simulator.rigidBodies.solver = custom
        XCTAssertThrowsError(try physics.apply(ScenePhysicsConfiguration.Preset.accurateImpacts.configuration))
        XCTAssertEqual(physics.configuration, .default)
        XCTAssertTrue(physics.simulator.rigidBodies.solver === custom)
    }
}
