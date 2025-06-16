//
//  File: CoordinateSpace.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

import Foundation

public enum CoordinateSpace {
    case global
    case local
    case named(AnyHashable)
}

extension CoordinateSpace {
    public var isGlobal: Bool {
        self == .global
    }
    public var isLocal: Bool {
        self == .local
    }
}

extension CoordinateSpace: Equatable, Hashable {
}

public protocol CoordinateSpaceProtocol {
    var coordinateSpace: CoordinateSpace { get }
}

public struct NamedCoordinateSpace: CoordinateSpaceProtocol, Equatable {
    public var coordinateSpace: CoordinateSpace {
        .named(name)
    }
    let name: AnyHashable
}

extension CoordinateSpaceProtocol where Self == NamedCoordinateSpace {
    public static func named(_ name: some Hashable) -> NamedCoordinateSpace {
        NamedCoordinateSpace(name: name)
    }
}

public struct LocalCoordinateSpace: CoordinateSpaceProtocol {
    public init() {}
    public var coordinateSpace: CoordinateSpace {
        .local
    }
}

extension CoordinateSpaceProtocol where Self == LocalCoordinateSpace {
    public static var local: LocalCoordinateSpace {
        LocalCoordinateSpace()
    }
}

public struct GlobalCoordinateSpace: CoordinateSpaceProtocol {
    public init() {}
    public var coordinateSpace: CoordinateSpace {
        .global
    }
}

extension CoordinateSpaceProtocol where Self == GlobalCoordinateSpace {
    public static var global: GlobalCoordinateSpace {
        GlobalCoordinateSpace()
    }
}
