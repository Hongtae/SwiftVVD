//
//  File: XPBDTopology.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

/// An undirected edge between two indices in one particle body.
public struct XPBDParticleEdge: Hashable, Sendable {
    public let first: Int
    public let second: Int

    public init(_ first: Int, _ second: Int) {
        self.first = Swift.min(first, second)
        self.second = Swift.max(first, second)
    }

    public func isValid(particleCount: Int) -> Bool {
        first >= 0 && second < particleCount && first != second
    }
}

/// Triangle topology in one particle body.
public struct XPBDParticleTriangle: Hashable, Sendable {
    public let a: Int
    public let b: Int
    public let c: Int

    public init(_ a: Int, _ b: Int, _ c: Int) {
        self.a = a
        self.b = b
        self.c = c
    }

    public var edges: [XPBDParticleEdge] {
        [XPBDParticleEdge(a, b),
         XPBDParticleEdge(b, c),
         XPBDParticleEdge(c, a)]
    }

    public func isValid(particleCount: Int) -> Bool {
        a >= 0 && b >= 0 && c >= 0 &&
            a < particleCount && b < particleCount && c < particleCount &&
            a != b && b != c && c != a
    }
}

/// Tetrahedral topology in one particle body.
public struct XPBDParticleTetrahedron: Hashable, Sendable {
    public let a: Int
    public let b: Int
    public let c: Int
    public let d: Int

    public init(_ a: Int, _ b: Int, _ c: Int, _ d: Int) {
        self.a = a
        self.b = b
        self.c = c
        self.d = d
    }

    public func isValid(particleCount: Int) -> Bool {
        let indices = [a, b, c, d]
        return indices.allSatisfy { $0 >= 0 && $0 < particleCount } &&
            Set(indices).count == 4
    }
}
