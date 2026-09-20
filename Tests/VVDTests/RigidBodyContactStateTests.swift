import XCTest
import VVD

final class RigidBodyContactStateTests: XCTestCase {
    func testCCDRebuildPreservesSupportFrictionWithAndWithoutWarmStarting() {
        let timeStep: Scalar = 1.0 / 60.0
        for mode: CCDConfiguration.Mode in [.speculative, .hybrid, .timeOfImpact] {
            for warmStarting in [false, true] {
                for sleepingTarget in [false, true] {
                    let material = PhysicsMaterial(friction: 1, restitution: 0)
                    let ground = floor(material: material)
                    let bullet = sphere(Vector3(0, 0.5, 0), material: material)
                    let target = sphere(Vector3(1 + 1.0e-8, 0.5, 0), material: material)
                    bullet.gravityScale = 0
                    bullet.linearVelocity = Vector3(0.2, 0, 0)
                    bullet.isContinuousCollisionDetectionEnabled = true
                    let solver = SequentialImpulseRigidBodySolver(velocityIterations: 100,
                        isWarmStartingEnabled: warmStarting, sleepDelay: 10,
                        ccdConfiguration: .init(mode: mode))
                    let simulator = RigidBodySimulator(gravity: Vector3(0, -10, 0), solver: solver)
                    for body in [ground, bullet, target] { simulator.add(body) }
                    if sleepingTarget { target.putToSleep() }

                    simulator.step(timeStep: timeStep)

                    // The target's support supplies a normal impulse of g * dt.
                    // Coulomb friction removes that much total horizontal momentum.
                    let expected = (Scalar(0.2) - 10 * timeStep) / 2
                    let scenario = "\(mode), warm=\(warmStarting), sleeping=\(sleepingTarget)"
                    XCTAssertEqual(bullet.linearVelocity.x, expected, accuracy: 1.0e-6, scenario)
                    XCTAssertEqual(target.linearVelocity.x, expected, accuracy: 1.0e-6, scenario)
                    XCTAssertEqual(target.linearVelocity.y, 0, accuracy: 1.0e-9, scenario)
                }
            }
        }
    }

    func testCCDExtraSolvesDoNotRenewFrictionOrCancelRestitution() {
        for mode: CCDConfiguration.Mode in [.speculative, .hybrid, .timeOfImpact] {
            for substeps in [1, 4] {
                let material = PhysicsMaterial(friction: 1, restitution: 0)
                let ground = floor(material: material)
                let slider = sphere(Vector3(0, 0.5, 10), material: material)
                slider.linearVelocity = Vector3(10, 0, 0)
                let bouncy = PhysicsMaterial(friction: 0, restitution: 1,
                    restitutionCombineMode: .maximum)
                let bouncing = sphere(Vector3(0, 0.5, 20), material: bouncy)
                bouncing.gravityScale = 0
                bouncing.linearVelocity = Vector3(0, -2, 0)
                let bullet = sphere(Vector3(0, 10, 0), material: material)
                bullet.gravityScale = 0
                bullet.linearVelocity = Vector3(10, 0, 0)
                bullet.isContinuousCollisionDetectionEnabled = true
                let target = sphere(Vector3(3, 10, 0), material: material)
                target.gravityScale = 0
                let simulator = RigidBodySimulator(gravity: Vector3(0, -10, 0),
                    solver: SequentialImpulseRigidBodySolver(velocityIterations: 100,
                        ccdConfiguration: .init(mode: mode, substepCount: substeps)))
                for body in [ground, slider, bouncing, bullet, target] { simulator.add(body) }
                target.putToSleep() // Forces a wake-up rebuild before the CCD solve.

                simulator.step(timeStep: 0.5)

                XCTAssertEqual(slider.linearVelocity.x, 5, accuracy: 1.0e-8, "\(mode)")
                XCTAssertEqual(bouncing.linearVelocity.y, 2, accuracy: 1.0e-8, "\(mode)")
            }
        }
    }

    func testCCDRebuildRetainsFrictionVectorWhenImpactChangesSlidingDirection() {
        let timeStep: Scalar = 1.0 / 60.0
        for mode: CCDConfiguration.Mode in [.speculative, .hybrid, .timeOfImpact] {
            let material = PhysicsMaterial(friction: 1, restitution: 0)
            let ground = floor(material: material)
            let bullet = sphere(Vector3(0, 0.5, 0), material: material)
            let target = sphere(Vector3(1 + 1.0e-8, 0.5, 0), material: material)
            bullet.gravityScale = 0
            bullet.linearVelocity = Vector3(0.2, 0, 0)
            bullet.isContinuousCollisionDetectionEnabled = true
            target.linearVelocity = Vector3(0, 0, 0.1)
            let simulator = RigidBodySimulator(gravity: Vector3(0, -10, 0),
                solver: SequentialImpulseRigidBodySolver(velocityIterations: 100,
                    isSleepingEnabled: false, ccdConfiguration: .init(mode: mode)))
            for body in [ground, bullet, target] { simulator.add(body) }

            simulator.step(timeStep: timeStep)

            // The floor is the only source of horizontal momentum change.
            // Its complete impulse must use one Coulomb disk, including the
            // z impulse applied before the bullet transfers x momentum.
            let impulse = bullet.linearVelocity + target.linearVelocity - Vector3(0.2, 0, 0.1)
            XCTAssertEqual(impulse.length, 10 * timeStep, accuracy: 1.0e-6, "\(mode)")
            XCTAssertEqual(Vector3.cross(impulse, target.linearVelocity).length,
                           0, accuracy: 1.0e-6, "\(mode)")
            XCTAssertLessThan(Vector3.dot(impulse, target.linearVelocity), 0)
        }
    }

    private func floor(material: PhysicsMaterial) -> RigidBody {
        RigidBody(primitive: StaticPlane(Plane(normal: Vector3(0, 1, 0), point: .zero)),
            motionType: .static, material: material)
    }

    private func sphere(_ position: Vector3, material: PhysicsMaterial) -> RigidBody {
        RigidBody(primitive: Sphere(center: .zero, radius: 0.5),
            transform: Transform(position: position), material: material)
    }
}
