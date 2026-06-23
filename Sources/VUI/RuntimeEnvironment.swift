//
//  File: RuntimeEnvironment.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

// Ordered tokens used by compile-time compatibility branches.
// All compatibility checks select the latest behavior baseline.
struct Semantics: Comparable, Hashable, Sendable {
    var rawValue: UInt32

    // These tokens only need stable ordering between compatibility baselines.
    // They are intentionally local monotonic values.
    static let v4 = Semantics(rawValue: 400)
    static let v5 = Semantics(rawValue: 500)
    static let v6 = Semantics(rawValue: 600)
    static let v6_4 = Semantics(rawValue: 640)
    static let v7 = Semantics(rawValue: 700)
    static let v8 = Semantics(rawValue: 800)

    static func < (lhs: Semantics, rhs: Semantics) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    static var current: Semantics {
        .v8
    }

}

enum SemanticRequirement {
    case build
    case runtime
}

protocol SemanticProtocol {
    static var semantic: Semantics { get }
}

protocol SemanticFeature {
    static var introduced: Semantics { get }
    static var requirement: SemanticRequirement { get }
}

extension SemanticFeature {
    static var requirement: SemanticRequirement {
        .build
    }

    static var prior: Semantics {
        Semantics(rawValue: introduced.rawValue &- 1)
    }

    static var isEnabled: Bool {
        switch requirement {
        case .build:
            return isBuildBaselineOnOrAfter(introduced)
        case .runtime:
            return isRuntimeBaselineOnOrAfter(introduced)
        }
    }
}

// Semantic version marker types used with _SemanticFeature<T>.
struct Semantics_v4: SemanticProtocol {
    static var semantic: Semantics { .v4 }
}

struct Semantics_v5: SemanticProtocol {
    static var semantic: Semantics { .v5 }
}

struct Semantics_v6: SemanticProtocol {
    static var semantic: Semantics { .v6 }
}

struct Semantics_v7: SemanticProtocol {
    static var semantic: Semantics { .v7 }
}

struct Semantics_v8: SemanticProtocol {
    static var semantic: Semantics { .v8 }
}

struct DisabledFeature: SemanticFeature {
    static var introduced: Semantics { Semantics(rawValue: UInt32.max) }
    static var isEnabled: Bool { false }
}

struct EnabledFeature: SemanticFeature {
    static var introduced: Semantics { .v4 }
    static var isEnabled: Bool { true }
}

func isBuildBaselineOnOrAfter(_ semantics: Semantics) -> Bool {
    Semantics.current >= semantics
}

func isRuntimeBaselineOnOrAfter(_ semantics: Semantics) -> Bool {
    Semantics.current >= semantics
}

func isLinkedOnOrAfter(_ semantics: Semantics) -> Bool {
    isBuildBaselineOnOrAfter(semantics)
}

func isDeployedOnOrAfter(_ semantics: Semantics) -> Bool {
    isRuntimeBaselineOnOrAfter(semantics)
}
