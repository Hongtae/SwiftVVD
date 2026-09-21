//
//  File: XPBDSimulator.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

/// Owns particle bodies and constraints, then delegates stepping to a solver.
public final class XPBDSimulator {
    public var gravity: Vector3
    public var solver: (any XPBDSolver)?

    private var bodyStorage: [any XPBDBody]
    private var constraintStorage: [any XPBDConstraint]

    public var bodies: [any XPBDBody] { bodyStorage }
    public var constraints: [any XPBDConstraint] { constraintStorage }

    public init(gravity: Vector3 = Vector3(0, -9.81, 0),
                solver: (any XPBDSolver)? = XPBDProjectionSolver()) {
        self.gravity = gravity
        self.solver = solver
        self.bodyStorage = []
        self.constraintStorage = []
    }

    @discardableResult
    public func add(_ body: any XPBDBody) -> Bool {
        let identifier = ObjectIdentifier(body)
        guard !bodyStorage.contains(where: { ObjectIdentifier($0) == identifier }) else {
            return false
        }
        bodyStorage.append(body)
        return true
    }

    @discardableResult
    public func remove(_ body: any XPBDBody) -> Bool {
        let identifier = ObjectIdentifier(body)
        guard let index = bodyStorage.firstIndex(where: {
            ObjectIdentifier($0) == identifier
        }) else { return false }
        bodyStorage.remove(at: index)
        constraintStorage.removeAll { constraint in
            constraint.particleReferences.contains {
                ObjectIdentifier($0.body) == identifier
            }
        }
        return true
    }

    @discardableResult
    public func add(_ constraint: any XPBDConstraint) -> Bool {
        let identifier = ObjectIdentifier(constraint)
        guard !constraintStorage.contains(where: { ObjectIdentifier($0) == identifier }) else {
            return false
        }
        let bodyIdentifiers = Set(bodyStorage.map(ObjectIdentifier.init))
        guard constraint.particleReferences.allSatisfy({ reference in
            reference.isValid &&
                bodyIdentifiers.contains(ObjectIdentifier(reference.body))
        }) else { return false }
        constraintStorage.append(constraint)
        return true
    }

    @discardableResult
    public func remove(_ constraint: any XPBDConstraint) -> Bool {
        let identifier = ObjectIdentifier(constraint)
        guard let index = constraintStorage.firstIndex(where: {
            ObjectIdentifier($0) == identifier
        }) else { return false }
        constraintStorage.remove(at: index)
        return true
    }

    public func solverContext(timeStep: Scalar) -> XPBDSolverContext {
        XPBDSolverContext(timeStep: timeStep,
                          gravity: gravity,
                          bodies: bodyStorage,
                          constraints: constraintStorage.filter(\.isEnabled))
    }

    public func step(timeStep: Scalar) {
        guard timeStep.isFinite, timeStep > .zero else { return }
        solver?.solve(solverContext(timeStep: timeStep))
    }
}
