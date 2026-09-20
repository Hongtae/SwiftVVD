//
//  WorldPhysics.swift
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import VVD

/// One scene's synchronously owned physics runtime. Call `step()` for each
/// simulation tick; rendering delays do not change the tick size or skip ticks.
/// Declarative entity-to-body materialization is not implemented yet.
public final class WorldPhysics {
    public let simulator: DynamicsSimulator
    public private(set) var configuration: ScenePhysicsConfiguration
    public private(set) var tickCount: UInt64 = 0

    public enum ConfigurationError: Error {
        /// Scene settings target the sequential solver. A caller that injects
        /// a different solver must configure that strategy separately.
        case incompatibleSolver
    }

    public init() {
        configuration = .default
        simulator = DynamicsSimulator()
    }

    public convenience init(configuration: ScenePhysicsConfiguration) throws {
        self.init()
        try apply(configuration)
    }

    /// Validate the entire change before mutating live state. Apply only between
    /// ticks on the simulation owner; this class is deliberately not Sendable.
    public func apply(_ configuration: ScenePhysicsConfiguration) throws {
        try configuration.validate()
        guard let solver = simulator.rigidBodies.solver as? SequentialImpulseRigidBodySolver
        else { throw ConfigurationError.incompatibleSolver }
        if self.configuration != configuration {
            solver.removeAllCachedContacts()
            for body in simulator.rigidBodies.bodies where body.isEnabled && body.motionType == .dynamic {
                body.wakeUp()
            }
        }
        solver.ccdConfiguration = configuration.ccd
        solver.velocityIterations = configuration.velocityIterations
        self.configuration = configuration
    }

    public func step() {
        simulator.step(timeStep: configuration.fixedTimeStep)
        tickCount &+= 1
    }

    public var ccdStatistics: CCDStatistics? {
        (simulator.rigidBodies.solver as? SequentialImpulseRigidBodySolver)?.ccdStatistics
    }
}
