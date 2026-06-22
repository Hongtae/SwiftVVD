//
//  File: TriangleMesh.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

public protocol TriangleMeshStorage: AnyObject {
    var bounds: AABB { get }
    var isValid: Bool { get }
    var triangleCount: Int { get }

    func triangle(at index: Int) -> Triangle
    func contains(_ point: Vector3) -> Bool
    func rayTest(rayOrigin origin: Vector3, direction: Vector3) -> Scalar
}

public struct TriangleMesh: ConcavePrimitive {
    public let storage: any TriangleMeshStorage

    public init() {
        self.storage = EmptyTriangleMeshStorage.shared
    }

    public init(storage: any TriangleMeshStorage) {
        self.storage = storage
    }

    public var bounds: AABB {
        storage.bounds
    }

    public var isValid: Bool {
        storage.isValid
    }

    public var triangleCount: Int {
        storage.triangleCount
    }

    public func triangle(at index: Int) -> Triangle {
        storage.triangle(at: index)
    }

    public func contains(_ point: Vector3) -> Bool {
        storage.contains(point)
    }

    public func rayTest(rayOrigin origin: Vector3, direction: Vector3) -> Scalar {
        storage.rayTest(rayOrigin: origin, direction: direction)
    }
}

extension TriangleMesh: Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.storage === rhs.storage
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(storage))
    }
}

private final class EmptyTriangleMeshStorage: TriangleMeshStorage, @unchecked Sendable {
    static let shared = EmptyTriangleMeshStorage()

    var bounds: AABB {
        .null
    }

    var triangleCount: Int {
        0
    }

    var isValid: Bool {
        false
    }

    private init() {
    }

    func triangle(at index: Int) -> Triangle {
        preconditionFailure("Triangle index is out of range.")
    }

    func contains(_ point: Vector3) -> Bool {
        false
    }

    func rayTest(rayOrigin origin: Vector3, direction: Vector3) -> Scalar {
        -1.0
    }
}

public struct TriangleMeshShape: ConcaveShape {
    public let primitive: TriangleMesh

    public init(_ primitive: TriangleMesh) {
        self.primitive = primitive
    }
}
