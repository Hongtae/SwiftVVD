//
//  File: PhysicsMaterialTests.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import XCTest
import VVD

final class PhysicsMaterialTests: XCTestCase {
    func testCoefficientsAreSanitizedOnInitializationAndMutation() {
        var material = PhysicsMaterial(friction: -2, restitution: 4)
        XCTAssertEqual(material.friction, 0)
        XCTAssertEqual(material.restitution, 1)

        material.friction = .infinity
        material.restitution = -.infinity
        XCTAssertEqual(material.friction, 0)
        XCTAssertEqual(material.restitution, 0)

        material.friction = 1.5
        material.restitution = 0.75
        XCTAssertEqual(material.friction, 1.5)
        XCTAssertEqual(material.restitution, 0.75)
    }

    func testMatchingCombineModesResolveCoefficients() {
        let a = PhysicsMaterial(friction: 0.25, restitution: 0.2)
        let b = PhysicsMaterial(friction: 0.75, restitution: 0.8)
        let average = a.combined(with: b)
        XCTAssertEqual(average.friction, 0.5, accuracy: 1.0e-9)
        XCTAssertEqual(average.restitution, 0.5, accuracy: 1.0e-9)

        for (mode, expectedFriction, expectedRestitution) in [
            (PhysicsMaterialCombineMode.minimum, Scalar(0.25), Scalar(0.2)),
            (.multiply, Scalar(0.1875), Scalar(0.16)),
            (.maximum, Scalar(0.75), Scalar(0.8)),
        ] {
            let lhs = PhysicsMaterial(friction: a.friction,
                                      restitution: a.restitution,
                                      frictionCombineMode: mode,
                                      restitutionCombineMode: mode)
            let rhs = PhysicsMaterial(friction: b.friction,
                                      restitution: b.restitution,
                                      frictionCombineMode: mode,
                                      restitutionCombineMode: mode)
            let combined = lhs.combined(with: rhs)
            XCTAssertEqual(combined.friction, expectedFriction,
                           accuracy: 1.0e-9)
            XCTAssertEqual(combined.restitution, expectedRestitution,
                           accuracy: 1.0e-9)
        }
    }

    func testHigherPriorityModeWinsSymmetricallyPerCoefficient() {
        let a = PhysicsMaterial(friction: 0.2,
                                restitution: 0.3,
                                frictionCombineMode: .minimum,
                                restitutionCombineMode: .maximum)
        let b = PhysicsMaterial(friction: 0.8,
                                restitution: 0.6,
                                frictionCombineMode: .multiply,
                                restitutionCombineMode: .average)

        let ab = a.combined(with: b)
        let ba = b.combined(with: a)
        XCTAssertEqual(ab, ba)
        XCTAssertEqual(ab.frictionCombineMode, .multiply)
        XCTAssertEqual(ab.restitutionCombineMode, .maximum)
        XCTAssertEqual(ab.friction, 0.16, accuracy: 1.0e-9)
        XCTAssertEqual(ab.restitution, 0.6, accuracy: 1.0e-9)
    }
}
