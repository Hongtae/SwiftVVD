//
//  CCDConfiguration.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

/// The continuous-collision policy shared by a simulator and its authoring UI.
/// Bodies participate through `isContinuousCollisionDetectionEnabled`.
public struct CCDConfiguration: Hashable, Codable, Sendable {
    public enum Mode: String, CaseIterable, Codable, Sendable {
        /// Resolve only contacts present at the start of each substep.
        case discrete
        /// Limit closing velocity using contacts predicted over the substep.
        case speculative
        /// Sweep solved motion and stop participating bodies at an impact.
        case motionClamping
        /// Predict contacts, solve constraints, then sweep and clamp motion.
        case hybrid
        /// Advance to impacts, resolve them, and sweep the remaining time again.
        case timeOfImpact
    }

    public enum Motion: String, CaseIterable, Codable, Sendable {
        /// Sweep translation with each shape's current orientation fixed.
        case translation
        /// Include rotation about the body's center of mass in the sweep.
        case translationAndRotation
    }

    public var mode: Mode
    public var motion: Motion
    /// Fixed substeps, independent of wall-clock time and machine speed.
    public var substepCount: Int
    /// Numerical limit for repeated TOI response. Unprocessed motion is stopped,
    /// never integrated without a collision check, when this limit is reached.
    public var maximumImpactIterations: Int
    /// World-space distance used by conservative motion sweeps.
    public var distanceTolerance: Scalar
    /// Numerical limit for a single conservative motion sweep.
    public var maximumSweepIterations: Int

    public init(mode: Mode = .hybrid,
                motion: Motion = .translation,
                substepCount: Int = 1,
                maximumImpactIterations: Int = 64,
                distanceTolerance: Scalar = 1.0e-6,
                maximumSweepIterations: Int = 64) {
        self.mode = mode
        self.motion = motion
        self.substepCount = substepCount
        self.maximumImpactIterations = maximumImpactIterations
        self.distanceTolerance = distanceTolerance
        self.maximumSweepIterations = maximumSweepIterations
    }

    /// General game dynamics: predictive contacts plus motion clamping.
    public static let `default` = CCDConfiguration()
}

/// Diagnostics from the last valid outer solve, including every substep and
/// repeated query. These count operations, not unique pairs or bodies.
public struct CCDStatistics: Hashable, Sendable {
    public internal(set) var sweepCount: Int = 0
    public internal(set) var predictiveContactCount: Int = 0
    public internal(set) var impactCount: Int = 0
    public internal(set) var clampedBodyCount: Int = 0
    public internal(set) var inconclusiveSweepCount: Int = 0
    public internal(set) var unsupportedPairCount: Int = 0
    public internal(set) var reachedImpactLimit: Bool = false

    public init() {}
}
