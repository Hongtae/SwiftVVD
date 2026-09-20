//
//  ScenePhysicsConfiguration.swift
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import VVD

/// Serializable authoring settings, independent of the editor's UI framework.
/// Priority, worker scheduling, and network synchronization are separate future
/// policies; these settings do not claim cross-platform bitwise determinism.
public struct ScenePhysicsConfiguration: Hashable, Codable, Sendable {
    public var fixedTimeStep: Scalar
    public var velocityIterations: Int
    public var ccd: CCDConfiguration

    public init(fixedTimeStep: Scalar = 1.0 / 60,
                velocityIterations: Int = 8,
                ccd: CCDConfiguration = .default) {
        self.fixedTimeStep = fixedTimeStep
        self.velocityIterations = velocityIterations
        self.ccd = ccd
    }

    public static let `default` = ScenePhysicsConfiguration()

    public enum Preset: String, CaseIterable, Codable, Sendable {
        case game
        case accurateImpacts
        case discrete

        public var configuration: ScenePhysicsConfiguration {
            switch self {
            case .game: return .default
            case .accurateImpacts:
                return ScenePhysicsConfiguration(velocityIterations: 12,
                    ccd: CCDConfiguration(mode: .timeOfImpact, motion: .translationAndRotation))
            case .discrete:
                return ScenePhysicsConfiguration(ccd: CCDConfiguration(mode: .discrete))
            }
        }
    }

    public enum ValidationIssue: String, Error, Codable, Sendable {
        case invalidTimeStep
        case invalidVelocityIterations
        case invalidSubstepCount
        case invalidImpactIterations
        case invalidSweepIterations
        case invalidDistanceTolerance
    }

    /// Stable codes that a code client or localized editor can present.
    public var validationIssues: [ValidationIssue] {
        var issues: [ValidationIssue] = []
        if !fixedTimeStep.isFinite || fixedTimeStep <= 0 { issues.append(.invalidTimeStep) }
        if velocityIterations <= 0 { issues.append(.invalidVelocityIterations) }
        if ccd.substepCount <= 0 || fixedTimeStep / Scalar(ccd.substepCount) <= 0 {
            issues.append(.invalidSubstepCount)
        }
        if ccd.maximumImpactIterations <= 0 { issues.append(.invalidImpactIterations) }
        if ccd.maximumSweepIterations <= 0 { issues.append(.invalidSweepIterations) }
        if !ccd.distanceTolerance.isFinite || ccd.distanceTolerance <= 0 {
            issues.append(.invalidDistanceTolerance)
        }
        return issues
    }

    public func validate() throws {
        if let issue = validationIssues.first { throw issue }
    }
}
