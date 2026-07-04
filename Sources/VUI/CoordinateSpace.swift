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
    struct ID: Equatable, Hashable, Sendable {
        let rawValue: UInt32

        init(rawValue: UInt32 = UInt32(truncatingIfNeeded: AGMakeUniqueID())) {
            self.rawValue = rawValue
        }
    }
}

enum ScrollCoordinateSpace: Equatable, Hashable, Sendable {
    case horizontal
    case vertical
    case all
    case content
    case safeArea

    var id: CoordinateSpace.ID {
        switch self {
        case .horizontal:
            return CoordinateSpace.ID(rawValue: UInt32.max - 0)
        case .vertical:
            return CoordinateSpace.ID(rawValue: UInt32.max - 1)
        case .all:
            return CoordinateSpace.ID(rawValue: UInt32.max - 2)
        case .content:
            return CoordinateSpace.ID(rawValue: UInt32.max - 3)
        case .safeArea:
            return CoordinateSpace.ID(rawValue: UInt32.max - 4)
        }
    }

    init?(id: CoordinateSpace.ID) {
        switch id.rawValue {
        case UInt32.max - 0:
            self = .horizontal
        case UInt32.max - 1:
            self = .vertical
        case UInt32.max - 2:
            self = .all
        case UInt32.max - 3:
            self = .content
        case UInt32.max - 4:
            self = .safeArea
        default:
            return nil
        }
    }
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
